import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_exception.dart';
import '../data/repositories/auth_repository.dart';
import '../models/session.dart';
import 'auth_storage.dart';

/// Where the app is in the activation → login → work flow.
sealed class AuthState {
  const AuthState();
}

/// This installation has no device key yet.
class NeedsActivation extends AuthState {
  const NeedsActivation();
}

/// Activated, no valid session. [error] explains why a previous session ended, if known.
class LoggedOut extends AuthState {
  const LoggedOut({required this.labName, this.error});

  final String labName;
  final AppException? error;
}

class LoggedIn extends AuthState {
  const LoggedIn(this.session, {this.restoredOffline = false});

  final Session session;

  /// The session was restored from disk while the server was unreachable.
  final bool restoredOffline;
}

/// Drives the auth flow; the router redirects on its state. Errors from
/// [activate] / [login] are rethrown for the form to show (state stays as is).
class AuthController extends AsyncNotifier<AuthState> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);
  AuthStorage get _storage => ref.read(authStorageProvider);

  @override
  Future<AuthState> build() async {
    if (!_storage.isActivated) return const NeedsActivation();
    try {
      final restored = await _repo.restore();
      final session = restored.session;
      if (session != null) return LoggedIn(session, restoredOffline: restored.offline);
      return _loggedOut(error: restored.error);
    } catch (_) {
      return _loggedOut();
    }
  }

  Future<void> activate(String activationCode) async {
    await _repo.activate(activationCode);
    state = AsyncData(_loggedOut());
  }

  Future<void> login(String username, String password) async {
    final session = await _repo.login(username, password);
    state = AsyncData(LoggedIn(session));
  }

  Future<void> logout() async {
    await _repo.logout();
    state = AsyncData(_loggedOut());
  }

  /// Back to the activation screen (e.g. the lab got a new activation code).
  Future<void> reactivate() async {
    await _repo.forgetActivation();
    state = const AsyncData(NeedsActivation());
  }

  /// The server rejected our token mid-session (revoked, device deactivated…).
  Future<void> sessionExpired() async {
    if (state.value is! LoggedIn) return;
    await _storage.clearSession();
    state = AsyncData(
      _loggedOut(error: const ApiException(statusCode: 401, code: 'not_authenticated')),
    );
  }

  LoggedOut _loggedOut({AppException? error}) =>
      LoggedOut(labName: _storage.activatedLabName ?? '', error: error);
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);

/// The current session, or null when logged out.
final sessionProvider = Provider<Session?>((ref) {
  final state = ref.watch(authControllerProvider).value;
  return state is LoggedIn ? state.session : null;
});
