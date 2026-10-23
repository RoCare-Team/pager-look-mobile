/// Build-time configuration, supplied with `--dart-define` (or
/// `--dart-define-from-file=env/dev.json`).
///
/// The defaults point at production, mirroring the web app's `.env.production`.
/// For local development against the backend on port 8080 use
/// `env/dev.json` (Android emulator reaches the host machine at 10.0.2.2).
class Env {
  Env._();

  /// Same value as the web app's `VITE_API_URL`.
  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://api.pagerlook.com/api',
  );

  /// Public web origin, used to build shareable links (`/u/:slug`, `/join/:code`).
  static const String appUrl = String.fromEnvironment(
    'APP_URL',
    defaultValue: 'https://www.pagerlook.com',
  );

  /// The backend's GOOGLE_CLIENT_ID (the *web* OAuth client). Google issues the
  /// mobile ID token for this audience, so the existing
  /// `/auth/employee/google` endpoint verifies it unchanged. Empty → the
  /// Google button is hidden.
  static const String googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// Origin that serves `/uploads/...` media — the API URL without `/api`.
  static String get mediaBase => apiUrl.replaceFirst(RegExp(r'/api/?$'), '');

  static String get appOrigin => appUrl.replaceFirst(RegExp(r'/$'), '');
}
