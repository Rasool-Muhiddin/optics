/// Typed exceptions thrown by the data layer. Screens show them through
/// [errorMessageFor] instead of raw text.
sealed class AppException implements Exception {
  const AppException(this.code, [this.detail]);

  /// Stable machine code (matches the backend's `code` where applicable).
  final String code;

  /// Developer-facing detail (English, from the server). Never shown as-is.
  final String? detail;

  @override
  String toString() => '$runtimeType($code${detail == null ? '' : ': $detail'})';
}

/// A write was attempted while the server is unreachable (online-first: no write queue).
class OfflineWriteException extends AppException {
  const OfflineWriteException() : super('offline_write');
}

/// The server could not be reached (no network, DNS, refused, timeout).
class NetworkException extends AppException {
  const NetworkException({bool timeout = false, String? detail})
    : super(timeout ? 'timeout' : 'network_error', detail);

  bool get isTimeout => code == 'timeout';
}

/// The server answered with an error (`{"detail": "...", "code": "..."}`).
class ApiException extends AppException {
  const ApiException({
    required this.statusCode,
    required String code,
    String? detail,
    this.fieldErrors,
    this.errorCodes,
  }) : super(code, detail);

  final int statusCode;

  /// Per-field validation errors (`errors` in the response), if any.
  final Map<String, dynamic>? fieldErrors;

  /// Same shape as [fieldErrors] with stable codes (`error_codes` in the response).
  final Map<String, dynamic>? errorCodes;
}

/// 401: token missing, invalid or revoked.
class UnauthorizedException extends ApiException {
  const UnauthorizedException({required super.code, super.detail}) : super(statusCode: 401);
}

/// Offline and the requested record was never cached on this device.
class NotCachedException extends AppException {
  const NotCachedException() : super('not_cached');
}
