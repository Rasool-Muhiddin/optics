import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formatters/formatters.dart';
import '../core/strings/app_strings.dart';
import '../models/catalog.dart';
import '../screens/inventory/inventory_providers.dart';
import '../screens/inventory/lens_power_grid.dart';
import 'common.dart';

Future<LensVariant?> pickLensVariant(BuildContext context, Product product) =>
    showDialog<LensVariant>(
      context: context,
      builder: (_) => _VariantPicker(product: product),
    );

/// Search-and-pick an active product of the given kinds (comma-separated server values).
Future<Product?> pickProduct(
  BuildContext context, {
  required String kinds,
  required String title,
}) => showDialog<Product>(
  context: context,
  builder: (_) => _ProductPicker(kinds: kinds, title: title),
);

class _ProductPicker extends ConsumerStatefulWidget {
  const _ProductPicker({required this.kinds, required this.title});

  final String kinds;
  final String title;

  @override
  ConsumerState<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends ConsumerState<_ProductPicker> {
  String _search = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(
      productListProvider(ProductQuery(search: _search, kinds: widget.kinds)),
    );
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(
          children: [
            TextField(
              key: const Key('product-picker-search'),
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: AppStrings.search,
              ),
              onChanged: (text) {
                _debounce?.cancel();
                _debounce = Timer(
                  const Duration(milliseconds: 300),
                  () => setState(() => _search = text),
                );
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: AsyncView(
                value: value,
                builder: (page) => ListView(
                  children: [
                    for (final p in page.items)
                      ListTile(
                        key: Key('pick-product-${p.id}'),
                        dense: true,
                        title: Text(p.name),
                        subtitle: Text(
                          '${AppStrings.productKinds[p.kind.value]}'
                          '${p.trackStock && !p.usesVariants ? '   •   ${AppStrings.available}: ${p.quantity}' : ''}',
                        ),
                        trailing: Text(Formatters.money(p.salePrice)),
                        onTap: () => Navigator.of(context).pop(p),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.cancel),
        ),
      ],
    );
  }
}

/// Lens power picker: the power grid (per ADD); tap a power to choose it.
class _VariantPicker extends ConsumerStatefulWidget {
  const _VariantPicker({required this.product});

  final Product product;

  @override
  ConsumerState<_VariantPicker> createState() => _VariantPickerState();
}

class _VariantPickerState extends ConsumerState<_VariantPicker> {
  double? _add;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${AppStrings.chooseVariant} — ${widget.product.name}'),
      content: SizedBox(
        width: 720,
        height: 480,
        child: AsyncView(
          value: ref.watch(lensGridProvider(widget.product.id)),
          builder: (grid) {
            final variants = grid.variants.where((v) => v.isActive).toList();
            if (variants.isEmpty) return const Center(child: Text(AppStrings.noVariants));
            final adds = {for (final v in variants) v.add}.toList()..sort();
            final add = adds.contains(_add) ? _add! : adds.first;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (adds.length > 1)
                  DropdownButton<double>(
                    value: add,
                    items: [
                      for (final a in adds)
                        DropdownMenuItem(
                          value: a,
                          child: Text(a == 0 ? 'ADD —' : 'ADD +${a.toStringAsFixed(2)}'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _add = v),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    child: LensPowerGrid(
                      variants: variants.where((v) => v.add == add).toList(),
                      onTap: (v) => Navigator.of(context).pop(v),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.cancel),
        ),
      ],
    );
  }
}
