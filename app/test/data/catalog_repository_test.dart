import 'package:flutter_test/flutter_test.dart';
import 'package:optics_app/core/errors/app_exception.dart';
import 'package:optics_app/data/api/catalog_api_service.dart';
import 'package:optics_app/data/repositories/catalog_repository.dart';
import 'package:optics_app/models/catalog.dart';

import '../helpers.dart';
import '../screens/inventory_test.dart' show inventoryServer;

void main() {
  test('products are cached online and served (filtered) offline; writes are refused', () async {
    final cache = await openTestCache();
    final server = inventoryServer();
    final api = CatalogApiService(fakeApi(server.handle));

    final online = fakeConnectivity(serverUp: true);
    await online.checkNow();
    final repo = CatalogRepository(online, api: api, cache: cache);
    expect((await repo.listProducts(const ProductQuery())).items, hasLength(2));

    final offline = fakeConnectivity(serverUp: false);
    await offline.checkNow();
    final offlineRepo = CatalogRepository(offline, api: api, cache: cache);
    final lenses = await offlineRepo.listProducts(const ProductQuery(kind: ProductKind.stockLens));
    expect(lenses.items.single.name, 'CR-39 1.56');
    expect(
      () => offlineRepo.saveProduct(null, {'name': 'x'}),
      throwsA(isA<OfflineWriteException>()),
    );
    expect(() => offlineRepo.getProduct(999), throwsA(isA<NotCachedException>()));
    await cache.close();
  });
}
