"""Media storage abstraction. Local filesystem now; an object-store implementation can replace it."""

import hashlib
import shutil
from pathlib import Path

MIME_TYPES = {
    ".mp3": "audio/mpeg",
    ".m4a": "audio/mp4",
    ".aac": "audio/aac",
    ".ogg": "audio/ogg",
    ".opus": "audio/ogg",
    ".flac": "audio/flac",
    ".wav": "audio/wav",
}


class UnsafePathError(ValueError):
    pass


class LocalMediaStorage:
    def __init__(self, root: Path):
        self.root = root.resolve()

    def resolve(self, relative_path: str) -> Path:
        """Map a stored relative path to an absolute file path, refusing anything outside the root."""
        candidate = (self.root / relative_path).resolve()
        if not candidate.is_relative_to(self.root) or candidate == self.root:
            raise UnsafePathError(relative_path)
        return candidate

    def store(self, source: Path) -> tuple[str, int]:
        """Copy ``source`` into content-addressed storage. Returns (relative path, size in bytes)."""
        sha = hashlib.sha256()
        with source.open("rb") as fh:
            for chunk in iter(lambda: fh.read(1024 * 1024), b""):
                sha.update(chunk)
        digest = sha.hexdigest()
        relative = f"{digest[:2]}/{digest}{source.suffix.lower()}"
        target = self.resolve(relative)
        if not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
        return relative, target.stat().st_size
