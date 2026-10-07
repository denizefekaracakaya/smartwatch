"""Catalog search: SQL filtering plus fuzzy ranking (typo- and word-order tolerant)."""

from dataclasses import dataclass

from rapidfuzz import fuzz, utils
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import Track, TrackKind

MIN_SCORE = 60.0
# Whole-string fuzzy match on short fields catches typos in a full title/artist ("midnite train").
_WHOLE_FIELDS = (("title", 1.0), ("artist", 0.95), ("album", 0.8))
# Per-word coverage across all fields ranks multi-word descriptions ("sabah rutini podcast").
_TOKEN_FIELDS = (("title", 1.0), ("artist", 1.0), ("album", 1.0), ("genre", 0.8), ("description", 0.8))
_TOKEN_MATCH = 80.0
_KIND_WORDS = {TrackKind.SONG: "sarki song muzik music", TrackKind.PODCAST: "podcast bolum episode"}
_FOLD = str.maketrans("çğıöşüâîû", "cgiosuaiu")


def normalise(text: str) -> str:
    """Lower-case and fold Turkish diacritics so "ruzgari" matches "Rüzgarı"."""
    return utils.default_process(text.replace("İ", "i").replace("I", "ı").lower().translate(_FOLD))


@dataclass
class ScoredTrack:
    track: Track
    score: float


def _token_matches(query_token: str, field_tokens: list[str]) -> bool:
    for token in field_tokens:
        if len(query_token) >= 3 and token.startswith(query_token):  # as-you-type prefixes
            return True
        if fuzz.ratio(query_token, token) >= _TOKEN_MATCH:
            return True
    return False


def _score(query: str, track: Track) -> float:
    q = normalise(query)
    best = 0.0
    for field, weight in _WHOLE_FIELDS:
        value = getattr(track, field)
        if value:
            best = max(best, fuzz.WRatio(q, normalise(value)) * weight)

    query_tokens = q.split()
    if not query_tokens:
        return best
    fields = [(normalise(getattr(track, f) or "").split(), w) for f, w in _TOKEN_FIELDS]
    fields.append((_KIND_WORDS[track.kind].split(), 0.8))
    covered = 0.0
    for qt in query_tokens:
        covered += max((w for tokens, w in fields if _token_matches(qt, tokens)), default=0.0)
    return max(best, 100.0 * covered / len(query_tokens))


def fuzzy_search(
    db: Session, query: str, kind: TrackKind | None = None, limit: int = 20, min_score: float = MIN_SCORE
) -> list[ScoredTrack]:
    """Rank the (optionally kind-filtered) catalog against ``query``.

    Loads the catalog into memory, which is fine for MVP-sized catalogs (≈ tens of thousands of rows);
    a full-text/vector index is the scaling path (see ARCHITECTURE risks).
    """
    stmt = select(Track)
    if kind is not None:
        stmt = stmt.where(Track.kind == kind)
    scored = [ScoredTrack(t, _score(query, t)) for t in db.scalars(stmt)]
    scored = [s for s in scored if s.score >= min_score]
    scored.sort(key=lambda s: (-s.score, s.track.id))
    return scored[:limit]


def list_tracks(
    db: Session,
    query: str | None,
    kind: TrackKind | None,
    genre: str | None,
    limit: int,
    offset: int,
) -> tuple[list[Track], int]:
    if query:
        results = [s.track for s in fuzzy_search(db, query, kind, limit=500)]
        if genre:
            results = [t for t in results if (t.genre or "").lower() == genre.lower()]
        return results[offset : offset + limit], len(results)

    stmt = select(Track)
    if kind is not None:
        stmt = stmt.where(Track.kind == kind)
    if genre:
        stmt = stmt.where(func.lower(Track.genre) == genre.lower())
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    rows = db.scalars(stmt.order_by(Track.created_at.desc(), Track.id.desc()).limit(limit).offset(offset))
    return list(rows), total
