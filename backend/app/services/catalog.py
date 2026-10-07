"""Catalog ingestion: import audio files (with tags) and generate a synthetic demo catalog."""

import json
import logging
import math
import random
import re
import struct
import tempfile
import wave
from dataclasses import dataclass, field
from pathlib import Path

import mutagen
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Track, TrackKind
from app.services.storage import MIME_TYPES, LocalMediaStorage

logger = logging.getLogger(__name__)


@dataclass
class TrackMetadata:
    title: str
    artist: str
    kind: TrackKind = TrackKind.SONG
    album: str | None = None
    genre: str | None = None
    year: int | None = None
    description: str | None = None
    duration_seconds: int = 0
    extra: dict = field(default_factory=dict)


def _first(tags, key: str) -> str | None:
    if not tags or key not in tags:
        return None
    value = tags[key]
    value = value[0] if isinstance(value, list) and value else value
    return str(value).strip() or None


_TRACK_NUMBER = re.compile(r"^\s*\d{1,3}\s*[-._)]\s*")
_NOISE = re.compile(r"\s*[\[(](official|lyrics?|audio|video|hq|hd|clip|music video)[^\])]*[\])]\s*", re.I)


def guess_from_filename(stem: str) -> tuple[str | None, str]:
    """Best-effort (artist, title) from names like "03 - Artist - Title (Official Audio)"."""
    name = _NOISE.sub(" ", stem.replace("_", " ")).strip()
    name = _TRACK_NUMBER.sub("", name).strip()
    parts = [part.strip() for part in re.split(r"\s+[-–—]\s+", name) if part.strip()]
    if len(parts) >= 2:
        return parts[0], " - ".join(parts[1:])
    return None, name or stem


def read_metadata(path: Path, default_kind: TrackKind) -> TrackMetadata:
    """Read tags with mutagen; a ``<file>.json`` sidecar overrides any field (useful for podcasts)."""
    audio = mutagen.File(path, easy=True)
    tags = audio.tags if audio is not None else None
    year_raw = _first(tags, "date")
    guessed_artist, guessed_title = guess_from_filename(path.stem)
    meta = TrackMetadata(
        title=_first(tags, "title") or guessed_title,
        artist=_first(tags, "artist") or guessed_artist or "Bilinmeyen Sanatçı",
        kind=default_kind,
        album=_first(tags, "album"),
        genre=_first(tags, "genre"),
        year=int(year_raw[:4]) if year_raw and year_raw[:4].isdigit() else None,
        duration_seconds=round(audio.info.length) if audio is not None and audio.info else 0,
    )
    sidecar = path.with_suffix(path.suffix + ".json")
    if sidecar.is_file():
        data = json.loads(sidecar.read_text(encoding="utf-8"))
        for key in ("title", "artist", "album", "genre", "year", "description"):
            if key in data:
                setattr(meta, key, data[key])
        if "kind" in data:
            meta.kind = TrackKind(data["kind"])
    return meta


def add_track(db: Session, storage: LocalMediaStorage, source: Path, meta: TrackMetadata) -> Track | None:
    """Store ``source`` and create a Track. Returns ``None`` if identical audio is already in the catalog."""
    mime = MIME_TYPES.get(source.suffix.lower())
    if mime is None:
        raise ValueError(f"Unsupported audio format: {source.suffix}")
    relative, size = storage.store(source)
    if db.scalar(select(Track.id).where(Track.file_path == relative)) is not None:
        return None
    track = Track(
        kind=meta.kind,
        title=meta.title[:200],
        artist=meta.artist[:200],
        album=meta.album,
        genre=meta.genre,
        year=meta.year,
        description=meta.description,
        duration_seconds=meta.duration_seconds,
        file_path=relative,
        mime_type=mime,
        file_size=size,
    )
    db.add(track)
    db.commit()
    return track


def ingest_directory(db: Session, storage: LocalMediaStorage, directory: Path, kind: TrackKind) -> int:
    added = 0
    for path in sorted(directory.rglob("*")):
        if path.suffix.lower() not in MIME_TYPES or not path.is_file():
            continue
        try:
            if add_track(db, storage, path, read_metadata(path, kind)) is not None:
                added += 1
                logger.info("Ingested %s", path.name)
        except (mutagen.MutagenError, ValueError, json.JSONDecodeError):
            logger.exception("Skipping %s", path)
    return added


# ---------------------------------------------------------------------------
# Demo catalog: fictional songs/podcasts with synthetic audio (no copyrighted material).
# ---------------------------------------------------------------------------
DEMO_CATALOG: list[dict] = [
    {
        "title": "Yaz Rüzgarı",
        "artist": "Deniz Mavisi",
        "album": "Kıyı Şeridi",
        "genre": "Pop",
        "year": 2024,
        "description": "Bodrum'da geçen bir yaz aşkı. Nakarat: 'gel yanıma, dalgalar şahit'. Neşeli, dans edilebilir.",
    },
    {
        "title": "Gece Yarısı İstanbul",
        "artist": "Boğaz Ekspresi",
        "album": "Şehir Işıkları",
        "genre": "Rock",
        "year": 2023,
        "description": "Gece Boğaz kıyısında araba sürerken dinlenen, elektro gitarlı hüzünlü rock.",
    },
    {
        "title": "Kahve ve Yağmur",
        "artist": "Lale Ses",
        "album": "Pencere Kenarı",
        "genre": "Akustik",
        "year": 2022,
        "description": "Yağmurlu bir sabah, sıcak kahve, akustik gitar ve sakin vokal. Ders çalışmak için ideal.",
    },
    {
        "title": "Neon Kalpler",
        "artist": "Sentetik Rüya",
        "album": "1987",
        "genre": "Synthwave",
        "year": 2021,
        "description": "80'ler esintili synthwave; retro arabalar, neon ışıklar, 'kalbim neon' tekrarlanan söz.",
    },
    {
        "title": "Dağların Ardında",
        "artist": "Anadolu Yolcusu",
        "album": "Toprak",
        "genre": "Türk Halk",
        "year": 2020,
        "description": "Bağlama eşliğinde göç ve memleket özlemi anlatan halk ezgisi.",
    },
    {
        "title": "Midnight Train",
        "artist": "The Copper Lines",
        "album": "Rails",
        "genre": "Blues",
        "year": 2019,
        "description": "Slow blues about leaving town on the last train, harmonica solo in the middle.",
    },
    {
        "title": "Sunrise Protocol",
        "artist": "Kilobyte",
        "album": "Bootloader",
        "genre": "Electronic",
        "year": 2024,
        "description": "Upbeat instrumental electronic track for workouts and running, 128 BPM.",
    },
    {
        "title": "Annemin Bahçesi",
        "artist": "Lale Ses",
        "album": "Pencere Kenarı",
        "genre": "Akustik",
        "year": 2022,
        "description": "Çocukluk anıları, anne ve bahçedeki erik ağacı üzerine duygusal bir şarkı.",
    },
    {
        "title": "Şampiyon",
        "artist": "Tribün Sesi",
        "album": "Maç Günü",
        "genre": "Hip-Hop",
        "year": 2023,
        "description": "Futbol ve azim üzerine motive edici rap; 'asla pes etme' nakaratı.",
    },
    {
        "title": "Ocean Lullaby",
        "artist": "Mira Vale",
        "album": "Tides",
        "genre": "Ambient",
        "year": 2018,
        "description": "Calm ambient lullaby with wave sounds, used for sleep and meditation.",
    },
    {
        "title": "Kırmızı Bisiklet",
        "artist": "Deniz Mavisi",
        "album": "Kıyı Şeridi",
        "genre": "Pop",
        "year": 2024,
        "description": "Çocukluktaki kırmızı bisiklet ve mahalle arkadaşları üzerine nostaljik pop.",
    },
    {
        "title": "Jazz on Galata",
        "artist": "Karaköy Quartet",
        "album": "Live at Galata",
        "genre": "Jazz",
        "year": 2017,
        "description": "Live jazz recording with saxophone and piano, recorded near the Galata Tower.",
    },
    {
        "kind": "podcast",
        "title": "Bölüm 12: Yapay Zeka ve Müzik",
        "artist": "Teknoloji Sohbetleri",
        "album": "Teknoloji Sohbetleri",
        "genre": "Teknoloji",
        "year": 2025,
        "description": "Yapay zekanın beste yapması, telif hakları ve müzisyenlerin geleceği tartışılıyor.",
    },
    {
        "kind": "podcast",
        "title": "Bölüm 3: Sabah Rutini",
        "artist": "İyi Yaşam Podcast",
        "album": "İyi Yaşam Podcast",
        "genre": "Sağlık",
        "year": 2025,
        "description": "Erken kalkmak, meditasyon ve kahvaltı alışkanlıkları üzerine bir uzmanla röportaj.",
    },
    {
        "kind": "podcast",
        "title": "Episode 41: History of the Silk Road",
        "artist": "Long Roads",
        "album": "Long Roads",
        "genre": "History",
        "year": 2024,
        "description": "Trade routes between China and Anatolia, caravanserais and the spread of ideas.",
    },
    {
        "kind": "podcast",
        "title": "Bölüm 7: Girişimcilikte İlk Yıl",
        "artist": "Start-Up Kahvesi",
        "album": "Start-Up Kahvesi",
        "genre": "İş",
        "year": 2025,
        "description": "Bir mobil uygulama girişiminin ilk yılında yaşanan hatalar ve yatırım süreci.",
    },
]

_SAMPLE_RATE = 22050


def synth_wav(path: Path, seed: int, seconds: int) -> None:
    """Write a short, pleasant-ish synthetic melody so each demo track sounds different."""
    rng = random.Random(seed)  # noqa: S311  # nosec B311
    scale = [261.63, 293.66, 329.63, 392.00, 440.00, 523.25, 587.33]
    note_len = rng.choice([0.25, 0.375, 0.5])
    notes = [rng.choice(scale) * rng.choice([0.5, 1, 1]) for _ in range(int(seconds / note_len))]
    frames = bytearray()
    per_note = int(_SAMPLE_RATE * note_len)
    for freq in notes:
        for i in range(per_note):
            envelope = min(1.0, i / 400) * max(0.0, 1 - i / per_note) ** 0.5
            t = i / _SAMPLE_RATE
            sample = 0.6 * math.sin(2 * math.pi * freq * t) + 0.2 * math.sin(4 * math.pi * freq * t)
            frames += struct.pack("<h", int(sample * envelope * 12000))
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(_SAMPLE_RATE)
        wav.writeframes(bytes(frames))


def seed_demo(db: Session, storage: LocalMediaStorage, seconds: int = 30) -> int:
    added = 0
    with tempfile.TemporaryDirectory() as tmp:
        for index, entry in enumerate(DEMO_CATALOG):
            kind = TrackKind(entry.get("kind", "song"))
            length = seconds * 2 if kind == TrackKind.PODCAST else seconds
            source = Path(tmp) / f"demo_{index}.wav"
            synth_wav(source, seed=index, seconds=length)
            meta = TrackMetadata(
                title=entry["title"],
                artist=entry["artist"],
                kind=kind,
                album=entry.get("album"),
                genre=entry.get("genre"),
                year=entry.get("year"),
                description=entry.get("description"),
                duration_seconds=length,
            )
            if add_track(db, storage, source, meta) is not None:
                added += 1
    return added
