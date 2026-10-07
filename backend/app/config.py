"""Application settings, loaded from environment variables (prefix ``APP_``) or a ``.env`` file."""

from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# Development-only default; Settings refuses it when APP_ENVIRONMENT=production.
INSECURE_DEFAULT_SECRET = "dev-insecure-secret-change-me-0123456789abcdef"  # noqa: S105  # nosec B105


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="APP_", env_file=".env", extra="ignore", populate_by_name=True
    )

    environment: Literal["development", "test", "production"] = "development"
    debug: bool = False
    log_level: str = "INFO"

    database_url: str = "sqlite:///./data/app.db"
    media_dir: Path = Path("./data/media")

    # Public base URL the mobile app uses to reach this API (used to build stream and e-mail links).
    public_base_url: str = "http://localhost:8000"
    cors_origins: list[str] = Field(default_factory=list)

    secret_key: str = INSECURE_DEFAULT_SECRET
    access_token_minutes: int = 15
    refresh_token_days: int = 30
    stream_token_hours: int = 6
    email_verify_hours: int = 48
    password_reset_minutes: int = 15
    password_reset_max_attempts: int = 5
    # When true, accounts must confirm their e-mail address before they can log in.
    require_email_verification: bool = True

    # E-mail delivery: "console" logs messages, "smtp" sends them.
    email_backend: Literal["console", "smtp"] = "console"
    email_from: str = "Efetüfe <no-reply@efetufe.local>"
    smtp_host: str = "localhost"
    smtp_port: int = 1025
    smtp_username: str | None = None
    smtp_password: str | None = None
    smtp_starttls: bool = False

    # Rate limits: "<count>/<seconds>"
    rate_limit_auth: str = "10/60"
    rate_limit_assistant: str = "20/60"
    rate_limit_enabled: bool = True

    # AI assistant (Anthropic). Without a key the assistant falls back to fuzzy search.
    anthropic_api_key: str | None = Field(default=None, validation_alias="ANTHROPIC_API_KEY")
    assistant_model: str = "claude-opus-5-5"
    assistant_effort: Literal["low", "medium", "high", "xhigh", "max"] = "low"
    assistant_max_iterations: int = 5
    assistant_timeout_seconds: float = 45.0

    @model_validator(mode="after")
    def _refuse_insecure_production(self) -> "Settings":
        if self.environment == "production":
            if self.secret_key == INSECURE_DEFAULT_SECRET or len(self.secret_key) < 32:
                raise ValueError("APP_SECRET_KEY must be set to a random value of at least 32 characters")
            if not self.public_base_url.startswith("https://"):
                raise ValueError("APP_PUBLIC_BASE_URL must use https in production")
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
