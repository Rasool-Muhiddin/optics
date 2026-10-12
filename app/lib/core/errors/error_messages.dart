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
  // Accounts & tenancy (P1)
  'invalid_activation_code': AppStrings.errInvalidActivationCode,
  'device_limit_reached': AppStrings.errDeviceLimit,
  'user_limit_reached': AppStrings.errUserLimit,
  'lab_inactive': AppStrings.errLabInactive,
  'no_license': AppStrings.errNoLicense,
  'license_expired': AppStrings.errLicenseExpired,
  'invalid_credentials': AppStrings.errInvalidCredentials,
  'device_not_activated': AppStrings.errDeviceNotActivated,
  'device_deactivated': AppStrings.errDeviceDeactivated,
  'device_lab_mismatch': AppStrings.errDeviceLabMismatch,
  'no_lab_membership': AppStrings.errNoLabMembership,
  'membership_inactive': AppStrings.errMembershipInactive,
  'owner_required': AppStrings.errOwnerRequired,
  'inventory_permission_required': AppStrings.errInventoryPermission,
  'feature_not_in_plan': AppStrings.errFeatureNotInPlan,
  'cannot_modify_self': AppStrings.errCannotModifySelf,
  'username_taken': AppStrings.errUsernameTaken,
  'not_cached': AppStrings.errNotCached,
  // Catalog & inventory (P2)
  'insufficient_stock': AppStrings.errInsufficientStock,
  'variant_required': AppStrings.errVariantRequired,
  'variant_not_allowed': AppStrings.errValidation,
  'variant_mismatch': AppStrings.errValidation,
  'not_stock_tracked': AppStrings.errNotStockTracked,
  'unit_cost_required': AppStrings.errUnitCostRequired,
  'invalid_quantity': AppStrings.errValidation,
  'duplicate_name': AppStrings.errDuplicateName,
  'duplicate_variant': AppStrings.errDuplicateVariant,
  'variant_locked': AppStrings.errVariantLocked,
  'kind_locked': AppStrings.errKindLocked,
  'too_many_variants': AppStrings.errTooManyVariants,
  'invalid_sph': AppStrings.errInvalidPower,
  'invalid_cyl': AppStrings.errInvalidPower,
  'invalid_add': AppStrings.errInvalidPower,
  'invalid_axis': AppStrings.errInvalidPower,
  'category_cycle': AppStrings.errCategoryCycle,
  'stock_not_empty': AppStrings.errStockNotEmpty,
  'duplicate_sku': AppStrings.errDuplicateCode,
  'duplicate_barcode': AppStrings.errDuplicateCode,
  // Patients (P3)
  'record_void': AppStrings.errRecordVoid,
  'patient_locked': AppStrings.errPatientLocked,
  'rx_empty': AppStrings.errRxEmpty,
  'axis_required': AppStrings.errAxisRequired,
  'sph_required': AppStrings.errSphRequired,
  'base_required': AppStrings.errBaseRequired,
  'invalid_pd': AppStrings.errInvalidPd,
  'invalid_prism': AppStrings.errInvalidPower,
  // Sales (P4)
  'discount_requires_owner': AppStrings.errDiscountRequiresOwner,
  'invalid_discount': AppStrings.errInvalidDiscount,
  'credit_requires_patient': AppStrings.errCreditRequiresPatient,
  'overpayment': AppStrings.errOverpayment,
  'invalid_amount': AppStrings.errInvalidAmount,
  'invoice_cancelled': AppStrings.errInvoiceCancelled,
  'product_inactive': AppStrings.errProductInactive,
  // Jobs (P5)
  'invalid_transition': AppStrings.errInvalidTransition,
  'job_closed': AppStrings.errJobClosed,
  'prescription_mismatch': AppStrings.errPrescriptionMismatch,
  'invoice_mismatch': AppStrings.errInvoiceMismatch,
  'invalid_frame': AppStrings.errInvalidFrame,
  'invalid_lens': AppStrings.errInvalidLens,
  // Supplier orders (P6)
  'order_locked': AppStrings.errOrderLocked,
  'order_closed': AppStrings.errOrderClosed,
  'over_receive': AppStrings.errOverReceive,
  'invalid_line': AppStrings.errValidation,
  'cancel_refund_required': AppStrings.errCancelRefundRequired,
  'order_not_sent': AppStrings.errOrderNotSent,
  'cost_permission_required': AppStrings.errCostPermission,
  'job_required': AppStrings.errJobRequired,
  'invalid_job': AppStrings.errInvalidJob,
};

/// Arabic, user-facing message for any error thrown by the data layer.
String errorMessageFor(Object error) {
  if (error is ApiException && error.code == 'validation_error') {
    for (final code in _allCodes(error.errorCodes)) {
      final message = _messagesByCode[code];
      if (message != null && code != 'invalid' && code != 'required') return message;
    }
    final nested = _firstNestedCode(error.fieldErrors);
    if (nested != null && _messagesByCode.containsKey(nested)) return _messagesByCode[nested]!;
  }
  if (error is AppException) {
    final message = _messagesByCode[error.code];
    if (message != null) return message;
    if (error is ApiException && error.statusCode >= 500) return AppStrings.errServer;
  }
  return AppStrings.errUnknown;
}

/// DRF puts per-field codes nowhere in the body, but our serializers raise power errors
/// with the code as the message key (`{"sph": ["…"]}`); map well-known field names.
String? _firstNestedCode(Map<String, dynamic>? errors) {
  if (errors == null) return null;
  for (final key in const ['sph', 'cyl', 'add', 'axis']) {
    if (errors.containsKey(key)) return 'invalid_$key';
  }
  for (final key in const ['sku', 'barcode']) {
    if (errors.containsKey(key)) return 'duplicate_$key';
  }
  return null;
}

/// Server message for one form field, in Arabic when known (used under inputs).
String? fieldErrorFor(Object? error, String field) {
  if (error is! ApiException) return null;
  final errors = error.fieldErrors;
  if (errors == null || !errors.containsKey(field)) return null;
  return _messagesByCode[_firstNestedCode({field: errors[field]}) ?? ''] ??
      AppStrings.errValidation;
}

/// Raw per-field errors of a validation failure, if any.
Map<String, dynamic>? errorFields(Object? error) =>
    error is ApiException ? error.fieldErrors : null;

Iterable<String> _allCodes(Object? codes) sync* {
  if (codes is String) {
    yield codes;
  } else if (codes is List) {
    for (final c in codes) {
      yield* _allCodes(c);
    }
  } else if (codes is Map) {
    for (final c in codes.values) {
      yield* _allCodes(c);
    }
  }
}

/// Arabic message for the first server error code under [path] (e.g. `['prescription', 'od_sph']`).
String? fieldCodeMessage(Object? error, List<String> path) {
  if (error is! ApiException) return null;
  Object? node = error.errorCodes;
  for (final key in path) {
    if (node is! Map) return null;
    node = node[key];
  }
  if (node == null) return null;
  final code = _allCodes(node).firstOrNull;
  return code == null ? null : (_messagesByCode[code] ?? AppStrings.errValidation);
}
