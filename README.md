# Efetüfe — cloud music & podcast streaming

Implementation of the idea in [`Efetüfe.md`](Efetüfe.md): an Android app that streams songs and podcasts
from a server (no files stored on the phone), with personal playlists, a full login/registration flow
(Argon2id hashing, e-mail verification, password reset) and an AI assistant that finds tracks you only
half-remember.

| Path | What |
|------|------|
| `backend/` | FastAPI + SQLAlchemy API (auth, catalog, range streaming, playlists, AI assistant) |
| `mobile/` | Flutter Android app (APK) |
| `ARCHITECTURE.md` | requirements analysis, architecture, data flow, security controls |
| `DECISIONS.md` | engineering decision log |
| `ROADMAP.md` / `IMPLEMENTATION_STATUS.md` | phase plan and current status |
| [`KURULUM.md`](KURULUM.md) | step-by-step guide (Turkish): run the server with Docker, install the APK on a phone |

## Quick start (local)

### 1. Backend
Requires Python 3.12 and [uv](https://docs.astral.sh/uv/).

```bash
cd backend
cp .env.example .env            # then set APP_SECRET_KEY (python -c "import secrets;print(secrets.token_urlsafe(48))")
uv sync
uv run python -m app.cli seed-demo          # 16 fictional demo tracks with synthetic audio
uv run uvicorn app.main:create_app --factory --host 0.0.0.0 --port 8000
```

- API docs: http://localhost:8000/docs · health: `GET /health`
- With `APP_EMAIL_BACKEND=console` the verification link and reset code are **printed in the server log**.
  Open the link and press the button to verify.
- The schema is migrated automatically on startup (Alembic). After changing models:
  `uv run alembic revision --autogenerate -m "..."`.
- Import your own (licensed) audio: `uv run python -m app.cli ingest <folder> [--kind podcast]`.
  Tags are read with mutagen; an optional `<file>.json` sidecar can set `title`, `artist`, `album`,
  `genre`, `year`, `description`, `kind`. The `description` (lyrics excerpt, episode summary…) is what the
  AI assistant searches.
- AI assistant: set `ANTHROPIC_API_KEY` to enable Claude (`claude-opus-5-5`). Without it, the assistant
  endpoint falls back to fuzzy search and says so in its response (`ai_used: false`).

### Full stack with Docker (PostgreSQL + Mailpit)
Create a `.env` file in the project root once (docker compose reads it; it is git-ignored):
```bash
echo "APP_SECRET_KEY=$(python -c 'import secrets;print(secrets.token_urlsafe(48))')" > .env
echo "APP_PUBLIC_BASE_URL=http://<your-pc-lan-ip>:8000" >> .env   # the address phones use
docker compose up -d --build
docker compose exec api python -m app.cli seed-demo
uv --directory backend run python scripts/smoke_test.py --base-url http://localhost:8000   # optional E2E check
```
Verification / reset e-mails are visible at http://localhost:8025 (Mailpit). The API container runs
migrations on startup, as a non-root user, with a health check; data lives in the `pgdata` and `media`
volumes.

### 2. Mobile app
Requires Flutter 3.29+ and the Android SDK.

```bash
cd mobile
flutter pub get
# Emulator talking to the backend on your PC (default base URL http://10.0.2.2:8000):
flutter run
# Physical phone on the same Wi-Fi (debug build allows plain HTTP):
flutter run --dart-define=API_BASE_URL=http://<your-pc-ip>:8000
```
The server address can also be changed **inside the app** (login screen → "Sunucu: …"); it is stored on
the device, so one APK works with any backend. Set `APP_PUBLIC_BASE_URL` on the backend to the same
address the phone uses — stream and e-mail links are built from it.

**Ready-made APK:** download it from the repository's
[Releases](https://github.com/denizefekaracakaya/smartwatch/releases/latest) page — see
[`KURULUM.md`](KURULUM.md) for installing it on a phone.

**APK**

The project folder name contains "ü", and Flutter's shader compiler cannot write to non-ASCII paths on
Windows. `build_apk.ps1` maps the folder to a temporary drive letter, builds, and removes the mapping:
```powershell
cd mobile
.\build_apk.ps1 -- --dart-define=API_BASE_URL=https://api.your-domain
# Test APK for a plain-HTTP LAN server:
$env:ALLOW_CLEARTEXT="true"; .\build_apk.ps1 -- --dart-define=API_BASE_URL=http://192.168.1.20:8000
.\build_apk.ps1 -Mode debug        # debug APK (plain HTTP always allowed)
```
On macOS/Linux, or from an ASCII path, plain `flutter build apk --release` works.
Output: `mobile/build/app/outputs/flutter-apk/app-release.apk`. Release builds are signed with the key
referenced by `android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`; git-ignored),
otherwise with the debug key. The project's release key and the matching GitHub Actions secrets are
described in DECISIONS D-018. Pushing a `v*` tag builds a release-signed APK in CI (`release.yml`) and
attaches it to a GitHub release.

## Tests & checks
```bash
cd backend && uv run pytest && uv run python scripts/smoke_test.py   # unit/API tests + live E2E over HTTP
TEST_DATABASE_URL=postgresql+psycopg://user:pw@localhost:5432/test uv run pytest   # same suite on PostgreSQL
cd backend && uv run ruff check . && uv run bandit -q -r app && uv run pip-audit
cd mobile  && flutter analyze && flutter test
```
CI runs all of these (`.github/workflows/ci.yml`): SQLite and PostgreSQL test runs, a Docker Compose end-to-end job (image build → stack up → seed → smoke test with Mailpit), and the Flutter build, which uploads the APK as an artifact.

## API overview (`/api/v1`)
| Area | Endpoints |
|------|-----------|
| Auth | `POST auth/register`, `POST auth/login`, `POST auth/refresh`, `POST auth/logout`, `POST auth/verify-email` (app), `GET auth/verify-email` + `POST auth/verify-email/confirm` (mail link), `POST auth/resend-verification`, `POST auth/forgot-password`, `POST auth/reset-password` |
| Account | `GET/PATCH/DELETE auth/me`, `POST auth/me/change-password` |
| Catalog | `GET tracks?q=&kind=&genre=&limit=&offset=`, `GET tracks/{id}`, `GET tracks/{id}/stream-url`, `GET tracks/{id}/stream?token=` (HTTP Range) |
| Playlists | `GET/POST playlists`, `GET/PATCH/DELETE playlists/{id}`, `POST playlists/{id}/tracks`, `PUT playlists/{id}/tracks` (reorder), `DELETE playlists/{id}/tracks/{track_id}` |
| Assistant | `POST assistant/search {query, kind?}` |

Errors always look like `{"detail": "...", "code": "machine_readable_code"}`.

## Production notes
- Run with `APP_ENVIRONMENT=production`: the app refuses to start with the default secret or a non-HTTPS
  `APP_PUBLIC_BASE_URL`, and disables `/docs`.
- Put it behind a TLS-terminating reverse proxy; configure uvicorn's `--forwarded-allow-ips` so rate
  limiting sees real client IPs.
- The rate limiter is in-process: use a single API instance or move it to Redis before scaling out.
- Migrations run on startup; with several API replicas, run `python -m app.cli init-db` once per deploy instead.
