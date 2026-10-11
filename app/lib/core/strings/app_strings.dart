/// Every user-facing string lives here (Arabic-first), ready for future localization.
class AppStrings {
  const AppStrings._();

  static const String appTitle = 'نظام إدارة مختبر العوينات';
  static const String companyName = 'تيرا';
  static const String home = 'الرئيسية';
  static const String welcome = 'مرحباً بك';
  static const String scaffoldReady = 'تم تجهيز النظام. ستتم إضافة الشاشات تباعاً.';

  // Connectivity
  static const String online = 'متصل بالخادم';
  static const String offline = 'غير متصل بالخادم — يمكنك تصفح البيانات المحفوظة والطباعة فقط';
  static const String checkingConnection = 'جارٍ التحقق من الاتصال…';
  static const String retry = 'إعادة المحاولة';

  // Errors (keyed by API `code`, see error_messages.dart)
  static const String errOfflineWrite =
      'لا يمكن حفظ التغييرات بدون اتصال بالخادم. يرجى التحقق من الإنترنت ثم المحاولة مجدداً.';
  static const String errNetwork = 'تعذّر الاتصال بالخادم. تحقق من اتصال الإنترنت.';
  static const String errTimeout = 'انتهت مهلة الاتصال بالخادم. حاول مرة أخرى.';
  static const String errNotAuthenticated = 'انتهت الجلسة. يرجى تسجيل الدخول مجدداً.';
  static const String errPermissionDenied = 'ليست لديك صلاحية لتنفيذ هذا الإجراء.';
  static const String errNotFound = 'العنصر المطلوب غير موجود.';
  static const String errValidation = 'يرجى التحقق من البيانات المدخلة.';
  static const String errServer = 'حدث خطأ في الخادم. يرجى المحاولة لاحقاً.';
  static const String errTooManyRequests = 'طلبات كثيرة جداً. انتظر قليلاً ثم حاول مجدداً.';
  static const String errUnknown = 'حدث خطأ غير متوقع.';

  // Currency
  static const String currencyIqd = 'د.ع';
}
