/// The logged-in session as returned by `desktop/login/` and `auth/me/`.
class Session {
  const Session({
    required this.user,
    required this.membership,
    required this.lab,
    required this.plan,
    this.deviceName,
    required this.raw,
  });

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    user: SessionUser.fromJson(json['user'] as Map<String, dynamic>),
    membership: Membership.fromJson(json['membership'] as Map<String, dynamic>),
    lab: LabInfo.fromJson(json['lab'] as Map<String, dynamic>),
    plan: PlanInfo.fromJson(json['plan'] as Map<String, dynamic>),
    deviceName: (json['device'] as Map<String, dynamic>?)?['name'] as String?,
    raw: json,
  );

  final SessionUser user;
  final Membership membership;
  final LabInfo lab;
  final PlanInfo plan;
  final String? deviceName;

  /// Server JSON, kept so the session can be restored from disk while offline.
  final Map<String, dynamic> raw;

  bool get isOwner => membership.isOwner;

  /// UI hint only — the server enforces plan features.
  bool hasFeature(String flag) => plan.features[flag] ?? false;
}

class SessionUser {
  const SessionUser({
    required this.id,
    required this.username,
    this.firstName = '',
    this.lastName = '',
  });

  factory SessionUser.fromJson(Map<String, dynamic> json) => SessionUser(
    id: json['id'] as int,
    username: json['username'] as String? ?? '',
    firstName: json['first_name'] as String? ?? '',
    lastName: json['last_name'] as String? ?? '',
  );

  final int id;
  final String username;
  final String firstName;
  final String lastName;

  String get displayName {
    final full = '$firstName $lastName'.trim();
    return full.isEmpty ? username : full;
  }
}

class Membership {
  const Membership({required this.role, required this.isOwner, required this.canViewCosts});

  factory Membership.fromJson(Map<String, dynamic> json) => Membership(
    role: json['role'] as String? ?? 'staff',
    isOwner: json['is_owner'] as bool? ?? false,
    canViewCosts: json['can_view_costs'] as bool? ?? false,
  );

  /// `owner` | `staff` (extendable).
  final String role;
  final bool isOwner;
  final bool canViewCosts;
}

class LabInfo {
  const LabInfo({
    required this.id,
    required this.name,
    this.phone = '',
    this.address = '',
    this.logo,
    this.currency = 'IQD',
    this.printHeader = '',
    this.printFooter = '',
  });

  factory LabInfo.fromJson(Map<String, dynamic> json) => LabInfo(
    id: json['id'] as int,
    name: json['name'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    address: json['address'] as String? ?? '',
    logo: json['logo'] as String?,
    currency: json['currency'] as String? ?? 'IQD',
    printHeader: json['print_header'] as String? ?? '',
    printFooter: json['print_footer'] as String? ?? '',
  );

  final int id;
  final String name;
  final String phone;
  final String address;
  final String? logo;
  final String currency;
  final String printHeader;
  final String printFooter;
}

class PlanInfo {
  const PlanInfo({
    required this.code,
    required this.name,
    this.features = const {},
    this.limits = const {},
    this.expiresOn,
  });

  factory PlanInfo.fromJson(Map<String, dynamic> json) => PlanInfo(
    code: json['code'] as String? ?? '',
    name: json['name'] as String? ?? '',
    features: {
      for (final e in (json['features'] as Map<String, dynamic>? ?? const {}).entries)
        e.key: e.value == true,
    },
    limits: {
      for (final e in (json['limits'] as Map<String, dynamic>? ?? const {}).entries)
        e.key: (e.value as num?)?.toInt() ?? 0,
    },
    expiresOn: DateTime.tryParse(json['expires_on'] as String? ?? ''),
  );

  final String code;
  final String name;
  final Map<String, bool> features;
  final Map<String, int> limits;
  final DateTime? expiresOn;
}

/// Plan feature flags (must match `apps/billing/features.py`).
class Features {
  const Features._();

  static const String doctorLinking = 'doctor_linking';
  static const String reportExport = 'report_export';
}
