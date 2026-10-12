import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/errors/app_exception.dart';
import '../../models/reports.dart';
import '../../models/session.dart';
import '../../services/connectivity_service.dart';
import '../api/reports_api_service.dart';
import '../cache/cache_database.dart';
import '../cache/json_cache_dao.dart';
import 'base_repository.dart';

/// Saves an exported file and returns where it went.
typedef FileSaver = Future<String> Function(String filename, Uint8List bytes);

/// Default [FileSaver]: the user's Downloads folder (documents folder as a fallback).
Future<String> saveToDownloads(String filename, Uint8List bytes) async {
  Directory? dir;
  try {
    dir = await getDownloadsDirectory();
  } catch (_) {
    dir = null;
  }
  dir ??= await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, filename));
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

final fileSaverProvider = Provider<FileSaver>((ref) => saveToDownloads);

/// Dashboard (cached for offline viewing), reports (online), CSV export, lab settings.
class ReportsRepository extends BaseRepository {
  ReportsRepository(
    super.connectivity, {
    required this.api,
    required CacheDatabase cache,
    required this.saveFile,
  }) : dashboardDao = JsonCacheDao(cache, CacheTables.dashboard);

  final ReportsApiService api;
  final JsonCacheDao dashboardDao;
  final FileSaver saveFile;

  Future<Dashboard> dashboard() => read(
    remote: () async {
      final json = await api.dashboard();
      await dashboardDao.upsertAll([
        {...json, 'id': 1},
      ]);
      return Dashboard.fromJson(json);
    },
    cached: () async {
      final json = await dashboardDao.getById(1);
      if (json == null) throw const NotCachedException();
      return Dashboard.fromJson(json);
    },
  );

  /// Reports need live data (no offline copy).
  Future<ReportTable> report(String name, Map<String, dynamic> query) => read(
    remote: () async => ReportTable.fromJson(await api.report(name, query)),
    cached: () async => throw const NotCachedException(),
  );

  /// Downloads the CSV export (plan `report_export`) and saves it; returns the file path.
  Future<String> exportCsv(String name, Map<String, dynamic> query) => write(() async {
    final bytes = await api.exportCsv(name, query);
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    return saveFile('report_${name}_$stamp.csv', bytes);
  });

  Future<LabInfo> saveLabSettings(Map<String, dynamic> body) =>
      write(() async => LabInfo.fromJson(await api.saveLabSettings(body)));

  Future<LabInfo> uploadLogo(List<int> bytes, String filename) =>
      write(() async => LabInfo.fromJson(await api.uploadLogo(bytes, filename)));
}

final reportsRepositoryProvider = Provider<ReportsRepository>(
  (ref) => ReportsRepository(
    ref.watch(connectivityServiceProvider),
    api: ref.watch(reportsApiServiceProvider),
    cache: ref.watch(cacheDatabaseProvider),
    saveFile: ref.watch(fileSaverProvider),
  ),
);
