import 'cache_dao.dart';
import 'cache_database.dart';

/// Cache table holding the API JSON of one collection (see [CacheDatabase.migrations]).
class JsonCacheDao extends CacheDao {
  JsonCacheDao(super.cache, this.table);

  @override
  final String table;

  /// Rows matching [test] (offline filtering happens in Dart; collections are small).
  Future<List<Map<String, dynamic>>> where(bool Function(Map<String, dynamic> row) test) async =>
      (await getAll()).where(test).toList();
}

/// Cache table names (one per cached collection).
class CacheTables {
  const CacheTables._();

  static const String products = 'products';
  static const String categories = 'categories';
  static const String brands = 'brands';
  static const String lensVariants = 'lens_variants';
  static const String stockMovements = 'stock_movements';
  static const String patients = 'patients';
  static const String exams = 'eye_exams';
  static const String prescriptions = 'prescriptions';
}
