import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// `reports/*` (dashboard + reports, CSV export) and the lab settings (`lab/`).
class ReportsApiService {
  const ReportsApiService(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> dashboard() async =>
      await _client.get('reports/dashboard/') as Map<String, dynamic>;

  Future<Map<String, dynamic>> report(String name, Map<String, dynamic> query) async =>
      await _client.get('reports/$name/', query: query) as Map<String, dynamic>;

  Future<Uint8List> exportCsv(String name, Map<String, dynamic> query) =>
      _client.getBytes('reports/$name/', query: {...query, 'export': 'csv'});

  Future<Map<String, dynamic>> labSettings() async =>
      await _client.get('lab/') as Map<String, dynamic>;

  Future<Map<String, dynamic>> saveLabSettings(Map<String, dynamic> body) async =>
      await _client.patch('lab/', body: body) as Map<String, dynamic>;

  Future<Map<String, dynamic>> uploadLogo(List<int> bytes, String filename) async =>
      await _client.multipart('PATCH', 'lab/', files: {'logo': (bytes: bytes, filename: filename)})
          as Map<String, dynamic>;
}

final reportsApiServiceProvider = Provider<ReportsApiService>(
  (ref) => ReportsApiService(ref.watch(apiClientProvider)),
);
