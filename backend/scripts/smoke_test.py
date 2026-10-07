"""End-to-end smoke test over real HTTP.

Walks the full user journey: register → verification link from the e-mail → verify → login → browse →
search → stream (range) → playlists → assistant → refresh → password reset → logout.

Local mode (default) starts uvicorn on a free port with a throw-away SQLite database and reads e-mails from
the server log:

    uv run python scripts/smoke_test.py

Remote mode targets an already running, seeded deployment (e.g. docker compose) and reads e-mails from
Mailpit's API:

    uv run python scripts/smoke_test.py --base-url http://localhost:8000 --mailpit http://localhost:8025
"""

import argparse
import os
import queue
import re
import socket
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from collections.abc import Callable
from pathlib import Path
from urllib.parse import urlsplit

import httpx

ROOT = Path(__file__).resolve().parents[1]
PASSWORD = "SmokeTest123"
NEW_PASSWORD = "NewSmoke4567"


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def path_of(url: str) -> str:
    """Strip scheme/host: the API builds absolute URLs from APP_PUBLIC_BASE_URL (e.g. the emulator address)."""
    parts = urlsplit(url)
    return f"{parts.path}?{parts.query}" if parts.query else parts.path


def step(name: str) -> None:
    print(f"  [ok] {name}")


def journey(c: httpx.Client, email: str, read_mail: Callable[[str], re.Match]) -> None:
    for _ in range(100):
        try:
            if c.get("/health").status_code == 200:
                break
        except httpx.TransportError:
            pass
        time.sleep(0.3)
    else:
        raise AssertionError("server did not become healthy")
    step("server healthy")

    r = c.post("/api/v1/auth/register", json={"email": email, "password": PASSWORD, "display_name": "Smoke"})
    assert r.status_code == 201, r.text
    link = read_mail(r"(https?://\S+/verify-email\?token=[\w\-]+)").group(1)
    step("registered; verification mail delivered")

    assert c.post("/api/v1/auth/login", json={"email": email, "password": PASSWORD}).status_code == 403
    token = link.split("token=")[1]
    assert c.get(path_of(link)).status_code == 200
    assert c.post("/api/v1/auth/verify-email/confirm", data={"token": token}).status_code == 200
    step("unverified login refused; verification link works")

    tokens = c.post("/api/v1/auth/login", json={"email": email, "password": PASSWORD}).json()
    h = {"Authorization": f"Bearer {tokens['access_token']}"}
    step("login")

    page = c.get("/api/v1/tracks", headers=h).json()
    assert page["total"] >= 16
    hits = c.get("/api/v1/tracks", headers=h, params={"q": "kahve yagmur"}).json()["items"]
    assert hits[0]["title"] == "Kahve ve Yağmur"
    step(f"browse ({page['total']} tracks) and fuzzy search")

    stream = c.get(f"/api/v1/tracks/{hits[0]['id']}/stream-url", headers=h).json()
    part = c.get(path_of(stream["url"]), headers={"Range": "bytes=0-43"})
    assert part.status_code == 206 and part.content[:4] == b"RIFF"
    step("stream URL + HTTP range request (206, WAV header)")

    pl = c.post("/api/v1/playlists", headers=h, json={"name": "Smoke Mix"}).json()
    first_three = [t["id"] for t in page["items"][:3]]
    for track_id in first_three:
        r = c.post(f"/api/v1/playlists/{pl['id']}/tracks", headers=h, json={"track_id": track_id})
        assert r.status_code == 201, r.text
    r = c.put(f"/api/v1/playlists/{pl['id']}/tracks", headers=h, json={"track_ids": first_three[::-1]})
    assert [t["id"] for t in r.json()["tracks"]] == first_three[::-1]
    step("playlist create + add + reorder")

    ai = c.post("/api/v1/assistant/search", headers=h, json={"query": "neon kalpler"}).json()
    assert ai["matches"] and ai["matches"][0]["track"]["title"] == "Neon Kalpler"
    step(f"assistant (ai_used={ai['ai_used']})")

    new = c.post("/api/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]}).json()
    assert new["refresh_token"] != tokens["refresh_token"]
    step("refresh rotation")

    assert c.post("/api/v1/auth/forgot-password", json={"email": email}).status_code == 202
    code = read_mail(r"kodunuz: (\d{6})").group(1)
    r = c.post(
        "/api/v1/auth/reset-password", json={"email": email, "code": code, "new_password": NEW_PASSWORD}
    )
    assert r.status_code == 204, r.text
    assert c.post("/api/v1/auth/refresh", json={"refresh_token": new["refresh_token"]}).status_code == 401
    assert c.get("/api/v1/auth/me", headers=h).status_code == 401  # outstanding access token invalidated
    again = c.post("/api/v1/auth/login", json={"email": email, "password": NEW_PASSWORD}).json()
    step("password reset revokes sessions and access tokens; new password works")

    assert c.post("/api/v1/auth/logout", json={"refresh_token": again["refresh_token"]}).status_code == 204
    step("logout")


def run_local() -> int:
    tmp = Path(tempfile.mkdtemp(prefix="efetufe-smoke-"))
    port = free_port()
    base = f"http://127.0.0.1:{port}"
    env = {
        **os.environ,
        "APP_DATABASE_URL": f"sqlite:///{(tmp / 'smoke.db').as_posix()}",
        "APP_MEDIA_DIR": str(tmp / "media"),
        "APP_PUBLIC_BASE_URL": base,
        "APP_EMAIL_BACKEND": "console",
        "APP_SECRET_KEY": "smoke-test-secret-key-0123456789abcdef",
        "PYTHONIOENCODING": "utf-8",
    }
    env.pop("ANTHROPIC_API_KEY", None)

    subprocess.run(
        [sys.executable, "-m", "app.cli", "seed-demo", "--seconds", "3"], cwd=ROOT, env=env, check=True
    )
    server = subprocess.Popen(
        [sys.executable, "-m", "uvicorn", "app.main:create_app", "--factory", "--port", str(port)],
        cwd=ROOT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
    )
    logs: queue.Queue[str] = queue.Queue()
    threading.Thread(target=lambda: [logs.put(line) for line in server.stdout], daemon=True).start()

    def read_log(pattern: str, timeout: float = 10) -> re.Match:
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                line = logs.get(timeout=0.2)
            except queue.Empty:
                continue
            if m := re.search(pattern, line):
                return m
        raise AssertionError(f"log pattern not found: {pattern}")

    try:
        with httpx.Client(base_url=base, timeout=10) as c:
            journey(c, "smoke@example.com", read_log)
    finally:
        server.terminate()
        server.wait(timeout=10)
    print("SMOKE TEST PASSED")
    return 0


def run_remote(base_url: str, mailpit: str) -> int:
    email = f"smoke-{uuid.uuid4().hex[:10]}@example.com"
    seen: set[str] = set()

    def read_mailpit(pattern: str, timeout: float = 20) -> re.Match:
        deadline = time.time() + timeout
        with httpx.Client(base_url=mailpit, timeout=10) as m:
            while time.time() < deadline:
                found = m.get("/api/v1/search", params={"query": f"to:{email}"}).json().get("messages") or []
                for msg in found:
                    if msg["ID"] in seen:
                        continue
                    text = m.get(f"/api/v1/message/{msg['ID']}").json().get("Text", "")
                    if match := re.search(pattern, text):
                        seen.add(msg["ID"])
                        return match
                time.sleep(0.5)
        raise AssertionError(f"no e-mail matching {pattern} for {email}")

    with httpx.Client(base_url=base_url, timeout=15) as c:
        journey(c, email, read_mailpit)
    print("SMOKE TEST PASSED")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--base-url", help="test an already running deployment instead of starting uvicorn")
    parser.add_argument("--mailpit", default="http://localhost:8025", help="Mailpit URL (remote mode)")
    args = parser.parse_args()
    return run_remote(args.base_url, args.mailpit) if args.base_url else run_local()


if __name__ == "__main__":
    raise SystemExit(main())
