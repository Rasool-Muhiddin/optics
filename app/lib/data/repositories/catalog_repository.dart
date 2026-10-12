import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../models/catalog.dart';
import '../../models/json.dart';
import '../../services/connectivity_service.dart';
import '../api/catalog_api_service.dart';
import '../cache/cache_database.dart';
import '../cache/json_cache_dao.dart';
import 'base_repository.dart';

/// Lens product + all its powers (the power grid).
class LensGrid {
  const LensGrid({required this.product, required this.variants});

  final Product product;
  final List<LensVariant> variants;
}

/// Catalog and stock. Reads fall back to the cache offline; writes need the server.
class CatalogRepository extends BaseRepository {
  CatalogRepository(super.connectivity, {required this.api, required CacheDatabase cache})
    : products = JsonCacheDao(cache, CacheTables.products),
      categoriesDao = JsonCacheDao(cache, CacheTables.categories),
      brandsDao = JsonCacheDao(cache, CacheTables.brands),
      variantsDao = JsonCacheDao(cache, CacheTables.lensVariants),
      movementsDao = JsonCacheDao(cache, CacheTables.stockMovements);

  final CatalogApiService api;
  final JsonCacheDao products;
  final JsonCacheDao categoriesDao;
  final JsonCacheDao brandsDao;
  final JsonCacheDao variantsDao;
  final JsonCacheDao movementsDao;

  // --- Products ---------------------------------------------------------------------

  Future<PageResult<Product>> listProducts(ProductQuery query) => read(
    remote: () async {
      final json = await api.products(query.toQuery());
      await products.upsertAll(PageResult.rows(json));
      return PageResult.fromJson(json, Product.fromJson);
    },
    cached: () async {
      final rows = (await products.getAll()).map(Product.fromJson).where(query.matches).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      return PageResult(items: rows, count: rows.length);
    },
  );

  Future<Product> getProduct(int id) => read(
    remote: () => api.product(id),
    cached: () async => await products.getById(id) ?? (throw const NotCachedException()),
    saveToCache: (json) => products.upsertAll([json]),
  ).then(Product.fromJson);

  Future<Product> saveProduct(int? id, Map<String, dynamic> body) => write(() async {
    final json = id == null ? await api.createProduct(body) : await api.updateProduct(id, body);
    await products.upsertAll([json]);
    return Product.fromJson(json);
  });

  /// Product by barcode/SKU (online only: scanning at the counter needs live stock).
  Future<({Product product, LensVariant? variant})> lookup(String code) async {
    final json = await api.lookup(code);
    final variant = json['variant'];
    return (
      product: Product.fromJson(Json.map(json['product'])),
      variant: variant == null ? null : LensVariant.fromJson(Json.map(variant)),
    );
  }

  // --- Lens powers ------------------------------------------------------------------

  Future<LensGrid> grid(int productId) => read(
    remote: () async {
      final json = await api.grid(productId);
      final rows = Json.list(json['variants']);
      await products.upsertAll([Json.map(json['product'])]);
      await variantsDao.upsertAll(rows);
      return LensGrid(
        product: Product.fromJson(Json.map(json['product'])),
        variants: rows.map(LensVariant.fromJson).toList(),
      );
    },
    cached: () async {
      final product = await products.getById(productId) ?? (throw const NotCachedException());
      final rows = await variantsDao.where((r) => Json.int0(r['product']) == productId);
      return LensGrid(
        product: Product.fromJson(product),
        variants: rows.map(LensVariant.fromJson).toList(),
      );
    },
  );

  Future<({int created, int skipped})> generateVariants(int productId, Map<String, dynamic> body) =>
      write(() async {
        final json = await api.generateVariants(productId, body);
        return (created: Json.int0(json['created']), skipped: Json.int0(json['skipped']));
      });

  Future<LensVariant> saveVariant(int? id, Map<String, dynamic> body) => write(() async {
    final json = id == null ? await api.createVariant(body) : await api.updateVariant(id, body);
    await variantsDao.upsertAll([json]);
    return LensVariant.fromJson(json);
  });

  /// Active variants with stock, for picking a power (POS).
  Future<List<LensVariant>> variantsOf(int productId) => read(
    remote: () async {
      final json = await api.variants({
        'product': productId,
        'is_active': 'true',
        'page_size': 500,
      });
      await variantsDao.upsertAll(PageResult.rows(json));
      return PageResult.fromJson(json, LensVariant.fromJson).items;
    },
    cached: () async => (await variantsDao.where(
      (r) => Json.int0(r['product']) == productId,
    )).map(LensVariant.fromJson).toList(),
  );

  // --- Categories & brands ----------------------------------------------------------

  Future<List<Category>> categories() => read(
    remote: () async {
      final json = await api.categories();
      await categoriesDao.replaceAll(PageResult.rows(json));
      return PageResult.fromJson(json, Category.fromJson).items;
    },
    cached: () async => (await categoriesDao.getAll()).map(Category.fromJson).toList(),
  );

  Future<Category> saveCategory(int? id, Map<String, dynamic> body) => write(() async {
    final json = await api.saveCategory(id, body);
    await categoriesDao.upsertAll([json]);
    return Category.fromJson(json);
  });

  Future<List<Brand>> brands() => read(
    remote: () async {
      final json = await api.brands();
      await brandsDao.replaceAll(PageResult.rows(json));
      return PageResult.fromJson(json, Brand.fromJson).items;
    },
    cached: () async => (await brandsDao.getAll()).map(Brand.fromJson).toList(),
  );

  Future<Brand> saveBrand(int? id, Map<String, dynamic> body) => write(() async {
    final json = await api.saveBrand(id, body);
    await brandsDao.upsertAll([json]);
    return Brand.fromJson(json);
  });

  // --- Stock ledger -----------------------------------------------------------------

  Future<List<StockMovement>> movements({int? productId, int? variantId}) => read(
    remote: () async {
      final json = await api.movements({
        'product': ?productId,
        'variant': ?variantId,
        'page_size': 100,
      });
      await movementsDao.upsertAll(PageResult.rows(json));
      return PageResult.fromJson(json, StockMovement.fromJson).items;
    },
    cached: () async {
      final rows = await movementsDao.where(
        (r) =>
            (productId == null || Json.int0(r['product']) == productId) &&
            (variantId == null || Json.int0(r['variant']) == variantId),
      );
      final list = rows.map(StockMovement.fromJson).toList()..sort((a, b) => b.id.compareTo(a.id));
      return list;
    },
  );

  /// One manual stock entry (all lines applied atomically on the server).
  Future<void> postStock({
    required MovementType type,
    required List<StockLineInput> lines,
    String note = '',
  }) => write(
    () => api.postMovements({
      'type': type.value,
      'note': note,
      'lines': [for (final l in lines) l.toJson()],
    }),
  );
}

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(
    ref.watch(connectivityServiceProvider),
    api: ref.watch(catalogApiServiceProvider),
    cache: ref.watch(cacheDatabaseProvider),
  ),
);
