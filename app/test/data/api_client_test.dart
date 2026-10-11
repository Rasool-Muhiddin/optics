import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:optics_app/core/errors/app_exception.dart';
import 'package:optics_app/data/api/api_client.dart';
import 'package:http/testing.dart';

import '../helpers.dart';

void main() {
  group('ApiClient', () {
    test('builds URLs from base + path + query', () {
      final api = ApiClient(baseUrl: 'http://h/api/v1/');
      expect(api.uri('health/').toString(), 'http://h/api/v1/health/');
      expect(
        api.uri('/patients/', {'page': 2, 'search': null}).toString(),
        'http://h/api/v1/patients/?page=2',
      );
    });

    test('POST sends JSON with explicit Content-Length and token', () async {
      late http.Request captured;
      final api = ApiClient(
        baseUrl: 'http://h/api/v1',
        tokenReader: () => 'abc123',
        httpClient: MockClient((request) async {
          captured = request;
          return jsonResponse({'id': 1}, 201);
        }),
      );

      final result = await api.post('patients/', body: {'full_name': 'علي'});

      expect(result, {'id': 1});
      final bytes = utf8.encode(jsonEncode({'full_name': 'علي'}));
      expect(captured.headers['content-length'], bytes.length.toString());
      expect(captured.headers['content-type'], startsWith('application/json'));
      expect(captured.headers['authorization'], 'Token abc123');
      expect(captured.bodyBytes, bytes);
    });

    test('maps server error body to ApiException', () async {
      final api = fakeApi(
        (_) async => jsonResponse({'detail': 'Stock too low.', 'code': 'insufficient_stock'}, 400),
      );
      await expectLater(
        api.get('x/'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'insufficient_stock')
              .having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });

    test('keeps validation field errors', () async {
      final api = fakeApi(
        (_) async => jsonResponse({
          'detail': 'Validation failed.',
          'code': 'validation_error',
          'errors': {
            'qty': ['bad'],
          },
        }, 400),
      );
      await expectLater(
        api.post('x/', body: {}),
        throwsA(isA<ApiException>().having((e) => e.fieldErrors, 'fieldErrors', contains('qty'))),
      );
    });

    test('401 becomes UnauthorizedException', () async {
      final api = fakeApi(
        (_) async =>
            jsonResponse({'detail': 'Invalid token.', 'code': 'authentication_failed'}, 401),
      );
      await expectLater(api.get('x/'), throwsA(isA<UnauthorizedException>()));
    });

    test('non-JSON 500 falls back to server_error', () async {
      final api = fakeApi((_) async => http.Response('<html>oops</html>', 500));
      await expectLater(
        api.get('x/'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'server_error')),
      );
    });

    test('connection failure becomes NetworkException', () async {
      final api = fakeApi((_) async => throw http.ClientException('refused'));
      await expectLater(api.get('x/'), throwsA(isA<NetworkException>()));
    });

    test('timeout becomes NetworkException(timeout)', () async {
      final api = ApiClient(
        baseUrl: 'http://h/api/v1',
        timeout: const Duration(milliseconds: 10),
        httpClient: MockClient((_) => Completer<http.Response>().future),
      );
      await expectLater(
        api.get('x/'),
        throwsA(isA<NetworkException>().having((e) => e.isTimeout, 'isTimeout', true)),
      );
    });
  });
}
