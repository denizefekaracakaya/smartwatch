"""Cryptographic primitives: password hashing, JWTs and opaque one-time tokens."""

import hashlib
import hmac
import secrets
from datetime import UTC, datetime, timedelta
from typing import Any, Literal

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError

_hasher = PasswordHasher()  # Argon2id with library-recommended parameters
_JWT_ALGORITHM = "HS256"

# A real hash used to equalise timing when a login targets an unknown e-mail.
_DUMMY_HASH = _hasher.hash(secrets.token_urlsafe(16))

JwtType = Literal["access", "stream"]


def as_utc(value: datetime) -> datetime:
    """SQLite drops tzinfo; treat naive datetimes from the DB as UTC."""
    return value if value.tzinfo else value.replace(tzinfo=UTC)


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password_hash: str | None, password: str) -> bool:
    try:
        return _hasher.verify(password_hash or _DUMMY_HASH, password) and password_hash is not None
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False


def password_needs_rehash(password_hash: str) -> bool:
    return _hasher.check_needs_rehash(password_hash)


def new_opaque_token() -> str:
    """256-bit URL-safe random secret."""
    return secrets.token_urlsafe(32)


def new_numeric_code(digits: int = 6) -> str:
    return f"{secrets.randbelow(10**digits):0{digits}d}"


def digest(secret: str) -> str:
    """SHA-256 hex digest used to store bearer secrets. High-entropy inputs make a slow hash unnecessary."""
    return hashlib.sha256(secret.encode()).hexdigest()


def keyed_digest(secret_key: str, value: str) -> str:
    """HMAC digest for low-entropy secrets (6-digit codes) so a DB leak does not reveal them by brute force."""
    return hmac.new(secret_key.encode(), value.encode(), hashlib.sha256).hexdigest()


def create_jwt(secret_key: str, subject: int, token_type: JwtType, ttl: timedelta, **claims: Any) -> str:
    now = datetime.now(UTC)
    payload = {"sub": str(subject), "type": token_type, "iat": now, "exp": now + ttl, **claims}
    return jwt.encode(payload, secret_key, algorithm=_JWT_ALGORITHM)


def decode_jwt(secret_key: str, token: str, expected_type: JwtType) -> dict[str, Any] | None:
    """Return the payload if the token is valid, unexpired and of the expected type; otherwise ``None``."""
    try:
        payload = jwt.decode(
            token, secret_key, algorithms=[_JWT_ALGORITHM], options={"require": ["exp", "sub", "type"]}
        )
    except jwt.PyJWTError:
        return None
    if payload.get("type") != expected_type:
        return None
    return payload
