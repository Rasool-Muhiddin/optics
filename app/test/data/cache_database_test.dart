import 'package:flutter_test/flutter_test.dart';
import 'package:optics_app/data/cache/cache_dao.dart';
import 'package:optics_app/data/cache/cache_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _ThingsDao extends CacheDao {
  _ThingsDao(super.cache);

  @override
  String get table => 'things';
}

void main() {
  late CacheDatabase cache;
  late _ThingsDao dao;

  setUp(() async {
    cache = await CacheDatabase.open(path: inMemoryDatabasePath);
    await cache.db.execute(CacheDao.createTableSql('things'));
    dao = _ThingsDao(cache);
  });

  tearDown(() => cache.close());

  test('creates the meta table on first open', () async {
    final tables = await cache.db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'cache_meta'",
    );
    expect(tables, hasLength(1));
  });

  test('upserts rows keyed by server id and reads them back', () async {
    await dao.upsertAll([
      {'id': 1, 'name': 'إطار'},
      {'id': 2, 'name': 'عدسة'},
    ]);
    await dao.upsertAll([
      {'id': 1, 'name': 'إطار معدل'},
    ]);

    expect(await dao.getAll(), hasLength(2));
    expect((await dao.getById(1))!['name'], 'إطار معدل');
    expect(await dao.getById(99), isNull);
    expect(await dao.lastSyncedAt(), isNotNull);
  });

  test('replaceAll drops rows the server no longer returns', () async {
    await dao.upsertAll([
      {'id': 1},
      {'id': 2},
    ]);
    await dao.replaceAll([
      {'id': 2},
    ]);
    expect((await dao.getAll()).map((r) => r['id']), [2]);
  });

  test('clearAll empties every table', () async {
    await dao.upsertAll([
      {'id': 1},
    ]);
    await cache.clearAll();
    expect(await dao.getAll(), isEmpty);
    expect(await dao.lastSyncedAt(), isNull);
  });
}
