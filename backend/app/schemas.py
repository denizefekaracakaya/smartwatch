"""Pydantic request/response schemas."""

import re
from datetime import datetime
from typing import Annotated

from pydantic import AfterValidator, BaseModel, ConfigDict, EmailStr, Field, StringConstraints

from app.models import TrackKind


def _normalise_email(value: str) -> str:
    return value.strip().lower()


def _check_password_strength(value: str) -> str:
    if not re.search(r"[A-Za-z]", value) or not re.search(r"\d", value):
        raise ValueError("Password must contain at least one letter and one digit")
    return value


Email = Annotated[EmailStr, AfterValidator(_normalise_email)]
NewPassword = Annotated[str, Field(min_length=10, max_length=128), AfterValidator(_check_password_strength)]
AnyPassword = Annotated[str, Field(min_length=1, max_length=128)]
DisplayName = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=80)]


# ---------- auth ----------
class RegisterRequest(BaseModel):
    email: Email
    password: NewPassword
    display_name: DisplayName


class LoginRequest(BaseModel):
    email: Email
    password: AnyPassword


class RefreshRequest(BaseModel):
    refresh_token: Annotated[str, Field(min_length=1, max_length=200)]


class EmailRequest(BaseModel):
    email: Email


class VerifyEmailRequest(BaseModel):
    token: Annotated[str, Field(min_length=1, max_length=200)]


class ResetPasswordRequest(BaseModel):
    email: Email
    code: Annotated[str, Field(pattern=r"^\d{6}$")]
    new_password: NewPassword


class ChangePasswordRequest(BaseModel):
    current_password: AnyPassword
    new_password: NewPassword


class DeleteAccountRequest(BaseModel):
    password: AnyPassword


class UpdateProfileRequest(BaseModel):
    display_name: DisplayName


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    email: str
    display_name: str
    email_verified: bool
    created_at: datetime


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"  # noqa: S105
    expires_in: int
    user: UserOut


class MessageOut(BaseModel):
    detail: str


# ---------- catalog ----------
class TrackOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    kind: TrackKind
    title: str
    artist: str
    album: str | None
    genre: str | None
    year: int | None
    duration_seconds: int
    description: str | None


class TrackPage(BaseModel):
    items: list[TrackOut]
    total: int
    limit: int
    offset: int


class StreamUrlOut(BaseModel):
    url: str
    expires_in: int
    mime_type: str


# ---------- playlists ----------
PlaylistName = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)]
PlaylistDescription = Annotated[str, StringConstraints(strip_whitespace=True, max_length=500)]


class PlaylistCreate(BaseModel):
    name: PlaylistName
    description: PlaylistDescription | None = None


class PlaylistUpdate(BaseModel):
    name: PlaylistName | None = None
    description: PlaylistDescription | None = None


class PlaylistAddTrack(BaseModel):
    track_id: int
    position: Annotated[int, Field(ge=0)] | None = None


class PlaylistReorder(BaseModel):
    track_ids: Annotated[list[int], Field(max_length=5000)]


class PlaylistSummary(BaseModel):
    id: int
    name: str
    description: str | None
    track_count: int
    updated_at: datetime


class PlaylistDetail(PlaylistSummary):
    tracks: list[TrackOut]


# ---------- assistant ----------
class AssistantRequest(BaseModel):
    query: Annotated[str, StringConstraints(strip_whitespace=True, min_length=2, max_length=500)]
    kind: TrackKind | None = None


class AssistantMatch(BaseModel):
    track: TrackOut
    reason: str | None = None


class AssistantResponse(BaseModel):
    matches: list[AssistantMatch]
    message: str
    ai_used: bool
