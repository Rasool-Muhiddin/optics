/// Every user-facing string lives here (Arabic-first), ready for future localization.
class AppStrings {
  const AppStrings._();

  static const String appTitle = 'نظام إدارة مختبر العوينات';
  static const String companyName = 'تيرا';
  static const String home = 'الرئيسية';
  static const String welcome = 'مرحباً بك';
  static const String loading = 'جارٍ التحميل…';

  // Activation
  static const String activationTitle = 'تفعيل الجهاز';
  static const String activationHint =
      'أدخل رمز التفعيل الذي حصلت عليه من شركة تيرا لربط هذا الجهاز بالمختبر.';
  static const String activationCode = 'رمز التفعيل';
  static const String activate = 'تفعيل';
  static const String activationCodeRequired = 'يرجى إدخال رمز التفعيل';
  static const String reactivate = 'إعادة تفعيل الجهاز';

  // Login
  static const String loginTitle = 'تسجيل الدخول';
  static const String username = 'اسم المستخدم';
  static const String password = 'كلمة المرور';
  static const String login = 'دخول';
  static const String usernameRequired = 'يرجى إدخال اسم المستخدم';
  static const String passwordRequired = 'يرجى إدخال كلمة المرور';
  static const String logout = 'تسجيل الخروج';
  static const String logoutConfirm = 'هل تريد تسجيل الخروج؟';
  static const String cancel = 'إلغاء';

  // Roles
  static const String roleOwner = 'المالك';
  static const String roleStaff = 'موظف';

  // Sidebar sections
  static const String navPatients = 'المراجعين';
  static const String navInventory = 'المخزون';
  static const String navPos = 'نافذة البيع';
  static const String navJobs = 'طلبات الزبائن';
  static const String navOrders = 'طلبات الموردين';
  static const String navReferrals = 'إحالات الأطباء';
  static const String navReports = 'التقارير';
  static const String navUsers = 'المستخدمين';
  static const String navSettings = 'إعدادات المختبر';
  static const String comingSoon = 'هذه الشاشة قيد التطوير وستتوفر قريباً.';

  // Home
  static const String homeLab = 'المختبر';
  static const String homeRole = 'الصلاحية';
  static const String homePlan = 'الاشتراك';
  static const String homePlanExpires = 'ينتهي الاشتراك في';
  static const String sessionOffline =
      'تم فتح الجلسة من البيانات المحفوظة لعدم توفر الاتصال بالخادم.';

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
  static const String errInvalidActivationCode = 'رمز التفعيل غير صحيح.';
  static const String errDeviceLimit =
      'تم الوصول إلى الحد الأقصى لعدد الأجهزة في اشتراكك. تواصل مع تيرا أو عطّل جهازاً آخر.';
  static const String errUserLimit = 'تم الوصول إلى الحد الأقصى لعدد المستخدمين في اشتراكك.';
  static const String errLabInactive = 'حساب المختبر موقوف. يرجى التواصل مع تيرا.';
  static const String errNoLicense = 'لا يوجد اشتراك فعّال لهذا المختبر. يرجى التواصل مع تيرا.';
  static const String errLicenseExpired = 'انتهى اشتراك المختبر. يرجى التواصل مع تيرا للتجديد.';
  static const String errInvalidCredentials = 'اسم المستخدم أو كلمة المرور غير صحيحة.';
  static const String errDeviceNotActivated = 'هذا الجهاز غير مفعّل. يرجى إعادة تفعيل الجهاز.';
  static const String errDeviceDeactivated = 'تم إيقاف هذا الجهاز من قبل مالك المختبر.';
  static const String errDeviceLabMismatch =
      'هذا المستخدم لا ينتمي إلى المختبر المفعّل على هذا الجهاز.';
  static const String errNoLabMembership = 'هذا الحساب غير مرتبط بأي مختبر.';
  static const String errMembershipInactive = 'تم إيقاف حسابك في المختبر.';
  static const String errOwnerRequired = 'هذا الإجراء متاح لمالك المختبر فقط.';
  static const String errFeatureNotInPlan = 'هذه الميزة غير مشمولة في اشتراكك الحالي.';
  static const String errCannotModifySelf = 'لا يمكنك إيقاف حسابك أو تغيير صلاحيتك بنفسك.';
  static const String errUsernameTaken = 'اسم المستخدم مستخدم مسبقاً.';

  // Currency
  static const String currencyIqd = 'د.ع';
}
