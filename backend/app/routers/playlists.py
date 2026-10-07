"""Personal playlists. Every query is scoped to the current user (other users' playlists → 404)."""

from fastapi import APIRouter, Response, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.deps import CurrentUser, DbDep
from app.errors import ApiError, not_found
from app.models import Playlist, PlaylistItem, Track, User, utcnow
from app.schemas import (
    PlaylistAddTrack,
    PlaylistCreate,
    PlaylistDetail,
    PlaylistReorder,
    PlaylistSummary,
    PlaylistUpdate,
    TrackOut,
)

router = APIRouter(prefix="/playlists", tags=["playlists"])

MAX_PLAYLISTS_PER_USER = 500
MAX_TRACKS_PER_PLAYLIST = 5000


def _owned(db: Session, user: User, playlist_id: int) -> Playlist:
    playlist = db.scalar(select(Playlist).where(Playlist.id == playlist_id, Playlist.owner_id == user.id))
    if playlist is None:
        raise not_found("Playlist")
    return playlist


def _detail(p: Playlist) -> PlaylistDetail:
    return PlaylistDetail(
        id=p.id,
        name=p.name,
        description=p.description,
        track_count=len(p.items),
        updated_at=p.updated_at,
        tracks=[TrackOut.model_validate(item.track) for item in p.items],
    )


def _renumber(p: Playlist) -> None:
    for index, item in enumerate(p.items):
        item.position = index
    p.updated_at = utcnow()


@router.get("", response_model=list[PlaylistSummary])
def list_playlists(user: CurrentUser, db: DbDep):
    counts = (
        select(PlaylistItem.playlist_id, func.count(PlaylistItem.id).label("n"))
        .group_by(PlaylistItem.playlist_id)
        .subquery()
    )
    rows = db.execute(
        select(Playlist, func.coalesce(counts.c.n, 0))
        .outerjoin(counts, counts.c.playlist_id == Playlist.id)
        .where(Playlist.owner_id == user.id)
        .order_by(Playlist.updated_at.desc(), Playlist.id.desc())
    )
    return [
        PlaylistSummary(
            id=p.id, name=p.name, description=p.description, track_count=n, updated_at=p.updated_at
        )
        for p, n in rows
    ]


@router.post("", status_code=status.HTTP_201_CREATED, response_model=PlaylistDetail)
def create_playlist(body: PlaylistCreate, user: CurrentUser, db: DbDep):
    count = db.scalar(select(func.count(Playlist.id)).where(Playlist.owner_id == user.id)) or 0
    if count >= MAX_PLAYLISTS_PER_USER:
        raise ApiError(status.HTTP_409_CONFLICT, "limit_reached", "Playlist limit reached")
    playlist = Playlist(owner_id=user.id, name=body.name, description=body.description or None)
    db.add(playlist)
    db.commit()
    db.refresh(playlist)
    return _detail(playlist)


@router.get("/{playlist_id}", response_model=PlaylistDetail)
def get_playlist(playlist_id: int, user: CurrentUser, db: DbDep):
    return _detail(_owned(db, user, playlist_id))


@router.patch("/{playlist_id}", response_model=PlaylistDetail)
def update_playlist(playlist_id: int, body: PlaylistUpdate, user: CurrentUser, db: DbDep):
    playlist = _owned(db, user, playlist_id)
    fields = body.model_fields_set
    if "name" in fields:
        if body.name is None:
            raise ApiError(status.HTTP_422_UNPROCESSABLE_CONTENT, "validation_error", "Name cannot be empty")
        playlist.name = body.name
    if "description" in fields:
        playlist.description = body.description or None
    playlist.updated_at = utcnow()
    db.commit()
    return _detail(playlist)


@router.delete("/{playlist_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_playlist(playlist_id: int, user: CurrentUser, db: DbDep) -> Response:
    db.delete(_owned(db, user, playlist_id))
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/{playlist_id}/tracks", status_code=status.HTTP_201_CREATED, response_model=PlaylistDetail)
def add_track(playlist_id: int, body: PlaylistAddTrack, user: CurrentUser, db: DbDep):
    playlist = _owned(db, user, playlist_id)
    if db.get(Track, body.track_id) is None:
        raise not_found("Track")
    if any(item.track_id == body.track_id for item in playlist.items):
        raise ApiError(status.HTTP_409_CONFLICT, "already_in_playlist", "Track is already in this playlist")
    if len(playlist.items) >= MAX_TRACKS_PER_PLAYLIST:
        raise ApiError(status.HTTP_409_CONFLICT, "limit_reached", "Playlist is full")
    position = len(playlist.items) if body.position is None else min(body.position, len(playlist.items))
    playlist.items.insert(position, PlaylistItem(track_id=body.track_id, position=position))
    _renumber(playlist)
    db.commit()
    db.refresh(playlist)
    return _detail(playlist)


@router.delete("/{playlist_id}/tracks/{track_id}", response_model=PlaylistDetail)
def remove_track(playlist_id: int, track_id: int, user: CurrentUser, db: DbDep):
    playlist = _owned(db, user, playlist_id)
    item = next((i for i in playlist.items if i.track_id == track_id), None)
    if item is None:
        raise not_found("Track in playlist")
    playlist.items.remove(item)
    _renumber(playlist)
    db.commit()
    db.refresh(playlist)
    return _detail(playlist)


@router.put("/{playlist_id}/tracks", response_model=PlaylistDetail)
def reorder_tracks(playlist_id: int, body: PlaylistReorder, user: CurrentUser, db: DbDep):
    """Reorder: ``track_ids`` must be a permutation of the playlist's current tracks."""
    playlist = _owned(db, user, playlist_id)
    by_track = {item.track_id: item for item in playlist.items}
    if sorted(body.track_ids) != sorted(by_track):
        raise ApiError(
            status.HTTP_422_UNPROCESSABLE_CONTENT,
            "validation_error",
            "track_ids must contain exactly the playlist's current tracks",
        )
    for index, track_id in enumerate(body.track_ids):
        by_track[track_id].position = index
    playlist.updated_at = utcnow()
    db.commit()
    db.expire(playlist, ["items"])
    return _detail(playlist)
