import json
from datetime import timedelta
from pathlib import Path

from sqlalchemy import select

from app.models import Track, TrackKind
from app.security import create_jwt
from app.services.catalog import DEMO_CATALOG, ingest_directory, synth_wav
from app.services.storage import LocalMediaStorage, UnsafePathError

API = "/api/v1/tracks"


def test_catalog_requires_auth(client, catalog):
    assert client.get(API).status_code == 401


def test_browse_and_filter(client, users, catalog):
    h = users.create()["headers"]
    page = client.get(API, headers=h).json()
    assert page["total"] == len(DEMO_CATALOG)
    assert "file_path" not in page["items"][0]  # storage layout is never exposed

    podcasts = client.get(API, headers=h, params={"kind": "podcast"}).json()
    assert podcasts["total"] == 4
    assert all(t["kind"] == "podcast" for t in podcasts["items"])

    jazz = client.get(API, headers=h, params={"genre": "jazz"}).json()
    assert [t["title"] for t in jazz["items"]] == ["Jazz on Galata"]

    paged = client.get(API, headers=h, params={"limit": 5, "offset": 5}).json()
    assert len(paged["items"]) == 5 and paged["total"] == len(DEMO_CATALOG)

    assert client.get(API, headers=h, params={"limit": 1000}).status_code == 422


def test_fuzzy_search_tolerates_typos(client, users, catalog):
    h = users.create()["headers"]
    titles = [t["title"] for t in client.get(API, headers=h, params={"q": "yaz ruzgari"}).json()["items"]]
    assert titles[0] == "Yaz Rüzgarı"
    titles = [t["title"] for t in client.get(API, headers=h, params={"q": "midnite train"}).json()["items"]]
    assert titles[0] == "Midnight Train"
    by_artist = client.get(API, headers=h, params={"q": "Lale Ses"}).json()["items"]
    assert {t["title"] for t in by_artist[:2]} == {"Kahve ve Yağmur", "Annemin Bahçesi"}
    assert client.get(API, headers=h, params={"q": "zzzzqqqq"}).json()["total"] == 0
    # multi-word descriptions: every word should count, not just the best single field
    titles = [
        t["title"] for t in client.get(API, headers=h, params={"q": "sabah rutini podcast"}).json()["items"]
    ]
    assert titles[0] == "Bölüm 3: Sabah Rutini"
    # as-you-type prefixes and dotless/dotted i folding
    titles = [t["title"] for t in client.get(API, headers=h, params={"q": "kirmizi bisik"}).json()["items"]]
    assert titles[0] == "Kırmızı Bisiklet"
    titles = [t["title"] for t in client.get(API, headers=h, params={"q": "IYI YASAM"}).json()["items"]]
    assert titles[0] == "Bölüm 3: Sabah Rutini"


def test_get_track(client, users, catalog):
    h = users.create()["headers"]
    tid = catalog["Neon Kalpler"]
    assert client.get(f"{API}/{tid}", headers=h).json()["artist"] == "Sentetik Rüya"
    assert client.get(f"{API}/99999", headers=h).status_code == 404


def _stream(client, h, tid):
    r = client.get(f"{API}/{tid}/stream-url", headers=h)
    assert r.status_code == 200
    body = r.json()
    assert body["mime_type"] == "audio/wav"
    return body["url"].replace("http://testserver", "")


def test_stream_full_and_range(client, users, catalog, app, settings):
    h = users.create()["headers"]
    tid = catalog["Yaz Rüzgarı"]
    url = _stream(client, h, tid)
    with app.state.db.session_factory() as db:
        track = db.get(Track, tid)
        data = LocalMediaStorage(settings.media_dir).resolve(track.file_path).read_bytes()

    full = client.get(url)
    assert full.status_code == 200
    assert full.content == data
    assert full.headers["accept-ranges"] == "bytes"

    part = client.get(url, headers={"Range": "bytes=100-199"})
    assert part.status_code == 206
    assert part.content == data[100:200]
    assert part.headers["content-range"] == f"bytes 100-199/{len(data)}"

    tail = client.get(url, headers={"Range": "bytes=-50"})
    assert tail.status_code == 206 and tail.content == data[-50:]

    bad = client.get(url, headers={"Range": f"bytes={len(data) + 10}-"})
    assert bad.status_code == 416


def test_stream_token_validation(client, users, catalog, settings):
    h = users.create()["headers"]
    a, b = catalog["Yaz Rüzgarı"], catalog["Neon Kalpler"]
    url = _stream(client, h, a)
    token = url.split("token=")[1]
    # token bound to track a cannot stream track b
    assert client.get(f"{API}/{b}/stream", params={"token": token}).status_code == 401
    # access tokens are not stream tokens
    access = h["Authorization"].split()[1]
    assert client.get(f"{API}/{a}/stream", params={"token": access}).status_code == 401
    # expired
    expired = create_jwt(settings.secret_key, 1, "stream", timedelta(seconds=-1), tid=a)
    assert client.get(f"{API}/{a}/stream", params={"token": expired}).status_code == 401
    # forged with another key
    forged = create_jwt("another-secret-key-0123456789abcdef0123", 1, "stream", timedelta(hours=1), tid=a)
    assert client.get(f"{API}/{a}/stream", params={"token": forged}).status_code == 401
    assert client.get(f"{API}/{a}/stream").status_code == 422


def test_storage_refuses_path_traversal(tmp_path):
    storage = LocalMediaStorage(tmp_path / "media")
    for bad in ["../secret.txt", r"..\secret.txt", "/etc/passwd", "a/../../x", ""]:
        try:
            storage.resolve(bad)
        except UnsafePathError:
            continue
        raise AssertionError(f"accepted {bad!r}")
    assert storage.resolve("ab/file.mp3").is_relative_to(storage.root)


def test_ingest_directory_reads_metadata_and_sidecar(app, settings, tmp_path):
    src = tmp_path / "incoming"
    src.mkdir()
    synth_wav(src / "My_Song.wav", seed=1, seconds=1)
    synth_wav(src / "ep1.wav", seed=2, seconds=1)
    (src / "ep1.wav.json").write_text(
        json.dumps(
            {"kind": "podcast", "title": "Episode One", "artist": "Pod", "description": "About tests"}
        ),
        encoding="utf-8",
    )
    (src / "notes.txt").write_text("ignored")
    storage = LocalMediaStorage(settings.media_dir)
    app.state.db.migrate()
    with app.state.db.session_factory() as db:
        assert ingest_directory(db, storage, src, TrackKind.SONG) == 2
        assert ingest_directory(db, storage, src, TrackKind.SONG) == 0  # idempotent (content-addressed)
        tracks = {t.title: t for t in db.scalars(select(Track))}
    assert tracks["My Song"].kind == TrackKind.SONG and tracks["My Song"].duration_seconds == 1
    assert tracks["Episode One"].kind == TrackKind.PODCAST
    assert Path(settings.media_dir / tracks["Episode One"].file_path).is_file()
