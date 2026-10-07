# Architecture & Project Analysis

Source specification: [`Efetüfe.md`](Efetüfe.md) (the only document in the repository at project start;
status `fikir-asamasi` / idea stage, no code existed).

## 1. Project overview

**Purpose.** A Spotify-style, cloud-based music & podcast platform. Users do not keep MP3 files on their
device; audio is streamed on demand from a remote server.

**Target users.** Listeners on Android phones (MVP), later smartwatches, cars, TVs, Chromecast.

**Expected result (MVP).** An Android APK that talks to a backend API where a user can register, verify their
e‑mail, log in, browse/search a catalog, stream tracks, manage personal playlists, and ask an AI assistant
to find a song/podcast they only vaguely remember.

## 2. Requirements extracted from the spec

### Functional
| ID | Requirement (spec section) |
|----|----------------------------|
| F1 | Stream audio from the server without storing files on the device (Temel Özellikler) |
| F2 | Create, edit, delete and manage personal playlists |
| F3 | AI search assistant that finds songs/podcasts from vague descriptions |
| F4 | Simple, modern, intuitive UI |
| F5 | Personal profile; each user sees only their own data/playlists (isolation) |
| F6 | Login / Register |
| F7 | E‑mail verification |
| F8 | Password reset |
| F9 | Catalog contains both songs and podcasts (implied by F3) |

### Non‑functional
| ID | Requirement |
|----|-------------|
| N1 | Passwords and login credentials are stored hashed with strong algorithms, never plain text |
| N2 | Strict security standards in app and API ("Güvenlik Açığı Kontrolü") |
| N3 | MVP platform: Android, distributed as APK |
| N4 | Low device storage use (streaming, no full downloads) |

### Out of MVP scope (spec: "Gelecek Entegrasyonlar")
Smartwatch app, Android Auto / CarPlay, advanced Bluetooth management, Chromecast, Android TV.
The architecture keeps these possible (media session via `audio_service`, see D‑008) but does not build them.

## 3. Documentation conflicts & ambiguities

```text
Issue: "Songs are pulled instantly from the remote server (database)"
Conflicting information: Suggests audio blobs live in the database.
Impact: Storing large audio blobs in a relational DB hurts performance, backups and HTTP range streaming.
Chosen interpretation: Metadata lives in the DB; audio files live in server-side file storage behind a
  storage abstraction (local disk now, object storage later). The client never stores files.
Reason: Same user-visible behaviour, standard and scalable design.

Issue: "Hashing of passwords and login documents (giriş belgeleri)"
Conflicting information: "login documents" is undefined.
Chosen interpretation: Passwords → Argon2id. All bearer secrets persisted server-side (refresh tokens,
  e-mail verification tokens, password reset tokens) → stored only as SHA-256 digests.
Reason: Covers every credential the server persists.

Issue: AI assistant searches "songs or podcasts", but core features only mention songs.
Chosen interpretation: Catalog items have a `kind` ∈ {song, podcast}.

Issue: "Güvenlik Açığı Kontrolü" (vulnerability control) is not specific.
Chosen interpretation: OWASP ASVS-style controls (see §7) + automated `bandit` / `pip-audit` checks.

Issue: Catalog source / licensing is not specified.
Chosen interpretation: Operators ingest audio they are licensed to distribute via a CLI. A demo seed
  generates synthetic audio so the system is testable without copyrighted material.
```

## 4. Architecture

```text
┌──────────────────────── Android app (Flutter) ────────────────────────┐
│ Screens: auth · library · search/AI · playlists · player · profile    │
│ State: provider/ChangeNotifier  · Storage: flutter_secure_storage     │
│ Audio: just_audio (+ just_audio_background → media session/notif.)    │
└───────────────┬───────────────────────────────────────────────────────┘
                │ HTTPS JSON (Bearer access token)  · HTTP Range audio (stream token)
┌───────────────▼──────────────────── Backend (FastAPI) ────────────────┐
│ routers: auth · users · tracks · playlists · assistant · health      │
│ services: security (argon2, JWT) · email · storage · search · AI      │
│ SQLAlchemy 2 ORM ── SQLite (dev/test) │ PostgreSQL (docker/prod)       │
│ Audio files: MEDIA_DIR (local disk; abstraction for object storage)    │
└───────────────┬───────────────────────────────────────────────────────┘
                │ (optional)                        │ SMTP (Mailpit in dev)
        Anthropic Claude API                        ▼
        (AI assistant; fuzzy fallback without key)
```

### Components
| Component | Responsibility |
|-----------|----------------|
| `backend/app/core` | settings, logging, DB session, security primitives, rate limiting |
| `backend/app/models.py` | ORM: User, AuthToken (refresh/verify/reset), Track, Playlist, PlaylistItem |
| `backend/app/routers/*` | HTTP layer, validation (Pydantic), authorization |
| `backend/app/services/*` | e-mail delivery, media storage, catalog search, AI assistant |
| `backend/app/cli.py` | DB init, catalog ingest from a folder, demo seed |
| `mobile/` | Flutter Android client |

### Data flow
```text
Register → validate → Argon2id hash → store user → e-mail verification token (hashed) → mail
Login → rate limit → verify hash → access JWT (15 min) + refresh token (30 d, hashed, rotated)
Browse/search → JWT auth → SQL filter + rapidfuzz ranking → JSON
Play → GET /tracks/{id}/stream-url → short-lived stream JWT → player requests audio with Range → 206 chunks
Playlist ops → JWT auth → ownership check → DB
AI search → JWT auth + rate limit → Claude tool loop (search_catalog tool over OUR catalog) → ranked ids
            → hydrated from DB (no hallucinated tracks can be returned)
```

## 5. Key technology choices
See [DECISIONS.md](DECISIONS.md) for full rationale (Flutter, FastAPI, SQLite/Postgres, Argon2id, JWT +
rotating refresh tokens, stream tokens, Claude tool loop with fuzzy fallback).

## 6. Risks
| Risk | Mitigation |
|------|------------|
| JWT on audio requests expires mid-playback | Separate long-lived (6 h), track-scoped stream token |
| LLM unavailable / no API key / invents songs | Fuzzy-search fallback; results are always hydrated from DB ids |
| Non-ASCII project path breaks Android Gradle on Windows | `android.overridePathCheck=true` (see D‑010) |
| In-memory rate limiter does not span multiple instances | Documented; swap for Redis when scaling out |
| Schema drift between models and DB | Alembic migrations + a test that fails on un-migrated model changes |
| Cleartext HTTP in local dev | Allowed only in debug builds; release builds require HTTPS |

## 7. Security controls
- Argon2id password hashing (argon2-cffi defaults, auto-rehash on login when parameters change).
- Password policy: ≥ 10 chars, letters + digits, max 128.
- Generic login errors; forgot-password and resend-verification never reveal whether an e-mail exists.
- Refresh token rotation with reuse detection (reuse revokes the whole token family).
- Password change/reset revokes all refresh tokens and, via the session epoch, every outstanding access/stream JWT.
- All one-time tokens stored as SHA-256 digests, single use, expiring; the e-mail link needs an explicit
  POST confirmation so link-prefetching scanners cannot consume it.
- Per-IP/per-account rate limiting on auth and AI endpoints.
- Object-level authorization on playlists (404 for other users' playlists, no existence leak).
- Path traversal-safe media resolution; Range header validation.
- Security headers, configurable CORS, no secrets in code (`.env`), startup refuses default secret in prod.
- Request size limits via Pydantic field constraints; AI prompt length capped.
