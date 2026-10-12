import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// `catalog/*` and `inventory/*` endpoints. Returns raw JSON; the repository parses/caches.
class CatalogApiService {
  const CatalogApiService(this._client);

  final ApiClient _client;

  Future<dynamic> products(Map<String, dynamic> query) =>
      _client.get('catalog/products/', query: query);

  Future<Map<String, dynamic>> product(int id) async =>
      await _client.get('catalog/products/$id/') as Map<String, dynamic>;

  Future<Map<String, dynamic>> createProduct(Map<String, dynamic> body) async =>
      await _client.post('catalog/products/', body: body) as Map<String, dynamic>;

  Future<Map<String, dynamic>> updateProduct(int id, Map<String, dynamic> body) async =>
      await _client.patch('catalog/products/$id/', body: body) as Map<String, dynamic>;

  Future<Map<String, dynamic>> grid(int productId) async =>
      await _client.get('catalog/products/$productId/grid/') as Map<String, dynamic>;

  Future<Map<String, dynamic>> matchRx(int productId, int prescriptionId) async =>
      await _client.get(
            'catalog/products/$productId/match/',
            query: {'prescription': prescriptionId},
          )
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> generateVariants(int productId, Map<String, dynamic> body) async =>
      await _client.post('catalog/products/$productId/generate-variants/', body: body)
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> updateVariant(int id, Map<String, dynamic> body) async =>
      await _client.patch('catalog/variants/$id/', body: body) as Map<String, dynamic>;

  Future<Map<String, dynamic>> createVariant(Map<String, dynamic> body) async =>
      await _client.post('catalog/variants/', body: body) as Map<String, dynamic>;

  Future<dynamic> variants(Map<String, dynamic> query) =>
      _client.get('catalog/variants/', query: query);

  Future<Map<String, dynamic>> lookup(String code) async =>
      await _client.get('catalog/lookup/', query: {'code': code}) as Map<String, dynamic>;

  Future<dynamic> categories() => _client.get('catalog/categories/', query: {'page_size': 500});

  Future<Map<String, dynamic>> saveCategory(int? id, Map<String, dynamic> body) async =>
      await (id == null
              ? _client.post('catalog/categories/', body: body)
              : _client.patch('catalog/categories/$id/', body: body))
          as Map<String, dynamic>;

  Future<dynamic> brands() => _client.get('catalog/brands/', query: {'page_size': 500});

  Future<Map<String, dynamic>> saveBrand(int? id, Map<String, dynamic> body) async =>
      await (id == null
              ? _client.post('catalog/brands/', body: body)
              : _client.patch('catalog/brands/$id/', body: body))
          as Map<String, dynamic>;

  Future<dynamic> movements(Map<String, dynamic> query) =>
      _client.get('inventory/movements/', query: query);

  Future<Map<String, dynamic>> postMovements(Map<String, dynamic> body) async =>
      await _client.post('inventory/movements/', body: body) as Map<String, dynamic>;
}

final catalogApiServiceProvider = Provider<CatalogApiService>(
  (ref) => CatalogApiService(ref.watch(apiClientProvider)),
);
