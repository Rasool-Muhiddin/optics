import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optics_app/app.dart';
import 'package:optics_app/core/strings/app_strings.dart';
import 'package:optics_app/data/api/api_client.dart';
import 'package:optics_app/data/cache/cache_database.dart';
import 'package:optics_app/data/repositories/reports_repository.dart';
import 'package:optics_app/screens/settings/settings_screen.dart';
import 'package:optics_app/services/auth_storage.dart';
import 'package:optics_app/services/connectivity_service.dart';
import 'package:optics_app/services/offline_sync_service.dart';

import '../helpers.dart';

Map<String, dynamic> dashboardJson({bool profit = true}) => {
  'today': {'invoices': 3, 'sales_total': '150000.00', 'collected': '120000.00'},
  'month': {'invoices': 40, 'sales_total': '2500000.00', if (profit) 'profit': '900000.00'},
  'credit': {'customers': 2, 'balance': '30000.00'},
  'jobs': {'open': 5, 'overdue': 1, 'ready': 2},
  'stock': {'low': 4},
  'orders': {'open': 2, 'late': 0},
  'sales_last_7_days': [
    for (var i = 0; i < 7; i++) {'date': '2026-10-0${i + 1}', 'total': '${i * 1000}.00'},
  ],
};

Map<String, dynamic> salesJson() => {
  'columns': ['period', 'invoices', 'subtotal', 'discount', 'total', 'balance'],
  'rows': [
    {
      'period': '2026-10-12',
      'invoices': 2,
      'subtotal': '110000.00',
      'discount': '10000.00',
      'total': '100000.00',
      'balance': '6000.00',
    },
  ],
  'totals': {'invoices': 2, 'total': '100000.00'},
  'payments_by_method': [
    {'method': 'cash', 'count': 2, 'amount': '94000.00'},
  ],
  'top_products': [],
};

Map<String, dynamic> withMembership(Map<String, dynamic> session, Map<String, dynamic> extra) => {
  ...session,
  'membership': {...session['membership'] as Map<String, dynamic>, ...extra},
};

FakeAuthServer reportsServer({String role = 'owner', bool costs = true, bool export = false}) {
  var session = sessionJson(role: role);
  session = withMembership(session, {'can_view_costs': costs});
  (session['plan'] as Map<String, dynamic>)['features'] = {
    'doctor_linking': false,
    'report_export': export,
  };
  final server = loggedInServer(session: session);
  server.routes.addAll({
    'GET reports/dashboard/': (_) async => jsonResponse(dashboardJson(profit: costs), 200),
    'GET reports/sales/': (_) async => jsonResponse(salesJson(), 200),
    'GET reports/profit/': (_) async => jsonResponse({
      'columns': ['period', 'revenue', 'cost', 'profit', 'margin'],
      'rows': [],
      'totals': {'revenue': '0.00'},
      'by_kind': [],
      'estimated_cost_lines': 0,
    }, 200),
  });
  return server;
}

Future<void> pumpWithSaver(
  WidgetTester tester,
  FakeAuthServer server,
  List<String> saved, {
  LogoPicker? picker,
}) async {
  tester.view.physicalSize = const Size(1600, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final CacheDatabase cache = await openTestCache();
  final AuthStorage storage = await loggedInStorage(session: server.session);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStorageProvider.overrideWithValue(storage),
        httpClientProvider.overrideWithValue(MockClient(server.handle)),
        connectivityServiceProvider.overrideWithValue(fakeConnectivity(serverUp: true)),
        cacheDatabaseProvider.overrideWithValue(cache),
        autoSyncEnabledProvider.overrideWithValue(false),
        fileSaverProvider.overrideWithValue((String name, Uint8List bytes) async {
          saved.add('$name:${String.fromCharCodes(bytes)}');
          return '/downloads/$name';
        }),
        if (picker != null) logoPickerProvider.overrideWithValue(picker),
      ],
      child: const OpticsApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('owner dashboard shows today, month profit and open work', (tester) async {
    await pumpOpticsApp(tester, server: reportsServer(), storage: await loggedInStorage());
    // The stored session is replaced by the server one at startup.
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('kpi-today-sales')), findsOneWidget);
    expect(find.text('150,000 ${AppStrings.currencyIqd}'), findsOneWidget);
    expect(find.byKey(const Key('kpi-month-profit')), findsOneWidget);
    expect(find.textContaining('${AppStrings.overdue}: 1'), findsOneWidget);
  });

  testWidgets('staff without cost permission: no profit, no reports section', (tester) async {
    final server = reportsServer(role: 'staff', costs: false);
    await pumpOpticsApp(
      tester,
      server: server,
      storage: await loggedInStorage(session: server.session),
    );

    expect(find.byKey(const Key('kpi-today-sales')), findsOneWidget);
    expect(find.byKey(const Key('kpi-month-profit')), findsNothing);
    expect(find.byKey(const Key('nav-/reports')), findsNothing);
  });

  testWidgets('staff with cost permission opens reports; export disabled without the plan', (
    tester,
  ) async {
    final server = reportsServer(role: 'staff', costs: true);
    final saved = <String>[];
    await pumpWithSaver(tester, server, saved);
    await tester.tap(find.byKey(const Key('nav-/reports')));
    await tester.pumpAndSettle();

    expect(find.text('2026-10-12'), findsOneWidget);
    expect(find.byKey(const Key('report-totals')), findsOneWidget);
    expect(find.text(AppStrings.paymentsByMethod), findsOneWidget);
    final export = tester.widget<ButtonStyleButton>(find.byKey(const Key('report-export')));
    expect(export.onPressed, isNull);

    await tester.tap(find.byKey(const Key('report-profit')));
    await tester.pumpAndSettle();
    expect(server.sent('GET', 'reports/profit/'), hasLength(1));
    expect(server.sent('GET', 'reports/profit/').single.url.queryParameters['group'], 'day');
  });

  testWidgets('CSV export downloads the server file and saves it', (tester) async {
    final server = reportsServer(export: true);
    server.routes['GET reports/sales/'] = (http.Request r) async {
      if (r.url.queryParameters['export'] == 'csv') {
        return http.Response.bytes(
          'period,total\n'.codeUnits,
          200,
          headers: {'content-type': 'text/csv'},
        );
      }
      return jsonResponse(salesJson(), 200);
    };
    final saved = <String>[];
    await pumpWithSaver(tester, server, saved);
    await tester.tap(find.byKey(const Key('nav-/reports')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-export')));
    await tester.pumpAndSettle();

    expect(saved.single, startsWith('report_sales_'));
    expect(saved.single, endsWith(':period,total\n'));
    expect(find.textContaining('${AppStrings.exportedTo}: /downloads/'), findsOneWidget);
  });

  testWidgets('owner edits lab settings and uploads a logo', (tester) async {
    final server = reportsServer();
    server.routes.addAll({
      'PATCH lab/': (http.Request r) async => jsonResponse({
        ...server.session['lab'] as Map<String, dynamic>,
        'name': 'مختبر جديد',
      }, 200),
    });
    final saved = <String>[];
    await pumpWithSaver(
      tester,
      server,
      saved,
      picker: () async => (bytes: Uint8List.fromList('PNGDATA'.codeUnits), name: 'logo.png'),
    );
    await tester.tap(find.byKey(const Key('nav-/settings')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('settings-name')), 'مختبر جديد');
    await tester.enterText(find.byKey(const Key('settings-discount')), '15');
    await tester.enterText(find.byKey(const Key('settings-footer')), 'شكراً لزيارتكم');
    final meCalls = server.sent('GET', 'auth/me/').length;
    await tester.tap(find.byKey(const Key('settings-save')));
    await tester.pumpAndSettle();

    final body = decodeBody(server.sent('PATCH', 'lab/').single);
    expect(body['name'], 'مختبر جديد');
    expect(body['max_discount_percent'], '15');
    expect(body['print_footer'], 'شكراً لزيارتكم');
    expect(server.sent('GET', 'auth/me/').length, meCalls + 1); // session refreshed
    expect(find.text(AppStrings.settingsSaved), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-logo')));
    await tester.pumpAndSettle();
    final upload = server.sent('PATCH', 'lab/').last;
    expect(upload.headers['content-type'], startsWith('multipart/form-data'));
    expect(upload.body, contains('filename="logo.png"'));
    expect(upload.body, contains('PNGDATA'));
  });

  testWidgets('settings are owner-only', (tester) async {
    final server = reportsServer(role: 'staff');
    await pumpOpticsApp(
      tester,
      server: server,
      storage: await loggedInStorage(session: server.session),
    );
    expect(find.byKey(const Key('nav-/settings')), findsNothing);
  });
}
