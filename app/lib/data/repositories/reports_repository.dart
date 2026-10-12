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

/// Stable cache key of a report query (FNV-1a 32-bit; Dart's `hashCode` is not stable).
int reportCacheId(String name, Map<String, dynamic> query) {
  final keys = query.keys.toList()..sort();
  final text = '$name?${[for (final k in keys) '$k=${query[k]}'].join('&')}';
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

final fileSaverProvider = Provider<FileSaver>((ref) => saveToDownloads);

/// Dashboard (cached for offline viewing), reports (online), CSV export, lab settings.
class ReportsRepository extends BaseRepository {
  ReportsRepository(
    super.connectivity, {
    required this.api,
    required CacheDatabase cache,
    required this.saveFile,
  }) : dashboardDao = JsonCacheDao(cache, CacheTables.dashboard),
       reportsDao = JsonCacheDao(cache, CacheTables.reportResults);

  final ReportsApiService api;
  final JsonCacheDao dashboardDao;
  final JsonCacheDao reportsDao;
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

  /// Live when online; offline, the last result fetched for the very same query.
  Future<ReportTable> report(String name, Map<String, dynamic> query) {
    final id = reportCacheId(name, query);
    return read(
      remote: () async {
        final json = await api.report(name, query);
        await reportsDao.upsertAll([
          {...json, 'id': id},
        ]);
        return ReportTable.fromJson(json);
      },
      cached: () async {
        final json = await reportsDao.getById(id);
        if (json == null) throw const NotCachedException();
        return ReportTable.fromJson(json);
      },
    );
  }

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
