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
import 'package:optics_app/models/catalog.dart';
import 'package:optics_app/models/sales.dart';
import 'package:optics_app/models/session.dart';
import 'package:optics_app/screens/pos/pos_controller.dart';
import 'package:optics_app/services/auth_storage.dart';
import 'package:optics_app/services/connectivity_service.dart';
import 'package:optics_app/services/printing/invoice_pdf.dart';
import 'package:optics_app/services/printing/pdf_kit.dart';
import 'package:optics_app/services/printing/print_service.dart';

import 'package:optics_app/services/offline_sync_service.dart';

import '../helpers.dart';
import 'inventory_test.dart' show productJson, variantJson;

Map<String, dynamic> invoiceJson({String status = 'paid', String balance = '0.00'}) => {
  'id': 40,
  'number': 17,
  'patient': null,
  'patient_name': '',
  'customer_name': 'زبون',
  'customer_phone': '',
  'payment_type': 'cash',
  'status': status,
  'subtotal': '115000.00',
  'lines_discount': '0.00',
  'invoice_discount': '0.00',
  'discount_total': '0.00',
  'total': '115000.00',
  'paid': '115000.00',
  'balance': balance,
  'cashier_name': 'owner1',
  'notes': '',
  'lines': [
    {
      'id': 1,
      'product': 1,
      'variant': null,
      'description': 'Ray-Ban 5154',
      'qty': 1,
      'unit_price': '85000.00',
      'discount': '0.00',
      'line_total': '85000.00',
    },
    {
      'id': 2,
      'product': 2,
      'variant': 12,
      'description': 'CR-39 1.56 (SPH -1.00 CYL +0.00)',
      'qty': 2,
      'unit_price': '15000.00',
      'discount': '0.00',
      'line_total': '30000.00',
    },
  ],
  'payments': [
    {'id': 3, 'invoice': 40, 'amount': '115000.00', 'method': 'cash', 'is_void': false},
  ],
  'created_at': '2026-10-11T10:00:00Z',
};

FakeAuthServer posServer() {
  final server = loggedInServer();
  final frame = productJson();
  final lens = productJson(id: 2, kind: 'stock_lens', name: 'CR-39 1.56', quantity: 7);
  server.routes.addAll({
    'GET catalog/products/': (_) async => jsonResponse(page([frame, lens]), 200),
    'GET catalog/products/2/grid/': (_) async => jsonResponse({
      'product': lens,
      'variants': [variantJson(10, 0, 0, 3), variantJson(12, -1, 0, 4)],
    }, 200),
    'GET catalog/lookup/': (http.Request r) async => r.url.queryParameters['code'] == '6291'
        ? jsonResponse({'product': frame, 'variant': null}, 200)
        : jsonResponse({'detail': 'x', 'code': 'not_found'}, 404),
    'POST sales/checkout/preview/': (http.Request r) async {
      final lines = decodeBody(r)['lines'] as List;
      return jsonResponse({
        'lines': [
          for (final l in lines)
            {
              'description': 'x',
              'qty': l['qty'],
              'unit_price': '1000.00',
              'discount': '0.00',
              'line_total': '1000.00',
              'available': 3,
            },
        ],
        'subtotal': '115000.00',
        'lines_discount': '0.00',
        'invoice_discount': '0.00',
        'discount_total': '0.00',
        'discount_percent': '0.00',
        'total': '115000.00',
        'max_discount_percent': '10.00',
        'requires_owner': false,
      }, 200);
    },
    'POST sales/checkout/': (_) async => jsonResponse(invoiceJson(), 201),
  });
  return server;
}

Future<List<(String, Uint8List)>> pumpPos(WidgetTester tester, FakeAuthServer server) async {
  final printed = <(String, Uint8List)>[];
  tester.view.physicalSize = const Size(1800, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStorageProvider.overrideWithValue(await loggedInStorage()),
        httpClientProvider.overrideWithValue(MockClient(server.handle)),
        connectivityServiceProvider.overrideWithValue(fakeConnectivity(serverUp: true)),
        cacheDatabaseProvider.overrideWithValue(await openTestCache()),
        autoSyncEnabledProvider.overrideWithValue(false),
        printServiceProvider.overrideWithValue(
          PrintService(
            lab: const LabInfo(id: 7, name: 'مختبر النور'),
            logoLoader: (_) async => null,
            printer: (bytes, name, format) async => printed.add((name, bytes)),
          ),
        ),
      ],
      child: const OpticsApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('nav-/pos')));
  await tester.pumpAndSettle();
  return printed;
}

void main() {
  testWidgets('barcode + lens grid pick fill the cart; checkout sends no prices', (tester) async {
    final server = posServer();
    final printed = await pumpPos(tester, server);

    // Barcode scan (Enter) adds the frame.
    await tester.enterText(find.byKey(const Key('pos-search')), '6291');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cart-line-0')), findsOneWidget);

    // Search, pick the lens, choose a power on the grid.
    await tester.enterText(find.byKey(const Key('pos-search')), 'CR');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pos-result-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('grid-cell-12')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cart-inc-1')));
    await tester.pumpAndSettle();

    expect(find.text('115,000 ${AppStrings.currencyIqd}'), findsWidgets); // server total

    await tester.tap(find.byKey(const Key('pos-checkout')));
    await tester.pumpAndSettle();
    final body = decodeBody(server.sent('POST', 'sales/checkout/').single);
    expect(body['lines'], [
      {'product': 1, 'qty': 1},
      {'variant': 12, 'qty': 2},
    ]);
    expect(body.containsKey('total'), isFalse);
    expect(body['payment_type'], 'cash');
    expect(find.textContaining('#17'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('print-invoice-thermal80')));
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pumpAndSettle();
    expect(printed.single.$1, '${AppStrings.invoice} 17');

    await tester.tap(find.byKey(const Key('checkout-done-close')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.emptyCart), findsOneWidget);
  });

  test('cart JSON carries only items, quantities and requested discounts', () {
    const frame = Product(id: 1, kind: ProductKind.frame, name: 'F');
    final state = const PosState(paymentType: 'credit', paymentAmount: '5000', discountValue: '10')
        .copyWith(
          lines: [const CartLine(product: frame, qty: 2, discount: '500')],
        );
    final json = state.toJson();
    expect(json['lines'], [
      {'product': 1, 'qty': 2, 'discount': '500'},
    ]);
    expect(json['payment'], {'method': 'cash', 'amount': '5000'});
    expect(json['invoice_discount_value'], '10');
  });

  test('controller merges repeated items and removes at zero', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final pos = container.read(posControllerProvider.notifier);
    const frame = Product(id: 1, kind: ProductKind.frame, name: 'F');
    pos.add(frame);
    pos.add(frame);
    expect(container.read(posControllerProvider).lines.single.qty, 2);
    pos.setQty(0, 0);
    expect(container.read(posControllerProvider).isEmpty, isTrue);
  });

  test('invoice PDFs build for A4, A5 and 80mm thermal', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final kit = await PdfKit.load(const LabInfo(id: 1, name: 'مختبر النور'));
    final invoice = Invoice.fromJson(invoiceJson(status: 'partially_paid', balance: '1000.00'));
    for (final paper in InvoicePaper.values) {
      final bytes = await InvoicePdf(kit).build(invoice, paper);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF', reason: paper.name);
    }
  });
}
