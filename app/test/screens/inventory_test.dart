import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:optics_app/core/strings/app_strings.dart';
import 'package:optics_app/models/catalog.dart';
import 'package:optics_app/screens/inventory/lens_power_grid.dart';

import '../helpers.dart';

Map<String, dynamic> productJson({
  int id = 1,
  String kind = 'frame',
  String name = 'Ray-Ban 5154',
  int quantity = 4,
  bool withCosts = true,
  bool lowStock = false,
}) => {
  'id': id,
  'kind': kind,
  'name': name,
  'brand': null,
  'brand_name': 'Ray-Ban',
  'category': null,
  'category_name': '',
  'sku': 'RB1',
  'barcode': '6291',
  'sale_price': '85000.00',
  if (withCosts) 'purchase_price': '50000.00',
  if (withCosts) 'average_cost': '48000.00',
  'track_stock': true,
  'uses_variants': kind == 'stock_lens' || kind == 'contact_lens',
  'quantity': quantity,
  'reorder_level': 2,
  'is_low_stock': lowStock,
  'attributes': {'size': '52-18-140', 'gender': 'unisex'},
  'is_active': true,
  'notes': '',
};

Map<String, dynamic> variantJson(int id, double sph, double cyl, int qty) => {
  'id': id,
  'product': 2,
  'product_name': 'CR-39 1.56',
  'sph': sph.toStringAsFixed(2),
  'cyl': cyl.toStringAsFixed(2),
  'add': '0.00',
  'sku': '',
  'barcode': '',
  'sale_price': null,
  'effective_sale_price': '15000.00',
  'quantity': qty,
  'is_active': true,
};

FakeAuthServer inventoryServer({bool owner = true, bool manager = false}) {
  final costs = owner;
  final session = sessionJson(role: owner ? 'owner' : 'staff');
  (session['membership'] as Map<String, dynamic>)['can_manage_inventory'] = owner || manager;
  final server = loggedInServer(session: session);
  final lens = productJson(
    id: 2,
    kind: 'stock_lens',
    name: 'CR-39 1.56',
    quantity: 7,
    withCosts: costs,
  );
  server.routes.addAll({
    'GET catalog/products/': (_) async =>
        jsonResponse(page([productJson(withCosts: costs, lowStock: true), lens]), 200),
    'GET catalog/categories/': (_) async => jsonResponse(page([]), 200),
    'GET catalog/brands/': (_) async => jsonResponse(
      page([
        {'id': 3, 'name': 'Ray-Ban', 'is_active': true},
      ]),
      200,
    ),
    'GET catalog/products/2/': (_) async => jsonResponse(lens, 200),
    'GET catalog/products/2/grid/': (_) async => jsonResponse({
      'product': lens,
      'variants': [
        variantJson(10, 0, 0, 3),
        variantJson(11, 0, -0.5, 0),
        variantJson(12, -1, 0, 4),
        variantJson(13, -1, -0.5, 0),
      ],
    }, 200),
    'GET inventory/movements/': (_) async => jsonResponse(page([]), 200),
    'POST inventory/movements/': (_) async => jsonResponse({'movements': []}, 201),
    'POST catalog/products/': (http.Request r) async =>
        jsonResponse({...productJson(id: 9), ...decodeBody(r)}, 201),
    'GET catalog/products/9/': (_) async => jsonResponse(productJson(id: 9), 200),
  });
  return server;
}

Future<void> openInventory(WidgetTester tester, FakeAuthServer server) async {
  await pumpOpticsApp(
    tester,
    server: server,
    storage: await loggedInStorage(session: server.session),
  );
  await tester.tap(find.byKey(const Key('nav-/inventory')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('owner sees the inventory with costs and low-stock rows', (tester) async {
    await openInventory(tester, inventoryServer());

    expect(find.text('Ray-Ban 5154'), findsOneWidget);
    expect(find.text('CR-39 1.56'), findsOneWidget);
    expect(find.text(AppStrings.averageCost), findsOneWidget);
    expect(find.byKey(const Key('add-product')), findsOneWidget);
  });

  testWidgets('staff without cost permission gets no cost column or owner actions', (tester) async {
    await openInventory(tester, inventoryServer(owner: false));

    expect(find.text('Ray-Ban 5154'), findsOneWidget);
    expect(find.text(AppStrings.averageCost), findsNothing);
    expect(find.byKey(const Key('add-product')), findsNothing);
  });

  testWidgets('inventory-manager staff gets product actions but still no costs', (tester) async {
    await openInventory(tester, inventoryServer(owner: false, manager: true));

    expect(find.text(AppStrings.averageCost), findsNothing);
    expect(find.byKey(const Key('add-product')), findsOneWidget);
    expect(find.byKey(const Key('manage-categories')), findsOneWidget);
  });

  testWidgets('lens product shows the power grid and grid entry posts one movement', (
    tester,
  ) async {
    final server = inventoryServer();
    await openInventory(tester, server);
    await tester.tap(find.byKey(const Key('product-row-2')));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.lensGrid), findsOneWidget);
    expect(find.byKey(const Key('grid-cell-12')), findsOneWidget);
    expect(find.text('-0.50'), findsOneWidget); // CYL column header

    await tester.tap(find.byKey(const Key('grid-entry')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('grid-input-11')), '5');
    await tester.enterText(find.byKey(const Key('grid-input-13')), '2');
    await tester.enterText(find.byKey(const Key('grid-entry-cost')), '3000');
    await tester.tap(find.byKey(const Key('grid-entry-save')));
    await tester.pumpAndSettle();

    final posts = server.sent('POST', 'inventory/movements/');
    expect(posts, hasLength(1));
    final body = decodeBody(posts.single);
    expect(body['type'], 'purchase');
    expect(body['lines'], [
      {'variant': 11, 'qty': 5, 'unit_cost': '3000'},
      {'variant': 13, 'qty': 2, 'unit_cost': '3000'},
    ]);
  });

  testWidgets('add product form validates and sends kind attributes', (tester) async {
    final server = inventoryServer();
    await openInventory(tester, server);
    await tester.tap(find.byKey(const Key('add-product')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dialog-save')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.required), findsWidgets);
    expect(server.sent('POST', 'catalog/products/'), isEmpty);

    await tester.enterText(find.byKey(const Key('product-name')), 'Oakley 8156');
    await tester.enterText(find.byKey(const Key('product-sale_price')), '120000');
    await tester.enterText(find.byKey(const Key('attr-size')), '54-17-140');
    await tester.tap(find.byKey(const Key('dialog-save')));
    await tester.pumpAndSettle();

    final body = decodeBody(server.sent('POST', 'catalog/products/').single);
    expect(body['kind'], 'frame');
    expect(body['name'], 'Oakley 8156');
    expect(body['attributes'], {'size': '54-17-140'});
  });

  testWidgets('barcode comes first and a registered code offers to open that product', (
    tester,
  ) async {
    final server = inventoryServer();
    server.routes['GET catalog/lookup/'] = (http.Request r) async =>
        r.url.queryParameters['code'] == '6291'
        ? jsonResponse({'product': productJson(id: 2, name: 'Oakley 8156'), 'variant': null}, 200)
        : jsonResponse({'detail': 'x', 'code': 'not_found'}, 404);
    await openInventory(tester, server);
    await tester.tap(find.byKey(const Key('add-product')));
    await tester.pumpAndSettle();

    // The scanner can be used at once: the barcode field has the focus.
    final barcode = find.descendant(
      of: find.byKey(const Key('product-barcode')),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(barcode).focusNode.hasFocus, isTrue);
    // Kind-dependent section title and the clearer labels.
    expect(find.text(AppStrings.attributesTitles['frame']!), findsOneWidget);
    expect(find.text(AppStrings.attributeLabels['gender']!), findsOneWidget);
    // SKU / track stock / notes stay folded away.
    expect(find.byKey(const Key('product-sku')), findsNothing);

    await tester.enterText(find.byKey(const Key('product-barcode')), '7777');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('product-duplicate')), findsNothing);

    await tester.enterText(find.byKey(const Key('product-barcode')), '6291');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.textContaining('Oakley 8156'), findsOneWidget);
    await tester.tap(find.byKey(const Key('product-open-duplicate')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('product-barcode')), findsNothing); // dialog closed
    expect(server.sent('GET', 'catalog/products/2/'), isNotEmpty); // product opened

    // Stock lenses: the barcode hint points to per-power barcodes.
    await tester.tap(find.byKey(const Key('nav-/inventory')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-product')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('product-kind-stock_lens')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.variantBarcodeHint), findsOneWidget);
  });

  test('power grid axes put plus SPH first and CYL from 0 down', () {
    final variants = [
      for (final (i, s, c) in [(1, -1.0, 0.0), (2, 0.5, -0.25), (3, 0.0, 0.0)])
        LensVariant(id: i, productId: 1, sph: s, cyl: c),
    ];
    final axes = LensPowerGrid.axes(variants);
    expect(axes.sphs, [0.5, 0.0, -1.0]);
    expect(axes.cyls, [0.0, -0.25]);
  });

  test('offline product filter mirrors the server filters', () {
    final p = Product.fromJson(productJson(lowStock: true));
    expect(const ProductQuery(search: 'ray').matches(p), isTrue);
    expect(const ProductQuery(kind: ProductKind.stockLens).matches(p), isFalse);
    expect(const ProductQuery(lowStock: true).matches(p), isTrue);
    expect(p.averageCost, '48000.00');
    expect(Product.fromJson(productJson(withCosts: false)).averageCost, isNull);
  });
}
