"""Application factory."""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from app.config import Settings, get_settings
from app.db import Database
from app.errors import register_error_handlers
from app.ratelimit import RateLimiter
from app.services.assistant import build_assistant_client
from app.services.email import EmailSender, build_email_sender

API_PREFIX = "/api/v1"


def configure_logging(level: str) -> None:
    logging.basicConfig(level=level.upper(), format="%(asctime)s %(levelname)s %(name)s: %(message)s")


def create_app(
    settings: Settings | None = None,
    email_sender: EmailSender | None = None,
    assistant_client=None,
) -> FastAPI:
    settings = settings or get_settings()
    configure_logging(settings.log_level)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        app.state.db.migrate()
        settings.media_dir.mkdir(parents=True, exist_ok=True)
        yield
        app.state.db.engine.dispose()

    app = FastAPI(
        title="Efetüfe Music API",
        version="0.1.0",
        lifespan=lifespan,
        docs_url=None if settings.environment == "production" else "/docs",
        redoc_url=None,
        openapi_url=None if settings.environment == "production" else "/openapi.json",
    )
    app.state.settings = settings
    app.state.db = Database(settings.database_url)
    app.state.email_sender = email_sender or build_email_sender(settings)
    app.state.rate_limiter = RateLimiter(enabled=settings.rate_limit_enabled)
    app.state.assistant_client = (
        assistant_client if assistant_client is not None else build_assistant_client(settings)
    )

    if settings.cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins,
            allow_methods=["GET", "POST", "PATCH", "PUT", "DELETE"],
            allow_headers=["Authorization", "Content-Type", "Range"],
        )

    @app.middleware("http")
    async def security_headers(request: Request, call_next):
        response = await call_next(request)
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault("Referrer-Policy", "no-referrer")
        if request.url.path not in ("/docs", "/openapi.json"):
            response.headers.setdefault(
                "Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'"
            )
        if request.url.path.startswith(API_PREFIX) and "/stream" not in request.url.path:
            response.headers.setdefault("Cache-Control", "no-store")
        if settings.environment == "production":
            response.headers.setdefault("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
        return response

    register_error_handlers(app)

    from app.routers import assistant, auth, playlists, tracks

    for router in (auth.router, tracks.router, playlists.router, assistant.router):
        app.include_router(router, prefix=API_PREFIX)

    @app.get("/health", tags=["health"])
    def health() -> dict[str, str]:
        with app.state.db.engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return {"status": "ok"}

    return app
