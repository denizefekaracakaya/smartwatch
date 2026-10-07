# Engineering Decision Log

## D-001 Mobile framework: Flutter
- **Context:** MVP is an Android APK; the vision adds TV, watch, car, Chromecast.
- **Alternatives:** Native Kotlin/Compose; React Native.
- **Selected:** Flutter 3.29 (installed locally with the Android SDK).
- **Reason:** Single codebase that can later target iOS/TV, mature audio stack (`just_audio`, `audio_service`),
  toolchain already present on the dev machine, so the APK can be built and verified.
- **Trade-offs:** Car/watch integrations need some platform channel work later.

## D-002 Backend: Python 3.12 + FastAPI + SQLAlchemy 2
- **Alternatives:** Node/NestJS, Django, Supabase/Firebase BaaS.
- **Reason:** Built-in validation (Pydantic) and OpenAPI docs, first-class Anthropic SDK, easy testing.
  A BaaS would hide the auth/hashing requirements that the spec explicitly asks to implement.
- **Trade-offs:** Python is slower than Go/Node for raw I/O; streaming is served via `FileResponse`-style
  chunked reads and can be moved to a CDN/object store later.

## D-003 Database: SQLite for dev/tests, PostgreSQL in Docker/prod
- **Reason:** Zero-setup local runs and fast tests; Postgres for concurrency in deployment. SQLAlchemy keeps
  the code portable. The schema is managed by Alembic (see D-015).
- **Trade-offs:** The PostgreSQL path is untested so far, because Docker was not available on the dev
  machine.

## D-004 Audio storage: files on disk behind a `MediaStorage` interface, metadata in DB
- **Context:** Spec says "pulled from the remote database" (see ARCHITECTURE §3).
- **Reason:** Blobs in an RDBMS hurt range-streaming and backups. The interface allows S3/GCS later.

## D-005 Password hashing: Argon2id (argon2-cffi)
- **Alternatives:** bcrypt (72-byte limit), scrypt, PBKDF2.
- **Reason:** OWASP's first recommendation; memory-hard. Parameters auto-upgrade via `check_needs_rehash`.

## D-006 Session model: short JWT access token + opaque rotating refresh token
- Access token: HS256 JWT, 15 min, contains `sub`, `type=access`.
- Refresh token: 256-bit random, stored as SHA-256, 30 days, rotated on every use, reuse of a rotated
  token revokes the whole family (theft detection).
- **Alternative:** server sessions/cookies — less natural for a mobile client.

## D-007 Streaming authorization: dedicated stream token
- **Context:** Media players issue Range requests for the whole duration of playback; a 15-min access token
  would expire mid-podcast. Headers on player requests are also brittle across platforms.
- **Selected:** `GET /tracks/{id}/stream-url` returns a URL containing a JWT (`type=stream`, bound to user and
  track, 6 h). The stream endpoint validates it and serves HTTP 206 range responses.
- **Trade-offs:** Token appears in URLs (could land in proxy logs). Mitigated by short scope (single track,
  single user, read-only) and access logs being configured to not log query strings by the app.

## D-008 Mobile audio: just_audio + just_audio_background
- **Reason:** Background playback, lock-screen/notification and Bluetooth media buttons via Android media
  session, which is also the foundation for Android Auto / watch control later.

## D-009 AI assistant: Claude tool loop over our own catalog, with deterministic fallback
- **Alternatives:** (a) send the whole catalog to the LLM; (b) embeddings/vector DB; (c) LLM picks songs from
  its own knowledge.
- **Selected:** Manual tool loop (Anthropic Python SDK, `claude-opus-5-5`, low effort for latency) where the
  model can call `search_catalog` (our fuzzy search) several times — using its world knowledge to turn
  "the song from Titanic" into title/artist guesses — then calls `submit_results` with catalog ids and a
  short reason. Returned ids are validated against the DB, so hallucinated tracks are impossible.
  Server-side refusal fallback (`fallbacks: "default"`) is enabled.
  Without `ANTHROPIC_API_KEY` (or on API failure) the endpoint degrades to fuzzy search and says so.
- **Trade-offs:** Latency of several LLM round trips (capped at 5); cost per query. Vector search would
  help for lyric-level queries on a large catalog — future work.

## D-010 Non-ASCII project path on Windows
- **Context:** The project directory is `efetüfey`; the Android Gradle Plugin refuses non-ASCII paths on
  Windows.
- **Selected:** `android.overridePathCheck=true` in `mobile/android/gradle.properties` for AGP. That alone is
  not enough: Flutter's shader compiler (impellerc) fails with "Could not write file" under non-ASCII paths,
  and a directory junction does not help because Flutter resolves it back to the real path.
  `mobile/build_apk.ps1` maps the project root to a temporary drive letter with `subst` for the duration of
  the build.

## D-011 Language
- Code, API, docs: English. Mobile UI strings: Turkish (the spec is written in Turkish, so the target audience
  is Turkish-speaking). API errors carry a machine-readable `code` that the app maps to Turkish messages.

## D-012 Rate limiting: in-process sliding window
- **Reason:** No extra infrastructure for the MVP. **Trade-off:** per-instance only; replace with Redis for
  horizontal scaling.

## D-013 E-mail: pluggable sender (console in dev/test, SMTP otherwise)
- Mailpit is provided in docker-compose so verification/reset mails can be viewed at `localhost:8025`.
- **E-mail verification:** high-entropy token in a link (`GET /api/v1/auth/verify-email?token=…`). The GET
  only renders a page with a "verify" button that POSTs to `/verify-email/confirm`; mail security scanners
  prefetch links, and a state-changing GET would let them burn the single-use token. Works from any mail
  client without app deep links.
- **Password reset:** 6-digit code (15 min, single use, max 5 wrong attempts, then invalidated) typed into
  the app together with the new password. Reason: good mobile UX; brute force bounded by the attempt cap
  plus rate limiting (1e6 space, 5 tries ⇒ 5e-6 success chance per issued code).

## D-014 Session epoch for stateless JWT revocation
- **Context:** Access JWTs (15 min) and stream JWTs (6 h) are stateless, so a password change or reset did
  not invalidate tokens that were already issued.
- **Alternatives:** a server-side deny-list of token ids; very short token lifetimes.
- **Selected:** `users.session_epoch` is embedded as the `ep` claim and compared on every authenticated
  request and every stream request. It is incremented on password change and password reset.
- **Trade-offs:** one extra column compared per request (the user row is loaded anyway). A plain logout
  only revokes the refresh token family; bumping the epoch there would also log out the user's other
  devices.

## D-015 Alembic migrations, applied on startup
- **Selected:** `Database.migrate()` runs `alembic upgrade head`. It is called on app startup, by the CLI
  and in tests, so the test suite exercises the migrations. `tests/test_migrations.py` fails when the
  models change without a migration.
- **Trade-offs:** running migrations on startup suits a single API instance. With several replicas, run
  `python -m app.cli init-db` as a deploy step instead.

## D-016 Android build pins
- `audio_session` is pinned below 0.2 via `dependency_overrides`, because 0.2.x needs Kotlin Gradle Plugin
  2.x and the project is on KGP 1.8.22 (Flutter 3.29 template). Remove the pin when upgrading KGP.
- No `ndkVersion` pin: the app has no native code, so building does not require a ~1 GB NDK download.
- Gradle heap is 3 GB (8 GB crashed the JVM on a 16 GB machine), with HTTP timeouts for stalled downloads.
- `compileSdk` is at least 36, because `flutter_secure_storage` 10 compiles against SDK 36.
- Release builds use `android/app/proguard-rules.pro` to keep just_audio, audio_service and media3 out of R8
  optimisation. Without it, the minified release APK crashed on the first track ("Parça yüklenemedi";
  logcat: `ExoPlayerImplInternal: Unexpected runtime error … NullPointerException` in just_audio's
  `ObserverRenderer`, found via the R8 mapping file). Debug builds were unaffected because they are not
  minified, which is why the earlier emulator test, run on a debug build, did not catch it.

## D-017 Server address chosen in the app; LAN test builds allow cleartext
- **Context:** A phone has to reach a backend that, for now, runs on the user's PC in the local network.
  Baking the address in at build time (`--dart-define`) would need one APK per network.
- **Selected:** The login screen has a "Sunucu" (server) setting; the address is validated (http/https,
  no query) and stored in secure storage, and changing it drops the stored session. `API_BASE_URL` stays as
  the default. The APK published on GitHub Releases is built with `ALLOW_CLEARTEXT=true` so it can talk to
  `http://<pc-ip>:8000`.
- **Trade-offs:** A cleartext-capable release build is acceptable only for LAN testing. A public deployment
  must run behind HTTPS and ship an APK built without `ALLOW_CLEARTEXT`.
