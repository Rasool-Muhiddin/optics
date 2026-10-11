import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../models/health_status.dart';
import 'api_client.dart';

/// `GET /api/v1/health/` — public, no token.
class HealthApiService {
  const HealthApiService(this._client);

  final ApiClient _client;

  Future<HealthStatus> check() async {
    final json = await _client.get('health/', timeout: AppConfig.healthCheckTimeout);
    return HealthStatus.fromJson(json as Map<String, dynamic>);
  }
}

final healthApiServiceProvider = Provider<HealthApiService>(
  (ref) => HealthApiService(ref.watch(apiClientProvider)),
);
