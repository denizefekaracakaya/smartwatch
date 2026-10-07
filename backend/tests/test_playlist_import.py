import json

import httpx
import pytest
from sqlalchemy import select

from app.models import Playlist, TrackKind, User
from app.services.catalog import TrackMetadata, add_track, clean_tag, guess_from_filename, synth_wav
from app.services.playlist_import import (
    ImportedPlaylist,
    WantedTrack,
    fetch_spotify_playlist,
    find_match,
    import_playlists,
    load_file,
    parse_exportify_csv,
    parse_spotify_export,
    write_missing_csv,
)
from app.services.storage import LocalMediaStorage


@pytest.fixture
def db(app, client, catalog, settings, tmp_path, users):
    """Demo catalog plus two "real" songs, and a verified user."""
    users.create("owner@example.com")
    storage = LocalMediaStorage(settings.media_dir)
    with app.state.db.session_factory() as session:
        for i, (artist, title) in enumerate([("Tarkan", "Şımarık"), ("Sezen Aksu", "Firuze")]):
            src = tmp_path / f"real{i}.wav"
            synth_wav(src, seed=100 + i, seconds=1)
            add_track(session, storage, src, TrackMetadata(title=title, artist=artist, kind=TrackKind.SONG))
        yield session


def test_filename_guessing():
    assert guess_from_filename("03 - Tarkan - Şımarık (Official Video)") == ("Tarkan", "Şımarık")
    assert guess_from_filename("Sezen Aksu - Firuze") == ("Sezen Aksu", "Firuze")
    assert guess_from_filename("My_Song") == (None, "My Song")


def test_tag_spam_is_removed():
    assert clean_tag("www.mp3indirdur.mobi") is None
    assert clean_tag("Aklımı Kaçırdım | mp3indirdur.mobi") == "Aklımı Kaçırdım"
    assert clean_tag("Bal Dudaklım [Vivaturkiye.eu]") == "Bal Dudaklım"
    assert clean_tag("Mr. Brightside") == "Mr. Brightside"
    assert clean_tag("Bu Delikanlıyı Unutamazsın (feat. Rober Hatemo)").endswith("(feat. Rober Hatemo)")


def test_parse_spotify_account_export():
    data = {
        "playlists": [
            {
                "name": "Yolculuk",
                "items": [
                    {"track": {"trackName": "Şımarık", "artistName": "Tarkan", "albumName": "Ölürüm Sana"}},
                    {"track": None, "episode": {"episodeName": "x"}},
                ],
            }
        ],
        "tracks": [{"artist": "Sezen Aksu", "album": "Firuze", "track": "Firuze"}],
    }
    playlists = parse_spotify_export(data)
    assert [p.name for p in playlists] == ["Yolculuk", "Beğenilen Şarkılar"]
    assert playlists[0].tracks == [WantedTrack("Şımarık", "Tarkan", "Ölürüm Sana")]
    assert playlists[1].tracks[0].artist == "Sezen Aksu"


def test_parse_exportify_csv():
    text = (
        "﻿Track URI,Track Name,Artist URI(s),Artist Name(s),Album Name\n"
        'spotify:track:1,Firuze,spotify:artist:a,"Sezen Aksu,Someone",Firuze\n'
        ",,,,\n"
    )
    playlist = parse_exportify_csv(text, "Favoriler")
    assert playlist.name == "Favoriler"
    assert playlist.tracks == [WantedTrack("Firuze", "Sezen Aksu", "Firuze")]


def test_matching_is_tolerant_but_strict_on_artist(db):
    assert find_match(db, WantedTrack("Simarik", "TARKAN")).title == "Şımarık"
    assert find_match(db, WantedTrack("Şımarık - 2005 Remaster", "Tarkan")).title == "Şımarık"
    assert find_match(db, WantedTrack("Firuze (Live)", "Sezen Aksu")).title == "Firuze"
    assert find_match(db, WantedTrack("Şımarık", "Sezen Aksu")) is None  # same title, wrong artist
    assert find_match(db, WantedTrack("Bohemian Rhapsody", "Queen")) is None


def test_import_creates_playlist_and_is_idempotent(db, tmp_path):
    user = db.scalar(select(User).where(User.email == "owner@example.com"))
    imported = [
        ImportedPlaylist(
            "Yolculuk",
            [
                WantedTrack("Şımarık", "Tarkan"),
                WantedTrack("Bohemian Rhapsody", "Queen"),
                WantedTrack("Firuze", "Sezen Aksu"),
                WantedTrack("Simarik", "Tarkan"),  # duplicate of the first after matching
            ],
        )
    ]
    preview = import_playlists(db, user, imported, dry_run=True)
    assert len(preview[0].matched) == 2 and preview[0].playlist_id is None
    assert db.scalar(select(Playlist).where(Playlist.owner_id == user.id)) is None

    reports = import_playlists(db, user, imported)
    report = reports[0]
    assert [t.title for _, t in report.matched] == ["Şımarık", "Firuze"]
    assert [w.title for w in report.missing] == ["Bohemian Rhapsody"]
    playlist = db.get(Playlist, report.playlist_id)
    assert [i.track.title for i in playlist.items] == ["Şımarık", "Firuze"]

    import_playlists(db, user, imported)  # second run must not duplicate
    db.expire_all()
    assert len(db.get(Playlist, report.playlist_id).items) == 2
    assert len(db.scalars(select(Playlist).where(Playlist.owner_id == user.id)).all()) == 1

    out = tmp_path / "missing.csv"
    assert write_missing_csv(reports, out) == 1
    assert "Bohemian Rhapsody" in out.read_text(encoding="utf-8-sig")


def test_load_file_dispatch(tmp_path):
    js = tmp_path / "Playlist1.json"
    js.write_text(json.dumps({"playlists": [{"name": "A", "items": []}]}), encoding="utf-8")
    assert [p.name for p in load_file(js)] == ["A"]
    csv_file = tmp_path / "Gece_Surusu.csv"
    csv_file.write_text("Track Name,Artist Name(s)\nFiruze,Sezen Aksu\n", encoding="utf-8")
    assert load_file(csv_file)[0].name == "Gece Surusu"
    with pytest.raises(ValueError):
        load_file(tmp_path / "x.txt")


def test_fetch_spotify_playlist_paginates():
    pid = "37i9dQZF1DXcBWIGoYBM5M"
    calls = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(str(request.url))
        if request.url.host == "accounts.spotify.com":
            assert request.headers["Authorization"].startswith("Basic ")
            return httpx.Response(200, json={"access_token": "tok", "token_type": "Bearer"})
        assert request.headers["Authorization"] == "Bearer tok"
        if request.url.path == f"/v1/playlists/{pid}":
            return httpx.Response(200, json={"name": "Hits"})
        if "offset=100" in str(request.url):
            return httpx.Response(
                200,
                json={
                    "items": [
                        {
                            "track": {
                                "name": "Firuze",
                                "artists": [{"name": "Sezen Aksu"}],
                                "album": {"name": "F"},
                            }
                        }
                    ],
                    "next": None,
                },
            )
        return httpx.Response(
            200,
            json={
                "items": [
                    {
                        "track": {
                            "name": "Şımarık",
                            "artists": [{"name": "Tarkan"}, {"name": "X"}],
                            "album": None,
                        }
                    },
                    {"track": None},
                ],
                "next": f"https://api.spotify.com/v1/playlists/{pid}/tracks?offset=100&limit=100",
            },
        )

    client = httpx.Client(transport=httpx.MockTransport(handler))
    playlist = fetch_spotify_playlist(
        f"https://open.spotify.com/playlist/{pid}?si=abc", "id", "secret", client
    )
    assert playlist.name == "Hits"
    assert playlist.tracks == [
        WantedTrack("Şımarık", "Tarkan", None),
        WantedTrack("Firuze", "Sezen Aksu", "F"),
    ]
    assert len(calls) == 4

    with pytest.raises(ValueError):
        fetch_spotify_playlist("https://example.com/not-spotify", "id", "secret", client)
