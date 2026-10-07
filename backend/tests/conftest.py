import os
import re
from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text

from app.config import Settings
from app.main import create_app
from app.services.email import ConsoleEmailSender

PASSWORD = "CorrectHorse42"

# Set TEST_DATABASE_URL (e.g. postgresql+psycopg://...) to run the suite against a real server database;
# it is wiped before every test. Default: a fresh SQLite file per test.
TEST_DATABASE_URL = os.environ.get("TEST_DATABASE_URL")


def _reset_database(url: str) -> None:
    from app import models  # noqa: F401  (register mappers)
    from app.db import Base

    engine = create_engine(url)
    with engine.begin() as conn:
        Base.metadata.drop_all(conn)
        conn.execute(text("DROP TABLE IF EXISTS alembic_version"))
    engine.dispose()


@pytest.fixture
def settings(tmp_path) -> Settings:
    if TEST_DATABASE_URL:
        _reset_database(TEST_DATABASE_URL)
    return Settings(
        environment="test",
        database_url=TEST_DATABASE_URL or f"sqlite:///{tmp_path / 'test.db'}",
        media_dir=tmp_path / "media",
        secret_key="test-secret-key-that-is-long-enough-0123456789",
        public_base_url="http://testserver",
        email_backend="console",
        anthropic_api_key=None,
        _env_file=None,
    )


@pytest.fixture
def mailer() -> ConsoleEmailSender:
    return ConsoleEmailSender()


@pytest.fixture
def assistant_client():
    return None


@pytest.fixture
def app(settings, mailer, assistant_client):
    return create_app(settings, email_sender=mailer, assistant_client=assistant_client)


@pytest.fixture
def client(app) -> Iterator[TestClient]:
    with TestClient(app) as c:
        yield c


def last_verification_token(mailer: ConsoleEmailSender) -> str:
    match = re.search(r"token=([\w\-]+)", mailer.outbox[-1].body)
    assert match, mailer.outbox[-1].body
    return match.group(1)


def last_reset_code(mailer: ConsoleEmailSender) -> str:
    match = re.search(r"\b(\d{6})\b", mailer.outbox[-1].body)
    assert match
    return match.group(1)


class UserFactory:
    def __init__(self, client: TestClient, mailer: ConsoleEmailSender):
        self.client = client
        self.mailer = mailer
        self.counter = 0

    def create(self, email: str | None = None, verified: bool = True) -> dict:
        self.counter += 1
        email = email or f"user{self.counter}@example.com"
        r = self.client.post(
            "/api/v1/auth/register",
            json={"email": email, "password": PASSWORD, "display_name": f"User {self.counter}"},
        )
        assert r.status_code == 201, r.text
        if not verified:
            return {"email": email}
        token = last_verification_token(self.mailer)
        assert self.client.post("/api/v1/auth/verify-email", json={"token": token}).status_code == 200
        r = self.client.post("/api/v1/auth/login", json={"email": email, "password": PASSWORD})
        assert r.status_code == 200, r.text
        tokens = r.json()
        return {
            "email": email,
            "tokens": tokens,
            "headers": {"Authorization": f"Bearer {tokens['access_token']}"},
        }


@pytest.fixture
def users(client, mailer) -> UserFactory:
    return UserFactory(client, mailer)


@pytest.fixture
def catalog(app, client, settings):
    """Seed the demo catalog (short clips) and return {title: id}."""
    from sqlalchemy import select

    from app.models import Track
    from app.services.catalog import seed_demo
    from app.services.storage import LocalMediaStorage

    with app.state.db.session_factory() as db:
        seed_demo(db, LocalMediaStorage(settings.media_dir), seconds=2)
        return {t.title: t.id for t in db.scalars(select(Track))}
