"""Authentication business logic: accounts, sessions, e-mail verification and password reset."""

import hmac
import logging
from datetime import UTC, datetime, timedelta
from urllib.parse import urlencode

from fastapi import status
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.config import Settings
from app.errors import ApiError
from app.models import AuthToken, TokenPurpose, User
from app.schemas import TokenPair, UserOut
from app.security import (
    as_utc,
    create_jwt,
    digest,
    hash_password,
    keyed_digest,
    new_numeric_code,
    new_opaque_token,
    password_needs_rehash,
    verify_password,
)
from app.services.email import OutgoingEmail

logger = logging.getLogger(__name__)


def _invalid_credentials() -> ApiError:
    return ApiError(status.HTTP_401_UNAUTHORIZED, "invalid_credentials", "Incorrect e-mail or password")


def _now() -> datetime:
    return datetime.now(UTC)


def _invalid_token() -> ApiError:
    return ApiError(status.HTTP_400_BAD_REQUEST, "invalid_token", "Token is invalid or has expired")


class AuthService:
    def __init__(self, db: Session, settings: Settings):
        self.db = db
        self.settings = settings

    # ----- accounts -----
    def register(self, email: str, password: str, display_name: str) -> tuple[User, OutgoingEmail]:
        user = User(email=email, display_name=display_name, password_hash=hash_password(password))
        self.db.add(user)
        try:
            self.db.flush()
        except IntegrityError:
            self.db.rollback()
            raise ApiError(
                status.HTTP_409_CONFLICT, "email_taken", "An account with this e-mail already exists"
            ) from None
        mail = self._issue_verification(user)
        self.db.commit()
        logger.info("Registered user id=%s", user.id)
        return user, mail

    def authenticate(self, email: str, password: str) -> User:
        user = self.db.scalar(select(User).where(User.email == email))
        if not verify_password(user.password_hash if user else None, password) or user is None:
            raise _invalid_credentials()
        if not user.is_active:
            raise _invalid_credentials()
        if self.settings.require_email_verification and not user.email_verified:
            raise ApiError(
                status.HTTP_403_FORBIDDEN, "email_not_verified", "Please verify your e-mail address first"
            )
        if password_needs_rehash(user.password_hash):
            user.password_hash = hash_password(password)
            self.db.commit()
        return user

    def change_password(self, user: User, current: str, new: str) -> TokenPair:
        if not verify_password(user.password_hash, current):
            raise _invalid_credentials()
        user.password_hash = hash_password(new)
        user.session_epoch += 1
        self.revoke_all_sessions(user.id)
        return self.issue_session(user)

    def delete_account(self, user: User, password: str) -> None:
        if not verify_password(user.password_hash, password):
            raise _invalid_credentials()
        self.db.delete(user)
        self.db.commit()
        logger.info("Deleted user id=%s", user.id)

    # ----- sessions -----
    def issue_session(self, user: User, family_id: str | None = None) -> TokenPair:
        refresh = new_opaque_token()
        self.db.add(
            AuthToken(
                user_id=user.id,
                purpose=TokenPurpose.REFRESH,
                token_hash=digest(refresh),
                family_id=family_id or new_opaque_token(),
                expires_at=_now() + timedelta(days=self.settings.refresh_token_days),
            )
        )
        self.db.commit()
        ttl = timedelta(minutes=self.settings.access_token_minutes)
        return TokenPair(
            access_token=create_jwt(self.settings.secret_key, user.id, "access", ttl, ep=user.session_epoch),
            refresh_token=refresh,
            expires_in=int(ttl.total_seconds()),
            user=UserOut.model_validate(user),
        )

    def refresh(self, refresh_token: str) -> TokenPair:
        token = self._find(TokenPurpose.REFRESH, digest(refresh_token))
        if token is None:
            raise ApiError(status.HTTP_401_UNAUTHORIZED, "invalid_token", "Invalid refresh token")
        if token.used_at is not None or token.revoked_at is not None:
            # A rotated/revoked token was presented again: assume theft and kill the whole session family.
            self._revoke_family(token.family_id)
            self.db.commit()
            logger.warning("Refresh token reuse detected for user id=%s", token.user_id)
            raise ApiError(status.HTTP_401_UNAUTHORIZED, "invalid_token", "Invalid refresh token")
        user = token.user
        if as_utc(token.expires_at) <= _now() or not user.is_active:
            raise ApiError(status.HTTP_401_UNAUTHORIZED, "invalid_token", "Invalid refresh token")
        # Claim the token atomically so two concurrent refreshes cannot both rotate it.
        claimed = self.db.execute(
            update(AuthToken)
            .where(AuthToken.id == token.id, AuthToken.used_at.is_(None), AuthToken.revoked_at.is_(None))
            .values(used_at=_now())
        )
        if claimed.rowcount != 1:
            self.db.rollback()
            raise ApiError(status.HTTP_401_UNAUTHORIZED, "invalid_token", "Invalid refresh token")
        return self.issue_session(user, family_id=token.family_id)

    def logout(self, refresh_token: str) -> None:
        token = self._find(TokenPurpose.REFRESH, digest(refresh_token))
        if token is not None:
            self._revoke_family(token.family_id)
            self.db.commit()

    def revoke_all_sessions(self, user_id: int) -> None:
        self.db.execute(
            update(AuthToken)
            .where(
                AuthToken.user_id == user_id,
                AuthToken.purpose == TokenPurpose.REFRESH,
                AuthToken.revoked_at.is_(None),
            )
            .values(revoked_at=_now())
        )
        self.db.commit()

    # ----- e-mail verification -----
    def resend_verification(self, email: str) -> OutgoingEmail | None:
        user = self.db.scalar(select(User).where(User.email == email))
        if user is None or user.email_verified:
            return None
        mail = self._issue_verification(user)
        self.db.commit()
        return mail

    def verify_email(self, raw_token: str) -> User:
        token = self._find(TokenPurpose.EMAIL_VERIFY, digest(raw_token))
        if token is None or not self._usable(token):
            raise _invalid_token()
        token.used_at = _now()
        token.user.email_verified = True
        self.db.commit()
        return token.user

    def _issue_verification(self, user: User) -> OutgoingEmail:
        self._revoke_active(user.id, TokenPurpose.EMAIL_VERIFY)
        raw = new_opaque_token()
        self.db.add(
            AuthToken(
                user_id=user.id,
                purpose=TokenPurpose.EMAIL_VERIFY,
                token_hash=digest(raw),
                expires_at=_now() + timedelta(hours=self.settings.email_verify_hours),
            )
        )
        link = f"{self.settings.public_base_url}/api/v1/auth/verify-email?{urlencode({'token': raw})}"
        return OutgoingEmail(
            to=user.email,
            subject="E-posta adresinizi doğrulayın",
            body=(
                f"Merhaba {user.display_name},\n\n"
                f"Hesabınızı etkinleştirmek için bağlantıya tıklayın:\n{link}\n\n"
                f"Bağlantı {self.settings.email_verify_hours} saat geçerlidir. "
                "Bu hesabı siz oluşturmadıysanız bu e-postayı yok sayabilirsiniz."
            ),
        )

    # ----- password reset -----
    def forgot_password(self, email: str) -> OutgoingEmail | None:
        user = self.db.scalar(select(User).where(User.email == email))
        if user is None or not user.is_active:
            return None
        self._revoke_active(user.id, TokenPurpose.PASSWORD_RESET)
        code = new_numeric_code()
        self.db.add(
            AuthToken(
                user_id=user.id,
                purpose=TokenPurpose.PASSWORD_RESET,
                token_hash=self._reset_digest(user.id, code),
                expires_at=_now() + timedelta(minutes=self.settings.password_reset_minutes),
            )
        )
        self.db.commit()
        return OutgoingEmail(
            to=user.email,
            subject="Şifre sıfırlama kodunuz",
            body=(
                f"Merhaba {user.display_name},\n\nŞifre sıfırlama kodunuz: {code}\n\n"
                f"Kod {self.settings.password_reset_minutes} dakika geçerlidir. "
                "Bu isteği siz yapmadıysanız bu e-postayı yok sayın; şifreniz değişmeyecektir."
            ),
        )

    def reset_password(self, email: str, code: str, new_password: str) -> None:
        user = self.db.scalar(select(User).where(User.email == email))
        if user is None:
            raise _invalid_token()
        token = self.db.scalar(
            select(AuthToken)
            .where(
                AuthToken.user_id == user.id,
                AuthToken.purpose == TokenPurpose.PASSWORD_RESET,
                AuthToken.used_at.is_(None),
                AuthToken.revoked_at.is_(None),
            )
            .order_by(AuthToken.id.desc())
        )
        if token is None or not self._usable(token):
            raise _invalid_token()
        if not hmac.compare_digest(token.token_hash, self._reset_digest(user.id, code)):
            token.failed_attempts += 1
            if token.failed_attempts >= self.settings.password_reset_max_attempts:
                token.revoked_at = _now()
            self.db.commit()
            raise _invalid_token()
        token.used_at = _now()
        user.password_hash = hash_password(new_password)
        # Possession of the mailbox proves ownership of the address.
        user.email_verified = True
        user.session_epoch += 1
        self.revoke_all_sessions(user.id)  # commits

    def _reset_digest(self, user_id: int, code: str) -> str:
        return keyed_digest(self.settings.secret_key, f"reset:{user_id}:{code}")

    # ----- helpers -----
    def _find(self, purpose: TokenPurpose, token_hash: str) -> AuthToken | None:
        return self.db.scalar(
            select(AuthToken).where(AuthToken.purpose == purpose, AuthToken.token_hash == token_hash)
        )

    @staticmethod
    def _usable(token: AuthToken) -> bool:
        return token.used_at is None and token.revoked_at is None and as_utc(token.expires_at) > _now()

    def _revoke_active(self, user_id: int, purpose: TokenPurpose) -> None:
        self.db.execute(
            update(AuthToken)
            .where(
                AuthToken.user_id == user_id,
                AuthToken.purpose == purpose,
                AuthToken.used_at.is_(None),
                AuthToken.revoked_at.is_(None),
            )
            .values(revoked_at=_now())
        )

    def _revoke_family(self, family_id: str | None) -> None:
        if family_id is None:
            return
        self.db.execute(
            update(AuthToken)
            .where(AuthToken.family_id == family_id, AuthToken.revoked_at.is_(None))
            .values(revoked_at=_now())
        )
