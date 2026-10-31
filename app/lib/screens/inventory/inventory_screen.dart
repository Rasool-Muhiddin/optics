import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_routes.dart';
import '../../core/strings/app_strings.dart';
import '../../data/cache/json_cache_dao.dart';
import '../../models/catalog.dart';
import '../../services/auth_controller.dart';
import '../../widgets/common.dart';
import 'categories_brands_dialog.dart';
import 'inventory_providers.dart';
import 'product_form_dialog.dart';

/// Inventory list: filters (kind, category, brand, low stock, search) + table.
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  ProductQuery _query = const ProductQuery();
  final _search = TextEditingController();
  Timer? _debounce;
  int _pages = 1;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _setQuery(ProductQuery q) => setState(() {
    _query = q.copyWith(page: 1);
    _pages = 1;
  });

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _setQuery(_query.copyWith(search: text)),
    );
  }

  Future<void> _addProduct() async {
    final product = await showDialog<Product>(
      context: context,
      builder: (_) => const ProductFormDialog(),
    );
    if (product != null && mounted) {
      ref.invalidate(productListProvider);
      context.go(AppRoutes.productDetail(product.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final canManage = session?.canManageInventory ?? false;
    final seesCosts = session?.membership.canViewCosts ?? false;
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final brands = ref.watch(brandsProvider).value ?? const <Brand>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: AppStrings.inventoryTitle,
          cacheTables: const [CacheTables.products, CacheTables.categories, CacheTables.brands],
          actions: [
            if (canManage)
              OutlinedButton.icon(
                key: const Key('manage-categories'),
                icon: const Icon(Icons.category_outlined),
                label: const Text(AppStrings.categoriesAndBrands),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const CategoriesBrandsDialog(),
                ),
              ),
            if (canManage)
              FilledButton.icon(
                key: const Key('add-product'),
                icon: const Icon(Icons.add),
                label: const Text(AppStrings.addProduct),
                onPressed: _addProduct,
              ),
          ],
        ),
        FilterBar(
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                key: const Key('inventory-search'),
                controller: _search,
                decoration: const InputDecoration(
                  hintText: AppStrings.search,
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: _onSearch,
              ),
            ),
            _Dropdown<ProductKind>(
              label: AppStrings.productKind,
              value: _query.kind,
              items: {for (final k in ProductKind.values) k: AppStrings.productKinds[k.value]!},
              onChanged: (v) => _setQuery(_query.copyWith(kind: () => v)),
            ),
            _Dropdown<int>(
              label: AppStrings.category,
              value: _query.categoryId,
              items: {for (final c in categories) c.id: c.name},
              onChanged: (v) => _setQuery(_query.copyWith(categoryId: () => v)),
            ),
            _Dropdown<int>(
              label: AppStrings.brand,
              value: _query.brandId,
              items: {for (final b in brands) b.id: b.name},
              onChanged: (v) => _setQuery(_query.copyWith(brandId: () => v)),
            ),
            FilterChip(
              key: const Key('filter-low-stock'),
              label: const Text(AppStrings.lowStockOnly),
              selected: _query.lowStock,
              onSelected: (v) => _setQuery(_query.copyWith(lowStock: v)),
            ),
            FilterChip(
              label: const Text(AppStrings.showInactive),
              selected: _query.includeInactive,
              onSelected: (v) => _setQuery(_query.copyWith(includeInactive: v)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              0,
              AppSpacing.page,
              AppSpacing.page,
            ),
            child: TableFrame(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header stays put while the pages of rows scroll (sticky header).
                  DataTableHeader(columns: ProductTable.columnsFor(seesCosts: seesCosts)),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        for (var page = 1; page <= _pages; page++)
                          _ProductPage(
                            query: _query.copyWith(page: page),
                            showHeader: page == 1,
                            seesCosts: seesCosts,
                            onLoadMore: page == _pages ? () => setState(() => _pages++) : null,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProductPage extends ConsumerWidget {
  const _ProductPage({
    required this.query,
    required this.showHeader,
    required this.seesCosts,
    this.onLoadMore,
  });

  final ProductQuery query;

  /// First page (shows the empty state when there are no products).
  final bool showHeader;
  final bool seesCosts;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(productListProvider(query));
    return AsyncView(
      value: value,
      skeleton: showHeader,
      onRetry: () => ref.invalidate(productListProvider(query)),
      builder: (page) {
        if (page.items.isEmpty && showHeader) {
          return const EmptyState(
            icon: Icons.inventory_2_outlined,
            message: AppStrings.emptyFilteredHint,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProductTable(
              products: page.items,
              showHeader: false,
              seesCosts: seesCosts,
              startIndex: (query.page - 1) * 100,
            ),
            if (page.hasMore && onLoadMore != null)
              TableFooter(count: page.items.length, onLoadMore: onLoadMore),
          ],
        );
      },
    );
  }
}

/// Inventory rows. The cost column exists only for users the server sends costs to.
class ProductTable extends StatelessWidget {
  const ProductTable({
    super.key,
    required this.products,
    this.showHeader = true,
    required this.seesCosts,
    this.startIndex = 0,
  });

  final List<Product> products;
  final bool showHeader;
  final bool seesCosts;

  /// Row index offset (zebra striping continues across pages).
  final int startIndex;

  static List<TableCol> columnsFor({required bool seesCosts}) => [
    const TableCol(AppStrings.productName, flex: 4),
    const TableCol(AppStrings.productKind, flex: 2),
    const TableCol(AppStrings.brand, flex: 2),
    const TableCol(AppStrings.barcode, flex: 2, center: true),
    const TableCol(AppStrings.salePrice, flex: 2, numeric: true),
    if (seesCosts) const TableCol(AppStrings.averageCost, flex: 2, numeric: true),
    const TableCol(AppStrings.quantity, flex: 2, numeric: true),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final columns = columnsFor(seesCosts: seesCosts);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader) DataTableHeader(columns: columns),
        for (var i = 0; i < products.length; i++)
          Builder(
            builder: (context) {
              final p = products[i];
              final low = p.trackStock && (p.isLowStock || p.quantity <= 0);
              return DataRowView(
                key: Key('product-row-${p.id}'),
                columns: columns,
                index: startIndex + i,
                muted: !p.isActive,
                accent: low ? colors.danger : null,
                onTap: () => context.go(AppRoutes.productDetail(p.id)),
                cells: [
                  Text(
                    p.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  StatusBadge(
                    label: AppStrings.productKinds[p.kind.value] ?? p.kind.value,
                    dense: true,
                  ),
                  Text(p.brandName, overflow: TextOverflow.ellipsis),
                  Text(
                    p.barcode.isNotEmpty ? p.barcode : p.sku,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(fontFeatures: AppText.tabular),
                  ),
                  MoneyText(p.salePrice),
                  if (seesCosts) MoneyText(p.averageCost, tone: Tone.neutral),
                  p.trackStock
                      ? NumText(
                          '${p.quantity}',
                          bold: p.isLowStock,
                          color: low ? colors.danger : null,
                        )
                      : Text(
                          AppStrings.noStockTracking,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final Map<T, String> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: DropdownButtonFormField<T?>(
        initialValue: items.containsKey(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          DropdownMenuItem<T?>(value: null, child: const Text(AppStrings.all)),
          for (final e in items.entries) DropdownMenuItem<T?>(value: e.key, child: Text(e.value)),
        ],
        onChanged: onChanged,
      ),
    );
  }
}
