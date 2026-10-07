"""Import playlists from Spotify as *metadata* and rebuild them from the local catalog.

Only titles and artists are imported: Spotify audio is DRM-protected and its terms (like YouTube's) do not
allow downloading it. Each wanted track is matched against the audio this server actually has (tracks the
operator ingested), and a report lists what is missing so it can be added from legitimately owned files.

Supported sources:
- Spotify account data export ("Download your data" → ``Playlist1.json``, ``YourLibrary.json``)
- Exportify CSV (https://exportify.net) — one CSV per playlist
- A Spotify playlist URL through the Web API (needs SPOTIFY_CLIENT_ID / SPOTIFY_CLIENT_SECRET)
"""

import csv
import io
import json
import logging
import re
from dataclasses import dataclass, field
from pathlib import Path

import httpx
from rapidfuzz import fuzz
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Playlist, PlaylistItem, Track, User, utcnow
from app.services.search import fuzzy_search, normalise

logger = logging.getLogger(__name__)

TITLE_THRESHOLD = 85.0
ARTIST_THRESHOLD = 70.0
_TITLE_NOISE = re.compile(
    r"\s*([(\[][^)\]]*\b(remaster(ed)?|live|edit|version|mono|stereo|feat\.?|ft\.?)\b[^)\]]*[)\]]"
    r"|\s-\s.*\b(remaster(ed)?|live|edit|version|mono|stereo)\b.*)$",
    re.I,
)


@dataclass
class WantedTrack:
    title: str
    artist: str
    album: str | None = None


@dataclass
class ImportedPlaylist:
    name: str
    tracks: list[WantedTrack] = field(default_factory=list)


@dataclass
class PlaylistReport:
    name: str
    playlist_id: int | None
    matched: list[tuple[WantedTrack, Track]] = field(default_factory=list)
    missing: list[WantedTrack] = field(default_factory=list)


# --------------------------------------------------------------------------- parsing
def parse_spotify_export(data: dict) -> list[ImportedPlaylist]:
    """Spotify "Download your data": Playlist1.json (``playlists``) or YourLibrary.json (``tracks``)."""
    playlists: list[ImportedPlaylist] = []
    for raw in data.get("playlists", []):
        pl = ImportedPlaylist(name=(raw.get("name") or "Spotify").strip())
        for item in raw.get("items", []):
            track = item.get("track") or {}
            title, artist = track.get("trackName"), track.get("artistName")
            if title and artist:
                pl.tracks.append(WantedTrack(title, artist, track.get("albumName")))
        playlists.append(pl)
    if data.get("tracks"):  # liked songs in YourLibrary.json
        liked = ImportedPlaylist(name="Beğenilen Şarkılar")
        for track in data["tracks"]:
            if track.get("track") and track.get("artist"):
                liked.tracks.append(WantedTrack(track["track"], track["artist"], track.get("album")))
        playlists.append(liked)
    return playlists


def parse_exportify_csv(text: str, name: str) -> ImportedPlaylist:
    reader = csv.DictReader(io.StringIO(text.lstrip("﻿")))
    playlist = ImportedPlaylist(name=name)
    for row in reader:
        title = (row.get("Track Name") or "").strip()
        artists = (row.get("Artist Name(s)") or "").strip()
        if title and artists:
            # Exportify joins multiple artists with ","; the first one is the main artist.
            playlist.tracks.append(WantedTrack(title, artists.split(",")[0].strip(), row.get("Album Name")))
    return playlist


def load_file(path: Path) -> list[ImportedPlaylist]:
    suffix = path.suffix.lower()
    if suffix not in (".json", ".csv"):
        raise ValueError(f"Unsupported file type: {path.suffix} (expected .json or .csv)")
    text = path.read_text(encoding="utf-8-sig")
    if suffix == ".json":
        return parse_spotify_export(json.loads(text))
    return [parse_exportify_csv(text, name=path.stem.replace("_", " "))]


_PLAYLIST_URL = re.compile(r"(?:playlist[/:])([A-Za-z0-9]{22})")


def fetch_spotify_playlist(
    url_or_id: str, client_id: str, client_secret: str, client: httpx.Client | None = None
) -> ImportedPlaylist:
    """Read a public playlist's track list with the Spotify Web API (client-credentials flow).

    Spotify does not serve its own editorial/algorithmic playlists to new API apps; user-created public
    playlists work. Private playlists need the account-data export or Exportify instead.
    """
    match = _PLAYLIST_URL.search(url_or_id)
    playlist_id = match.group(1) if match else url_or_id.strip()
    if not re.fullmatch(r"[A-Za-z0-9]{22}", playlist_id):
        raise ValueError(f"Not a Spotify playlist URL or id: {url_or_id}")
    http = client or httpx.Client(timeout=20)
    token = http.post(
        "https://accounts.spotify.com/api/token",
        data={"grant_type": "client_credentials"},
        auth=(client_id, client_secret),
    )
    token.raise_for_status()
    headers = {"Authorization": f"Bearer {token.json()['access_token']}"}
    meta = http.get(
        f"https://api.spotify.com/v1/playlists/{playlist_id}", headers=headers, params={"fields": "name"}
    )
    meta.raise_for_status()
    playlist = ImportedPlaylist(name=meta.json().get("name") or "Spotify")
    url: str | None = f"https://api.spotify.com/v1/playlists/{playlist_id}/tracks"
    params: dict | None = {"limit": 100, "fields": "next,items(track(name,artists(name),album(name)))"}
    while url:
        page = http.get(url, headers=headers, params=params)
        page.raise_for_status()
        body = page.json()
        for item in body.get("items", []):
            track = item.get("track") or {}
            artists = track.get("artists") or []
            if track.get("name") and artists:
                playlist.tracks.append(
                    WantedTrack(track["name"], artists[0]["name"], (track.get("album") or {}).get("name"))
                )
        url, params = body.get("next"), None  # "next" already carries the query
    return playlist


# --------------------------------------------------------------------------- matching
def _clean_title(title: str) -> str:
    return _TITLE_NOISE.sub("", title).strip() or title


def find_match(db: Session, wanted: WantedTrack) -> Track | None:
    """Best catalog track whose title and artist both match closely enough, else ``None``."""
    title = normalise(_clean_title(wanted.title))
    artist = normalise(wanted.artist)
    best: tuple[float, Track] | None = None
    for hit in fuzzy_search(db, f"{wanted.artist} {_clean_title(wanted.title)}", limit=10, min_score=40):
        t_score = fuzz.ratio(title, normalise(_clean_title(hit.track.title)))
        a_score = fuzz.token_set_ratio(artist, normalise(hit.track.artist))
        if t_score >= TITLE_THRESHOLD and a_score >= ARTIST_THRESHOLD:
            score = t_score + a_score
            if best is None or score > best[0]:
                best = (score, hit.track)
    return best[1] if best else None


def import_playlists(
    db: Session, user: User, playlists: list[ImportedPlaylist], dry_run: bool = False
) -> list[PlaylistReport]:
    """Create (or extend) one Efetüfe playlist per imported playlist with the tracks the catalog has."""
    reports: list[PlaylistReport] = []
    for imported in playlists:
        report = PlaylistReport(name=imported.name[:100] or "Spotify", playlist_id=None)
        seen: set[int] = set()
        for wanted in imported.tracks:
            track = find_match(db, wanted)
            if track is None:
                report.missing.append(wanted)
            elif track.id not in seen:
                seen.add(track.id)
                report.matched.append((wanted, track))
        if not dry_run and report.matched:
            playlist = db.scalar(
                select(Playlist).where(Playlist.owner_id == user.id, Playlist.name == report.name)
            )
            if playlist is None:
                playlist = Playlist(owner_id=user.id, name=report.name, description="Spotify'dan aktarıldı")
                db.add(playlist)
                db.flush()
            present = {item.track_id for item in playlist.items}
            for _, track in report.matched:
                if track.id not in present:
                    playlist.items.append(PlaylistItem(track_id=track.id, position=len(playlist.items)))
                    present.add(track.id)
            playlist.updated_at = utcnow()
            db.commit()
            report.playlist_id = playlist.id
        reports.append(report)
    return reports


def write_missing_csv(reports: list[PlaylistReport], path: Path) -> int:
    rows = [(r.name, w.artist, w.title, w.album or "") for r in reports for w in r.missing]
    with path.open("w", newline="", encoding="utf-8-sig") as fh:
        writer = csv.writer(fh)
        writer.writerow(["Playlist", "Artist", "Title", "Album"])
        writer.writerows(rows)
    return len(rows)
