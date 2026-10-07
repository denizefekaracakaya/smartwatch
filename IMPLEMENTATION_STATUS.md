# Implementation Status

```text
Phase 0  — Discovery & baseline            ✅ Complete
Phase 1  — Backend foundation              ✅ Complete
Phase 2  — Authentication & accounts       ✅ Complete
Phase 3  — Catalog & streaming             ✅ Complete
Phase 4  — Playlists                       ✅ Complete
Phase 5  — AI search assistant             ✅ Complete (live Claude call not exercised — no API key on dev machine)
Phase 6  — Mobile foundation & auth UI     ✅ Complete
Phase 7  — Mobile features & player        ✅ Complete (debug + release APK built)
Phase 8  — Integration                     ✅ Complete (HTTP smoke test + full app run on an Android 16 emulator)
Phase 9  — DevOps                          ✅ Complete (image built, full stack verified on PostgreSQL, CI jobs added)
Phase 10 — Security review & final audit   ✅ Complete (see audit below)
```

## Phase 0 — Discovery & baseline
- Only `Efetüfe.md` existed (idea stage). Requirements, conflicts and assumptions extracted into
  `ARCHITECTURE.md`; decisions in `DECISIONS.md`; phases in `ROADMAP.md`. Git repository initialised,
  `.gitignore` added.

## Phase 1 — Backend foundation
- `backend/app/{config,db,errors,deps,main}.py`: pydantic-settings config (production refuses insecure
  secret / non-HTTPS URL), SQLAlchemy 2 engine (SQLite FK pragma), uniform `{detail, code}` errors,
  security headers, optional CORS, `/health` with DB ping.
- Tests: `tests/test_health.py`.

## Phase 2 — Authentication & accounts
- `app/security.py` (Argon2id, JWT, opaque tokens, HMAC for 6-digit codes), `app/services/auth.py`,
  `app/routers/auth.py`, `app/ratelimit.py`, `app/services/email.py`.
- Register → verification link (hashed token, 48 h) → login (unverified accounts get `403 email_not_verified`)
  → 15-min access JWT + 30-day refresh token with rotation and reuse detection → logout revokes family.
- Forgot/reset password with 6-digit code (15 min, 5 attempts), reset revokes all sessions.
- Change password, rename, delete account (password-confirmed, cascades playlists).
- No user enumeration (generic login error, 202 for forgot/resend), rate limits on all auth endpoints.
- Tests: `tests/test_auth.py` (25 tests, including token invalidation after a password change or reset and the
  prefetch-safe verification link).

## Phase 3 — Catalog & streaming
- `Track` model with `kind` (song/podcast); content-addressed `LocalMediaStorage` with path-traversal guard;
  `app/services/catalog.py` ingest (mutagen tags + JSON sidecar, idempotent) and synthetic demo seed;
  `app/services/search.py` fuzzy ranking (rapidfuzz) tolerant to typos / missing Turkish characters.
- `GET /tracks/{id}/stream-url` issues a 6-hour track- and user-bound stream JWT; `/stream` serves
  `206 Partial Content` / `416` via Starlette `FileResponse`.
- Tests: `tests/test_tracks.py` (8 tests: filters, fuzzy, ranges, token binding/expiry/forgery, traversal, ingest).

## Phase 4 — Playlists
- CRUD, add (optionally at position), remove, reorder (must be a permutation), per-user limits.
  Every query is owner-scoped → other users get 404.
- Tests: `tests/test_playlists.py` (5 tests incl. cross-user isolation).

## Phase 5 — AI search assistant
- `app/services/assistant.py`: manual Claude tool loop (`search_catalog`, `submit_results`, strict schemas),
  `claude-opus-5-5` at low effort, server-side refusal fallback enabled, iteration cap 5, returned ids
  accepted only if our search produced them, fuzzy fallback on missing key / API error / refusal / no submit.
- Tests: `tests/test_assistant.py` (9 tests with a scripted fake client).
- **Limitation:** no Anthropic credentials were available, so the live API path is covered by the fake-client
  tests only.

## Phase 6 — Mobile foundation & auth UI
- Flutter project `mobile/` (Android only), `ApiClient` (typed endpoints, single-flight token refresh,
  refresh token in `flutter_secure_storage`, access token in memory), `AuthState`, Turkish error mapping.
- Screens: login, register, verify-pending (resend), forgot password, reset password.
- Tests: `test/api_client_test.dart` (7), `test/auth_screens_test.dart` (5), `test/library_state_test.dart` (3).
  `flutter analyze`: no issues.

## Phase 7 — Mobile features & player (code complete)
- Discover (songs/podcasts tabs, infinite scroll), search (fuzzy as-you-type + AI assistant mode), library,
  playlist detail (play all, remove, drag reorder, rename, delete), full player (seek, shuffle, repeat),
  mini player, profile (rename, change password, logout, delete account). Background playback via
  just_audio_background (media notification / lock screen / Bluetooth buttons).
- `AuthGate` stops playback and clears the library whenever a session ends, whether by logout, account
  deletion or a session that expired on its own.
- `flutter analyze`: no issues; `flutter test`: 18/18 pass.
- **APK:** `app-debug.apk` and `app-release.apk` (49 MB) build successfully, via `mobile/build_apk.ps1`
  (see D-010). Build fixes needed along the way:
  - Gradle heap cut to 3 GB, with HTTP timeouts for stalled downloads.
  - No `ndkVersion` pin.
  - `audio_session` pinned below 0.2 (KGP 1.8 compatibility).
  - `compileSdk` set to 36.
  - The Unicode-path workaround for the shader compiler.

## Phase 9 — DevOps
- Docker image built and the compose stack (API + PostgreSQL 17 + Mailpit) run locally:
  - Alembic migrated PostgreSQL on startup.
  - The container runs as non-root `appuser` (uid 10001), and all three services report healthy.
  - Data survived an API restart and a full `compose up` recreate.
- `scripts/smoke_test.py --base-url … --mailpit …` (remote mode, which reads e-mails through Mailpit's API)
  passes against the stack, so SMTP delivery is covered too.
- The full pytest suite also passes on PostgreSQL (`TEST_DATABASE_URL`; the database is wiped per test).
- The release APK was installed on the emulator. The server address was set in the app to the PC's LAN
  address (`192.168.1.8:8000`) and persisted across a cold restart. Registration went through the app to
  the Docker stack, and verification via the Mailpit link and login succeeded over the LAN address.
- CI now has three backend jobs (SQLite, PostgreSQL service, Docker Compose E2E) plus the Flutter job.
- `KURULUM.md`: Turkish step-by-step guide covering the server on Docker, APK install and server address.

### Post-release fix (0.1.1)
- On a real phone, the 0.1.0 release APK logged in fine but showed "Parça yüklenemedi" for every track.
  The emulator reproduced it with the release APK: R8 optimisation broke just_audio's renderer (an NPE
  inside ExoPlayer). Fixed with keep rules (DECISIONS D-016). Release 0.1.1 was verified on the emulator:
  song and podcast playback, and an upgrade install from 0.1.0.
- Player errors are now also written to the log (`adb logcat -s flutter`) with ExoPlayer's code/message.
- Lesson: release-mode playback must be tested on a device before publishing; the debug-build E2E run
  could not catch minification issues.

### Real-device verification (0.1.2 → 0.1.3)
- Tested on a Samsung Galaxy A56 (SM-A566B, Android 16) over ADB:
  - Release-signed 0.1.2 installed and played tracks.
  - 0.1.3 installed as an in-place upgrade; the session was kept and playback works both through
    `adb reverse` (server `127.0.0.1:8000`) and over Wi-Fi (`192.168.1.8:8000`).
- 0.1.3: the app fetches audio from the server address it is configured with, not the host the server
  advertises in `APP_PUBLIC_BASE_URL`. A changed DHCP address, `adb reverse` or a proxy can no longer break
  playback while login works.

### Real music and Spotify playlists
- Real audio comes from the operator's own files: `scripts/add_music.ps1` → `app.cli ingest`. Tags are
  used when present, otherwise the artist and title are guessed from the file name ("03 - Artist - Title
  (Official Audio)").
- `app.cli import-playlists` imports Spotify playlists as metadata, from the account-data export JSON, an
  Exportify CSV, or a playlist URL via the Web API. Tracks are matched to the catalog and the rest are
  reported to a CSV (`scripts/import_playlists.ps1` writes `eksik-sarkilar.csv`). No audio is downloaded
  from Spotify or YouTube (DECISIONS D-019).
- Tests: `tests/test_playlist_import.py` (7). Verified against the Docker/PostgreSQL stack with a sample
  folder and a sample `Playlist1.json`: 2/3 tracks matched, the playlist was created, and the missing track
  was written to the CSV. Re-running added nothing twice. The test data was removed from the server
  afterwards.
- The Spotify Web API path is tested against a mocked HTTP transport only; no Spotify credentials were
  available.

## Phase 8 — Integration
- `backend/scripts/smoke_test.py` starts uvicorn and runs the full journey over real HTTP. It passes.
- Manual end-to-end run of the debug APK on an Android 16 (API 36) emulator against a local backend
  (`APP_PUBLIC_BASE_URL=http://10.0.2.2:8000`). Each step was checked with screenshots and with the
  server's access log:
  - register → verification link (GET page + POST confirm) → login;
  - catalog browsing → streaming playback, with auto-advance through the queue;
  - media session and notification active (`dumpsys media_session` / `notification`);
  - AI assistant mode (fuzzy fallback without a key);
  - add to a new playlist from the sheet → library → playlist playback;
  - full player: seek to the end, replay;
  - session restored after an app restart;
  - logout: server-side revocation, playback stops;
  - forgot password: 6-digit code → reset → login with the new password.
- Bugs found and fixed during that run:
  - The hidden search field kept focus in the `IndexedStack`, so the keyboard popped up over other tabs.
    Tab switches now unfocus.
  - The playlist screen had no mini player.
  - After the queue finished, the UI still showed "pause" and the play button did nothing. It now shows
    "play" and replays the queue.
  - The player repeated the album when album == artist (podcasts).
  - Enter in the multi-line assistant field inserted a newline instead of asking.
  - Search ranking: "sabah rutini podcast" ranked a song first, because one shared word in its description
    scored 100. Ranking now combines whole-string matching with per-word coverage across fields, folds
    Turkish characters (ruzgari ≈ Rüzgarı) and matches typing prefixes.

## Open items / known limitations
1. ~~Verify the APK and run it on an emulator.~~ Done (Phase 7/8).
2. ~~Docker image / PostgreSQL untested.~~ Done (Phase 9).
3. ~~Access JWTs stay valid after a password change or reset.~~ Fixed: `User.session_epoch` is embedded
   in access and stream tokens (`ep` claim) and is bumped on password change/reset, which invalidates all
   outstanding tokens. A plain logout still leaves the current access token valid for up to 15 minutes.
   Development databases created before the switch to Alembic (D-015) must be recreated once.
4. The live Claude API path has not been tested (no API key on this machine).
5. Registration returns 409 for an existing e-mail, so the endpoint reveals whether an account exists.
   This is an accepted UX trade-off and the endpoint is rate limited.
6. The rate limiter keeps state in process memory, so it works for a single API instance only.
7. ~~No migrations; the verification GET link could be consumed by prefetching mail scanners.~~ Fixed:
   Alembic migrations (D-015), and the verification link now needs an explicit POST confirmation.

## Phase 10 — Security review & final audit

Automated checks, all passing: `ruff check`, `ruff format --check`, `bandit -r app migrations`,
`pip-audit` (no known vulnerabilities), backend `pytest` (50 tests), `scripts/smoke_test.py` (live HTTP),
`flutter analyze`, `flutter test` (18 tests).

The manual review against ARCHITECTURE §7 found and fixed three issues:
- concurrent refreshes could both rotate one refresh token; the token is now claimed with an atomic UPDATE;
- outstanding JWTs survived a password change or reset; fixed with the session epoch (D-014);
- link-prefetching mail scanners could consume the verification token; fixed with POST confirmation.

### Requirement coverage

| Requirement (Efetüfe.md) | Implemented? | Evidence | Notes |
|---|---|---|---|
| F1 Cloud streaming, no files on device | ✅ | `routers/tracks.py` stream-url + HTTP Range; `PlaybackController` streams URLs | `test_stream_full_and_range`, smoke test |
| F2 Personal playlists (create/edit/manage) | ✅ | `routers/playlists.py`; library + playlist screens | CRUD, add/remove, drag reorder |
| F3 AI search assistant (songs + podcasts) | ✅ / ⚠️ | `services/assistant.py`; "AI asistan" mode in search | Live Claude call not exercised (no API key); fuzzy fallback verified |
| F4 Simple, modern UI | ✅ | Material 3 dark theme, 4-tab shell, mini player | Turkish UI |
| F5 Isolated personal profiles | ✅ | owner-scoped queries | `test_playlists_are_isolated_between_users` |
| F6 Login / Register | ✅ | `routers/auth.py`; login/register screens | |
| F7 E-mail verification | ✅ | link + confirm page, resend | login blocked until verified |
| F8 Password reset | ✅ | 6-digit code, 5-attempt cap, revokes sessions | |
| N1 Strong hashing, no plain text | ✅ | Argon2id; SHA-256 / HMAC for stored tokens | `test_register_stores_argon2_hash…` |
| N2 Strict security standards | ✅ | ARCHITECTURE §7 controls, rate limits, headers, bandit/pip-audit in CI | |
| N3 Android APK MVP | ✅ | `app-release.apk` built and published on GitHub Releases; emulator runs (debug + release) | test build allows LAN HTTP and is signed with the debug key; production needs HTTPS + a real signing key |
| N4 Low device storage | ✅ | streaming only; no download feature | |
| Future: watch, CarPlay/Auto, Bluetooth, Chromecast, TV | ➖ Intentionally omitted | spec marks them as future | media session via `audio_service` already handles Bluetooth media buttons |

### Remaining technical debt / future work
- Playing from a list requests one stream URL per queued track (up to 100); a batch `stream-urls` endpoint
  or lazy URL fetching would cut the request count.
- uvicorn's default access log records stream URLs including the stream token (the Docker image runs with
  `--no-access-log`); a custom log filter would be needed if access logs are enabled in production.
- Rate limiting backed by Redis for multi-instance deployments; object storage (S3/GCS) behind `LocalMediaStorage`.
- Vector/lyrics search for large catalogs; deep links for verification; offline downloads (explicitly not MVP).
