import 'json.dart';

/// Product kinds (must match `catalog.Product.Kind`).
enum ProductKind {
  frame('frame'),
  stockLens('stock_lens'),
  rxLens('rx_lens'),
  contactLens('contact_lens'),
  accessory('accessory'),
  solution('solution'),
  service('service');

  const ProductKind(this.value);

  final String value;

  static ProductKind parse(Object? v) =>
      values.firstWhere((k) => k.value == v, orElse: () => ProductKind.accessory);

  /// Stock tracked per power (lens variants).
  bool get usesVariants => this == stockLens || this == contactLens;

  /// Never tracks stock (made to order / services).
  bool get isNonStock => this == rxLens || this == service;

  bool get isLens => this == stockLens || this == rxLens;
}

class Category {
  const Category({required this.id, required this.name, this.parentId, this.isActive = true});

  factory Category.fromJson(Map<String, dynamic> j) => Category(
    id: Json.int0(j['id']),
    name: Json.str(j['name']),
    parentId: Json.intOrNull(j['parent']),
    isActive: Json.boolean(j['is_active'], fallback: true),
  );

  final int id;
  final String name;
  final int? parentId;
  final bool isActive;
}

class Brand {
  const Brand({required this.id, required this.name, this.isActive = true});

  factory Brand.fromJson(Map<String, dynamic> j) => Brand(
    id: Json.int0(j['id']),
    name: Json.str(j['name']),
    isActive: Json.boolean(j['is_active'], fallback: true),
  );

  final int id;
  final String name;
  final bool isActive;
}

class Product {
  const Product({
    required this.id,
    required this.kind,
    required this.name,
    this.brandId,
    this.brandName = '',
    this.categoryId,
    this.categoryName = '',
    this.sku = '',
    this.barcode = '',
    this.salePrice = '0',
    this.purchasePrice,
    this.averageCost,
    this.trackStock = true,
    this.quantity = 0,
    this.reorderLevel = 0,
    this.isLowStock = false,
    this.attributes = const {},
    this.isActive = true,
    this.notes = '',
  });

  factory Product.fromJson(Map<String, dynamic> j) => Product(
    id: Json.int0(j['id']),
    kind: ProductKind.parse(j['kind']),
    name: Json.str(j['name']),
    brandId: Json.intOrNull(j['brand']),
    brandName: Json.str(j['brand_name']),
    categoryId: Json.intOrNull(j['category']),
    categoryName: Json.str(j['category_name']),
    sku: Json.str(j['sku']),
    barcode: Json.str(j['barcode']),
    salePrice: Json.str(j['sale_price']),
    purchasePrice: Json.decimal(j['purchase_price']),
    averageCost: Json.decimal(j['average_cost']),
    trackStock: Json.boolean(j['track_stock'], fallback: true),
    quantity: Json.int0(j['quantity']),
    reorderLevel: Json.int0(j['reorder_level']),
    isLowStock: Json.boolean(j['is_low_stock']),
    attributes: Json.map(j['attributes']),
    isActive: Json.boolean(j['is_active'], fallback: true),
    notes: Json.str(j['notes']),
  );

  final int id;
  final ProductKind kind;
  final String name;
  final int? brandId;
  final String brandName;
  final int? categoryId;
  final String categoryName;
  final String sku;
  final String barcode;
  final String salePrice;

  /// Null when the server hid costs from this user.
  final String? purchasePrice;
  final String? averageCost;
  final bool trackStock;
  final int quantity;
  final int reorderLevel;
  final bool isLowStock;
  final Map<String, dynamic> attributes;
  final bool isActive;
  final String notes;

  bool get usesVariants => kind.usesVariants;
}

/// One power of a stock/contact lens (stock is tracked here).
class LensVariant {
  const LensVariant({
    required this.id,
    required this.productId,
    this.productName = '',
    required this.sph,
    required this.cyl,
    this.add = 0,
    this.sku = '',
    this.barcode = '',
    this.salePrice,
    this.effectiveSalePrice = '0',
    this.quantity = 0,
    this.averageCost,
    this.isActive = true,
  });

  factory LensVariant.fromJson(Map<String, dynamic> j) => LensVariant(
    id: Json.int0(j['id']),
    productId: Json.int0(j['product']),
    productName: Json.str(j['product_name']),
    sph: Json.dbl(j['sph']),
    cyl: Json.dbl(j['cyl']),
    add: Json.dbl(j['add']),
    sku: Json.str(j['sku']),
    barcode: Json.str(j['barcode']),
    salePrice: Json.decimal(j['sale_price']),
    effectiveSalePrice: Json.str(j['effective_sale_price']),
    quantity: Json.int0(j['quantity']),
    averageCost: Json.decimal(j['average_cost']),
    isActive: Json.boolean(j['is_active'], fallback: true),
  );

  final int id;
  final int productId;
  final String productName;
  final double sph;
  final double cyl;
  final double add;
  final String sku;
  final String barcode;
  final String? salePrice;
  final String effectiveSalePrice;
  final int quantity;
  final String? averageCost;
  final bool isActive;
}

enum MovementType {
  purchase('purchase'),
  sale('sale'),
  returnIn('return_in'),
  returnOut('return_out'),
  adjustment('adjustment'),
  damage('damage');

  const MovementType(this.value);

  final String value;

  static MovementType parse(Object? v) =>
      values.firstWhere((t) => t.value == v, orElse: () => MovementType.adjustment);

  /// Types a user can post by hand (sales come from checkout).
  static const manual = [purchase, adjustment, damage, returnIn, returnOut];
}

class StockMovement {
  const StockMovement({
    required this.id,
    required this.productId,
    this.productName = '',
    this.variantId,
    this.variantLabel = '',
    required this.type,
    required this.qty,
    this.unitCost,
    this.totalCost,
    this.qtyAfter = 0,
    this.referenceType = '',
    this.referenceId,
    this.note = '',
    this.createdByName = '',
    this.createdAt,
  });

  factory StockMovement.fromJson(Map<String, dynamic> j) => StockMovement(
    id: Json.int0(j['id']),
    productId: Json.int0(j['product']),
    productName: Json.str(j['product_name']),
    variantId: Json.intOrNull(j['variant']),
    variantLabel: Json.str(j['variant_label']),
    type: MovementType.parse(j['type']),
    qty: Json.int0(j['qty']),
    unitCost: Json.decimal(j['unit_cost']),
    totalCost: Json.decimal(j['total_cost']),
    qtyAfter: Json.int0(j['qty_after']),
    referenceType: Json.str(j['reference_type']),
    referenceId: Json.intOrNull(j['reference_id']),
    note: Json.str(j['note']),
    createdByName: Json.str(j['created_by_name']),
    createdAt: Json.date(j['created_at']),
  );

  final int id;
  final int productId;
  final String productName;
  final int? variantId;
  final String variantLabel;
  final MovementType type;
  final int qty;
  final String? unitCost;
  final String? totalCost;
  final int qtyAfter;
  final String referenceType;
  final int? referenceId;
  final String note;
  final String createdByName;
  final DateTime? createdAt;
}

/// One line of a manual stock entry.
class StockLineInput {
  const StockLineInput({this.productId, this.variantId, required this.qty, this.unitCost});

  final int? productId;
  final int? variantId;
  final int qty;
  final String? unitCost;

  Map<String, dynamic> toJson() => {
    if (productId != null) 'product': productId,
    if (variantId != null) 'variant': variantId,
    'qty': qty,
    if (unitCost != null && unitCost!.isNotEmpty) 'unit_cost': unitCost,
  };
}

/// Product list filters (also the key of the list provider, hence ==/hashCode).
class ProductQuery {
  const ProductQuery({
    this.search = '',
    this.kind,
    this.categoryId,
    this.brandId,
    this.lowStock = false,
    this.includeInactive = false,
    this.page = 1,
  });

  final String search;
  final ProductKind? kind;
  final int? categoryId;
  final int? brandId;
  final bool lowStock;
  final bool includeInactive;
  final int page;

  Map<String, dynamic> toQuery({int pageSize = 100}) => {
    if (search.trim().isNotEmpty) 'search': search.trim(),
    if (kind != null) 'kind': kind!.value,
    if (categoryId != null) 'category': categoryId,
    if (brandId != null) 'brand': brandId,
    if (lowStock) 'low_stock': 'true',
    if (!includeInactive) 'is_active': 'true',
    'page': page,
    'page_size': pageSize,
  };

  /// Offline equivalent of the server filters.
  bool matches(Product p) {
    final q = search.trim().toLowerCase();
    return (q.isEmpty ||
            p.name.toLowerCase().contains(q) ||
            p.sku.toLowerCase().contains(q) ||
            p.barcode.toLowerCase().contains(q) ||
            p.brandName.toLowerCase().contains(q)) &&
        (kind == null || p.kind == kind) &&
        (categoryId == null || p.categoryId == categoryId) &&
        (brandId == null || p.brandId == brandId) &&
        (!lowStock || p.isLowStock) &&
        (includeInactive || p.isActive);
  }

  ProductQuery copyWith({
    String? search,
    ProductKind? Function()? kind,
    int? Function()? categoryId,
    int? Function()? brandId,
    bool? lowStock,
    bool? includeInactive,
    int? page,
  }) => ProductQuery(
    search: search ?? this.search,
    kind: kind != null ? kind() : this.kind,
    categoryId: categoryId != null ? categoryId() : this.categoryId,
    brandId: brandId != null ? brandId() : this.brandId,
    lowStock: lowStock ?? this.lowStock,
    includeInactive: includeInactive ?? this.includeInactive,
    page: page ?? this.page,
  );

  @override
  bool operator ==(Object other) =>
      other is ProductQuery &&
      other.search == search &&
      other.kind == kind &&
      other.categoryId == categoryId &&
      other.brandId == brandId &&
      other.lowStock == lowStock &&
      other.includeInactive == includeInactive &&
      other.page == page;

  @override
  int get hashCode =>
      Object.hash(search, kind, categoryId, brandId, lowStock, includeInactive, page);
}
