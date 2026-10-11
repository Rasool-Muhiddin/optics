import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optics_app/data/api/api_client.dart';
import 'package:optics_app/data/api/health_api_service.dart';
import 'package:optics_app/services/connectivity_service.dart';

/// ApiClient whose server is a function.
ApiClient fakeApi(Future<http.Response> Function(http.Request request) handler) =>
    ApiClient(baseUrl: 'http://test/api/v1', httpClient: MockClient(handler));

http.Response jsonResponse(Object? body, int status) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// ConnectivityService backed by a fake health endpoint that is up or down.
ConnectivityService fakeConnectivity({required bool serverUp}) => ConnectivityService(
  HealthApiService(
    fakeApi((_) async {
      if (!serverUp) throw http.ClientException('connection refused');
      return jsonResponse({'status': 'ok', 'database': 'ok', 'version': '0.1.0'}, 200);
    }),
  ),
);
