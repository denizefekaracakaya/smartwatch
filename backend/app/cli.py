"""Operator CLI.

Usage:
    python -m app.cli init-db
    python -m app.cli seed-demo [--seconds 30]
    python -m app.cli ingest <directory> [--kind song|podcast]
    python -m app.cli import-playlists <file.json|file.csv|spotify-playlist-url> --user <email>
                                       [--dry-run] [--missing-out missing.csv]
"""

import argparse
import logging
import os
import sys
from pathlib import Path

from sqlalchemy import select

from app.config import get_settings
from app.db import Database
from app.models import TrackKind, User
from app.services.catalog import ingest_directory, seed_demo
from app.services.playlist_import import (
    fetch_spotify_playlist,
    import_playlists,
    load_file,
    write_missing_csv,
)
from app.services.storage import LocalMediaStorage


def _import_playlists(db, args) -> int:
    user = db.scalar(select(User).where(User.email == args.user.strip().lower()))
    if user is None:
        print(f"No account with e-mail {args.user}", file=sys.stderr)
        return 2
    source = args.source
    if source.startswith(("http://", "https://", "spotify:")):
        client_id, secret = os.environ.get("SPOTIFY_CLIENT_ID"), os.environ.get("SPOTIFY_CLIENT_SECRET")
        if not client_id or not secret:
            print(
                "Set SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET to read playlists from the Spotify API.",
                file=sys.stderr,
            )
            return 2
        playlists = [fetch_spotify_playlist(source, client_id, secret)]
    else:
        path = Path(source)
        if not path.is_file():
            print(f"Not a file: {path}", file=sys.stderr)
            return 2
        playlists = load_file(path)
        if args.name and len(playlists) == 1:
            playlists[0].name = args.name

    reports = import_playlists(db, user, playlists, dry_run=args.dry_run)
    total = matched = 0
    for report in reports:
        wanted = len(report.matched) + len(report.missing)
        total += wanted
        matched += len(report.matched)
        status = (
            "(dry run)" if args.dry_run else f"→ playlist #{report.playlist_id}" if report.playlist_id else ""
        )
        print(f"{report.name}: {len(report.matched)}/{wanted} matched {status}")
    print(f"Total: {matched}/{total} tracks found in the catalog.")
    if args.missing_out:
        count = write_missing_csv(reports, Path(args.missing_out))
        print(f"Wrote {count} missing tracks to {args.missing_out}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="python -m app.cli")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("init-db", help="create database tables")
    seed = sub.add_parser("seed-demo", help="add the synthetic demo catalog")
    seed.add_argument("--seconds", type=int, default=30)
    ingest = sub.add_parser("ingest", help="import audio files from a directory (recursive)")
    ingest.add_argument("directory", type=Path)
    ingest.add_argument("--kind", choices=[k.value for k in TrackKind], default=TrackKind.SONG.value)
    imp = sub.add_parser(
        "import-playlists",
        help="rebuild Spotify playlists (export JSON, Exportify CSV or playlist URL) from the catalog",
    )
    imp.add_argument("source", help="Playlist1.json / YourLibrary.json, an Exportify .csv, or a playlist URL")
    imp.add_argument("--user", required=True, help="e-mail of the Efetüfe account that gets the playlists")
    imp.add_argument("--dry-run", action="store_true", help="only report matches, change nothing")
    imp.add_argument("--missing-out", help="write tracks not found in the catalog to this CSV file")
    imp.add_argument("--name", help="playlist name for a single-playlist source (default: CSV file name)")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("alembic").setLevel(logging.WARNING)
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
        elif args.command == "import-playlists":
            return _import_playlists(db, args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
