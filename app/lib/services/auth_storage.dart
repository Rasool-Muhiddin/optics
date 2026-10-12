import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/config/app_config.dart';
import 'secret_store.dart';

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
///
/// **Secrets** (`device_key`, `token`) live in a [SecretStore] (DPAPI / Keychain / libsecret);
/// `optics_auth.json` keeps only non-secret values. Files written by older versions are
/// migrated once on [open]: the secrets move to the store and are removed from the file.
class AuthStorage {
  AuthStorage._(this._store, this._data, this._secretStore, this._secrets);

  static const secretKeys = ['device_key', 'token'];

  final AuthStore _store;
  final Map<String, dynamic> _data;
  final SecretStore _secretStore;

  /// In-memory copy of the secrets (getters stay synchronous).
  final Map<String, String> _secrets;

  /// Without [store] the real files + the OS secret store are used; with a [store] (tests)
  /// the secrets default to memory unless [secrets] is given.
  static Future<AuthStorage> open([AuthStore? store, SecretStore? secrets]) async {
    final backing = store ?? await FileAuthStore.inAppSupportDir();
    final secretStore =
        secrets ?? (store == null ? await SecretStore.platform() : MemorySecretStore());
    final data = await backing.load();
    final values = <String, String>{};
    var migrated = false;
    for (final key in secretKeys) {
      final plain = data.remove(key);
      if (plain is String && plain.isNotEmpty) {
        await secretStore.write(key, plain); // one-time migration from the plain file
        values[key] = plain;
        migrated = true;
      } else {
        final stored = await secretStore.read(key);
        if (stored != null) values[key] = stored;
      }
    }
    if (migrated) await backing.save(data); // the plain copies are gone from disk
    return AuthStorage._(backing, data, secretStore, values);
  }

  /// False only on the Linux fallback without libsecret.
  bool get secretsEncrypted => _secretStore.isEncrypted;

  String? get deviceId => _data['device_id'] as String?;
  String? get deviceKey => _secrets['device_key'];
  String? get activatedLabName => _data['lab_name'] as String?;
  int? get activatedLabId => _data['lab_id'] as int?;
  String? get token => _secrets['token'];
  Map<String, dynamic>? get session => _data['session'] as Map<String, dynamic>?;

  bool get isActivated => deviceKey != null;

  /// The stored token/session belong to a doctor account (no lab, no activation).
  bool get isDoctorSession => token != null && session?['role'] == 'doctor';

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
  }) async {
    _data
      ..['lab_id'] = labId
      ..['lab_name'] = labName
      ..remove('session');
    await _setSecret('device_key', deviceKey);
    await _setSecret('token', null);
    return _persist();
  }

  Future<void> saveSession({required String token, required Map<String, dynamic> session}) async {
    _data['session'] = session;
    await _setSecret('token', token);
    return _persist();
  }

  Future<void> updateSession(Map<String, dynamic> session) {
    _data['session'] = session;
    return _persist();
  }

  Future<void> clearSession() async {
    _data.remove('session');
    await _setSecret('token', null);
    return _persist();
  }

  /// Forgets the activation (keeps `device_id`, so re-activating reuses the device slot).
  Future<void> clearActivation() async {
    _data
      ..remove('lab_id')
      ..remove('lab_name')
      ..remove('session');
    await _setSecret('device_key', null);
    await _setSecret('token', null);
    return _persist();
  }

  Future<void> _setSecret(String key, String? value) async {
    value == null ? _secrets.remove(key) : _secrets[key] = value;
    await _secretStore.write(key, value);
  }

  Future<void> _persist() => _store.save(_data);
}

/// Opened in `main()` and injected with `overrideWithValue`.
final authStorageProvider = Provider<AuthStorage>(
  (ref) => throw UnimplementedError('authStorageProvider must be overridden in main()'),
);
