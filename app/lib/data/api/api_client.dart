import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../services/auth_controller.dart';
import '../../services/auth_storage.dart';

/// Returns the current auth token, or null when logged out.
typedef TokenReader = FutureOr<String?> Function();

/// Low-level HTTP client shared by every domain `*ApiService`.
///
/// - Sends/receives JSON, adds `Authorization: Token <key>` when a token exists.
/// - Sets `Content-Length` explicitly on bodies (Django runserver on Windows
///   mishandles chunked requests).
/// - Maps failures to typed [AppException]s.
class ApiClient {
  ApiClient({
    String baseUrl = AppConfig.apiBaseUrl,
    http.Client? httpClient,
    this.tokenReader,
    this.onUnauthorized,
    this.timeout = AppConfig.apiTimeout,
  }) : baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
       _http = httpClient ?? http.Client();

  final String baseUrl;
  final Duration timeout;
  final http.Client _http;
  final TokenReader? tokenReader;

  /// Called when an authenticated request gets 401 (token revoked, device deactivated…).
  final void Function(UnauthorizedException error)? onUnauthorized;

  Future<dynamic> get(String path, {Map<String, dynamic>? query, Duration? timeout}) =>
      send('GET', path, query: query, timeout: timeout);

  Future<dynamic> post(String path, {Object? body}) => send('POST', path, body: body);

  Future<dynamic> put(String path, {Object? body}) => send('PUT', path, body: body);

  Future<dynamic> patch(String path, {Object? body}) => send('PATCH', path, body: body);

  Future<dynamic> delete(String path) => send('DELETE', path);

  /// Raw body of a GET (e.g. a CSV export). Errors map like [send].
  Future<Uint8List> getBytes(String path, {Map<String, dynamic>? query}) async {
    final request = http.Request('GET', uri(path, query));
    final response = await _transport(request);
    if (response.statusCode >= 200 && response.statusCode < 300) return response.bodyBytes;
    return await _guard(request, () => _handle(response)) as Uint8List;
  }

  /// `multipart/form-data` (file uploads, e.g. the lab logo). [files]: field → (bytes, filename).
  Future<dynamic> multipart(
    String method,
    String path, {
    Map<String, String> fields = const {},
    Map<String, ({List<int> bytes, String filename})> files = const {},
  }) async {
    final request = http.MultipartRequest(method, uri(path))..fields.addAll(fields);
    for (final f in files.entries) {
      request.files.add(
        http.MultipartFile.fromBytes(f.key, f.value.bytes, filename: f.value.filename),
      );
    }
    final response = await _transport(request);
    return _guard(request, () => _handle(response));
  }

  /// Adds auth headers, sends, and maps transport failures to [NetworkException].
  Future<http.Response> _transport(http.BaseRequest request, {Duration? timeout}) async {
    request.headers[HttpHeaders.acceptHeader] = 'application/json';
    final token = await tokenReader?.call();
    if (token != null && token.isNotEmpty) {
      request.headers[HttpHeaders.authorizationHeader] = 'Token $token';
    }
    try {
      final streamed = await _http.send(request).timeout(timeout ?? this.timeout);
      return await http.Response.fromStream(streamed).timeout(timeout ?? this.timeout);
    } on TimeoutException {
      throw const NetworkException(timeout: true);
    } on SocketException catch (e) {
      throw NetworkException(detail: e.message);
    } on http.ClientException catch (e) {
      throw NetworkException(detail: e.message);
    }
  }

  dynamic _guard(http.BaseRequest request, dynamic Function() handle) {
    try {
      return handle();
    } on UnauthorizedException catch (e) {
      if (request.headers.containsKey(HttpHeaders.authorizationHeader)) onUnauthorized?.call(e);
      rethrow;
    }
  }

  Uri uri(String path, [Map<String, dynamic>? query]) {
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    final uri = Uri.parse('$baseUrl/$cleanPath');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        for (final entry in query.entries)
          if (entry.value != null) entry.key: entry.value.toString(),
      },
    );
  }

  Future<dynamic> send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    Duration? timeout,
  }) async {
    final request = http.Request(method, uri(path, query))
      ..headers[HttpHeaders.acceptHeader] = 'application/json';

    final token = await tokenReader?.call();
    final authenticated = token != null && token.isNotEmpty;
    if (authenticated) {
      request.headers[HttpHeaders.authorizationHeader] = 'Token $token';
    }

    if (body != null) {
      final bytes = utf8.encode(jsonEncode(body));
      request
        ..headers[HttpHeaders.contentTypeHeader] = 'application/json; charset=utf-8'
        ..headers[HttpHeaders.contentLengthHeader] = bytes.length.toString()
        ..bodyBytes = bytes;
    }

    final http.Response response;
    try {
      final streamed = await _http.send(request).timeout(timeout ?? this.timeout);
      response = await http.Response.fromStream(streamed).timeout(timeout ?? this.timeout);
    } on TimeoutException {
      throw const NetworkException(timeout: true);
    } on SocketException catch (e) {
      throw NetworkException(detail: e.message);
    } on http.ClientException catch (e) {
      throw NetworkException(detail: e.message);
    }

    try {
      return _handle(response);
    } on UnauthorizedException catch (e) {
      if (authenticated) onUnauthorized?.call(e);
      rethrow;
    }
  }

  dynamic _handle(http.Response response) {
    final decoded = _decode(response);
    final status = response.statusCode;
    if (status >= 200 && status < 300) return decoded;

    final map = decoded is Map<String, dynamic> ? decoded : const <String, dynamic>{};
    final code = map['code']?.toString() ?? _defaultCode(status);
    final detail = map['detail']?.toString();

    if (status == 401) throw UnauthorizedException(code: code, detail: detail);
    throw ApiException(
      statusCode: status,
      code: code,
      detail: detail,
      fieldErrors: map['errors'] is Map<String, dynamic>
          ? map['errors'] as Map<String, dynamic>
          : null,
      errorCodes: map['error_codes'] is Map<String, dynamic>
          ? map['error_codes'] as Map<String, dynamic>
          : null,
    );
  }

  dynamic _decode(http.Response response) {
    if (response.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      return null;
    }
  }

  static String _defaultCode(int status) => switch (status) {
    400 => 'invalid',
    401 => 'not_authenticated',
    403 => 'permission_denied',
    404 => 'not_found',
    405 => 'method_not_allowed',
    429 => 'throttled',
    >= 500 => 'server_error',
    _ => 'error',
  };

  void close() => _http.close();
}

/// Underlying HTTP client (overridden with a `MockClient` in tests).
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    httpClient: ref.watch(httpClientProvider),
    tokenReader: () => ref.read(authStorageProvider).token,
    onUnauthorized: (_) => ref.read(authControllerProvider.notifier).sessionExpired(),
  ),
);
