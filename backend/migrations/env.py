"""Alembic environment. Migrations run through ``Database.migrate()`` (app startup / CLI) or the alembic CLI."""

from alembic import context
from sqlalchemy import engine_from_config, pool

from app import models  # noqa: F401  (register mappers)
from app.db import Base

config = context.config
target_metadata = Base.metadata


def _run(connection) -> None:
    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        render_as_batch=connection.dialect.name == "sqlite",  # SQLite needs batch mode for ALTER TABLE
        compare_type=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connection = config.attributes.get("connection")
    if connection is not None:
        _run(connection)
        return
    if not config.get_main_option("sqlalchemy.url"):
        from app.config import get_settings

        config.set_main_option("sqlalchemy.url", get_settings().database_url)
    engine = engine_from_config(
        config.get_section(config.config_ini_section, {}), prefix="sqlalchemy.", poolclass=pool.NullPool
    )
    with engine.connect() as conn:
        _run(conn)


if context.is_offline_mode():
    raise SystemExit("Offline migrations are not supported; run against a database.")
run_migrations_online()
