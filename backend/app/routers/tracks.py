"""Catalog browsing, search and audio streaming."""

from datetime import timedelta
from typing import Annotated
from urllib.parse import urlencode

from fastapi import APIRouter, Query, Request, status
from fastapi.responses import FileResponse

from app.deps import CurrentUser, DbDep, SettingsDep
from app.errors import ApiError, not_found
from app.models import Track, TrackKind, User
from app.schemas import StreamUrlOut, TrackOut, TrackPage
from app.security import create_jwt, decode_jwt
from app.services.search import list_tracks
from app.services.storage import LocalMediaStorage, UnsafePathError

router = APIRouter(prefix="/tracks", tags=["tracks"])


@router.get("", response_model=TrackPage)
def browse(
    _: CurrentUser,
    db: DbDep,
    q: Annotated[str | None, Query(max_length=200)] = None,
    kind: TrackKind | None = None,
    genre: Annotated[str | None, Query(max_length=80)] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    items, total = list_tracks(db, (q or "").strip() or None, kind, genre, limit, offset)
    return TrackPage(
        items=[TrackOut.model_validate(t) for t in items], total=total, limit=limit, offset=offset
    )


@router.get("/{track_id}", response_model=TrackOut)
def get_track(track_id: int, _: CurrentUser, db: DbDep):
    track = db.get(Track, track_id)
    if track is None:
        raise not_found("Track")
    return track


@router.get("/{track_id}/stream-url", response_model=StreamUrlOut)
def stream_url(track_id: int, user: CurrentUser, db: DbDep, settings: SettingsDep):
    track = db.get(Track, track_id)
    if track is None:
        raise not_found("Track")
    ttl = timedelta(hours=settings.stream_token_hours)
    token = create_jwt(settings.secret_key, user.id, "stream", ttl, tid=track.id, ep=user.session_epoch)
    url = f"{settings.public_base_url}/api/v1/tracks/{track.id}/stream?{urlencode({'token': token})}"
    return StreamUrlOut(url=url, expires_in=int(ttl.total_seconds()), mime_type=track.mime_type)


@router.get("/{track_id}/stream", response_class=FileResponse)
def stream(
    track_id: int,
    request: Request,
    db: DbDep,
    settings: SettingsDep,
    token: Annotated[str, Query(min_length=1, max_length=2000)],
):
    """Serve audio with HTTP Range support (206 Partial Content) so players can seek and buffer."""
    payload = decode_jwt(settings.secret_key, token, "stream")
    if payload is None or payload.get("tid") != track_id:
        raise ApiError(status.HTTP_401_UNAUTHORIZED, "invalid_token", "Invalid or expired stream token")
    user = db.get(User, int(payload["sub"]))
    track = db.get(Track, track_id)
    if user is None or not user.is_active or payload.get("ep") != user.session_epoch:
        raise ApiError(status.HTTP_401_UNAUTHORIZED, "invalid_token", "Invalid or expired stream token")
    if track is None:
        raise not_found("Track")
    try:
        path = LocalMediaStorage(settings.media_dir).resolve(track.file_path)
    except UnsafePathError:
        raise not_found("Track") from None
    if not path.is_file():
        raise not_found("Audio file")
    return FileResponse(
        path,
        media_type=track.mime_type,
        headers={"Cache-Control": "private, max-age=3600"},
    )
