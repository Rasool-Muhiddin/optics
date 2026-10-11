import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/session.dart';
import 'api_client.dart';

class ActivationResult {
  const ActivationResult({required this.deviceKey, required this.labId, required this.labName});

  final String deviceKey;
  final int labId;
  final String labName;
}

class LoginResult {
  const LoginResult({required this.token, required this.session});

  final String token;
  final Session session;
}

/// `desktop/activate/`, `desktop/login/`, `auth/me/`, `auth/logout/`.
class AuthApiService {
  const AuthApiService(this._client);

  final ApiClient _client;

  Future<ActivationResult> activate({
    required String activationCode,
    required String deviceId,
    required String deviceName,
    required String appVersion,
  }) async {
    final json =
        await _client.post(
              'desktop/activate/',
              body: {
                'activation_code': activationCode,
                'device_id': deviceId,
                'device_name': deviceName,
                'app_version': appVersion,
              },
            )
            as Map<String, dynamic>;
    final lab = json['lab'] as Map<String, dynamic>;
    return ActivationResult(
      deviceKey: json['device_key'] as String,
      labId: lab['id'] as int,
      labName: lab['name'] as String? ?? '',
    );
  }

  Future<LoginResult> login({
    required String username,
    required String password,
    required String deviceKey,
    required String appVersion,
  }) async {
    final json =
        await _client.post(
              'desktop/login/',
              body: {
                'username': username,
                'password': password,
                'device_key': deviceKey,
                'app_version': appVersion,
              },
            )
            as Map<String, dynamic>;
    final token = json.remove('token') as String;
    return LoginResult(token: token, session: Session.fromJson(json));
  }

  Future<Session> me() async =>
      Session.fromJson(await _client.get('auth/me/') as Map<String, dynamic>);

  Future<void> logout() => _client.post('auth/logout/', body: const {});
}

final authApiServiceProvider = Provider<AuthApiService>(
  (ref) => AuthApiService(ref.watch(apiClientProvider)),
);
