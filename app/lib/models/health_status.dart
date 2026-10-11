/// Response of `GET /api/v1/health/`.
class HealthStatus {
  const HealthStatus({
    required this.status,
    required this.database,
    required this.version,
    this.serverTime,
  });

  factory HealthStatus.fromJson(Map<String, dynamic> json) => HealthStatus(
    status: json['status'] as String? ?? 'unknown',
    database: json['database'] as String? ?? 'unknown',
    version: json['version'] as String? ?? '',
    serverTime: DateTime.tryParse(json['server_time'] as String? ?? ''),
  );

  final String status;
  final String database;
  final String version;
  final DateTime? serverTime;

  bool get isOk => status == 'ok';
}
