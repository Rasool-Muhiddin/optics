import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// `sales/*`: checkout (+ preview), invoices, payments, credit customers.
class SalesApiService {
  const SalesApiService(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> preview(Map<String, dynamic> cart) async =>
      await _client.post('sales/checkout/preview/', body: cart) as Map<String, dynamic>;

  Future<Map<String, dynamic>> checkout(Map<String, dynamic> cart) async =>
      await _client.post('sales/checkout/', body: cart) as Map<String, dynamic>;

  Future<dynamic> invoices(Map<String, dynamic> query) =>
      _client.get('sales/invoices/', query: query);

  Future<Map<String, dynamic>> invoice(int id) async =>
      await _client.get('sales/invoices/$id/') as Map<String, dynamic>;

  Future<Map<String, dynamic>> addPayment(int invoiceId, Map<String, dynamic> body) async =>
      await _client.post('sales/invoices/$invoiceId/payments/', body: body) as Map<String, dynamic>;

  Future<Map<String, dynamic>> cancel(int invoiceId, String reason) async =>
      await _client.post('sales/invoices/$invoiceId/cancel/', body: {'reason': reason})
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> voidPayment(int paymentId, String reason) async =>
      await _client.post('sales/payments/$paymentId/void/', body: {'reason': reason})
          as Map<String, dynamic>;

  Future<dynamic> creditCustomers(Map<String, dynamic> query) =>
      _client.get('sales/credit-customers/', query: query);

  Future<Map<String, dynamic>> payCustomer(int patientId, Map<String, dynamic> body) async =>
      await _client.post('sales/credit-customers/$patientId/pay/', body: body)
          as Map<String, dynamic>;
}

final salesApiServiceProvider = Provider<SalesApiService>(
  (ref) => SalesApiService(ref.watch(apiClientProvider)),
);
