import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// `jobs/*`: customer glasses jobs.
class JobsApiService {
  const JobsApiService(this._client);

  final ApiClient _client;

  Future<dynamic> jobs(Map<String, dynamic> query) => _client.get('jobs/', query: query);

  Future<Map<String, dynamic>> job(int id) async =>
      await _client.get('jobs/$id/') as Map<String, dynamic>;

  Future<Map<String, dynamic>> save(int? id, Map<String, dynamic> body) async =>
      await (id == null
              ? _client.post('jobs/', body: body)
              : _client.patch('jobs/$id/', body: body))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> changeStatus(int id, String status, String note) async =>
      await _client.post('jobs/$id/status/', body: {'status': status, 'note': note})
          as Map<String, dynamic>;
}

final jobsApiServiceProvider = Provider<JobsApiService>(
  (ref) => JobsApiService(ref.watch(apiClientProvider)),
);
