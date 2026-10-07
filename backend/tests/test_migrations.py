from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from sqlalchemy import inspect

from app.db import Base, Database


def test_migrations_match_models_and_are_idempotent(tmp_path):
    db = Database(f"sqlite:///{tmp_path / 'm.db'}")
    db.migrate()
    db.migrate()  # second run is a no-op
    with db.engine.connect() as conn:
        diff = compare_metadata(MigrationContext.configure(conn), Base.metadata)
    assert diff == [], f"models changed without a migration: {diff}"
    tables = set(inspect(db.engine).get_table_names())
    assert {"users", "auth_tokens", "tracks", "playlists", "playlist_items", "alembic_version"} <= tables
