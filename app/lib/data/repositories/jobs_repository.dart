import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../models/jobs.dart';
import '../../models/json.dart';
import '../../services/connectivity_service.dart';
import '../api/jobs_api_service.dart';
import '../cache/cache_database.dart';
import '../cache/json_cache_dao.dart';
import 'base_repository.dart';

/// Board query: open jobs + recently delivered (provider key).
typedef JobQuery = ({String search, int? patientId, bool overdueOnly});

class JobsRepository extends BaseRepository {
  JobsRepository(super.connectivity, {required this.api, required CacheDatabase cache})
    : dao = JsonCacheDao(cache, CacheTables.jobs);

  final JobsApiService api;
  final JsonCacheDao dao;

  /// Jobs for the board: everything not cancelled, delivered only from the last [deliveredDays].
  Future<List<Job>> board(JobQuery q, {int deliveredDays = 14}) => read(
    remote: () async {
      final since = DateTime.now().subtract(Duration(days: deliveredDays));
      final common = <String, dynamic>{
        if (q.search.trim().isNotEmpty) 'search': q.search.trim(),
        'patient': ?q.patientId,
        if (q.overdueOnly) 'overdue': 'true',
        'page_size': 500,
      };
      final open = await api.jobs({...common, 'status': 'pending,lens_ordered,in_workshop,ready'});
      final delivered = q.overdueOnly
          ? null
          : await api.jobs({
              ...common,
              'status': 'delivered',
              'delivered_from': since.toIso8601String().substring(0, 10),
            });
      final rows = [...PageResult.rows(open), if (delivered != null) ...PageResult.rows(delivered)];
      await dao.upsertAll(rows);
      return rows.map(Job.fromJson).toList();
    },
    cached: () async {
      final now = DateTime.now();
      final query = q.search.trim().toLowerCase();
      return (await dao.getAll())
          .map(Job.fromJson)
          .where(
            (j) =>
                j.status != JobStatuses.cancelled &&
                (query.isEmpty ||
                    '${j.number}' == query ||
                    j.patientName.toLowerCase().contains(query) ||
                    j.patientPhone.contains(query)) &&
                (q.patientId == null || j.patientId == q.patientId) &&
                (!q.overdueOnly || j.overdueOn(now)),
          )
          .toList();
    },
  );

  /// All jobs of one patient (any status), newest first.
  Future<List<Job>> ofPatient(int patientId) => read(
    remote: () async {
      final json = await api.jobs({'patient': patientId, 'page_size': 200});
      await dao.upsertAll(PageResult.rows(json));
      return PageResult.fromJson(json, Job.fromJson).items;
    },
    cached: () async =>
        (await dao.where((r) => Json.int0(r['patient']) == patientId)).map(Job.fromJson).toList()
          ..sort((a, b) => b.number.compareTo(a.number)),
  );

  Future<Job> get(int id) => read(
    remote: () => api.job(id),
    cached: () async => await dao.getById(id) ?? (throw const NotCachedException()),
    saveToCache: (json) => dao.upsertAll([json]),
  ).then(Job.fromJson);

  Future<Job> save(int? id, Map<String, dynamic> body) => write(() async {
    final json = await api.save(id, body);
    await dao.upsertAll([json]);
    return Job.fromJson(json);
  });

  Future<Job> changeStatus(int id, String status, {String note = ''}) => write(() async {
    final json = await api.changeStatus(id, status, note);
    await dao.upsertAll([json]);
    return Job.fromJson(json);
  });
}

final jobsRepositoryProvider = Provider<JobsRepository>(
  (ref) => JobsRepository(
    ref.watch(connectivityServiceProvider),
    api: ref.watch(jobsApiServiceProvider),
    cache: ref.watch(cacheDatabaseProvider),
  ),
);
