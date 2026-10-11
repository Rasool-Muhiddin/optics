import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/config/app_config.dart';

/// Where [AuthStorage] persists its values.
abstract class AuthStore {
  Future<Map<String, dynamic>> load();
  Future<void> save(Map<String, dynamic> data);
}

/// JSON file in the app-support directory (per Windows user).
class FileAuthStore implements AuthStore {
  FileAuthStore(this.path);

  final String path;

  static Future<FileAuthStore> inAppSupportDir() async {
    final dir = await getApplicationSupportDirectory();
    return FileAuthStore(p.join(dir.path, AppConfig.authFileName));
  }

  @override
  Future<Map<String, dynamic>> load() async {
    final file = File(path);
    if (!await file.exists()) return {};
    try {
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } on FormatException {
      return {};
    }
  }

  @override
  Future<void> save(Map<String, dynamic> data) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final tmp = File('$path.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(path);
  }
}

class MemoryAuthStore implements AuthStore {
  MemoryAuthStore([Map<String, dynamic>? initial]) : data = {...?initial};

  Map<String, dynamic> data;

  @override
  Future<Map<String, dynamic>> load() async => {...data};

  @override
  Future<void> save(Map<String, dynamic> data) async => this.data = {...data};
}

/// Device activation + login session, persisted locally.
///
/// - `device_id`: random, generated once per installation.
/// - `device_key` + `lab_name`: from `desktop/activate/`.
/// - `token` + `session`: from `desktop/login/` (session JSON lets the app start offline).
class AuthStorage {
  AuthStorage._(this._store, this._data);

  final AuthStore _store;
  final Map<String, dynamic> _data;

  static Future<AuthStorage> open([AuthStore? store]) async {
    final backing = store ?? await FileAuthStore.inAppSupportDir();
    return AuthStorage._(backing, await backing.load());
  }

  String? get deviceId => _data['device_id'] as String?;
  String? get deviceKey => _data['device_key'] as String?;
  String? get activatedLabName => _data['lab_name'] as String?;
  int? get activatedLabId => _data['lab_id'] as int?;
  String? get token => _data['token'] as String?;
  Map<String, dynamic>? get session => _data['session'] as Map<String, dynamic>?;

  bool get isActivated => deviceKey != null;

  /// Returns this installation's id, creating it on first use.
  Future<String> ensureDeviceId() async {
    final existing = deviceId;
    if (existing != null) return existing;
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _data['device_id'] = id;
    await _persist();
    return id;
  }

  Future<void> saveActivation({
    required String deviceKey,
    required int labId,
    required String labName,
  }) {
    _data
      ..['device_key'] = deviceKey
      ..['lab_id'] = labId
      ..['lab_name'] = labName
      ..remove('token')
      ..remove('session');
    return _persist();
  }

  Future<void> saveSession({required String token, required Map<String, dynamic> session}) {
    _data
      ..['token'] = token
      ..['session'] = session;
    return _persist();
  }

  Future<void> updateSession(Map<String, dynamic> session) {
    _data['session'] = session;
    return _persist();
  }

  Future<void> clearSession() {
    _data
      ..remove('token')
      ..remove('session');
    return _persist();
  }

  /// Forgets the activation (keeps `device_id`, so re-activating reuses the device slot).
  Future<void> clearActivation() {
    _data
      ..remove('device_key')
      ..remove('lab_id')
      ..remove('lab_name')
      ..remove('token')
      ..remove('session');
    return _persist();
  }

  Future<void> _persist() => _store.save(_data);
}

/// Opened in `main()` and injected with `overrideWithValue`.
final authStorageProvider = Provider<AuthStorage>(
  (ref) => throw UnimplementedError('authStorageProvider must be overridden in main()'),
);
