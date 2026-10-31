import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters/formatters.dart';
import '../../core/optics/powers.dart';
import '../../core/router/app_routes.dart';
import '../../core/strings/app_strings.dart';
import '../../data/cache/json_cache_dao.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../models/catalog.dart';
import '../../services/auth_controller.dart';
import '../../widgets/common.dart';
import 'inventory_providers.dart';
import 'lens_power_grid.dart';
import 'product_form_dialog.dart';
import 'stock_dialogs.dart';

/// Product info, lens power grid (stock per power) and the stock ledger.
class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final int productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final canManage = session?.canManageInventory ?? false;
    final seesCosts = session?.membership.canViewCosts ?? false;

    return AsyncView(
      value: ref.watch(productProvider(productId)),
      onRetry: () => ref.invalidate(productProvider(productId)),
      builder: (product) {
        Future<void> edit() async {
          final saved = await showDialog<Product>(
            context: context,
            builder: (_) => ProductFormDialog(product: product),
          );
          if (saved != null) invalidateProduct(ref, productId);
        }

        Future<void> stock() async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (_) => StockEntryDialog(product: product),
          );
          if (ok == true) invalidateProduct(ref, productId);
        }

        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            PageHeader(
              title: product.name,
              cacheTables: const [
                CacheTables.products,
                CacheTables.lensVariants,
                CacheTables.stockMovements,
              ],
              leading: IconButton(
                tooltip: AppStrings.back,
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => context.go(AppRoutes.inventory),
              ),
              actions: [
                if (canManage && product.trackStock && !product.usesVariants)
                  FilledButton.tonalIcon(
                    key: const Key('stock-entry'),
                    icon: const Icon(Icons.swap_vert),
                    label: const Text(AppStrings.stockEntry),
                    onPressed: stock,
                  ),
                if (canManage)
                  OutlinedButton.icon(
                    key: const Key('edit-product'),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text(AppStrings.edit),
                    onPressed: edit,
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: _InfoCard(product: product, seesCosts: seesCosts),
            ),
            if (product.usesVariants)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.lg,
                  AppSpacing.page,
                  0,
                ),
                child: _GridCard(product: product, canManage: canManage),
              ),
            if (product.trackStock)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.lg,
                  AppSpacing.page,
                  0,
                ),
                child: _MovementsCard(productId: productId, seesCosts: seesCosts),
              ),
          ],
        );
      },
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.product, required this.seesCosts});

  final Product product;
  final bool seesCosts;

  @override
  Widget build(BuildContext context) {
    final p = product;
    return SectionCard(
      title: AppStrings.sectionBasics,
      icon: Icons.info_outline,
      actions: [
        StatusBadge(label: AppStrings.productKinds[p.kind.value]!, tone: Tone.primary),
        if (p.trackStock && (p.isLowStock || p.quantity <= 0))
          const StatusBadge(
            label: AppStrings.lowStock,
            tone: Tone.danger,
            icon: Icons.warning_amber_outlined,
          ),
      ],
      child: Padding(
        padding: EdgeInsets.zero,
        child: Wrap(
          spacing: AppSpacing.lg,
          children: [
            InfoTile(label: AppStrings.productKind, value: AppStrings.productKinds[p.kind.value]!),
            InfoTile(label: AppStrings.brand, value: p.brandName),
            InfoTile(label: AppStrings.category, value: p.categoryName),
            InfoTile(label: AppStrings.sku, value: p.sku),
            InfoTile(label: AppStrings.barcode, value: p.barcode),
            InfoTile(label: AppStrings.salePrice, value: Formatters.money(p.salePrice)),
            if (seesCosts && p.purchasePrice != null)
              InfoTile(label: AppStrings.purchasePrice, value: Formatters.money(p.purchasePrice)),
            if (seesCosts && p.averageCost != null && !p.usesVariants)
              InfoTile(label: AppStrings.averageCost, value: Formatters.money(p.averageCost)),
            InfoTile(
              label: AppStrings.quantity,
              value: p.trackStock ? '${p.quantity}' : AppStrings.noStockTracking,
            ),
            if (p.reorderLevel > 0)
              InfoTile(label: AppStrings.reorderLevel, value: '${p.reorderLevel}'),
            InfoTile(
              label: AppStrings.status,
              value: p.isActive ? AppStrings.active : AppStrings.inactive,
            ),
            for (final e in p.attributes.entries)
              InfoTile(
                label: AppStrings.label(AppStrings.attributeLabels, e.key),
                value: AttributeSpec.display(e.value),
              ),
            if (p.notes.isNotEmpty) InfoTile(label: AppStrings.notes, value: p.notes, width: 420),
          ],
        ),
      ),
    );
  }
}

class _GridCard extends ConsumerStatefulWidget {
  const _GridCard({required this.product, required this.canManage});

  final Product product;
  final bool canManage;

  @override
  ConsumerState<_GridCard> createState() => _GridCardState();
}

class _GridCardState extends ConsumerState<_GridCard> {
  double _add = 0;
  Map<int, TextEditingController>? _entry;
  final _entryCost = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _disposeEntry();
    _entryCost.dispose();
    super.dispose();
  }

  void _disposeEntry() {
    for (final c in _entry?.values ?? const <TextEditingController>[]) {
      c.dispose();
    }
    _entry = null;
  }

  Future<void> _saveEntry() async {
    final lines = <StockLineInput>[
      for (final e in _entry!.entries)
        if ((int.tryParse(e.value.text) ?? 0) > 0)
          StockLineInput(
            variantId: e.key,
            qty: int.parse(e.value.text),
            unitCost: _entryCost.text.trim(),
          ),
    ];
    if (lines.isEmpty) {
      setState(_disposeEntry);
      return;
    }
    if (_entryCost.text.trim().isEmpty) {
      showSnack(context, AppStrings.errUnitCostRequired, error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(catalogRepositoryProvider)
          .postStock(type: MovementType.purchase, lines: lines);
      if (!mounted) return;
      setState(_disposeEntry);
      invalidateProduct(ref, widget.product.id);
      showSnack(context, AppStrings.saved);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openVariant(LensVariant v) async {
    if (!widget.canManage) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                'SPH ${Powers.format(v.sph)}  CYL ${Powers.format(v.cyl)}  —  ${AppStrings.quantity}: ${v.quantity}',
                textDirection: TextDirection.ltr,
              ),
              subtitle: Text(Formatters.money(v.effectiveSalePrice)),
            ),
            ListTile(
              key: const Key('variant-stock'),
              leading: const Icon(Icons.swap_vert),
              title: const Text(AppStrings.stockEntry),
              onTap: () => Navigator.of(context).pop('stock'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text(AppStrings.edit),
              onTap: () => Navigator.of(context).pop('edit'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => action == 'stock'
          ? StockEntryDialog(product: widget.product, variant: v)
          : VariantEditDialog(variant: v),
    );
    if (ok == true) invalidateProduct(ref, widget.product.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gridValue = ref.watch(lensGridProvider(widget.product.id));
    return SectionCard(
      title: AppStrings.lensGrid,
      icon: Icons.grid_on,
      child: Padding(
        padding: EdgeInsets.zero,
        child: AsyncView(
          value: gridValue,
          onRetry: () => ref.invalidate(lensGridProvider(widget.product.id)),
          builder: (grid) {
            final adds = {for (final v in grid.variants) v.add}.toList()..sort();
            final add = adds.contains(_add) ? _add : (adds.isEmpty ? 0.0 : adds.first);
            final variants = grid.variants.where((v) => v.add == add).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Spacer(),
                    if (adds.length > 1)
                      DropdownButton<double>(
                        value: add,
                        items: [
                          for (final a in adds)
                            DropdownMenuItem(
                              value: a,
                              child: Text(a == 0 ? 'ADD —' : 'ADD ${Powers.format(a)}'),
                            ),
                        ],
                        onChanged: (v) => setState(() => _add = v!),
                      ),
                    if (widget.canManage && _entry == null) ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        key: const Key('generate-variants'),
                        icon: const Icon(Icons.grid_on),
                        label: const Text(AppStrings.generateVariants),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => GenerateVariantsDialog(product: widget.product),
                          );
                          if (ok == true) invalidateProduct(ref, widget.product.id);
                        },
                      ),
                      if (variants.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          key: const Key('grid-entry'),
                          icon: const Icon(Icons.edit_note),
                          label: const Text(AppStrings.gridEntryMode),
                          onPressed: () => setState(
                            () =>
                                _entry = {for (final v in variants) v.id: TextEditingController()},
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
                if (_entry != null) ...[
                  const SizedBox(height: 8),
                  Text(AppStrings.gridEntryHint, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(
                        width: 200,
                        child: TextField(
                          key: const Key('grid-entry-cost'),
                          controller: _entryCost,
                          inputFormatters: Inputs.money,
                          decoration: const InputDecoration(labelText: AppStrings.unitCost),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _busy ? null : () => setState(_disposeEntry),
                        child: const Text(AppStrings.cancel),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        key: const Key('grid-entry-save'),
                        onPressed: _busy ? null : _saveEntry,
                        child: const Text(AppStrings.save),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                if (variants.isEmpty)
                  const EmptyState(
                    icon: Icons.grid_off,
                    title: AppStrings.noVariants,
                    compact: true,
                  )
                else
                  LensPowerGrid(
                    variants: variants,
                    controllers: _entry,
                    lowThreshold: widget.product.reorderLevel > 0 ? widget.product.reorderLevel : 1,
                    onTap: _openVariant,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MovementsCard extends ConsumerWidget {
  const _MovementsCard({required this.productId, required this.seesCosts});

  final int productId;
  final bool seesCosts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    return SectionCard(
      title: AppStrings.stockMovements,
      icon: Icons.swap_vert,
      padding: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AsyncView(
              value: ref.watch(productMovementsProvider(productId)),
              onRetry: () => ref.invalidate(productMovementsProvider(productId)),
              builder: (movements) {
                if (movements.isEmpty) {
                  return const EmptyState(icon: Icons.swap_vert, compact: true);
                }
                return Table(
                  columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(2)},
                  children: [
                    TableRow(
                      decoration: BoxDecoration(color: colors.surfaceMuted),
                      children: [
                        _cell(AppStrings.date, bold: true),
                        _cell(AppStrings.movementType, bold: true),
                        _cell(AppStrings.chooseVariant, bold: true),
                        _cell(AppStrings.quantity, bold: true),
                        _cell(AppStrings.qtyAfter, bold: true),
                        if (seesCosts) _cell(AppStrings.unitCost, bold: true),
                        _cell(AppStrings.byUser, bold: true),
                      ],
                    ),
                    for (final (i, m) in movements.indexed)
                      TableRow(
                        decoration: BoxDecoration(
                          color: i.isOdd ? colors.zebra : null,
                          border: Border(top: BorderSide(color: colors.border)),
                        ),
                        children: [
                          _cell(Formatters.dateTime(m.createdAt)),
                          _cell(
                            AppStrings.movementTypes[m.type.value]! +
                                (m.note.isEmpty ? '' : ' — ${m.note}'),
                          ),
                          _cell(m.variantLabel, ltr: true),
                          _cell(
                            m.qty > 0 ? '+${m.qty}' : '${m.qty}',
                            ltr: true,
                            color: m.qty > 0 ? colors.success : colors.danger,
                          ),
                          _cell('${m.qtyAfter}'),
                          if (seesCosts) _cell(Formatters.money(m.unitCost)),
                          _cell(m.createdByName),
                        ],
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  static Widget _cell(String text, {bool bold = false, bool ltr = false, Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
    child: Text(
      text,
      textDirection: ltr ? TextDirection.ltr : null,
      textAlign: TextAlign.start,
      style: TextStyle(
        fontWeight: bold ? FontWeight.w600 : null,
        fontFeatures: AppText.tabular,
        color: color,
      ),
    ),
  );
}
