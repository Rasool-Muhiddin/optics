import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// `lab/users/`, `lab/devices/`, `lab/usage/` (owner only).
class UsersApiService {
  const UsersApiService(this._client);

  final ApiClient _client;

  Future<dynamic> users() => _client.get('lab/users/', query: {'page_size': 200});

  Future<Map<String, dynamic>> saveUser(int? id, Map<String, dynamic> body) async =>
      await (id == null
              ? _client.post('lab/users/', body: body)
              : _client.patch('lab/users/$id/', body: body))
          as Map<String, dynamic>;

  Future<dynamic> devices() => _client.get('lab/devices/', query: {'page_size': 200});

  Future<Map<String, dynamic>> saveDevice(int id, Map<String, dynamic> body) async =>
      await _client.patch('lab/devices/$id/', body: body) as Map<String, dynamic>;

  Future<Map<String, dynamic>> usage() async =>
      await _client.get('lab/usage/') as Map<String, dynamic>;
}

final usersApiServiceProvider = Provider<UsersApiService>(
  (ref) => UsersApiService(ref.watch(apiClientProvider)),
);
