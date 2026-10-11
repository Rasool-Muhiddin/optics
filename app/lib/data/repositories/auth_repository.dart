import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../models/session.dart';
import '../../services/auth_storage.dart';
import '../../services/connectivity_service.dart';
import '../api/auth_api_service.dart';
import '../cache/cache_database.dart';
import 'base_repository.dart';

/// Result of restoring a stored session at startup.
class RestoredSession {
  const RestoredSession({this.session, this.offline = false, this.error});

  /// Null when the user must log in again.
  final Session? session;

  /// True when the session came from disk because the server is unreachable.
  final bool offline;

  /// Why the stored session was dropped (e.g. `license_expired`), if it was.
  final AppException? error;
}

/// Device activation and login. Both are writes, so they need the server (online-first).
class AuthRepository extends BaseRepository {
  AuthRepository(super.connectivity, {required this.api, required this.storage, this.clearCache});

  final AuthApiService api;
  final AuthStorage storage;

  /// Wipes the read cache (called when this device is activated for a different lab).
  final Future<void> Function()? clearCache;

  Future<void> activate(String activationCode) async {
    final deviceId = await storage.ensureDeviceId();
    final result = await write(
      () => api.activate(
        activationCode: activationCode.trim(),
        deviceId: deviceId,
        deviceName: _deviceName(),
        appVersion: AppConfig.appVersion,
      ),
    );
    final previousLab = storage.activatedLabId;
    if (previousLab != null && previousLab != result.labId) await clearCache?.call();
    await storage.saveActivation(
      deviceKey: result.deviceKey,
      labId: result.labId,
      labName: result.labName,
    );
  }

  Future<Session> login(String username, String password) async {
    final deviceKey = storage.deviceKey;
    if (deviceKey == null) {
      throw const ApiException(statusCode: 403, code: 'device_not_activated');
    }
    final result = await write(
      () => api.login(
        username: username.trim(),
        password: password,
        deviceKey: deviceKey,
        appVersion: AppConfig.appVersion,
      ),
    );
    await storage.saveSession(token: result.token, session: result.session.raw);
    return result.session;
  }

  /// Validates the stored token with the server, or falls back to the stored
  /// session when the server is unreachable (read-only offline use).
  Future<RestoredSession> restore() async {
    if (storage.token == null) return const RestoredSession();
    final cached = storage.session;
    try {
      var fromServer = true;
      final session = await read<Session?>(
        remote: api.me,
        cached: () async {
          fromServer = false;
          return cached == null ? null : Session.fromJson(cached);
        },
        saveToCache: (s) async => storage.updateSession(s!.raw),
      );
      if (session == null) await storage.clearSession();
      return RestoredSession(session: session, offline: !fromServer);
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        // Token revoked, license expired, membership disabled…: log in again.
        await storage.clearSession();
        return RestoredSession(error: e);
      }
      // Server error: keep the session and work from the cache meanwhile.
      return RestoredSession(
        session: cached == null ? null : Session.fromJson(cached),
        offline: true,
        error: e,
      );
    }
  }

  /// Revokes the token on the server when reachable; always forgets it locally.
  Future<void> logout() async {
    if (storage.token != null && !connectivity.isOffline) {
      try {
        await api.logout();
      } on AppException {
        // Offline or already revoked: the local logout still happens.
      }
    }
    await storage.clearSession();
  }

  Future<void> forgetActivation() => storage.clearActivation();

  static String _deviceName() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return '';
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(connectivityServiceProvider),
    api: ref.watch(authApiServiceProvider),
    storage: ref.watch(authStorageProvider),
    clearCache: () => ref.read(cacheDatabaseProvider).clearAll(),
  ),
);
