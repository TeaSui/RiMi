/// App-wide configuration loaded from build-time environment.
///
/// Values are injected via --dart-define at build time. No secrets are
/// stored here — only the public API base URL. JWTs live in secure storage only
/// (CLIENT-01, SECRETS-03).
abstract final class AppConfig {
  /// API base URL. Override at build time:
  ///   flutter run --dart-define=RIMI_API_BASE_URL=https://api.example.com
  ///
  /// Default points to Android emulator loopback (10.0.2.2) on port 8080.
  /// For iOS simulator use http://localhost:8080 via --dart-define.
  static const String apiBaseUrl = String.fromEnvironment(
    'RIMI_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );

  /// API version prefix.
  static const String apiVersion = '/v1';

  /// Full base with version.
  static String get apiBase => '$apiBaseUrl$apiVersion';
}
