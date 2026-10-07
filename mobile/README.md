# Efetüfe — Android app (Flutter)

See the [root README](../README.md) for running the app against the backend and building the APK
(`build_apk.ps1` on Windows), and [ARCHITECTURE.md](../ARCHITECTURE.md) for the overall design.

```bash
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000   # Android emulator → backend on the host
```
