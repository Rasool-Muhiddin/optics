import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'cache_database.dart';

/// Base DAO for a cached server collection.
///
/// Rows are keyed by the server `id` and stored as the JSON the API returned,
/// plus `last_synced_at`. Domain DAOs add indexed columns only when they need
/// to search/filter offline.
abstract class CacheDao {
  CacheDao(this.cache);

  final CacheDatabase cache;

  /// Table name, e.g. `patients`.
  String get table;

  Database get db => cache.db;

  /// SQL for a standard cache table; use it inside a [CacheDatabase] migration.
  static String createTableSql(String table) =>
      'CREATE TABLE IF NOT EXISTS $table ('
      'id INTEGER PRIMARY KEY, '
      'data TEXT NOT NULL, '
      'last_synced_at TEXT NOT NULL)';

  /// Inserts or replaces rows (each must contain an integer `id`).
  Future<void> upsertAll(Iterable<Map<String, dynamic>> rows, {DateTime? syncedAt}) async {
    final stamp = (syncedAt ?? DateTime.now()).toUtc().toIso8601String();
    final batch = db.batch();
    for (final row in rows) {
      batch.insert(table, {
        'id': row['id'] as int,
        'data': jsonEncode(row),
        'last_synced_at': stamp,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Replaces the whole collection (use after fetching a complete list).
  Future<void> replaceAll(Iterable<Map<String, dynamic>> rows, {DateTime? syncedAt}) async {
    final stamp = (syncedAt ?? DateTime.now()).toUtc().toIso8601String();
    await db.transaction((txn) async {
      await txn.delete(table);
      final batch = txn.batch();
      for (final row in rows) {
        batch.insert(table, {
          'id': row['id'] as int,
          'data': jsonEncode(row),
          'last_synced_at': stamp,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<Map<String, dynamic>?> getById(int id) async {
    final rows = await db.query(
      table,
      columns: ['data'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _decode(rows.first);
  }

  Future<List<Map<String, dynamic>>> getAll() async {
    final rows = await db.query(table, columns: ['data'], orderBy: 'id');
    return rows.map(_decode).toList();
  }

  Future<void> deleteById(int id) => db.delete(table, where: 'id = ?', whereArgs: [id]);

  /// Most recent sync time of any row, or null if nothing is cached.
  Future<DateTime?> lastSyncedAt() async {
    final rows = await db.rawQuery('SELECT MAX(last_synced_at) AS t FROM $table');
    final value = rows.first['t'] as String?;
    return value == null ? null : DateTime.parse(value);
  }

  Map<String, dynamic> _decode(Map<String, Object?> row) =>
      jsonDecode(row['data']! as String) as Map<String, dynamic>;
}
