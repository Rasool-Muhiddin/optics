import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// Doctor side: `doctor/*` (doctor accounts only).
class DoctorApiService {
  const DoctorApiService(this._client);

  final ApiClient _client;

  Future<dynamic> links() => _client.get('doctor/links/', query: {'page_size': 200});

  Future<Map<String, dynamic>> requestLink(String code) async =>
      await _client.post('doctor/links/', body: {'code': code}) as Map<String, dynamic>;

  Future<Map<String, dynamic>> linkAction(int id, String action) async =>
      await _client.post('doctor/links/$id/$action/', body: const {}) as Map<String, dynamic>;

  Future<dynamic> referrals(Map<String, dynamic> query) =>
      _client.get('doctor/referrals/', query: query);

  Future<Map<String, dynamic>> sendReferral(Map<String, dynamic> body) async =>
      await _client.post('doctor/referrals/', body: body) as Map<String, dynamic>;
}

/// Lab side: `referrals/*` (plan `doctor_linking`).
class ReferralsApiService {
  const ReferralsApiService(this._client);

  final ApiClient _client;

  Future<dynamic> inbox(Map<String, dynamic> query) => _client.get('referrals/', query: query);

  Future<Map<String, dynamic>> referral(int id) async =>
      await _client.get('referrals/$id/') as Map<String, dynamic>;

  Future<Map<String, dynamic>> action(int id, String action, Map<String, dynamic> body) async =>
      await _client.post('referrals/$id/$action/', body: body) as Map<String, dynamic>;

  Future<Map<String, dynamic>> summary() async =>
      await _client.get('referrals/summary/') as Map<String, dynamic>;

  Future<dynamic> links() => _client.get('referrals/links/', query: {'page_size': 200});

  Future<Map<String, dynamic>> requestLink(String code) async =>
      await _client.post('referrals/links/', body: {'code': code}) as Map<String, dynamic>;

  Future<Map<String, dynamic>> linkAction(int id, String action) async =>
      await _client.post('referrals/links/$id/$action/', body: const {}) as Map<String, dynamic>;

  Future<String> labCode({bool regenerate = false}) async {
    final json = regenerate
        ? await _client.post('referrals/links/code/', body: const {})
        : await _client.get('referrals/links/code/');
    return (json as Map<String, dynamic>)['code'] as String? ?? '';
  }
}

final doctorApiServiceProvider = Provider<DoctorApiService>(
  (ref) => DoctorApiService(ref.watch(apiClientProvider)),
);

final referralsApiServiceProvider = Provider<ReferralsApiService>(
  (ref) => ReferralsApiService(ref.watch(apiClientProvider)),
);
