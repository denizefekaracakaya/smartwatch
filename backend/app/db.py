"""Database engine and session management."""

from collections.abc import Iterator
from pathlib import Path

from sqlalchemy import create_engine, event
from sqlalchemy.engine import Engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

MIGRATIONS_DIR = Path(__file__).resolve().parent.parent / "migrations"


class Base(DeclarativeBase):
    pass


def make_engine(database_url: str) -> Engine:
    if database_url.startswith("sqlite"):
        db_path = database_url.split("///", 1)[-1]
        if db_path and db_path != ":memory:":
            Path(db_path).parent.mkdir(parents=True, exist_ok=True)
        engine = create_engine(database_url, connect_args={"check_same_thread": False})

        @event.listens_for(engine, "connect")
        def _enable_sqlite_fk(dbapi_conn, _record):  # pragma: no cover - trivial
            cursor = dbapi_conn.cursor()
            cursor.execute("PRAGMA foreign_keys=ON")
            cursor.close()

        return engine
    return create_engine(database_url, pool_pre_ping=True)


class Database:
    """Holds the engine and session factory for one application instance."""

    def __init__(self, database_url: str):
        self.engine = make_engine(database_url)
        self.session_factory = sessionmaker(bind=self.engine, autoflush=False, expire_on_commit=False)

    def migrate(self) -> None:
        """Bring the schema up to date by running Alembic migrations (idempotent)."""
        from alembic import command
        from alembic.config import Config

        config = Config(str(MIGRATIONS_DIR.parent / "alembic.ini"))
        config.set_main_option("script_location", str(MIGRATIONS_DIR))
        with self.engine.begin() as connection:
            config.attributes["connection"] = connection
            command.upgrade(config, "head")

    def session(self) -> Iterator[Session]:
        with self.session_factory() as session:
            yield session
