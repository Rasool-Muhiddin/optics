import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers.dart';
import 'pos_test.dart' show invoiceJson;

void main() {
  testWidgets('credit customer payment is posted to the FIFO endpoint', (tester) async {
    final server = loggedInServer();
    server.routes.addAll({
      'GET sales/credit-customers/': (_) async => jsonResponse(
        page([
          {
            'patient': 5,
            'name': 'زينب علي',
            'phone': '0770',
            'balance': '25000.00',
            'invoices': 2,
            'oldest': '2026-09-01T10:00:00Z',
          },
        ]),
        200,
      ),
      'POST sales/credit-customers/5/pay/': (http.Request r) async =>
          jsonResponse({'payments': []}, 201),
      'GET sales/invoices/': (_) async =>
          jsonResponse(page([invoiceJson(status: 'open', balance: '25000.00')]), 200),
    });
    await pumpOpticsApp(tester, server: server, storage: await loggedInStorage());
    await tester.tap(find.byKey(const Key('nav-/credit')));
    await tester.pumpAndSettle();
    expect(find.text('زينب علي'), findsOneWidget);

    await tester.tap(find.byKey(const Key('credit-row-5')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('invoice-row-40')), findsOneWidget);

    await tester.tap(find.byKey(const Key('credit-pay-5')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('payment-amount')), '10000');
    await tester.tap(find.byKey(const Key('dialog-save')));
    await tester.pumpAndSettle();

    final body = decodeBody(server.sent('POST', 'sales/credit-customers/5/pay/').single);
    expect(body, {'amount': '10000', 'method': 'cash', 'note': ''});
  });
}
