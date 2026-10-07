"""FastAPI dependencies shared by routers."""

from collections.abc import Iterator
from typing import Annotated

from fastapi import Depends, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.config import Settings
from app.errors import ApiError
from app.models import User
from app.ratelimit import RateLimiter
from app.security import decode_jwt
from app.services.email import EmailSender

_bearer = HTTPBearer(auto_error=False)


def get_settings_dep(request: Request) -> Settings:
    return request.app.state.settings


def get_db(request: Request) -> Iterator[Session]:
    yield from request.app.state.db.session()


def get_email_sender(request: Request) -> EmailSender:
    return request.app.state.email_sender


def get_rate_limiter(request: Request) -> RateLimiter:
    return request.app.state.rate_limiter


def client_ip(request: Request) -> str:
    return request.client.host if request.client else "unknown"


SettingsDep = Annotated[Settings, Depends(get_settings_dep)]
DbDep = Annotated[Session, Depends(get_db)]
EmailDep = Annotated[EmailSender, Depends(get_email_sender)]
LimiterDep = Annotated[RateLimiter, Depends(get_rate_limiter)]


def _unauthorized(detail: str = "Not authenticated") -> ApiError:
    return ApiError(
        status.HTTP_401_UNAUTHORIZED, "unauthorized", detail, headers={"WWW-Authenticate": "Bearer"}
    )


def get_current_user(
    db: DbDep,
    settings: SettingsDep,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> User:
    if credentials is None:
        raise _unauthorized()
    payload = decode_jwt(settings.secret_key, credentials.credentials, "access")
    if payload is None:
        raise _unauthorized("Invalid or expired token")
    user = db.get(User, int(payload["sub"]))
    if user is None or not user.is_active or payload.get("ep") != user.session_epoch:
        raise _unauthorized("Invalid or expired token")
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]
