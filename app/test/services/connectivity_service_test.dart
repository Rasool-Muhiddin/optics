import 'package:flutter_test/flutter_test.dart';
import 'package:optics_app/services/connectivity_service.dart';

import '../helpers.dart';

void main() {
  test('starts unknown, becomes online when /health/ answers ok', () async {
    final service = fakeConnectivity(serverUp: true);
    expect(service.status, ConnectionStatus.unknown);
    expect(await service.checkNow(), ConnectionStatus.online);
    expect(service.isOnline, isTrue);
    service.dispose();
  });

  test('becomes offline when the server is unreachable and emits the change', () async {
    final service = fakeConnectivity(serverUp: false);
    final emitted = expectLater(service.statusStream, emits(ConnectionStatus.offline));
    await service.checkNow();
    await emitted;
    expect(service.isOffline, isTrue);
    service.dispose();
  });
}
