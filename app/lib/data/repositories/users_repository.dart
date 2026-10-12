import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../models/json.dart';
import '../../models/users.dart';
import '../../services/connectivity_service.dart';
import '../api/users_api_service.dart';
import '../cache/cache_database.dart';
import '../cache/json_cache_dao.dart';
import 'base_repository.dart';

/// Lab users and devices (owner). Readable from the cache offline; changes need the server.
class UsersRepository extends BaseRepository {
  UsersRepository(super.connectivity, {required this.api, required CacheDatabase cache})
    : usersDao = JsonCacheDao(cache, CacheTables.labUsers),
      devicesDao = JsonCacheDao(cache, CacheTables.devices);

  final UsersApiService api;
  final JsonCacheDao usersDao;
  final JsonCacheDao devicesDao;

  Future<List<LabMember>> users() => read(
    remote: () async {
      final rows = PageResult.rows(await api.users());
      await usersDao.replaceAll(rows);
      return rows.map(LabMember.fromJson).toList();
    },
    cached: () async => (await usersDao.getAll()).map(LabMember.fromJson).toList(),
  );

  Future<LabMember> saveUser(int? id, Map<String, dynamic> body) => write(() async {
    final json = await api.saveUser(id, body);
    await usersDao.upsertAll([json]);
    return LabMember.fromJson(json);
  });

  Future<List<LabDevice>> devices() => read(
    remote: () async {
      final rows = PageResult.rows(await api.devices());
      await devicesDao.replaceAll(rows);
      return rows.map(LabDevice.fromJson).toList();
    },
    cached: () async => (await devicesDao.getAll()).map(LabDevice.fromJson).toList(),
  );

  Future<LabDevice> saveDevice(int id, Map<String, dynamic> body) => write(() async {
    final json = await api.saveDevice(id, body);
    await devicesDao.upsertAll([json]);
    return LabDevice.fromJson(json);
  });

  /// Live counts only (limits must not be judged from stale data).
  Future<LabUsage> usage() => read(
    remote: () async => LabUsage.fromJson(await api.usage()),
    cached: () async => throw const NotCachedException(),
  );
}

final usersRepositoryProvider = Provider<UsersRepository>(
  (ref) => UsersRepository(
    ref.watch(connectivityServiceProvider),
    api: ref.watch(usersApiServiceProvider),
    cache: ref.watch(cacheDatabaseProvider),
  ),
);
