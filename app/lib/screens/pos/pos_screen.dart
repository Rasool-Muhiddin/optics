import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/errors/error_messages.dart';
import '../../core/formatters/formatters.dart';
import '../../core/strings/app_strings.dart';
import '../../data/cache/json_cache_dao.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../models/catalog.dart';
import '../../models/sales.dart';
import '../../widgets/common.dart';
import '../../widgets/patient_picker.dart';
import '../../widgets/product_pickers.dart';
import '../inventory/inventory_providers.dart';
import '../sales/invoice_actions.dart';
import 'pos_controller.dart';

/// POS: product search / barcode on one side, the cart and checkout on the other.
/// Totals always come from the server (`checkout/preview/`).
class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  String _query = '';
  bool _busy = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  PosController get _pos => ref.read(posControllerProvider.notifier);

  Future<void> _addProduct(Product product, {LensVariant? variant}) async {
    if (product.usesVariants && variant == null) {
      final picked = await pickLensVariant(context, product);
      if (picked == null) return;
      variant = picked;
    }
    _pos.add(product, variant: variant);
    _searchFocus.requestFocus();
  }

  /// Enter in the search box: treat the text as a barcode/SKU first.
  Future<void> _onSubmit(String text) async {
    final code = text.trim();
    if (code.isEmpty) return;
    try {
      final found = await ref.read(catalogRepositoryProvider).lookup(code);
      await _addProduct(found.product, variant: found.variant);
      _search.clear();
      setState(() => _query = '');
    } on ApiException catch (e) {
      if (e.statusCode != 404 && mounted) showErrorSnack(context, e);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _checkout() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final invoice = await ref
          .read(salesRepositoryProvider)
          .checkout(ref.read(posControllerProvider).toJson());
      _pos.clear();
      ref.invalidate(productListProvider);
      if (!mounted) return;
      setState(() => _busy = false);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${AppStrings.checkoutDone} — #${invoice.number}'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${AppStrings.total}: ${Formatters.money(invoice.total)}'),
                Text('${AppStrings.paid}: ${Formatters.money(invoice.paid)}'),
                if (invoice.hasBalance)
                  Text('${AppStrings.balance}: ${Formatters.money(invoice.balance)}'),
                const SizedBox(height: 16),
                InvoicePrintButtons(invoice: invoice),
              ],
            ),
          ),
          actions: [
            FilledButton(
              key: const Key('checkout-done-close'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(AppStrings.newSale),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(posControllerProvider);
    final preview = ref.watch(cartPreviewProvider);
    final results = _query.trim().isEmpty
        ? null
        : ref.watch(productListProvider(ProductQuery(search: _query)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: AppStrings.posTitle,
          cacheTables: const [CacheTables.products],
          offlineHint: AppStrings.offlineSaleBlocked,
          actions: [
            OutlinedButton.icon(
              key: const Key('pos-clear'),
              icon: const Icon(Icons.restart_alt),
              label: const Text(AppStrings.newSale),
              onPressed: cart.isEmpty ? null : _pos.clear,
            ),
          ],
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Search / results
                Expanded(
                  flex: 3,
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          TextField(
                            key: const Key('pos-search'),
                            controller: _search,
                            focusNode: _searchFocus,
                            autofocus: true,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.qr_code_scanner),
                              hintText: AppStrings.searchOrScan,
                            ),
                            onChanged: (text) {
                              _debounce?.cancel();
                              _debounce = Timer(
                                const Duration(milliseconds: 300),
                                () => setState(() => _query = text),
                              );
                            },
                            onSubmitted: _onSubmit,
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: results == null
                                ? const SizedBox.shrink()
                                : AsyncView(
                                    value: results,
                                    builder: (page) => ListView(
                                      children: [
                                        for (final p in page.items)
                                          ListTile(
                                            key: Key('pos-result-${p.id}'),
                                            dense: true,
                                            title: Text(p.name),
                                            subtitle: Text(
                                              '${AppStrings.productKinds[p.kind.value]}'
                                              '${p.trackStock ? '   •   ${AppStrings.available}: ${p.quantity}' : ''}',
                                            ),
                                            trailing: Text(Formatters.money(p.salePrice)),
                                            onTap: () => _addProduct(p),
                                          ),
                                      ],
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Cart
                Expanded(
                  flex: 4,
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _CustomerSection(cart: cart),
                          const Divider(),
                          Expanded(
                            child: cart.isEmpty
                                ? const Center(child: Text(AppStrings.emptyCart))
                                : _CartLines(cart: cart, preview: preview.value),
                          ),
                          const Divider(),
                          _PaymentSection(cart: cart),
                          const SizedBox(height: 8),
                          _Totals(preview: preview),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            key: const Key('pos-checkout'),
                            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                            icon: _busy
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(),
                                  )
                                : const Icon(Icons.check),
                            label: const Text(AppStrings.checkout),
                            onPressed: cart.isEmpty || _busy || preview.value == null
                                ? null
                                : _checkout,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CustomerSection extends ConsumerWidget {
  const _CustomerSection({required this.cart});

  final PosState cart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = ref.read(posControllerProvider.notifier);
    final patient = cart.patient;
    if (patient != null) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.person),
        title: Text(patient.fullName, key: const Key('pos-patient')),
        subtitle: Text(patient.phone),
        trailing: IconButton(
          tooltip: AppStrings.removePatient,
          icon: const Icon(Icons.close),
          onPressed: () => pos.setPatient(null),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            key: const Key('pos-customer-name'),
            initialValue: cart.customerName,
            decoration: const InputDecoration(
              labelText: '${AppStrings.customerName} (${AppStrings.walkIn})',
            ),
            onChanged: (v) => pos.update((s) => s.copyWith(customerName: v)),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          key: const Key('pos-pick-patient'),
          icon: const Icon(Icons.person_search),
          label: const Text(AppStrings.choosePatient),
          onPressed: () async {
            final p = await pickPatient(context);
            if (p != null) pos.setPatient(p);
          },
        ),
      ],
    );
  }
}

class _CartLines extends ConsumerWidget {
  const _CartLines({required this.cart, required this.preview});

  final PosState cart;
  final CartPreview? preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = ref.read(posControllerProvider.notifier);
    final theme = Theme.of(context);
    final priced = preview != null && preview!.lines.length == cart.lines.length
        ? preview!.lines
        : null;
    return ListView.separated(
      itemCount: cart.lines.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final line = cart.lines[i];
        final p = priced?[i];
        return Padding(
          key: Key('cart-line-$i'),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(line.label),
                    if (p != null)
                      Text(
                        '${Formatters.money(p.unitPrice)}'
                        '${p.shortOfStock ? '   •   ${AppStrings.outOfStock} (${p.available})' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: p.shortOfStock ? theme.colorScheme.error : null,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => pos.setQty(i, line.qty - 1),
              ),
              Text('${line.qty}', key: Key('cart-qty-$i')),
              IconButton(
                key: Key('cart-inc-$i'),
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => pos.setQty(i, line.qty + 1),
              ),
              SizedBox(
                width: 110,
                child: TextFormField(
                  key: Key('cart-discount-$i'),
                  initialValue: line.discount,
                  inputFormatters: Inputs.money,
                  decoration: const InputDecoration(labelText: AppStrings.lineDiscount),
                  onChanged: (v) => pos.setLineDiscount(i, v),
                ),
              ),
              SizedBox(
                width: 120,
                child: Text(
                  p == null ? '' : Formatters.money(p.lineTotal),
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => pos.remove(i)),
            ],
          ),
        );
      },
    );
  }
}

class _PaymentSection extends ConsumerWidget {
  const _PaymentSection({required this.cart});

  final PosState cart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = ref.read(posControllerProvider.notifier);
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<String>(
          key: const Key('pos-payment-type'),
          segments: [
            for (final t in AppStrings.paymentTypes.entries)
              ButtonSegment(value: t.key, label: Text(t.value)),
          ],
          selected: {cart.paymentType},
          onSelectionChanged: (v) => pos.update((s) => s.copyWith(paymentType: v.first)),
        ),
        SizedBox(
          width: 140,
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: cart.paymentMethod,
            decoration: const InputDecoration(labelText: AppStrings.paymentMethod),
            items: [
              for (final m in AppStrings.paymentMethods.entries)
                DropdownMenuItem(value: m.key, child: Text(m.value)),
            ],
            onChanged: (v) => pos.update((s) => s.copyWith(paymentMethod: v ?? 'cash')),
          ),
        ),
        if (cart.paymentType == 'credit')
          SizedBox(
            width: 160,
            child: TextFormField(
              key: const Key('pos-down-payment'),
              initialValue: cart.paymentAmount,
              inputFormatters: Inputs.money,
              decoration: const InputDecoration(labelText: AppStrings.downPayment),
              onChanged: (v) => pos.update((s) => s.copyWith(paymentAmount: v)),
            ),
          ),
        SizedBox(
          width: 150,
          child: TextFormField(
            key: const Key('pos-invoice-discount'),
            initialValue: cart.discountValue,
            inputFormatters: Inputs.money,
            decoration: const InputDecoration(labelText: AppStrings.invoiceDiscount),
            onChanged: (v) => pos.update((s) => s.copyWith(discountValue: v)),
          ),
        ),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'amount', label: Text(AppStrings.discountAmount)),
            ButtonSegment(value: 'percent', label: Text(AppStrings.discountPercent)),
          ],
          selected: {cart.discountType},
          onSelectionChanged: (v) => pos.update((s) => s.copyWith(discountType: v.first)),
        ),
      ],
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.preview});

  final AsyncValue<CartPreview?> preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = preview.error;
    if (error != null) {
      return Text(
        error is OfflineWriteException ? AppStrings.posOfflineHint : errorMessageFor(error),
        key: const Key('pos-preview-error'),
        style: TextStyle(color: theme.colorScheme.error),
      );
    }
    final p = preview.value;
    if (p == null) return const SizedBox.shrink();
    Widget row(String label, String value, {bool big = false}) => Row(
      children: [
        Expanded(child: Text(label, style: big ? theme.textTheme.titleLarge : null)),
        Text(
          Formatters.money(value),
          style: big ? theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold) : null,
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(AppStrings.subtotal, p.subtotal),
        if ((double.tryParse(p.discountTotal) ?? 0) > 0)
          row('${AppStrings.discount} (${p.discountPercent}%)', p.discountTotal),
        if (p.requiresOwner)
          Text(
            '${AppStrings.requiresOwnerDiscount} (${p.maxDiscountPercent}%)',
            style: TextStyle(color: theme.colorScheme.error),
          ),
        KeyedSubtree(key: const Key('pos-total'), child: row(AppStrings.total, p.total, big: true)),
      ],
    );
  }
}
