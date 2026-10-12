import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters/formatters.dart';
import '../../core/router/app_routes.dart';
import '../../core/strings/app_strings.dart';
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
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
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
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
  final bool showHeader;
  final bool seesCosts;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(productListProvider(query));
    return AsyncView(
      value: value,
      onRetry: () => ref.invalidate(productListProvider(query)),
      builder: (page) {
        if (page.items.isEmpty && showHeader) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text(AppStrings.noData)),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProductTable(products: page.items, showHeader: showHeader, seesCosts: seesCosts),
            if (page.hasMore && onLoadMore != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: TextButton(onPressed: onLoadMore, child: const Text(AppStrings.loadMore)),
                ),
              ),
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
  });

  final List<Product> products;
  final bool showHeader;
  final bool seesCosts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final columns = <(String, int)>[
      (AppStrings.productName, 4),
      (AppStrings.productKind, 2),
      (AppStrings.brand, 2),
      (AppStrings.barcode, 2),
      (AppStrings.salePrice, 2),
      if (seesCosts) (AppStrings.averageCost, 2),
      (AppStrings.quantity, 1),
    ];
    Widget row(List<Widget> cells, {Color? color, VoidCallback? onTap, Key? key}) => InkWell(
      key: key,
      onTap: onTap,
      child: Container(
        color: color,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            for (var i = 0; i < cells.length; i++) Expanded(flex: columns[i].$2, child: cells[i]),
          ],
        ),
      ),
    );

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (showHeader)
            row([
              for (final c in columns) Text(c.$1, style: theme.textTheme.labelLarge),
            ], color: theme.colorScheme.surfaceContainerHighest),
          for (final p in products) ...[
            const Divider(height: 1),
            row(
              key: Key('product-row-${p.id}'),
              onTap: () => context.go(AppRoutes.productDetail(p.id)),
              color: p.isActive ? null : theme.colorScheme.surfaceContainerLow,
              [
                Text(p.name, overflow: TextOverflow.ellipsis),
                Text(AppStrings.productKinds[p.kind.value] ?? p.kind.value),
                Text(p.brandName, overflow: TextOverflow.ellipsis),
                Text(p.barcode.isNotEmpty ? p.barcode : p.sku, textDirection: TextDirection.ltr),
                Text(Formatters.money(p.salePrice)),
                if (seesCosts) Text(Formatters.money(p.averageCost)),
                p.trackStock
                    ? Text(
                        '${p.quantity}',
                        style: TextStyle(
                          color: p.isLowStock || p.quantity <= 0 ? theme.colorScheme.error : null,
                          fontWeight: p.isLowStock ? FontWeight.bold : null,
                        ),
                      )
                    : Text(AppStrings.noStockTracking, style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ],
      ),
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
