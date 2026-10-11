import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:optics_app/data/api/api_client.dart';
import 'package:optics_app/data/api/auth_api_service.dart';
import 'package:optics_app/data/repositories/auth_repository.dart';
import 'package:optics_app/services/auth_storage.dart';

import '../helpers.dart';

Future<(AuthRepository, AuthStorage, List<String>)> _repo(
  FakeAuthServer server, [
  Map<String, dynamic>? stored,
]) async {
  final storage = await AuthStorage.open(MemoryAuthStore(stored));
  final events = <String>[];
  final api = ApiClient(
    baseUrl: 'http://test/api/v1',
    httpClient: MockClient(server.handle),
    tokenReader: () => storage.token,
  );
  final repo = AuthRepository(
    fakeConnectivity(serverUp: true),
    api: AuthApiService(api),
    storage: storage,
    clearCache: () async => events.add('cache-cleared'),
  );
  return (repo, storage, events);
}

void main() {
  test('activating for another lab wipes the read cache', () async {
    final (repo, storage, events) = await _repo(FakeAuthServer(), {
      'device_key': 'old',
      'lab_id': 99,
      'lab_name': 'Old lab',
    });
    await repo.activate('ABC123');
    expect(events, ['cache-cleared']);
    expect(storage.activatedLabId, 7);
  });

  test('re-activating the same lab keeps the cache', () async {
    final (repo, _, events) = await _repo(FakeAuthServer(), {'device_key': 'old', 'lab_id': 7});
    await repo.activate('ABC123');
    expect(events, isEmpty);
  });

  test('server error at startup keeps the stored session', () async {
    final server = FakeAuthServer()
      ..tokens.add('saved')
      ..meError = (status: 500, code: 'server_error');
    final (repo, storage, _) = await _repo(server, {
      'device_key': 'device-key-1',
      'token': 'saved',
      'session': sessionJson(),
    });
    final restored = await repo.restore();
    expect(restored.session, isNotNull);
    expect(restored.offline, isTrue);
    expect(storage.token, 'saved');
  });

  test('logout forgets the token even if the server is unreachable', () async {
    final server = FakeAuthServer()..down = true;
    final (repo, storage, _) = await _repo(server, {'device_key': 'k', 'token': 't'});
    await repo.logout();
    expect(storage.token, isNull);
    expect(storage.deviceKey, 'k');
  });
}
