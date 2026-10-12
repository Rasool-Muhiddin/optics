import 'json.dart';

/// A lab member as the owner manages it (`lab/users/`).
class LabMember {
  const LabMember({
    required this.id,
    required this.username,
    this.firstName = '',
    this.lastName = '',
    this.phone = '',
    this.role = 'staff',
    this.canViewCosts = false,
    this.canManageInventory = false,
    this.isActive = true,
    this.lastLogin,
  });

  factory LabMember.fromJson(Map<String, dynamic> j) => LabMember(
    id: Json.int0(j['id']),
    username: Json.str(j['username']),
    firstName: Json.str(j['first_name']),
    lastName: Json.str(j['last_name']),
    phone: Json.str(j['phone']),
    role: Json.str(j['role']).isEmpty ? 'staff' : Json.str(j['role']),
    canViewCosts: Json.boolean(j['can_view_costs']),
    canManageInventory: Json.boolean(j['can_manage_inventory']),
    isActive: Json.boolean(j['is_active'], fallback: true),
    lastLogin: Json.date(j['last_login']),
  );

  final int id;
  final String username;
  final String firstName;
  final String lastName;
  final String phone;
  final String role;
  final bool canViewCosts;
  final bool canManageInventory;
  final bool isActive;
  final DateTime? lastLogin;

  bool get isOwner => role == 'owner';

  String get displayName {
    final full = '$firstName $lastName'.trim();
    return full.isEmpty ? username : full;
  }

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty ||
        username.toLowerCase().contains(q) ||
        displayName.toLowerCase().contains(q) ||
        phone.contains(q);
  }
}

/// An activated desktop installation (`lab/devices/`).
class LabDevice {
  const LabDevice({
    required this.id,
    required this.deviceId,
    this.name = '',
    this.isActive = true,
    this.appVersion = '',
    this.lastLoginAt,
    this.createdAt,
  });

  factory LabDevice.fromJson(Map<String, dynamic> j) => LabDevice(
    id: Json.int0(j['id']),
    deviceId: Json.str(j['device_id']),
    name: Json.str(j['name']),
    isActive: Json.boolean(j['is_active'], fallback: true),
    appVersion: Json.str(j['app_version']),
    lastLoginAt: Json.date(j['last_login_at']),
    createdAt: Json.date(j['created_at']),
  );

  final int id;
  final String deviceId;
  final String name;
  final bool isActive;
  final String appVersion;
  final DateTime? lastLoginAt;
  final DateTime? createdAt;
}

/// `lab/usage/`: active users/devices against the plan limits (0 = unlimited).
class LabUsage {
  const LabUsage({this.users = 0, this.maxUsers = 0, this.devices = 0, this.maxDevices = 0});

  factory LabUsage.fromJson(Map<String, dynamic> j) => LabUsage(
    users: Json.int0(j['users']),
    maxUsers: Json.int0(j['max_users']),
    devices: Json.int0(j['devices']),
    maxDevices: Json.int0(j['max_devices']),
  );

  final int users;
  final int maxUsers;
  final int devices;
  final int maxDevices;

  bool get usersFull => maxUsers > 0 && users >= maxUsers;
  bool get devicesFull => maxDevices > 0 && devices >= maxDevices;
}
