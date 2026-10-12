/// Route paths. Feature screens register in `app_router.dart` as they are built.
class AppRoutes {
  const AppRoutes._();

  static const String splash = '/splash';
  static const String activate = '/activate';
  static const String login = '/login';
  static const String doctorLogin = '/doctor-login';

  // Doctor mode (own layout).
  static const String doctorHome = '/doctor';
  static const String doctorLabs = '/doctor/labs';

  // Inside the main layout (sidebar).
  static const String home = '/';
  static const String patients = '/patients';
  static const String pos = '/pos';
  static const String invoices = '/invoices';
  static const String credit = '/credit';
  static const String jobs = '/jobs';
  static const String inventory = '/inventory';
  static const String orders = '/orders';
  static const String referrals = '/referrals';
  static const String reports = '/reports';
  static const String users = '/users';
  static const String settings = '/settings';

  static String productDetail(int id) => '$inventory/$id';
  static String patientDetail(int id) => '$patients/$id';
  static String invoiceDetail(int id) => '$invoices/$id';
  static String jobDetail(int id) => '$jobs/$id';
  static String orderDetail(int id) => '$orders/$id';
  static String referralDetail(int id) => '$referrals/$id';

  static const Set<String> _public = {splash, activate, login, doctorLogin};

  static bool isDoctorArea(String location) =>
      location == doctorHome || location.startsWith('$doctorHome/');

  static bool isPublic(String location) => _public.contains(location);
}
