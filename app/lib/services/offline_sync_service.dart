import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_exception.dart';
import '../data/api/api_client.dart';
import '../data/cache/cache_database.dart';
import '../data/cache/json_cache_dao.dart';
import '../data/repositories/reports_repository.dart';
import '../data/repositories/sales_repository.dart';
import '../models/json.dart';
import '../models/session.dart';
import 'auth_controller.dart';
import 'connectivity_service.dart';

/// One collection pulled into a cache table during a full sync.
class SyncSource {
  const SyncSource(this.table, this.path, {this.query = const {}, this.maxPages = 2});

  final String table;
  final String path;
  final Map<String, dynamic> query;

  /// Upper bound on pages (`page_size` 500) so a sync stays bounded on big labs.
  final int maxPages;
}

/// What a lab session caches (P9). Owner-only / plan-gated collections are added by [labSources].
const _commonLabSources = [
  SyncSource(CacheTables.products, 'catalog/products/', maxPages: 10),
  SyncSource(CacheTables.categories, 'catalog/categories/', maxPages: 1),
  SyncSource(CacheTables.brands, 'catalog/brands/', maxPages: 1),
  SyncSource(CacheTables.lensVariants, 'catalog/variants/', maxPages: 10),
  SyncSource(CacheTables.stockMovements, 'inventory/movements/', maxPages: 1),
  SyncSource(CacheTables.patients, 'patients/', query: {'is_archived': 'false'}, maxPages: 6),
  SyncSource(CacheTables.exams, 'patients/exams/', query: {'ordering': '-exam_date'}, maxPages: 4),
  SyncSource(
    CacheTables.prescriptions,
    'patients/prescriptions/',
    query: {'ordering': '-rx_date'},
    maxPages: 4,
  ),
  // Full invoices (lines + payments) so any recent invoice can be printed offline.
  SyncSource(
    CacheTables.invoices,
    'sales/invoices/',
    query: {'with_lines': 'true', 'ordering': '-number'},
    maxPages: 2,
  ),
  SyncSource(CacheTables.jobs, 'jobs/', query: {'ordering': '-number'}, maxPages: 2),
  SyncSource(CacheTables.suppliers, 'purchasing/suppliers/', maxPages: 1),
  SyncSource(
    CacheTables.supplierOrders,
    'purchasing/orders/',
    query: {'ordering': '-number'},
    maxPages: 2,
  ),
];

List<SyncSource> labSources(Session session) => [
  ..._commonLabSources,
  if (session.hasFeature(Features.doctorLinking)) ...const [
    SyncSource(CacheTables.referrals, 'referrals/', maxPages: 2),
    SyncSource(CacheTables.labDoctorLinks, 'referrals/links/', maxPages: 1),
  ],
  if (session.isOwner) ...const [
    SyncSource(CacheTables.labUsers, 'lab/users/', maxPages: 1),
    SyncSource(CacheTables.devices, 'lab/devices/', maxPages: 1),
  ],
];

const doctorSources = [
  SyncSource(CacheTables.doctorSideLinks, 'doctor/links/', maxPages: 1),
  SyncSource(CacheTables.doctorSideReferrals, 'doctor/referrals/', maxPages: 4),
];

/// Result of a full sync.
class SyncResult {
  const SyncResult({required this.at, required this.failed});

  final DateTime at;

  /// Tables that could not be refreshed (permission, feature, server error…).
  final List<String> failed;
}

/// Warms the read cache for every domain so the app can browse, search and print
/// offline (CLAUDE.md §2). Runs after login, when the server comes back, and on demand.
class OfflineSyncService {
  OfflineSyncService({
    required this.api,
    required this.cache,
    required this.connectivity,
    this.afterSync = const [],
  });

  static const metaKey = 'last_full_sync';
  static const minInterval = Duration(minutes: 15);

  final ApiClient api;
  final CacheDatabase cache;
  final ConnectivityService connectivity;

  /// Extra steps that refresh caches through their repositories (credit, dashboard…).
  final List<Future<void> Function()> afterSync;

  Future<SyncResult>? _running;

  Future<DateTime?> lastFullSync() async {
    final value = await cache.meta(metaKey);
    return value == null ? null : DateTime.tryParse(value);
  }

  /// Pulls every source (errors are per table: one failure never stops the rest).
  Future<SyncResult> sync(List<SyncSource> sources) =>
      _running ??= _sync(sources).whenComplete(() => _running = null);

  Future<SyncResult> _sync(List<SyncSource> sources) async {
    if (connectivity.isOffline) throw const OfflineWriteException();
    final failed = <String>[];
    for (final source in sources) {
      try {
        await _pull(source);
      } on NetworkException {
        connectivity.markOffline();
        rethrow;
      } on AppException {
        failed.add(source.table);
      }
    }
    for (final step in afterSync) {
      try {
        await step();
      } on AppException {
        // Best effort.
      }
    }
    final at = DateTime.now();
    await cache.setMeta(metaKey, at.toUtc().toIso8601String());
    return SyncResult(at: at, failed: failed);
  }

  Future<void> _pull(SyncSource source) async {
    final dao = JsonCacheDao(cache, source.table);
    for (var page = 1; page <= source.maxPages; page++) {
      final json = await api.get(
        source.path,
        query: {...source.query, 'page': page, 'page_size': 500},
      );
      await dao.upsertAll(PageResult.rows(json));
      if (Json.map(json)['next'] == null) break;
    }
  }
}

/// Off in widget tests (they override it) so fake servers only see the requests under test.
final autoSyncEnabledProvider = Provider<bool>((ref) => true);

final offlineSyncServiceProvider = Provider<OfflineSyncService>(
  (ref) => OfflineSyncService(
    api: ref.watch(apiClientProvider),
    cache: ref.watch(cacheDatabaseProvider),
    connectivity: ref.watch(connectivityServiceProvider),
    afterSync: [
      () async {
        if (ref.read(sessionProvider) != null) {
          await ref.read(salesRepositoryProvider).creditCustomers();
          await ref.read(reportsRepositoryProvider).dashboard();
        }
      },
    ],
  ),
);

/// What the sidebar shows about the offline copy.
class SyncState {
  const SyncState({this.running = false, this.lastSync, this.failed = const []});

  final bool running;
  final DateTime? lastSync;
  final List<String> failed;

  SyncState copyWith({bool? running, DateTime? lastSync, List<String>? failed}) => SyncState(
    running: running ?? this.running,
    lastSync: lastSync ?? this.lastSync,
    failed: failed ?? this.failed,
  );
}

/// Runs [OfflineSyncService] for whoever is logged in: automatically after login and
/// whenever the server becomes reachable (at most every 15 minutes), or on demand.
class SyncController extends Notifier<SyncState> {
  OfflineSyncService get _service => ref.read(offlineSyncServiceProvider);

  @override
  SyncState build() {
    unawaited(_loadLast());
    // Already logged in when the shell first shows this: sync if the copy is stale.
    Future.microtask(_auto);
    ref.listen(connectionStatusProvider, (_, next) {
      if (next.value == ConnectionStatus.online) unawaited(_auto());
    });
    ref.listen(authControllerProvider, (_, next) {
      final s = next.value;
      if (s is LoggedIn || s is DoctorLoggedIn) unawaited(_auto());
    });
    return const SyncState();
  }

  List<SyncSource> get _sources {
    final session = ref.read(sessionProvider);
    if (session != null) return labSources(session);
    if (ref.read(doctorSessionProvider) != null) return doctorSources;
    return const [];
  }

  Future<void> _loadLast() async {
    final last = await _service.lastFullSync();
    if (last != null) state = state.copyWith(lastSync: last);
  }

  Future<void> _auto() async {
    if (!ref.read(autoSyncEnabledProvider) || state.running || _sources.isEmpty) return;
    final last = await _service.lastFullSync();
    if (last != null && DateTime.now().difference(last) < OfflineSyncService.minInterval) return;
    await syncNow();
  }

  /// Full sync now. Errors (offline…) are rethrown for the caller to show.
  Future<SyncResult?> syncNow() async {
    final sources = _sources;
    if (sources.isEmpty || state.running) return null;
    state = state.copyWith(running: true);
    try {
      final result = await _service.sync(sources);
      state = SyncState(lastSync: result.at, failed: result.failed);
      return result;
    } catch (_) {
      state = state.copyWith(running: false);
      rethrow;
    }
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncState>(SyncController.new);
