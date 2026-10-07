"""End-to-end smoke test against a real uvicorn process.

Starts the API on a free port with a throw-away database, seeds the demo catalog, and walks the full user
journey over real HTTP: register → read verification link from the server log → verify → login → browse →
search → stream (range) → playlists → assistant → refresh → password reset → logout.

    uv run python scripts/smoke_test.py
"""

import os
import queue
import re
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[1]
PASSWORD = "SmokeTest123"


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def main() -> int:
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

    def wait_log(pattern: str, timeout: float = 10) -> re.Match:
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                line = logs.get(timeout=0.2)
            except queue.Empty:
                continue
            if m := re.search(pattern, line):
                return m
        raise AssertionError(f"log pattern not found: {pattern}")

    def step(name: str) -> None:
        print(f"  [ok] {name}")

    try:
        with httpx.Client(base_url=base, timeout=10) as c:
            for _ in range(50):
                try:
                    if c.get("/health").status_code == 200:
                        break
                except httpx.TransportError:
                    time.sleep(0.2)
            else:
                raise AssertionError("server did not start")
            step("server healthy")

            email = "smoke@example.com"
            r = c.post(
                "/api/v1/auth/register", json={"email": email, "password": PASSWORD, "display_name": "Smoke"}
            )
            assert r.status_code == 201, r.text
            link = wait_log(r"(http://\S+/verify-email\?token=[\w\-]+)").group(1)
            step("registered; verification mail logged")

            assert (
                c.post("/api/v1/auth/login", json={"email": email, "password": PASSWORD}).status_code == 403
            )
            token = link.split("token=")[1]
            assert c.get(link.replace(base, "")).status_code == 200
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
            part = c.get(stream["url"].replace(base, ""), headers={"Range": "bytes=0-43"})
            assert part.status_code == 206 and part.content[:4] == b"RIFF"
            step("stream URL + HTTP range request (206, WAV header)")

            pl = c.post("/api/v1/playlists", headers=h, json={"name": "Smoke Mix"}).json()
            for t in page["items"][:3]:
                assert (
                    c.post(
                        f"/api/v1/playlists/{pl['id']}/tracks", headers=h, json={"track_id": t["id"]}
                    ).status_code
                    == 201
                )
            detail = c.get(f"/api/v1/playlists/{pl['id']}", headers=h).json()
            assert len(detail["tracks"]) == 3
            step("playlist create + add tracks")

            ai = c.post("/api/v1/assistant/search", headers=h, json={"query": "neon kalpler"}).json()
            assert ai["matches"] and ai["matches"][0]["track"]["title"] == "Neon Kalpler"
            step(f"assistant (ai_used={ai['ai_used']})")

            new = c.post("/api/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]}).json()
            assert new["refresh_token"] != tokens["refresh_token"]
            step("refresh rotation")

            assert c.post("/api/v1/auth/forgot-password", json={"email": email}).status_code == 202
            code = wait_log(r"kodunuz: (\d{6})").group(1)
            r = c.post(
                "/api/v1/auth/reset-password",
                json={"email": email, "code": code, "new_password": "NewSmoke4567"},
            )
            assert r.status_code == 204, r.text
            assert (
                c.post("/api/v1/auth/refresh", json={"refresh_token": new["refresh_token"]}).status_code
                == 401
            )
            again = c.post("/api/v1/auth/login", json={"email": email, "password": "NewSmoke4567"}).json()
            step("password reset revokes sessions; new password works")

            assert (
                c.post("/api/v1/auth/logout", json={"refresh_token": again["refresh_token"]}).status_code
                == 204
            )
            step("logout")
        print("SMOKE TEST PASSED")
        return 0
    finally:
        server.terminate()
        server.wait(timeout=10)


if __name__ == "__main__":
    raise SystemExit(main())
