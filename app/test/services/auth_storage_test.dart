import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:optics_app/services/auth_storage.dart';
import 'package:path/path.dart' as p;

void main() {
  test('device id is generated once and persisted', () async {
    final store = MemoryAuthStore();
    final storage = await AuthStorage.open(store);
    final id = await storage.ensureDeviceId();

    expect(id, hasLength(32));
    expect(await storage.ensureDeviceId(), id);
    expect((await AuthStorage.open(store)).deviceId, id);
  });

  test('activation clears any session; clearActivation keeps the device id', () async {
    final storage = await AuthStorage.open(MemoryAuthStore({'device_id': 'd1'}));
    await storage.saveSession(token: 'old', session: {'a': 1});
    await storage.saveActivation(deviceKey: 'k', labId: 1, labName: 'Lab');

    expect(storage.isActivated, isTrue);
    expect(storage.token, isNull);

    await storage.saveSession(token: 't', session: {'a': 1});
    await storage.clearSession();
    expect(storage.token, isNull);
    expect(storage.deviceKey, 'k');

    await storage.clearActivation();
    expect(storage.isActivated, isFalse);
    expect(storage.activatedLabName, isNull);
    expect(storage.deviceId, 'd1');
  });

  test('file store round-trips and tolerates a corrupt file', () async {
    final dir = await Directory.systemTemp.createTemp('auth_store');
    addTearDown(() => dir.delete(recursive: true));
    final path = p.join(dir.path, 'nested', 'auth.json');

    final storage = await AuthStorage.open(FileAuthStore(path));
    await storage.saveActivation(deviceKey: 'k', labId: 2, labName: 'مختبر');
    final reopened = await AuthStorage.open(FileAuthStore(path));
    expect(reopened.deviceKey, 'k');
    expect(reopened.activatedLabName, 'مختبر');

    await File(path).writeAsString('{not json');
    expect((await AuthStorage.open(FileAuthStore(path))).isActivated, isFalse);
  });
}
