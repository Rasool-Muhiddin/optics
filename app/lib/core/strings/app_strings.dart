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
  static const String errInventoryPermission =
      'إدارة المخزون (الأصناف وإدخالات المخزون) متاحة للمالك أو لمن لديه صلاحية إدارة المخزون.';
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

  // Patients, exams, prescriptions (P3)
  static const String patientsTitle = 'المراجعين';
  static const String addPatient = 'مراجع جديد';
  static const String editPatient = 'تعديل بيانات المراجع';
  static const String patientName = 'اسم المراجع';
  static const String age = 'العمر';
  static const String birthDate = 'تاريخ الميلاد';
  static const String gender = 'الجنس';
  static const String phone = 'الهاتف';
  static const String address = 'العنوان';
  static const String lastExam = 'آخر فحص';
  static const String archived = 'مؤرشف';
  static const String archive = 'أرشفة';
  static const String exams = 'الفحوصات';
  static const String prescriptions = 'الوصفات';
  static const String newExam = 'فحص جديد';
  static const String editExam = 'تعديل الفحص';
  static const String newPrescription = 'وصفة جديدة';
  static const String editPrescription = 'تعديل الوصفة';
  static const String examDate = 'تاريخ الفحص';
  static const String rxDate = 'تاريخ الوصفة';
  static const String examinedBy = 'الفاحص';
  static const String examinerName = 'اسم الفاحص (طبيب خارجي)';
  static const String chiefComplaint = 'الشكوى';
  static const String diagnosis = 'التشخيص';
  static const String diagnosisDetails = 'تفاصيل التشخيص';
  static const String vaUncorrected = 'حدة البصر بدون نظارة (VA)';
  static const String iop = 'ضغط العين (IOP)';
  static const String examSection = 'الفحص';
  static const String prescriptionTitle = 'وصفة طبية للنظارة';
  static const String examReportTitle = 'تقرير فحص النظر';
  static const String withPrescription = 'تتضمن وصفة';
  static const String rightEye = 'اليمنى OD';
  static const String leftEye = 'اليسرى OS';
  static const String usage = 'الاستخدام';
  static const String lensDesign = 'تصميم العدسة';
  static const String lensIndex = 'معامل الانكسار';
  static const String lensCoatings = 'الطلاءات';
  static const String frameNotes = 'ملاحظات الإطار';
  static const String prescribedBy = 'الطبيب / الجهة';
  static const String signature = 'التوقيع';
  static const String transpose = 'تحويل الأسطوانة (±)';
  static const String transposeHint =
      'تحويل الوصفة بين صيغة الأسطوانة الموجبة والسالبة (تُحفظ الوصفة وتُطبع كما أُدخلت)';
  static const String matchRxPowers = 'اختيار القوى المطابقة للوصفة';
  static const String matchRxPartial = 'لا توجد قوة مطابقة في المخزون لإحدى العينين أو كلتيهما.';
  static const String pdDistance = 'PD بعيد';
  static const String pdNear = 'PD قريب';
  static const String pdRight = 'PD يمين';
  static const String pdLeft = 'PD يسار';
  static const String voidRecord = 'إلغاء';
  static const String voidReason = 'سبب الإلغاء';
  static const String voided = 'ملغى';
  static const String printPrescription = 'طباعة الوصفة';
  static const String printExamReport = 'طباعة تقرير الفحص';
  static const String axisRequired = 'المحور مطلوب عند وجود أسطوانة';
  static const String sphRequired = 'SPH مطلوب';
  static const String invalidAxis = 'المحور من 1 إلى 180';
  static const String invalidPd = 'قيمة PD غير صحيحة';
  static const String baseRequired = 'اختر اتجاه القاعدة';
  static const String noExams = 'لا توجد فحوصات بعد';
  static const String noPrescriptions = 'لا توجد وصفات بعد';
  static const String sphericalEquivalent = 'المكافئ الكروي';

  static const Map<String, String> genders = {'male': 'ذكر', 'female': 'أنثى'};

  static const Map<String, String> patientStatuses = {
    'new': 'جديد',
    'exam_done': 'تم الفحص',
    'lens_selected': 'تم اختيار العدسة',
    'in_job': 'قيد التجهيز',
    'delivered': 'تم التسليم',
  };

  static const Map<String, String> usages = {
    'distance': 'بعيد',
    'near': 'قريب',
    'both': 'بعيد وقريب',
  };

  static const Map<String, String> prismBases = {
    'up': 'للأعلى',
    'down': 'للأسفل',
    'in': 'للداخل',
    'out': 'للخارج',
  };

  /// Printed Rx tables are Latin (BU/BD/BI/BO).
  static const Map<String, String> prismBasesLatin = {
    'up': 'BU',
    'down': 'BD',
    'in': 'BI',
    'out': 'BO',
  };

  // Errors (P3)
  static const String errRecordVoid = 'هذا السجل ملغى ولا يمكن تعديله.';
  static const String errPatientLocked = 'لا يمكن تغيير المراجع في فحص مسجل.';
  static const String errRxEmpty = 'أدخل وصفة لعين واحدة على الأقل.';
  static const String errAxisRequired = 'المحور مطلوب عند وجود أسطوانة.';
  static const String errSphRequired = 'SPH مطلوب للعين التي لها وصفة.';
  static const String errBaseRequired = 'المنشور يحتاج اتجاه القاعدة.';
  static const String errInvalidPd = 'قيمة المسافة بين الحدقتين (PD) غير صحيحة.';

  // POS & sales (P4)
  static const String navInvoices = 'الفواتير';
  static const String navCredit = 'الزبائن بالآجل';
  static const String posTitle = 'نافذة البيع';
  static const String newSale = 'بيع جديد';
  static const String sell = 'بيع';
  static const String cart = 'السلة';
  static const String emptyCart = 'السلة فارغة. ابحث عن مادة أو امسح الباركود.';
  static const String searchOrScan = 'ابحث بالاسم أو امسح الباركود ثم Enter';
  static const String customer = 'الزبون';
  static const String walkIn = 'زبون عابر';
  static const String choosePatient = 'اختيار مراجع';
  static const String removePatient = 'إزالة المراجع';
  static const String customerName = 'اسم الزبون';
  static const String paymentType = 'طريقة الدفع';
  static const String paymentMethod = 'وسيلة الدفع';
  static const String downPayment = 'المبلغ المدفوع الآن';
  static const String invoiceDiscount = 'خصم الفاتورة';
  static const String discountAmount = 'مبلغ';
  static const String discountPercent = 'نسبة %';
  static const String discount = 'الخصم';
  static const String lineDiscount = 'خصم السطر';
  static const String subtotal = 'المجموع';
  static const String total = 'الإجمالي';
  static const String paid = 'المدفوع';
  static const String balance = 'المتبقي';
  static const String checkout = 'إتمام البيع';
  static const String checkoutDone = 'تم حفظ الفاتورة';
  static const String invoice = 'فاتورة';
  static const String invoices = 'الفواتير';
  static const String invoiceNumber = 'رقم الفاتورة';
  static const String item = 'المادة';
  static const String unitPrice = 'سعر الوحدة';
  static const String lineTotal = 'المبلغ';
  static const String amount = 'المبلغ';
  static const String cashier = 'الكاشير';
  static const String payments = 'الدفعات';
  static const String addPayment = 'تسجيل دفعة';
  static const String receivePayment = 'استلام دفعة';
  static const String cancelInvoice = 'إلغاء الفاتورة';
  static const String cancelInvoiceConfirm =
      'سيتم إرجاع المواد إلى المخزون وإلغاء الدفعات. هل تريد المتابعة؟';
  static const String cancelled = 'ملغاة';
  static const String printA4 = 'طباعة A4';
  static const String printA5 = 'طباعة A5';
  static const String printThermal = 'طباعة حرارية 80mm';
  static const String requiresOwnerDiscount = 'الخصم أعلى من الحد المسموح للموظف';
  static const String outOfStock = 'الكمية غير متوفرة';
  static const String available = 'المتوفر';
  static const String onlyWithBalance = 'غير المسددة فقط';
  static const String oldestInvoice = 'أقدم فاتورة';
  static const String invoicesCount = 'عدد الفواتير';
  static const String totalCredit = 'إجمالي الديون';
  static const String profit = 'الربح';
  static const String costTotal = 'الكلفة';
  static const String posOfflineHint = 'البيع يحتاج اتصالاً بالخادم.';
  static const String paymentsSpread = 'تُوزّع الدفعة على أقدم الفواتير أولاً.';

  static const Map<String, String> paymentTypes = {'cash': 'نقدي', 'credit': 'آجل'};
  static const Map<String, String> paymentMethods = {
    'cash': 'نقداً',
    'card': 'بطاقة',
    'transfer': 'تحويل',
    'other': 'أخرى',
  };
  static const Map<String, String> invoiceStatuses = {
    'open': 'غير مسددة',
    'paid': 'مسددة',
    'partially_paid': 'مسددة جزئياً',
    'cancelled': 'ملغاة',
  };

  // Errors (P4)
  static const String errDiscountRequiresOwner =
      'الخصم أعلى من الحد المسموح به للموظف ويحتاج موافقة المالك.';
  static const String errInvalidDiscount = 'قيمة الخصم غير صحيحة أو أكبر من المبلغ.';
  static const String errCreditRequiresPatient = 'البيع بالآجل يتطلب اختيار مراجع مسجّل.';
  static const String errOverpayment = 'المبلغ أكبر من المتبقي.';
  static const String errInvalidAmount = 'المبلغ غير صحيح.';
  static const String errInvoiceCancelled = 'الفاتورة ملغاة.';
  static const String errProductInactive = 'المادة غير فعّالة.';

  // Customer jobs (P5)
  static const String jobsTitle = 'طلبات الزبائن';
  static const String newJob = 'طلب نظارة جديد';
  static const String editJob = 'تعديل الطلب';
  static const String job = 'طلب';
  static const String jobNumber = 'رقم الطلب';
  static const String promisedDate = 'موعد التسليم';
  static const String overdue = 'متأخر';
  static const String overdueOnly = 'المتأخرة فقط';
  static const String frameSource = 'الإطار';
  static const String frame = 'الإطار';
  static const String lens = 'العدسة';
  static const String lensOd = 'عدسة اليمنى OD';
  static const String lensOs = 'عدسة اليسرى OS';
  static const String lensNotes = 'ملاحظات العدسة';
  static const String linkedInvoice = 'الفاتورة المرتبطة';
  static const String linkedPrescription = 'الوصفة';
  static const String statusHistory = 'سجل الحالات';
  static const String moveTo = 'نقل إلى';
  static const String changeStatus = 'تغيير الحالة';
  static const String statusNote = 'ملاحظة';
  static const String printJobTicket = 'طباعة بطاقة الطلب';
  static const String jobTicket = 'بطاقة طلب نظارة';
  static const String deliveredAt = 'تاريخ التسليم';
  static const String noJobs = 'لا توجد طلبات';
  static const String jobsOfPatient = 'الطلبات';
  static const String chooseFrame = 'اختر إطاراً من المخزون';
  static const String chooseLens = 'اختر العدسة';
  static const String customerSignature = 'توقيع الزبون عند الاستلام';

  static const Map<String, String> jobStatuses = {
    'pending': 'قيد الانتظار',
    'lens_ordered': 'تم طلب العدسة',
    'in_workshop': 'في الورشة',
    'ready': 'جاهز للتسليم',
    'delivered': 'تم التسليم',
    'cancelled': 'ملغى',
  };

  static const Map<String, String> frameSources = {
    'lab': 'من المختبر',
    'customer': 'إطار الزبون',
    'none': 'بدون إطار (عدسات فقط)',
  };

  // Errors (P5)
  static const String errInvalidTransition = 'لا يمكن نقل الطلب إلى هذه الحالة.';
  static const String errJobClosed = 'الطلب مُسلَّم أو ملغى ولا يمكن تعديله.';
  static const String errPrescriptionMismatch = 'الوصفة تعود لمراجع آخر.';
  static const String errInvoiceMismatch = 'الفاتورة تعود لزبون آخر.';
  static const String errInvalidFrame = 'اختيار الإطار غير صحيح.';
  static const String errInvalidLens = 'اختيار العدسة أو القوة غير صحيح.';

  // Supplier orders (P6)
  static const String ordersTitle = 'طلبات الموردين';
  static const String pendingOrders = 'الطلبات المفتوحة';
  static const String supplier = 'المورد';
  static const String suppliers = 'الموردون';
  static const String manageSuppliers = 'إدارة الموردين';
  static const String addSupplier = 'إضافة مورد';
  static const String editSupplier = 'تعديل المورد';
  static const String chooseSupplier = 'اختر المورد';
  static const String supplierBalance = 'المستحق للمورد';
  static const String paySupplier = 'دفع للمورد';
  static const String openOrdersCount = 'طلبات مفتوحة';
  static const String newOrder = 'طلب جديد من مورد';
  static const String editOrder = 'تعديل طلب المورد';
  static const String orderNumber = 'رقم الطلب';
  static const String orderType = 'نوع الطلب';
  static const String orderDate = 'تاريخ الطلب';
  static const String expectedDate = 'تاريخ الوصول المتوقع';
  static const String supplierRef = 'رقم فاتورة المورد';
  static const String paymentStatus = 'حالة الدفع';
  static const String orderLines = 'المواد المطلوبة';
  static const String addLine = 'إضافة مادة';
  static const String addProductLine = 'منتج من المخزون';
  static const String addTextLine = 'مادة بوصف حر';
  static const String description = 'الوصف';
  static const String eye = 'العين';
  static const String received = 'المستلم';
  static const String remaining = 'المتبقي';
  static const String receive = 'استلام';
  static const String receiveAll = 'استلام الكل';
  static const String receiveOrder = 'استلام الطلب';
  static const String receiveHint =
      'أدخل الكميات المستلمة الآن (المواد المخزنية تُضاف إلى المخزون).';
  static const String markOrdered = 'تم إرسال الطلب';
  static const String markPending = 'إرجاع إلى غير مُرسل';
  static const String cancelOrder = 'إلغاء الطلب';
  static const String cancelOrderConfirm =
      'سيتم إلغاء ما لم يُستلم من الطلب. ما استُلم يبقى في المخزون ويبقى مستحقاً للمورد.';
  static const String ageDays = 'العمر (يوم)';
  static const String daysOld = 'يوم';
  static const String late = 'متأخر';
  static const String lateOnly = 'المتأخرة فقط';
  static const String openOnly = 'المفتوحة فقط';
  static const String minAge = 'أقدم من (يوم)';
  static const String ageing = 'أعمار الطلبات المفتوحة';
  static const String totalOwed = 'إجمالي المستحق للموردين';
  static const String noOrders = 'لا توجد طلبات.';
  static const String orderForJob = 'طلب عدسة من المورد';
  static const String supplierOrdersOfJob = 'طلبات الموردين لهذا الطلب';
  static const String chooseJob = 'اختر طلب الزبون';
  static const String linesRequired = 'أضف مادة واحدة على الأقل';

  static const Map<String, String> orderStatuses = {
    'pending': 'غير مُرسل',
    'ordered': 'مطلوب',
    'partially_received': 'مستلم جزئياً',
    'received': 'مستلم',
    'cancelled': 'ملغى',
  };

  static const Map<String, String> orderTypes = {
    'stock': 'مخزون',
    'rx_for_job': 'عدسة طبية لطلب زبون',
    'other': 'أخرى',
  };

  static const Map<String, String> orderPaymentStatuses = {
    'unpaid': 'غير مدفوع',
    'partial': 'مدفوع جزئياً',
    'paid': 'مدفوع',
  };

  static const Map<String, String> eyes = {'': '—', 'od': 'اليمنى (OD)', 'os': 'اليسرى (OS)'};

  // Errors (P6)
  static const String errOrderLocked = 'لا يمكن تعديل طلب تم استلامه أو إلغاؤه.';
  static const String errOrderClosed = 'الطلب مستلم بالكامل أو ملغى.';
  static const String errOverReceive = 'لا يمكن استلام كمية أكبر من المطلوبة.';
  static const String errCancelRefundRequired =
      'المبلغ المدفوع أكبر من قيمة المستلم. ألغِ الدفعات الزائدة أولاً.';
  static const String errOrderNotSent = 'أرسل الطلب إلى المورد قبل الدفع.';
  static const String errCostPermission = 'هذا الإجراء يتطلب صلاحية الاطلاع على التكاليف.';
  static const String errJobRequired = 'طلب العدسة الطبية يجب أن يرتبط بطلب زبون.';
  static const String errInvalidJob = 'فقط طلبات العدسات الطبية ترتبط بطلب زبون.';

  // Doctor linking (P7)
  static const String doctorMode = 'وضع الطبيب';
  static const String doctorLogin = 'دخول الطبيب';
  static const String doctorLoginHint = 'حساب الطبيب لا يحتاج إلى تفعيل الجهاز.';
  static const String iAmDoctor = 'أنا طبيب — دخول حساب طبيب';
  static const String backToLab = 'العودة إلى دخول المختبر';
  static const String navDoctorReferrals = 'إحالاتي';
  static const String navDoctorLabs = 'المختبرات المرتبطة';
  static const String myLinkCode = 'رمز الربط الخاص بك';
  static const String myLinkCodeHint =
      'أعطِ هذا الرمز للمختبر ليرسل طلب ربط، أو أدخل رمز المختبر هنا.';
  static const String labLinkCode = 'رمز ربط المختبر';
  static const String labLinkCodeHint =
      'أعطِ هذا الرمز للأطباء ليرسلوا طلب ربط، أو أدخل رمز الطبيب لإرسال الطلب منك.';
  static const String regenerateCode = 'رمز جديد';
  static const String requestLink = 'طلب ربط';
  static const String enterLabCode = 'رمز المختبر';
  static const String enterDoctorCode = 'رمز الطبيب';
  static const String linkedDoctors = 'الأطباء المرتبطون';
  static const String linkedLabs = 'المختبرات';
  static const String acceptLink = 'قبول';
  static const String rejectLink = 'رفض';
  static const String revokeLink = 'إلغاء الربط';
  static const String requestedByThem = 'طلب وارد';
  static const String requestedByUs = 'طلب مُرسل';
  static const String noLinks = 'لا توجد روابط بعد.';
  static const String referralsTitle = 'إحالات الأطباء';
  static const String referralInbox = 'الإحالات الواردة';
  static const String referral = 'إحالة';
  static const String newReferral = 'إحالة جديدة';
  static const String sendReferral = 'إرسال الإحالة';
  static const String chooseLab = 'المختبر';
  static const String doctor = 'الطبيب';
  static const String noReferrals = 'لا توجد إحالات.';
  static const String referralSent = 'تم إرسال الإحالة.';
  static const String markReceived = 'تأكيد الاستلام';
  static const String acceptReferral = 'قبول وإنشاء ملف';
  static const String acceptIntoNew = 'ملف مراجع جديد';
  static const String acceptIntoExisting = 'ربط بملف مراجع موجود';
  static const String rejectReferral = 'رفض الإحالة';
  static const String completeReferral = 'إنهاء الإحالة';
  static const String openPatientFile = 'فتح ملف المراجع';
  static const String doctorNote = 'ملاحظة الطبيب';
  static const String rejectReason = 'سبب الرفض';
  static const String openReferralsOnly = 'المفتوحة فقط';
  static const String noLinkedLabs = 'لا يوجد مختبر مرتبط مقبول. اطلب الربط من شاشة المختبرات.';

  static const Map<String, String> linkStatuses = {
    'pending': 'بانتظار الرد',
    'accepted': 'مرتبط',
    'rejected': 'مرفوض',
    'revoked': 'ملغى',
  };

  static const Map<String, String> referralStatuses = {
    'sent': 'مُرسلة',
    'received': 'مستلمة',
    'in_progress': 'قيد العمل',
    'completed': 'مكتملة',
    'rejected': 'مرفوضة',
  };

  // Errors (P7)
  static const String errNotADoctor = 'هذا الحساب ليس حساب طبيب.';
  static const String errDoctorInactive = 'حساب الطبيب موقوف. يرجى التواصل مع تيرا.';
  static const String errInvalidLinkCode = 'رمز الربط غير صحيح.';
  static const String errAlreadyLinked = 'الربط موجود مسبقاً.';
  static const String errAlreadyRequested = 'طلب الربط مُرسل مسبقاً وينتظر الرد.';
  static const String errCannotAnswerOwnRequest = 'لا يمكنك الرد على طلب أرسلته بنفسك.';
  static const String errNotLinked = 'لست مرتبطاً بهذا المختبر.';
  static const String errLabUnavailable = 'المختبر غير متاح حالياً.';

  // Dashboard & reports (P8)
  static const String dashboard = 'لوحة المتابعة';
  static const String todaySales = 'مبيعات اليوم';
  static const String todayCollected = 'المقبوض اليوم';
  static const String monthSales = 'مبيعات الشهر';
  static const String monthProfit = 'ربح الشهر';
  static const String creditOutstanding = 'ديون الزبائن';
  static const String openJobs = 'طلبات زبائن مفتوحة';
  static const String readyJobs = 'جاهزة للتسليم';
  static const String lowStockItems = 'أصناف منخفضة';
  static const String openSupplierOrders = 'طلبات موردين مفتوحة';
  static const String openReferrals = 'إحالات جديدة';
  static const String last7Days = 'المبيعات آخر ٧ أيام';
  static const String invoicesCountShort = 'فاتورة';
  static const String reportsTitle = 'التقارير';
  static const String exportCsv = 'تصدير CSV';
  static const String exportedTo = 'تم حفظ الملف في';
  static const String exportNotInPlan = 'التصدير غير مشمول في اشتراكك';
  static const String dateFrom = 'من تاريخ';
  static const String dateTo = 'إلى تاريخ';
  static const String groupByDay = 'يومي';
  static const String groupByMonth = 'شهري';
  static const String showAll = 'عرض الكل';
  static const String totals = 'المجاميع';
  static const String paymentsByMethod = 'المقبوضات حسب طريقة الدفع';
  static const String topProducts = 'الأكثر مبيعاً';
  static const String byKind = 'حسب النوع (قبل خصم الفاتورة)';
  static const String stockValueByKind = 'قيمة المخزون حسب النوع';
  static const String estimatedCostLines = 'أسطر بكلفة تقديرية (عدسات لم تُستلم من المورد بعد)';
  static const String countsByStatus = 'العدد حسب الحالة';

  static const Map<String, String> reportNames = {
    'sales': 'المبيعات',
    'profit': 'الأرباح',
    'credit': 'ديون الزبائن',
    'stock': 'المخزون المنخفض',
    'jobs': 'الطلبات المتأخرة',
    'suppliers': 'أرصدة الموردين',
  };

  /// Column / total keys of the report tables.
  static const Map<String, String> reportColumns = {
    'period': 'الفترة',
    'invoices': 'الفواتير',
    'subtotal': 'قبل الخصم',
    'discount': 'الخصم',
    'total': 'الإجمالي',
    'balance': 'المتبقي',
    'revenue': 'المبيعات',
    'cost': 'الكلفة',
    'profit': 'الربح',
    'margin': 'الهامش %',
    'name': 'الاسم',
    'phone': 'الهاتف',
    'oldest': 'أقدم فاتورة',
    'days': 'الأيام',
    'customers': 'الزبائن',
    'kind': 'النوع',
    'brand': 'الماركة',
    'quantity': 'الكمية',
    'reorder_level': 'حد الطلب',
    'value': 'القيمة',
    'products': 'الأصناف',
    'number': 'الرقم',
    'patient': 'المراجع',
    'status': 'الحالة',
    'promised_date': 'موعد التسليم',
    'days_late': 'أيام التأخير',
    'overdue': 'المتأخرة',
    'open_orders': 'طلبات مفتوحة',
    'suppliers': 'الموردون',
    'method': 'الطريقة',
    'count': 'العدد',
    'amount': 'المبلغ',
    'qty': 'الكمية',
    'range': 'العمر (يوم)',
  };
  static const String creditAgeing = 'أعمار الديون (حسب أقدم فاتورة)';

  // Lab settings (P8)
  static const String settingsTitle = 'إعدادات المختبر';
  static const String labName = 'اسم المختبر';
  static const String logo = 'الشعار';
  static const String chooseLogo = 'اختيار شعار';
  static const String removeLogo = 'حذف الشعار';
  static const String logoHint = 'صورة PNG أو JPG بحجم 1 ميغابايت كحد أقصى.';
  static const String printHeader = 'ترويسة الطباعة (أسطر تحت اسم المختبر)';
  static const String printFooter = 'تذييل الطباعة';
  static const String maxDiscountPercent = 'أقصى خصم للموظفين (%)';
  static const String maxDiscountHint = 'الخصم الأعلى من هذه النسبة يحتاج المالك.';
  static const String settingsSaved = 'تم حفظ الإعدادات.';
  static const String errLogoTooLarge = 'حجم الشعار أكبر من 1 ميغابايت.';
}
