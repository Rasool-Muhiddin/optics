import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../data/api/health_api_service.dart';

enum ConnectionStatus { unknown, online, offline }

/// Online = the Django server answers `GET /health/` with `status: ok`
/// (real server reachability, not mere network presence).
class ConnectivityService {
  ConnectivityService(this._healthApi, {this.interval = AppConfig.healthCheckInterval});

  final HealthApiService _healthApi;
  final Duration interval;

  final _controller = StreamController<ConnectionStatus>.broadcast();
  ConnectionStatus _status = ConnectionStatus.unknown;
  Timer? _timer;
  Future<ConnectionStatus>? _inFlight;

  ConnectionStatus get status => _status;
  Stream<ConnectionStatus> get statusStream => _controller.stream;

  bool get isOnline => _status == ConnectionStatus.online;
  bool get isOffline => _status == ConnectionStatus.offline;

  /// Starts periodic pings (and pings immediately).
  void start() {
    if (_timer != null) return;
    unawaited(checkNow());
    _timer = Timer.periodic(interval, (_) => unawaited(checkNow()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Pings the server now. Concurrent callers share one request.
  Future<ConnectionStatus> checkNow() => _inFlight ??= _ping().whenComplete(() => _inFlight = null);

  Future<ConnectionStatus> _ping() async {
    try {
      final health = await _healthApi.check();
      _set(health.isOk ? ConnectionStatus.online : ConnectionStatus.offline);
    } catch (_) {
      _set(ConnectionStatus.offline);
    }
    return _status;
  }

  /// Called by repositories when a request fails at the network level.
  void markOffline() => _set(ConnectionStatus.offline);

  void _set(ConnectionStatus value) {
    if (value == _status) return;
    _status = value;
    if (!_controller.isClosed) _controller.add(value);
  }

  void dispose() {
    stop();
    _controller.close();
  }
}

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = ConnectivityService(ref.watch(healthApiServiceProvider))..start();
  ref.onDispose(service.dispose);
  return service;
});

final connectionStatusProvider = StreamProvider<ConnectionStatus>((ref) async* {
  final service = ref.watch(connectivityServiceProvider);
  yield service.status;
  yield* service.statusStream;
});
