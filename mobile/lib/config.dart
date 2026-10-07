/// Build-time configuration.
///
/// Override with `--dart-define=API_BASE_URL=https://api.example.com`.
/// The default targets a backend on the development machine as seen from the Android emulator.
class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );
}
