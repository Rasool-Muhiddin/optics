import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optics_app/app.dart';
import 'package:optics_app/core/strings/app_strings.dart';
import 'package:optics_app/data/api/api_client.dart';
import 'package:optics_app/data/api/health_api_service.dart';
import 'package:optics_app/data/cache/cache_database.dart';
import 'package:optics_app/data/cache/json_cache_dao.dart';
import 'package:optics_app/data/repositories/reports_repository.dart';
import 'package:optics_app/models/session.dart';
import 'package:optics_app/services/auth_storage.dart';
import 'package:optics_app/services/connectivity_service.dart';
import 'package:optics_app/services/offline_sync_service.dart';
import 'package:optics_app/services/printing/print_service.dart';

import '../helpers.dart';
import '../screens/pos_test.dart' show invoiceJson;

Map<String, dynamic> pageWithNext(List<Map<String, dynamic>> rows, {bool next = false}) => {
  'count': rows.length,
  'next': next ? 'more' : null,
  'previous': null,
  'results': rows,
};

void main() {
  test('full sync pulls every page of every source and records the time', () async {
    final requests = <Uri>[];
    final api = fakeApi((request) async {
      requests.add(request.url);
      final path = request.url.path.replaceFirst('/api/v1/', '');
      final page = request.url.queryParameters['page'];
      switch (path) {
        case 'catalog/products/':
          return page == '1'
              ? jsonResponse(
                  pageWithNext([
                    {'id': 1, 'name': 'A'},
                  ], next: true),
                  200,
                )
              : jsonResponse(
                  pageWithNext([
                    {'id': 2, 'name': 'B'},
                  ]),
                  200,
                );
        case 'sales/invoices/':
          return jsonResponse(pageWithNext([invoiceJson()]), 200);
        case 'lab/users/':
          return jsonResponse({'detail': 'x', 'code': 'owner_required'}, 403);
      }
      return jsonResponse(pageWithNext([]), 200);
    });
    final cache = await openTestCache();
    final service = OfflineSyncService(
      api: api,
      cache: cache,
      connectivity: fakeConnectivity(serverUp: true),
    );
    final sources = labSources(Session.fromJson(sessionJson()));
    expect(sources.map((s) => s.table), containsAll([CacheTables.patients, CacheTables.jobs]));

    final result = await service.sync(sources);

    expect((await JsonCacheDao(cache, CacheTables.products).getAll()).length, 2);
    final invoice = (await JsonCacheDao(cache, CacheTables.invoices).getAll()).single;
    expect(invoice['lines'], isNotEmpty); // printable offline
    expect(
      requests.firstWhere((u) => u.path.endsWith('sales/invoices/')).queryParameters['with_lines'],
      'true',
    );
    expect(result.failed, contains(CacheTables.labUsers));
    expect(await service.lastFullSync(), isNotNull);
  });

  test('doctor mode syncs only the doctor tables', () {
    expect(doctorSources.map((s) => s.table).toSet(), {
      CacheTables.doctorSideLinks,
      CacheTables.doctorSideReferrals,
    });
  });

  test('report cache ids are stable and order-independent', () {
    expect(reportCacheId('sales', {'a': 1, 'b': 2}), reportCacheId('sales', {'b': 2, 'a': 1}));
    expect(reportCacheId('sales', {'a': 1}), isNot(reportCacheId('profit', {'a': 1})));
  });

  testWidgets('offline: synced invoices are listed, searchable, and print from the cache', (
    tester,
  ) async {
    final server = loggedInServer();
    server.routes.addAll({
      'GET sales/invoices/': (http.Request r) async => jsonResponse(page([invoiceJson()]), 200),
      'GET sales/invoices/40/': (_) async => jsonResponse(invoiceJson(), 200),
    });
    final printed = <String>[];
    final connectivity = ConnectivityService(
      HealthApiService(
        fakeApi((_) async {
          if (server.down) throw http.ClientException('down');
          return jsonResponse({'status': 'ok', 'database': 'ok'}, 200);
        }),
      ),
    );
    await connectivity.checkNow();
    final CacheDatabase cache = await openTestCache();
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStorageProvider.overrideWithValue(await loggedInStorage()),
          httpClientProvider.overrideWithValue(MockClient(server.handle)),
          connectivityServiceProvider.overrideWithValue(connectivity),
          cacheDatabaseProvider.overrideWithValue(cache),
          autoSyncEnabledProvider.overrideWithValue(false),
          printServiceProvider.overrideWithValue(
            PrintService(
              lab: const LabInfo(id: 7, name: 'مختبر النور'),
              logoLoader: (_) async => null,
              printer: (bytes, name, format) async => printed.add(name),
            ),
          ),
        ],
        child: const OpticsApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Manual sync from the sidebar while online.
    await tester.tap(find.byKey(const Key('sync-now')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.notSyncedYet), findsNothing);
    expect(server.sent('GET', 'sales/invoices/').last.url.queryParameters['with_lines'], 'true');

    // The server goes away.
    server.down = true;
    await connectivity.checkNow();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-/invoices')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('offline-notice')), findsOneWidget);
    expect(find.textContaining(AppStrings.lastSynced), findsOneWidget);
    expect(find.byKey(const Key('invoice-row-40')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('invoices-search')), 'لا يوجد');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('invoice-row-40')), findsNothing);
    await tester.enterText(find.byKey(const Key('invoices-search')), '17');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('invoice-row-40')), findsOneWidget);

    // Never opened online, but printable from the synced copy.
    await tester.tap(find.byKey(const Key('invoice-row-40')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('print-invoice-thermal80')));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();
    expect(printed, ['${AppStrings.invoice} 17']);
    expect(server.sent('GET', 'sales/invoices/40/'), isEmpty);
  });
}
