import '../strings/app_strings.dart';
import 'app_exception.dart';

/// Arabic messages per error `code`. Backend codes are added here as domains grow.
const Map<String, String> _messagesByCode = {
  'offline_write': AppStrings.errOfflineWrite,
  'network_error': AppStrings.errNetwork,
  'timeout': AppStrings.errTimeout,
  'not_authenticated': AppStrings.errNotAuthenticated,
  'authentication_failed': AppStrings.errNotAuthenticated,
  'permission_denied': AppStrings.errPermissionDenied,
  'not_found': AppStrings.errNotFound,
  'validation_error': AppStrings.errValidation,
  'invalid': AppStrings.errValidation,
  'throttled': AppStrings.errTooManyRequests,
  'server_error': AppStrings.errServer,
};

/// Arabic, user-facing message for any error thrown by the data layer.
String errorMessageFor(Object error) {
  if (error is AppException) {
    final message = _messagesByCode[error.code];
    if (message != null) return message;
    if (error is ApiException && error.statusCode >= 500) return AppStrings.errServer;
  }
  return AppStrings.errUnknown;
}
