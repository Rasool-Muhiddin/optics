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

  // Common
  static const String save = 'حفظ';
  static const String add = 'إضافة';
  static const String edit = 'تعديل';
  static const String close = 'إغلاق';
  static const String back = 'رجوع';
  static const String search = 'بحث';
  static const String all = 'الكل';
  static const String active = 'فعّال';
  static const String inactive = 'غير فعّال';
  static const String showInactive = 'عرض غير الفعّال';
  static const String loadMore = 'تحميل المزيد';
  static const String noData = 'لا توجد بيانات';
  static const String required = 'مطلوب';
  static const String invalidNumber = 'رقم غير صحيح';
  static const String notes = 'ملاحظات';
  static const String name = 'الاسم';
  static const String date = 'التاريخ';
  static const String status = 'الحالة';
  static const String saved = 'تم الحفظ';
  static const String confirm = 'تأكيد';
  static const String print = 'طباعة';
  static const String none = '—';
  static const String yes = 'نعم';
  static const String no = 'لا';
  static const String fromCache = 'معروض من البيانات المحفوظة';
  static const String errNotCached =
      'هذه البيانات غير محفوظة على هذا الجهاز ولا يوجد اتصال بالخادم.';

  // Inventory (P2)
  static const String inventoryTitle = 'المخزون';
  static const String addProduct = 'إضافة مادة';
  static const String editProduct = 'تعديل مادة';
  static const String productKind = 'النوع';
  static const String productName = 'اسم المادة';
  static const String brand = 'الماركة';
  static const String brands = 'الماركات';
  static const String category = 'الصنف';
  static const String categories = 'الأصناف';
  static const String parentCategory = 'الصنف الأب';
  static const String categoriesAndBrands = 'الأصناف والماركات';
  static const String sku = 'الرمز (SKU)';
  static const String barcode = 'الباركود';
  static const String salePrice = 'سعر البيع';
  static const String purchasePrice = 'سعر الشراء';
  static const String averageCost = 'متوسط الكلفة';
  static const String quantity = 'الكمية';
  static const String reorderLevel = 'حد إعادة الطلب';
  static const String trackStock = 'تتبع المخزون';
  static const String lowStock = 'مخزون منخفض';
  static const String lowStockOnly = 'المنخفض فقط';
  static const String noStockTracking = 'بدون مخزون';
  static const String productDetails = 'تفاصيل المادة';
  static const String stockMovements = 'حركات المخزون';
  static const String stockEntry = 'حركة مخزون';
  static const String movementType = 'نوع الحركة';
  static const String unitCost = 'كلفة الوحدة';
  static const String qtyAfter = 'الرصيد بعد';
  static const String byUser = 'بواسطة';
  static const String lensGrid = 'شبكة القوى (SPH × CYL)';
  static const String generateVariants = 'توليد القوى';
  static const String sphFrom = 'SPH من';
  static const String sphTo = 'SPH إلى';
  static const String cylFrom = 'CYL من';
  static const String cylTo = 'CYL إلى';
  static const String addPower = 'ADD';
  static const String step = 'الخطوة';
  static const String variantsCreated = 'تم إنشاء القوى';
  static const String gridEntryMode = 'إدخال كميات للشبكة';
  static const String gridEntryHint =
      'أدخل الكمية الواردة في كل خانة ثم احفظ. تُسجَّل جميع الخانات كحركة واحدة.';
  static const String noVariants = 'لا توجد قوى لهذه العدسة بعد. استخدم «توليد القوى».';
  static const String variantPrice = 'سعر خاص لهذه القوة (اختياري)';
  static const String invalidPower = 'قيمة غير صحيحة (خطوات 0.25)';
  static const String minusCylOnly = 'الأسطوانة بالسالب فقط (CYL ≤ 0)';
  static const String attributes = 'المواصفات';
  static const String chooseVariant = 'اختر القوة';

  static const Map<String, String> productKinds = {
    'frame': 'إطار',
    'stock_lens': 'عدسة جاهزة',
    'rx_lens': 'عدسة طبية (تفصيل)',
    'contact_lens': 'عدسة لاصقة',
    'accessory': 'إكسسوار',
    'solution': 'محلول',
    'service': 'خدمة',
  };

  static const Map<String, String> movementTypes = {
    'purchase': 'شراء / إدخال',
    'sale': 'بيع',
    'return_in': 'إرجاع من زبون',
    'return_out': 'إرجاع إلى مورد',
    'adjustment': 'تسوية جرد',
    'damage': 'تالف',
  };

  static const Map<String, String> attributeLabels = {
    'model': 'الموديل',
    'color': 'اللون',
    'size': 'المقاس (عين-جسر-ذراع)',
    'material': 'المادة',
    'gender': 'الفئة',
    'shape': 'الشكل',
    'frame_type': 'نوع الإطار',
    'index': 'معامل الانكسار',
    'design': 'التصميم',
    'coatings': 'الطلاءات',
    'diameter': 'القطر',
    'replacement': 'مدة الاستبدال',
    'base_curve': 'الانحناء (BC)',
    'pack_size': 'عدد العدسات في العلبة',
    'volume_ml': 'الحجم (مل)',
  };

  static const Map<String, String> choiceLabels = {
    // gender
    'men': 'رجالي', 'women': 'نسائي', 'unisex': 'للجنسين', 'kids': 'أطفال',
    // frame type
    'full_rim': 'إطار كامل', 'semi_rimless': 'نصف إطار', 'rimless': 'بدون إطار',
    // lens design
    'single_vision': 'أحادي البؤرة',
    'bifocal': 'ثنائي البؤرة',
    'progressive': 'متعدد البؤر (تدريجي)',
    'office': 'مكتبي',
    // coatings
    'ar': 'مضاد للانعكاس', 'blue_cut': 'حماية الضوء الأزرق', 'photochromic': 'فوتوكروميك',
    'hard_coat': 'طلاء صلب', 'uv': 'حماية UV', 'polarized': 'مستقطب', 'hydrophobic': 'طارد للماء',
    'mirror': 'مرآة', 'tint': 'ملوّن',
    // contact lens replacement
    'daily': 'يومي',
    'biweekly': 'أسبوعين',
    'monthly': 'شهري',
    'quarterly': 'ثلاثة أشهر',
    'yearly': 'سنوي',
  };

  static String label(Map<String, String> labels, String key) => labels[key] ?? key;

  // Errors (P2)
  static const String errInsufficientStock = 'الكمية المتوفرة في المخزون غير كافية.';
  static const String errVariantRequired = 'مخزون العدسات يُتابع لكل قوة: اختر القوة.';
  static const String errNotStockTracked = 'هذه المادة لا تتابع المخزون.';
  static const String errUnitCostRequired = 'يجب إدخال كلفة الشراء.';
  static const String errDuplicateName = 'الاسم موجود مسبقاً.';
  static const String errDuplicateVariant = 'هذه القوة موجودة مسبقاً لهذه العدسة.';
  static const String errVariantLocked = 'لا يمكن تغيير قوة لها حركات مخزون.';
  static const String errKindLocked = 'لا يمكن تغيير نوع مادة لها مخزون أو قوى.';
  static const String errTooManyVariants =
      'المدى كبير جداً. الحد الأقصى 2000 قوة في المرة الواحدة.';
  static const String errInvalidPower = 'قيمة القوة غير صحيحة.';
  static const String errCategoryCycle = 'لا يمكن وضع الصنف داخل نفسه.';
  static const String errStockNotEmpty = 'أفرغ المخزون قبل إيقاف تتبعه.';
  static const String errDuplicateCode = 'الرمز أو الباركود مستخدم مسبقاً.';
}
