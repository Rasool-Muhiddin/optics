import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart' show NotCachedException;
import '../../models/doctors.dart';
import '../../models/json.dart';
import '../../services/connectivity_service.dart';
import '../api/doctors_api_service.dart';
import '../cache/cache_database.dart';
import '../cache/json_cache_dao.dart';
import 'base_repository.dart';

/// Doctor mode: the doctor's labs and referrals (cached for offline reading).
class DoctorRepository extends BaseRepository {
  DoctorRepository(super.connectivity, {required this.api, required CacheDatabase cache})
    : linksDao = JsonCacheDao(cache, CacheTables.doctorSideLinks),
      referralsDao = JsonCacheDao(cache, CacheTables.doctorSideReferrals);

  final DoctorApiService api;
  final JsonCacheDao linksDao;
  final JsonCacheDao referralsDao;

  Future<List<DoctorLink>> links() => read(
    remote: () async {
      final rows = PageResult.rows(await api.links());
      await linksDao.replaceAll(rows);
      return rows.map(DoctorLink.fromDoctorJson).toList();
    },
    cached: () async => (await linksDao.getAll()).map(DoctorLink.fromDoctorJson).toList(),
  );

  Future<DoctorLink> requestLink(String code) => write(() async {
    final json = await api.requestLink(code.trim());
    await linksDao.upsertAll([json]);
    return DoctorLink.fromDoctorJson(json);
  });

  /// [action] = `accept` | `reject` | `revoke`.
  Future<DoctorLink> linkAction(int id, String action) => write(() async {
    final json = await api.linkAction(id, action);
    await linksDao.upsertAll([json]);
    return DoctorLink.fromDoctorJson(json);
  });

  Future<List<Referral>> referrals({String? status}) => read(
    remote: () async {
      final rows = PageResult.rows(await api.referrals({'status': ?status, 'page_size': 500}));
      await referralsDao.upsertAll(rows);
      return rows.map(Referral.fromJson).toList();
    },
    cached: () async =>
        (await referralsDao.getAll())
            .map(Referral.fromJson)
            .where((r) => status == null || status.split(',').contains(r.status))
            .toList()
          ..sort((a, b) => b.id.compareTo(a.id)),
  );

  Future<Referral> send(Map<String, dynamic> body) => write(() async {
    final json = await api.sendReferral(body);
    await referralsDao.upsertAll([json]);
    return Referral.fromJson(json);
  });
}

/// Inbox filters (provider key).
typedef ReferralQuery = ({String search, String? status});

/// Lab side: referral inbox and the lab's doctors.
class ReferralsRepository extends BaseRepository {
  ReferralsRepository(super.connectivity, {required this.api, required CacheDatabase cache})
    : referralsDao = JsonCacheDao(cache, CacheTables.referrals),
      linksDao = JsonCacheDao(cache, CacheTables.labDoctorLinks);

  final ReferralsApiService api;
  final JsonCacheDao referralsDao;
  final JsonCacheDao linksDao;

  Future<List<Referral>> inbox(ReferralQuery q) => read(
    remote: () async {
      final rows = PageResult.rows(
        await api.inbox({
          if (q.search.trim().isNotEmpty) 'search': q.search.trim(),
          'status': ?q.status,
          'page_size': 500,
        }),
      );
      await referralsDao.upsertAll(rows);
      return rows.map(Referral.fromJson).toList();
    },
    cached: () async {
      final search = q.search.trim().toLowerCase();
      return (await referralsDao.getAll())
          .map(Referral.fromJson)
          .where(
            (r) =>
                (q.status == null || q.status!.split(',').contains(r.status)) &&
                (search.isEmpty ||
                    r.patientName.toLowerCase().contains(search) ||
                    r.patientPhone.contains(search) ||
                    r.doctorName.toLowerCase().contains(search)),
          )
          .toList()
        ..sort((a, b) => b.id.compareTo(a.id));
    },
  );

  Future<Referral> referral(int id) => read(
    remote: () => api.referral(id),
    cached: () async => await referralsDao.getById(id) ?? (throw const NotCachedException()),
    saveToCache: (json) => referralsDao.upsertAll([json]),
  ).then(Referral.fromJson);

  /// [action] = `receive` | `accept` | `reject` | `complete`.
  Future<Referral> act(int id, String action, [Map<String, dynamic> body = const {}]) =>
      write(() async {
        final json = await api.action(id, action, body);
        await referralsDao.upsertAll([json]);
        return Referral.fromJson(json);
      });

  Future<List<DoctorLink>> links() => read(
    remote: () async {
      final rows = PageResult.rows(await api.links());
      await linksDao.replaceAll(rows);
      return rows.map(DoctorLink.fromLabJson).toList();
    },
    cached: () async => (await linksDao.getAll()).map(DoctorLink.fromLabJson).toList(),
  );

  Future<DoctorLink> requestLink(String code) => write(() async {
    final json = await api.requestLink(code.trim());
    await linksDao.upsertAll([json]);
    return DoctorLink.fromLabJson(json);
  });

  Future<DoctorLink> linkAction(int id, String action) => write(() async {
    final json = await api.linkAction(id, action);
    await linksDao.upsertAll([json]);
    return DoctorLink.fromLabJson(json);
  });

  /// The lab's code for doctors (owner); online only.
  Future<String> labCode({bool regenerate = false}) =>
      write(() => api.labCode(regenerate: regenerate));
}

final doctorRepositoryProvider = Provider<DoctorRepository>(
  (ref) => DoctorRepository(
    ref.watch(connectivityServiceProvider),
    api: ref.watch(doctorApiServiceProvider),
    cache: ref.watch(cacheDatabaseProvider),
  ),
);

final referralsRepositoryProvider = Provider<ReferralsRepository>(
  (ref) => ReferralsRepository(
    ref.watch(connectivityServiceProvider),
    api: ref.watch(referralsApiServiceProvider),
    cache: ref.watch(cacheDatabaseProvider),
  ),
);
