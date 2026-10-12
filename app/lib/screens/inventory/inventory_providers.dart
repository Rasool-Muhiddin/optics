import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/catalog_repository.dart';
import '../../models/catalog.dart';
import '../../models/json.dart';

final productListProvider = FutureProvider.autoDispose.family<PageResult<Product>, ProductQuery>(
  (ref, query) => ref.watch(catalogRepositoryProvider).listProducts(query),
);

final categoriesProvider = FutureProvider.autoDispose<List<Category>>(
  (ref) => ref.watch(catalogRepositoryProvider).categories(),
);

final brandsProvider = FutureProvider.autoDispose<List<Brand>>(
  (ref) => ref.watch(catalogRepositoryProvider).brands(),
);

final productProvider = FutureProvider.autoDispose.family<Product, int>(
  (ref, id) => ref.watch(catalogRepositoryProvider).getProduct(id),
);

final lensGridProvider = FutureProvider.autoDispose.family<LensGrid, int>(
  (ref, productId) => ref.watch(catalogRepositoryProvider).grid(productId),
);

final productMovementsProvider = FutureProvider.autoDispose.family<List<StockMovement>, int>(
  (ref, productId) => ref.watch(catalogRepositoryProvider).movements(productId: productId),
);

/// Refreshes everything that shows stock for [productId] after a write.
void invalidateProduct(WidgetRef ref, int productId) {
  ref.invalidate(productProvider(productId));
  ref.invalidate(lensGridProvider(productId));
  ref.invalidate(productMovementsProvider(productId));
  ref.invalidate(productListProvider);
}
