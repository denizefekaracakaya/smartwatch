# Implementation Roadmap

Execution order (dependency-aware):

```text
P0 Discovery → P1 Backend foundation → P2 Auth → P3 Catalog & streaming → P4 Playlists
   → P5 AI assistant → P6 Mobile foundation + auth UI → P7 Mobile features & player
   → P8 Integration (E2E smoke + APK) → P9 DevOps (Docker, compose, CI) → P10 Security & final audit
```

---

## P0 — Discovery & baseline
- **Objective:** Understand spec, pick architecture, set up repo hygiene.
- **Files:** `ARCHITECTURE.md`, `DECISIONS.md`, `ROADMAP.md`, `IMPLEMENTATION_STATUS.md`, `.gitignore`.
- **Acceptance:** requirements table, conflicts, decisions and phases written; git repo initialised.

## P1 — Backend foundation
- **Prereq:** P0.
- **Tasks:** `pyproject.toml` (uv), settings via `pydantic-settings`, logging, SQLAlchemy engine/session,
  app factory, error-response format `{detail, code}`, security headers, CORS, `/health`, pytest fixtures.
- **Files:** `backend/pyproject.toml`, `backend/app/{main,config,db,errors,logging_setup}.py`, `backend/tests/conftest.py`.
- **Acceptance:** app starts; `GET /health` → 200; tests run against isolated temp SQLite DB.
- **Risks:** none significant. **Dependents:** all backend phases.

## P2 — Authentication & user management
- **Tasks:** User + AuthToken models; Argon2id; JWT access; refresh rotation + reuse detection; register,
  login, refresh, logout, me, change password, verify-email (POST + GET link page), resend verification,
  forgot/reset password (6-digit code with attempt cap); rate limiting; console/SMTP e-mail senders.
- **Acceptance:** all flows tested incl. wrong password, duplicate e-mail, weak password, expired/used
  tokens, refresh reuse → family revoked, no user enumeration, rate limit → 429, hashes never plaintext.
- **Dependents:** P3–P5, P6.

## P3 — Catalog & streaming
- **Tasks:** Track model (`kind` song/podcast), storage abstraction, ingest CLI (mutagen metadata),
  demo seed (synthetic WAV), list/filter/search (rapidfuzz), stream-url + Range streaming (206/416).
- **Acceptance:** seed creates playable tracks; full and partial range requests return correct bytes;
  invalid/expired/foreign stream token → 401; path traversal impossible.

## P4 — Playlists
- **Tasks:** CRUD, add/remove/reorder items, ownership isolation.
- **Acceptance:** user A can never read/modify user B's playlist (404); positions stay contiguous.

## P5 — AI search assistant
- **Tasks:** `POST /assistant/search`; Claude manual tool loop (`search_catalog`, `submit_results`),
  iteration cap, DB-validated ids, fuzzy fallback, rate limit; tests with a fake LLM client.
- **Acceptance:** works without API key (fallback flagged); with fake client, tool loop returns hydrated
  tracks and ignores unknown ids.

## P6 — Mobile foundation & auth UI
- **Tasks:** Flutter project (Android), theme, API client with automatic refresh, secure token storage,
  auth state, login/register/forgot/reset screens, error-code → Turkish message mapping.
- **Acceptance:** `flutter analyze` clean; unit/widget tests pass.

## P7 — Mobile features & player
- **Tasks:** Home (catalog, songs/podcasts tabs), search + AI assistant, playlists list/detail/editing,
  mini-player + full player, background playback, profile (verification status, resend, logout).
- **Acceptance:** analyze clean, tests pass, debug + release APK build.

## P8 — Integration
- **Tasks:** Run backend, seed, E2E smoke script exercising the real HTTP API end-to-end
  (register → verify → login → search → stream range → playlist → assistant). Install APK on emulator if
  one can be started.
- **Acceptance:** smoke script passes against a live server; APK builds.

## P9 — DevOps
- **Tasks:** backend Dockerfile (non-root), docker-compose (api + postgres + mailpit), `.env.example`,
  GitHub Actions (backend tests/lint/security, flutter analyze/test/build).
- **Acceptance:** compose config validates; image builds if Docker daemon is available.

## P10 — Security review & final audit
- **Tasks:** `bandit`, `pip-audit`, manual review against ARCHITECTURE §7, requirement coverage table,
  README finalisation.
