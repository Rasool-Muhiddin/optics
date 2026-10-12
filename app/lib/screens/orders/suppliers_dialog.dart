import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_messages.dart';
import '../../core/formatters/formatters.dart';
import '../../core/strings/app_strings.dart';
import '../../data/repositories/purchasing_repository.dart';
import '../../models/purchasing.dart';
import '../../services/auth_controller.dart';
import '../../widgets/common.dart';
import '../sales/invoice_actions.dart' show askPayment;
import 'orders_providers.dart';

/// Supplier list with balances (cost permission), add / edit, and "pay supplier"
/// (spread over the oldest unpaid orders).
class SuppliersDialog extends ConsumerWidget {
  const SuppliersDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final canManage = session?.canManageInventory ?? false;
    final canPay = canManage && (session?.membership.canViewCosts ?? false);

    Future<void> edit([Supplier? s]) async {
      final saved = await showDialog<Supplier>(
        context: context,
        builder: (_) => _SupplierForm(supplier: s),
      );
      if (saved != null) invalidateOrders(ref);
    }

    Future<void> pay(Supplier s) async {
      final input = await askPayment(context, maxAmount: s.balance, hint: s.name);
      if (input == null) return;
      try {
        await ref
            .read(purchasingRepositoryProvider)
            .paySupplier(s.id, amount: input.amount, method: input.method);
        invalidateOrders(ref);
        if (context.mounted) showSnack(context, AppStrings.saved);
      } catch (e) {
        if (context.mounted) showErrorSnack(context, e);
      }
    }

    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text(AppStrings.suppliers)),
          if (canManage)
            FilledButton.icon(
              key: const Key('add-supplier'),
              icon: const Icon(Icons.add),
              label: const Text(AppStrings.addSupplier),
              onPressed: edit,
            ),
        ],
      ),
      content: SizedBox(
        width: 640,
        height: 460,
        child: AsyncView(
          value: ref.watch(suppliersProvider),
          onRetry: () => ref.invalidate(suppliersProvider),
          builder: (suppliers) => suppliers.isEmpty
              ? const Center(child: Text(AppStrings.noData))
              : ListView(
                  children: [
                    for (final s in suppliers)
                      ListTile(
                        key: Key('supplier-row-${s.id}'),
                        title: Text(s.name),
                        subtitle: Text(
                          [
                            if (s.phone.isNotEmpty) s.phone,
                            '${AppStrings.openOrdersCount}: ${s.openOrders}',
                            if (!s.isActive) AppStrings.inactive,
                          ].join('   •   '),
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (s.balance != null)
                              Text('${AppStrings.supplierBalance}: ${Formatters.money(s.balance)}'),
                            if (canPay && (double.tryParse(s.balance ?? '') ?? 0) > 0)
                              TextButton(
                                key: Key('pay-supplier-${s.id}'),
                                onPressed: () => pay(s),
                                child: const Text(AppStrings.paySupplier),
                              ),
                            if (canManage)
                              IconButton(
                                tooltip: AppStrings.edit,
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => edit(s),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.close),
        ),
      ],
    );
  }
}

class _SupplierForm extends ConsumerStatefulWidget {
  const _SupplierForm({this.supplier});

  final Supplier? supplier;

  @override
  ConsumerState<_SupplierForm> createState() => _SupplierFormState();
}

class _SupplierFormState extends ConsumerState<_SupplierForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.supplier?.name ?? '');
  late final _phone = TextEditingController(text: widget.supplier?.phone ?? '');
  late final _address = TextEditingController(text: widget.supplier?.address ?? '');
  late final _notes = TextEditingController(text: widget.supplier?.notes ?? '');
  late bool _active = widget.supplier?.isActive ?? true;
  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await ref.read(purchasingRepositoryProvider).saveSupplier(widget.supplier?.id, {
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'address': _address.text.trim(),
        'notes': _notes.text.trim(),
        'is_active': _active,
      });
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormDialog(
      title: widget.supplier == null ? AppStrings.addSupplier : AppStrings.editSupplier,
      width: 440,
      busy: _busy,
      error: _error == null ? null : errorMessageFor(_error!),
      onSave: _save,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              key: const Key('supplier-name'),
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: AppStrings.name),
              validator: Inputs.requiredText,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(labelText: AppStrings.phone),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(labelText: AppStrings.address),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(labelText: AppStrings.notes),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              title: const Text(AppStrings.active),
              onChanged: (v) => setState(() => _active = v),
            ),
          ],
        ),
      ),
    );
  }
}
