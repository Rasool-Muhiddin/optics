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
}
