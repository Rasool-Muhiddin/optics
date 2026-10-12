import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// `purchasing/*`: suppliers, supplier orders, receiving and supplier payments.
class PurchasingApiService {
  const PurchasingApiService(this._client);

  final ApiClient _client;

  Future<dynamic> suppliers(Map<String, dynamic> query) =>
      _client.get('purchasing/suppliers/', query: query);

  Future<Map<String, dynamic>> saveSupplier(int? id, Map<String, dynamic> body) async =>
      await (id == null
              ? _client.post('purchasing/suppliers/', body: body)
              : _client.patch('purchasing/suppliers/$id/', body: body))
          as Map<String, dynamic>;

  Future<dynamic> paySupplier(int id, Map<String, dynamic> body) =>
      _client.post('purchasing/suppliers/$id/pay/', body: body);

  Future<dynamic> orders(Map<String, dynamic> query) =>
      _client.get('purchasing/orders/', query: query);

  Future<Map<String, dynamic>> order(int id) async =>
      await _client.get('purchasing/orders/$id/') as Map<String, dynamic>;

  Future<Map<String, dynamic>> summary() async =>
      await _client.get('purchasing/orders/summary/') as Map<String, dynamic>;

  Future<Map<String, dynamic>> saveOrder(int? id, Map<String, dynamic> body) async =>
      await (id == null
              ? _client.post('purchasing/orders/', body: body)
              : _client.patch('purchasing/orders/$id/', body: body))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> action(int id, String action, Map<String, dynamic> body) async =>
      await _client.post('purchasing/orders/$id/$action/', body: body) as Map<String, dynamic>;

  Future<Map<String, dynamic>> voidPayment(int id, String reason) async =>
      await _client.post('purchasing/payments/$id/void/', body: {'reason': reason})
          as Map<String, dynamic>;
}

final purchasingApiServiceProvider = Provider<PurchasingApiService>(
  (ref) => PurchasingApiService(ref.watch(apiClientProvider)),
);
