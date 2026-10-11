/// Tolerant JSON readers shared by the domain models (the API sends decimals as strings).
class Json {
  const Json._();

  static int? intOrNull(Object? v) => switch (v) {
    int i => i,
    num n => n.toInt(),
    String s => int.tryParse(s),
    _ => null,
  };

  static int int0(Object? v) => intOrNull(v) ?? 0;

  static String str(Object? v) => v == null ? '' : v.toString();

  static String? strOrNull(Object? v) => v?.toString();

  /// Decimal as the server sent it (`"125000.00"`); null stays null.
  static String? decimal(Object? v) => v?.toString();

  static double dbl(Object? v) => switch (v) {
    num n => n.toDouble(),
    String s => double.tryParse(s) ?? 0,
    _ => 0,
  };

  static bool boolean(Object? v, {bool fallback = false}) => v is bool ? v : fallback;

  static DateTime? date(Object? v) => v is String ? DateTime.tryParse(v) : null;

  static Map<String, dynamic> map(Object? v) =>
      v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

  static List<Map<String, dynamic>> list(Object? v) =>
      v is List ? [for (final e in v) map(e)] : const [];
}

/// One page of a DRF list endpoint.
class PageResult<T> {
  const PageResult({required this.items, required this.count, this.hasMore = false});

  factory PageResult.fromJson(Object? json, T Function(Map<String, dynamic>) parse) {
    final map = Json.map(json);
    return PageResult(
      items: [for (final row in Json.list(map['results'])) parse(row)],
      count: Json.int0(map['count']),
      hasMore: map['next'] != null,
    );
  }

  final List<T> items;
  final int count;
  final bool hasMore;

  /// Raw rows are what gets cached.
  static List<Map<String, dynamic>> rows(Object? json) => Json.list(Json.map(json)['results']);
}
