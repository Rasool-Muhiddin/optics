import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:optics_app/services/auth_storage.dart';
import 'package:optics_app/services/secret_store.dart';
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

    final secrets = MemorySecretStore();
    final storage = await AuthStorage.open(FileAuthStore(path), secrets);
    await storage.saveActivation(deviceKey: 'k', labId: 2, labName: 'مختبر');
    final reopened = await AuthStorage.open(FileAuthStore(path), secrets);
    expect(reopened.deviceKey, 'k');
    expect(reopened.activatedLabName, 'مختبر');
    // The secret is not in the JSON file.
    expect(await File(path).readAsString(), isNot(contains('"k"')));

    await File(path).writeAsString('{not json');
    expect((await AuthStorage.open(FileAuthStore(path), secrets)).activatedLabName, isNull);
  });

  test('plain-file token and device key are migrated once into the secret store', () async {
    final store = MemoryAuthStore({
      'device_id': 'd1',
      'device_key': 'old-key',
      'lab_id': 7,
      'lab_name': 'مختبر النور',
      'token': 'old-token',
      'session': {'role': 'x'},
    });
    final secrets = MemorySecretStore();
    final storage = await AuthStorage.open(store, secrets);

    expect((storage.deviceKey, storage.token), ('old-key', 'old-token'));
    expect(secrets.values, {'device_key': 'old-key', 'token': 'old-token'});
    expect(store.data.containsKey('device_key'), isFalse);
    expect(store.data.containsKey('token'), isFalse);
    expect(store.data['lab_name'], 'مختبر النور');

    // Next start: read from the secret store, nothing in the file.
    final again = await AuthStorage.open(store, secrets);
    expect((again.deviceKey, again.token), ('old-key', 'old-token'));

    await again.clearSession();
    expect(secrets.values.containsKey('token'), isFalse);
    await again.clearActivation();
    expect(secrets.values, isEmpty);
  });

  test('plain-file fallback store round-trips (Linux without libsecret)', () async {
    final dir = await Directory.systemTemp.createTemp('secrets');
    addTearDown(() => dir.delete(recursive: true));
    final store = PlainFileSecretStore(File(p.join(dir.path, 's.json')));
    await store.write('token', 't1');
    expect(await store.read('token'), 't1');
    await store.write('token', null);
    expect(await store.read('token'), isNull);
    expect(store.isEncrypted, isFalse);
  });
}
