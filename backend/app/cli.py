"""Operator CLI.

Usage:
    python -m app.cli init-db
    python -m app.cli seed-demo [--seconds 30]
    python -m app.cli ingest <directory> [--kind song|podcast]
"""

import argparse
import logging
import sys
from pathlib import Path

from app.config import get_settings
from app.db import Database
from app.models import TrackKind
from app.services.catalog import ingest_directory, seed_demo
from app.services.storage import LocalMediaStorage


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="python -m app.cli")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("init-db", help="create database tables")
    seed = sub.add_parser("seed-demo", help="add the synthetic demo catalog")
    seed.add_argument("--seconds", type=int, default=30)
    ingest = sub.add_parser("ingest", help="import audio files from a directory (recursive)")
    ingest.add_argument("directory", type=Path)
    ingest.add_argument("--kind", choices=[k.value for k in TrackKind], default=TrackKind.SONG.value)
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    settings = get_settings()
    database = Database(settings.database_url)
    database.migrate()
    settings.media_dir.mkdir(parents=True, exist_ok=True)
    storage = LocalMediaStorage(settings.media_dir)

    with database.session_factory() as db:
        if args.command == "init-db":
            print("Database ready.")
        elif args.command == "seed-demo":
            print(f"Added {seed_demo(db, storage, seconds=args.seconds)} demo tracks.")
        elif args.command == "ingest":
            if not args.directory.is_dir():
                print(f"Not a directory: {args.directory}", file=sys.stderr)
                return 2
            print(f"Added {ingest_directory(db, storage, args.directory, TrackKind(args.kind))} tracks.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
