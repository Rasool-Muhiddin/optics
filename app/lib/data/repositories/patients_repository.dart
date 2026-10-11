import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../models/json.dart';
import '../../models/patients.dart';
import '../../services/connectivity_service.dart';
import '../api/patients_api_service.dart';
import '../cache/cache_database.dart';
import '../cache/json_cache_dao.dart';
import 'base_repository.dart';

/// Patients, exams and prescriptions. Cached for offline browsing and printing.
class PatientsRepository extends BaseRepository {
  PatientsRepository(super.connectivity, {required this.api, required CacheDatabase cache})
    : patientsDao = JsonCacheDao(cache, CacheTables.patients),
      examsDao = JsonCacheDao(cache, CacheTables.exams),
      rxDao = JsonCacheDao(cache, CacheTables.prescriptions);

  final PatientsApiService api;
  final JsonCacheDao patientsDao;
  final JsonCacheDao examsDao;
  final JsonCacheDao rxDao;

  Future<PageResult<Patient>> list({String search = '', String? status, int page = 1}) => read(
    remote: () async {
      final json = await api.patients({
        if (search.trim().isNotEmpty) 'search': search.trim(),
        'status': ?status,
        'is_archived': 'false',
        'page': page,
        'page_size': 100,
      });
      await patientsDao.upsertAll(PageResult.rows(json));
      return PageResult.fromJson(json, Patient.fromJson);
    },
    cached: () async {
      final rows =
          (await patientsDao.getAll())
              .map(Patient.fromJson)
              .where(
                (p) => !p.isArchived && p.matches(search) && (status == null || p.status == status),
              )
              .toList()
            ..sort((a, b) => b.id.compareTo(a.id));
      return PageResult(items: rows, count: rows.length);
    },
  );

  Future<Patient> get(int id) => read(
    remote: () => api.patient(id),
    cached: () async => await patientsDao.getById(id) ?? (throw const NotCachedException()),
    saveToCache: (json) => patientsDao.upsertAll([json]),
  ).then(Patient.fromJson);

  Future<Patient> save(int? id, Map<String, dynamic> body) => write(() async {
    final json = await api.savePatient(id, body);
    await patientsDao.upsertAll([json]);
    return Patient.fromJson(json);
  });

  Future<List<EyeExam>> exams(int patientId) => read(
    remote: () async {
      final json = await api.exams(patientId);
      await examsDao.upsertAll(PageResult.rows(json));
      return PageResult.fromJson(json, EyeExam.fromJson).items;
    },
    cached: () async =>
        (await examsDao.where(
            (r) => Json.int0(r['patient']) == patientId,
          )).map(EyeExam.fromJson).toList()
          ..sort((a, b) => (b.examDate ?? DateTime(0)).compareTo(a.examDate ?? DateTime(0))),
  );

  Future<EyeExam> saveExam(int? id, Map<String, dynamic> body) => write(() async {
    final json = await api.saveExam(id, body);
    await examsDao.upsertAll([json]);
    if (json['prescription'] is Map) await rxDao.upsertAll([Json.map(json['prescription'])]);
    return EyeExam.fromJson(json);
  });

  Future<EyeExam> voidExam(int id, String reason) => write(() async {
    final json = await api.voidExam(id, reason);
    await examsDao.upsertAll([json]);
    return EyeExam.fromJson(json);
  });

  Future<List<Prescription>> prescriptions(int patientId) => read(
    remote: () async {
      final json = await api.prescriptions(patientId);
      await rxDao.upsertAll(PageResult.rows(json));
      return PageResult.fromJson(json, Prescription.fromJson).items;
    },
    cached: () async =>
        (await rxDao.where(
            (r) => Json.int0(r['patient']) == patientId,
          )).map(Prescription.fromJson).toList()
          ..sort((a, b) => (b.rxDate ?? DateTime(0)).compareTo(a.rxDate ?? DateTime(0))),
  );

  Future<Prescription> savePrescription(int? id, Map<String, dynamic> body) => write(() async {
    final json = await api.savePrescription(id, body);
    await rxDao.upsertAll([json]);
    return Prescription.fromJson(json);
  });

  Future<Prescription> voidPrescription(int id, String reason) => write(() async {
    final json = await api.voidPrescription(id, reason);
    await rxDao.upsertAll([json]);
    return Prescription.fromJson(json);
  });
}

final patientsRepositoryProvider = Provider<PatientsRepository>(
  (ref) => PatientsRepository(
    ref.watch(connectivityServiceProvider),
    api: ref.watch(patientsApiServiceProvider),
    cache: ref.watch(cacheDatabaseProvider),
  ),
);
