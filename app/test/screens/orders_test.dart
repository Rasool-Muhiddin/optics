import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:optics_app/core/strings/app_strings.dart';
import 'package:optics_app/models/purchasing.dart';

import '../helpers.dart';

String _day(int offset) =>
    DateTime.now().add(Duration(days: offset)).toIso8601String().substring(0, 10);

Map<String, dynamic> orderJson({
  int id = 1,
  int number = 1,
  String status = 'ordered',
  int ageDays = 3,
  int? expectedIn,
  bool withCosts = true,
}) => {
  'id': id,
  'number': number,
  'supplier': 4,
  'supplier_name': 'Essilor Baghdad',
  'type': 'stock',
  'job': null,
  'job_number': null,
  'job_patient_name': '',
  'status': status,
  'payment_status': 'unpaid',
  'order_date': _day(-ageDays),
  'expected_date': expectedIn == null ? null : _day(expectedIn),
  'supplier_ref': '',
  'notes': '',
  if (withCosts) ...{'total': '13000.00', 'paid': '0.00', 'balance': '13000.00', 'payments': []},
  'age_days': ageDays,
  'is_late': expectedIn != null && expectedIn < 0,
  'is_open': true,
  'lines': [
    {
      'id': 11,
      'product': 7,
      'product_name': 'Ray-Ban 5154',
      'product_kind': 'frame',
      'variant': null,
      'variant_label': '',
      'description': '',
      'eye': '',
      'qty': 4,
      if (withCosts) ...{'unit_cost': '2000.00', 'line_total': '8000.00'},
      'qty_received': 0,
      'qty_remaining': 4,
    },
    {
      'id': 12,
      'product': 8,
      'product_name': 'CR-39',
      'product_kind': 'stock_lens',
      'variant': 30,
      'variant_label': 'SPH -1.00 CYL +0.00',
      'description': '',
      'eye': '',
      'qty': 10,
      if (withCosts) ...{'unit_cost': '500.00', 'line_total': '5000.00'},
      'qty_received': 0,
      'qty_remaining': 10,
    },
  ],
  'created_by_name': 'owner1',
};

FakeAuthServer ordersServer({bool owner = true}) {
  final session = sessionJson(role: owner ? 'owner' : 'staff');
  final server = loggedInServer(session: session);
  server.routes.addAll({
    'GET purchasing/orders/': (http.Request r) async => jsonResponse(
      page([
        orderJson(id: 1, number: 1, ageDays: 20, expectedIn: -2, withCosts: owner),
        orderJson(id: 2, number: 2, status: 'pending', withCosts: owner),
      ]),
      200,
    ),
    'GET purchasing/orders/summary/': (_) async => jsonResponse({
      'counts': {'pending': 1, 'ordered': 1},
      'open': 2,
      'late': 1,
      'ageing': [
        {'from_days': 0, 'to_days': 7, 'count': 1},
        {'from_days': 8, 'to_days': 14, 'count': 0},
        {'from_days': 15, 'to_days': 30, 'count': 1},
        {'from_days': 31, 'to_days': null, 'count': 0},
      ],
      if (owner) 'owed': '26000.00',
    }, 200),
    'GET purchasing/suppliers/': (_) async => jsonResponse(
      page([
        {
          'id': 4,
          'name': 'Essilor Baghdad',
          'phone': '',
          'is_active': true,
          'open_orders': 2,
          if (owner) 'balance': '26000.00',
        },
      ]),
      200,
    ),
    'GET purchasing/orders/1/': (_) async =>
        jsonResponse(orderJson(id: 1, ageDays: 20, expectedIn: -2, withCosts: owner), 200),
    'POST purchasing/orders/1/receive/': (_) async =>
        jsonResponse({...orderJson(id: 1), 'status': 'partially_received'}, 200),
    'GET catalog/products/': (_) async => jsonResponse(
      page([
        {
          'id': 7,
          'kind': 'frame',
          'name': 'Ray-Ban 5154',
          'sale_price': '50000.00',
          'track_stock': true,
          'uses_variants': false,
          'quantity': 2,
          'is_active': true,
        },
      ]),
      200,
    ),
    'POST purchasing/orders/': (http.Request r) async =>
        jsonResponse(orderJson(id: 3, number: 3), 201),
    'GET purchasing/orders/3/': (_) async => jsonResponse(orderJson(id: 3, number: 3), 200),
  });
  return server;
}

Future<void> openOrders(WidgetTester tester, FakeAuthServer server) async {
  await pumpOpticsApp(tester, server: server, storage: await loggedInStorage(session: server.session));
  tester.view.physicalSize = const Size(1600, 1000);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('nav-/orders')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('open orders list shows late orders, ageing and totals', (tester) async {
    final server = ordersServer();
    await openOrders(tester, server);

    expect(find.byKey(const Key('order-row-1')), findsOneWidget);
    expect(find.byKey(const Key('order-late-1')), findsOneWidget);
    expect(find.byKey(const Key('order-late-2')), findsNothing);
    expect(find.textContaining('20 ${AppStrings.daysOld}'), findsOneWidget);
    expect(find.textContaining(AppStrings.totalOwed), findsOneWidget);
    expect(server.sent('GET', 'purchasing/orders/').first.url.queryParameters['open'], 'true');

    // Tapping an ageing bucket filters by minimum age.
    await tester.tap(find.byKey(const Key('ageing-15')));
    await tester.pumpAndSettle();
    expect(server.sent('GET', 'purchasing/orders/').last.url.queryParameters['min_age'], '15');
  });

  testWidgets('staff without cost permission sees no money and no actions', (tester) async {
    await openOrders(tester, ordersServer(owner: false));

    expect(find.byKey(const Key('order-row-1')), findsOneWidget);
    expect(find.textContaining(AppStrings.totalOwed), findsNothing);
    expect(find.byKey(const Key('new-order')), findsNothing);
    await tester.tap(find.byKey(const Key('order-row-1')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.unitCost), findsNothing);
    expect(find.byKey(const Key('order-receive')), findsNothing);
  });

  testWidgets('receive dialog posts the quantities per line', (tester) async {
    final server = ordersServer();
    await openOrders(tester, server);
    await tester.tap(find.byKey(const Key('order-row-1')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.unitCost), findsOneWidget);

    await tester.tap(find.byKey(const Key('order-receive')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('receive-qty-11')), '2');
    await tester.enterText(find.byKey(const Key('receive-qty-12')), '0');
    await tester.tap(find.byKey(const Key('dialog-save')));
    await tester.pumpAndSettle();

    final body = decodeBody(server.sent('POST', 'purchasing/orders/1/receive/').single);
    expect(body['lines'], [
      {'line': 11, 'qty': 2},
    ]);
  });

  testWidgets('new stock order sends supplier, status and lines', (tester) async {
    final server = ordersServer();
    await openOrders(tester, server);
    await tester.tap(find.byKey(const Key('new-order')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('order-supplier')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Essilor Baghdad').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('order-add-product')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pick-product-7')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('order-line-qty-0')), '3');
    await tester.enterText(find.byKey(const Key('order-line-cost-0')), '2500');
    await tester.tap(find.byKey(const Key('dialog-save')));
    await tester.pumpAndSettle();

    final body = decodeBody(server.sent('POST', 'purchasing/orders/').single);
    expect(body['supplier'], 4);
    expect(body['type'], 'stock');
    expect(body['status'], 'ordered');
    expect(body['lines'], [
      {
        'product': 7,
        'variant': null,
        'description': '',
        'eye': '',
        'qty': 3,
        'unit_cost': '2500',
      },
    ]);
    // Opens the new order.
    expect(find.textContaining('#3'), findsWidgets);
  });

  test('ageing and lateness are re-evaluated offline', () {
    final now = DateTime.now();
    final late = SupplierOrder.fromJson(orderJson(ageDays: 9, expectedIn: -1));
    expect(late.ageOn(now), 9);
    expect(late.lateOn(now), isTrue);
    expect(SupplierOrder.fromJson(orderJson(expectedIn: 0)).lateOn(now), isFalse);
    expect(
      SupplierOrder.fromJson({...orderJson(expectedIn: -3), 'status': 'received'}).lateOn(now),
      isFalse,
    );
  });
}
