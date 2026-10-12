import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/config/app_config.dart';
import 'cache_dao.dart';

/// One schema step. Each domain adds its cache tables as a new migration
/// (append only — never edit a shipped one).
typedef CacheMigration = Future<void> Function(Database db);

/// Local **read-only** cache of server data (online-first: the server is the
/// source of truth; this only serves browsing/printing during outages).
class CacheDatabase {
  CacheDatabase._(this.db);

  final Database db;

  static final List<CacheMigration> migrations = [
    // v1: bookkeeping (e.g. per-table sync markers).
    (db) => db.execute(
      'CREATE TABLE IF NOT EXISTS cache_meta ('
      'key TEXT PRIMARY KEY, '
      'value TEXT)',
    ),
    // v2 (P2): catalog & inventory.
    (db) async {
      for (final table in const [
        'products',
        'categories',
        'brands',
        'lens_variants',
        'stock_movements',
      ]) {
        await db.execute(CacheDao.createTableSql(table));
      }
    },
    // v3 (P3): patients, exams, prescriptions.
    (db) async {
      for (final table in const ['patients', 'eye_exams', 'prescriptions']) {
        await db.execute(CacheDao.createTableSql(table));
      }
    },
    // v4 (P4): sales.
    (db) async {
      for (final table in const ['invoices', 'credit_customers']) {
        await db.execute(CacheDao.createTableSql(table));
      }
    },
    // v5 (P5): customer jobs.
    (db) => db.execute(CacheDao.createTableSql('jobs')),
    // v6 (P6): suppliers and supplier orders.
    (db) async {
      for (final table in const ['suppliers', 'supplier_orders']) {
        await db.execute(CacheDao.createTableSql(table));
      }
    },
    // v7 (P7): referrals and doctor links (lab side) + doctor mode tables.
    (db) async {
      for (final table in const [
        'referrals',
        'lab_doctor_links',
        'doctor_side_links',
        'doctor_side_referrals',
      ]) {
        await db.execute(CacheDao.createTableSql(table));
      }
    },
    // v8 (P8): last dashboard (single row, id 1).
    (db) => db.execute(CacheDao.createTableSql('dashboard')),
    // v9 (Users screen): lab users and devices.
    (db) async {
      for (final table in const ['lab_users', 'devices']) {
        await db.execute(CacheDao.createTableSql(table));
      }
    },
  ];

  static int get schemaVersion => migrations.length;

  /// Opens (and migrates) the cache. Pass [path] = [inMemoryDatabasePath] in tests.
  static Future<CacheDatabase> open({String? path, DatabaseFactory? factory}) async {
    final dbFactory = factory ?? _ffiFactory();
    final dbPath = path ?? await _defaultPath();
    final db = await dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, version) => _migrate(db, 0, version),
        onUpgrade: _migrate,
      ),
    );
    return CacheDatabase._(db);
  }

  static Future<void> _migrate(Database db, int from, int to) async {
    for (var v = from; v < to; v++) {
      await migrations[v](db);
    }
  }

  static DatabaseFactory _ffiFactory() {
    sqfliteFfiInit();
    return databaseFactoryFfi;
  }

  static Future<String> _defaultPath() async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, AppConfig.cacheDbFileName);
  }

  /// Clears every cached row (e.g. on logout or lab switch).
  Future<void> clearAll() async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
    );
    await db.transaction((txn) async {
      for (final row in tables) {
        await txn.delete(row['name']! as String);
      }
    });
  }

  Future<void> close() => db.close();
}

/// Opened in `main()` and injected with `overrideWithValue`.
final cacheDatabaseProvider = Provider<CacheDatabase>(
  (ref) => throw UnimplementedError('cacheDatabaseProvider must be overridden in main()'),
);
