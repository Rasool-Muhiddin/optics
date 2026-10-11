/// Compile-time configuration.
///
/// Override with `--dart-define=API_BASE_URL=https://optics-api.tera-software1.com/api/v1`.
class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api/v1',
  );

  /// How often [ConnectivityService] pings `/health/`.
  static const Duration healthCheckInterval = Duration(seconds: 20);

  /// Timeout for the health ping itself (short: it decides online/offline).
  static const Duration healthCheckTimeout = Duration(seconds: 5);

  /// Default timeout for regular API calls.
  static const Duration apiTimeout = Duration(seconds: 20);

  /// File name of the local read-only cache database.
  static const String cacheDbFileName = 'optics_cache.db';
}
