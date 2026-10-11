import 'package:flutter_test/flutter_test.dart';
import 'package:optics_app/core/errors/app_exception.dart';
import 'package:optics_app/data/repositories/base_repository.dart';
import 'package:optics_app/services/connectivity_service.dart';

import '../helpers.dart';

class _Repo extends BaseRepository {
  _Repo(super.connectivity);
}

void main() {
  test('online read hits the server and refreshes the cache', () async {
    final connectivity = fakeConnectivity(serverUp: true);
    await connectivity.checkNow();
    String? saved;

    final value = await _Repo(connectivity).read<String>(
      remote: () async => 'server',
      cached: () async => 'cache',
      saveToCache: (v) async => saved = v,
    );

    expect(value, 'server');
    expect(saved, 'server');
    connectivity.dispose();
  });

  test('offline read uses the cache without calling the server', () async {
    final connectivity = fakeConnectivity(serverUp: false);
    await connectivity.checkNow();
    var remoteCalled = false;

    final value = await _Repo(connectivity).read<String>(
      remote: () async {
        remoteCalled = true;
        return 'server';
      },
      cached: () async => 'cache',
    );

    expect(value, 'cache');
    expect(remoteCalled, isFalse);
    connectivity.dispose();
  });

  test('network failure during read falls back to cache and marks offline', () async {
    final connectivity = fakeConnectivity(serverUp: true);
    await connectivity.checkNow();

    final value = await _Repo(
      connectivity,
    ).read<String>(remote: () async => throw const NetworkException(), cached: () async => 'cache');

    expect(value, 'cache');
    expect(connectivity.status, ConnectionStatus.offline);
    connectivity.dispose();
  });

  test('offline write is refused with OfflineWriteException', () async {
    final connectivity = fakeConnectivity(serverUp: false);
    await connectivity.checkNow();

    await expectLater(
      _Repo(connectivity).write(() async => 'saved'),
      throwsA(isA<OfflineWriteException>()),
    );
    connectivity.dispose();
  });

  test('online write goes to the server', () async {
    final connectivity = fakeConnectivity(serverUp: true);
    await connectivity.checkNow();
    expect(await _Repo(connectivity).write(() async => 'saved'), 'saved');
    connectivity.dispose();
  });
}
