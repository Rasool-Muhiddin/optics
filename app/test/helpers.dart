import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optics_app/app.dart';
import 'package:optics_app/data/api/api_client.dart';
import 'package:optics_app/data/api/health_api_service.dart';
import 'package:optics_app/data/cache/cache_database.dart';
import 'package:optics_app/services/auth_storage.dart';
import 'package:optics_app/services/connectivity_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

Map<String, dynamic> sessionJson({
  String role = 'owner',
  String labName = 'مختبر النور',
  bool doctorLinking = false,
}) => {
  'user': {'id': 1, 'username': 'owner1', 'first_name': 'أحمد', 'last_name': 'علي', 'email': ''},
  'membership': {
    'id': 1,
    'role': role,
    'is_owner': role == 'owner',
    'can_view_costs': role == 'owner',
    'can_manage_inventory': role == 'owner',
  },
  'lab': {
    'id': 7,
    'name': labName,
    'phone': '',
    'address': '',
    'logo': null,
    'currency': 'IQD',
    'print_header': '',
    'print_footer': '',
  },
  'plan': {
    'code': 'basic',
    'name': 'Basic',
    'features': {'doctor_linking': doctorLinking, 'report_export': false},
    'limits': {'max_users': 3, 'max_devices': 1},
    'expires_on': null,
  },
  'device': {'id': 3, 'name': 'PC'},
};

/// In-memory stand-in for the Django auth endpoints.
class FakeAuthServer {
  FakeAuthServer({
    this.activationCode = 'ABC123',
    this.password = 'pass',
    Map<String, dynamic>? session,
  }) : session = session ?? sessionJson();

  final String activationCode;
  final String password;
  Map<String, dynamic> session;

  /// Valid tokens; `me` with anything else is 401.
  final Set<String> tokens = {};

  /// When set, `auth/me/` answers with this error instead.
  ({int status, String code})? meError;

  /// When true every request fails at the network level.
  bool down = false;

  final List<http.Request> requests = [];

  /// Extra domain endpoints: key `"GET catalog/products/"` (path without query string).
  final Map<String, Future<http.Response> Function(http.Request request)> routes = {};

  /// Requests sent to [routes] (for asserting bodies).
  List<http.Request> sent(String method, String path) => [
    for (final r in requests)
      if (r.method == method && r.url.path.replaceFirst('/api/v1/', '') == path) r,
  ];

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    if (down) throw http.ClientException('connection refused');
    final path = request.url.path.replaceFirst('/api/v1/', '');
    final route = routes['${request.method} $path'];
    if (route != null) return route(request);
    final body = request.body.isEmpty ? <String, dynamic>{} : jsonDecode(request.body) as Map;
    final auth = request.headers['authorization']?.replaceFirst('Token ', '');

    switch (path) {
      case 'health/':
        return jsonResponse({'status': 'ok', 'database': 'ok', 'version': '0.1.0'}, 200);
      case 'desktop/activate/':
        if (body['activation_code'] != activationCode) {
          return jsonResponse({'detail': 'x', 'code': 'invalid_activation_code'}, 400);
        }
        return jsonResponse({
          'device_key': 'device-key-1',
          'device': {'id': 3, 'name': body['device_name']},
          'lab': {'id': session['lab']['id'], 'name': session['lab']['name']},
        }, 201);
      case 'desktop/login/':
        if (body['device_key'] != 'device-key-1') {
          return jsonResponse({'detail': 'x', 'code': 'device_not_activated'}, 403);
        }
        if (body['password'] != password) {
          return jsonResponse({'detail': 'x', 'code': 'invalid_credentials'}, 400);
        }
        final token = 'token-${tokens.length + 1}';
        tokens.add(token);
        return jsonResponse({'token': token, ...session}, 200);
      case 'auth/me/':
        if (auth == null || !tokens.contains(auth)) {
          return jsonResponse({'detail': 'x', 'code': 'authentication_failed'}, 401);
        }
        final error = meError;
        if (error != null) return jsonResponse({'detail': 'x', 'code': error.code}, error.status);
        return jsonResponse(session, 200);
      case 'auth/logout/':
        tokens.remove(auth);
        return http.Response('', 204);
    }
    return jsonResponse({'detail': 'x', 'code': 'not_found'}, 404);
  }
}

/// Pumps the whole app against [server] with in-memory auth storage.
Future<void> pumpOpticsApp(
  WidgetTester tester, {
  required FakeAuthServer server,
  required AuthStorage storage,
  ConnectivityService? connectivity,
  CacheDatabase? cache,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStorageProvider.overrideWithValue(storage),
        httpClientProvider.overrideWithValue(MockClient(server.handle)),
        connectivityServiceProvider.overrideWithValue(
          connectivity ?? fakeConnectivity(serverUp: !server.down),
        ),
        cacheDatabaseProvider.overrideWithValue(cache ?? await openTestCache()),
      ],
      child: const OpticsApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// In-memory cache DB usable inside `testWidgets` (no isolate, so futures complete).
Future<CacheDatabase> openTestCache() {
  sqfliteFfiInit();
  return CacheDatabase.open(path: inMemoryDatabasePath, factory: databaseFactoryFfiNoIsolate);
}

/// Storage of an activated, logged-in device.
Future<AuthStorage> loggedInStorage({Map<String, dynamic>? session, String token = 'token-1'}) =>
    AuthStorage.open(
      MemoryAuthStore({
        'device_id': 'dev-1',
        'device_key': 'device-key-1',
        'lab_id': 7,
        'lab_name': 'مختبر النور',
        'token': token,
        'session': session ?? sessionJson(),
      }),
    );

/// A server that already knows [token] (so `auth/me/` restores the session).
FakeAuthServer loggedInServer({Map<String, dynamic>? session, String token = 'token-1'}) =>
    FakeAuthServer(session: session)..tokens.add(token);

/// DRF-style page.
Map<String, dynamic> page(List<Map<String, dynamic>> rows) => {
  'count': rows.length,
  'next': null,
  'previous': null,
  'results': rows,
};

Map<String, dynamic> decodeBody(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;
