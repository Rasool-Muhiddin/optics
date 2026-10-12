import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_messages.dart';
import '../../core/optics/powers.dart';
import '../../core/strings/app_strings.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../models/catalog.dart';
import '../../widgets/common.dart';

/// Manual stock movement for one product or one lens power. Returns true when saved.
class StockEntryDialog extends ConsumerStatefulWidget {
  const StockEntryDialog({super.key, required this.product, this.variant});

  final Product product;
  final LensVariant? variant;

  @override
  ConsumerState<StockEntryDialog> createState() => _StockEntryDialogState();
}

class _StockEntryDialogState extends ConsumerState<StockEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  MovementType _type = MovementType.purchase;
  final _qty = TextEditingController();
  final _cost = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    final reference = widget.product.purchasePrice;
    if (reference != null && (double.tryParse(reference) ?? 0) > 0) {
      _cost.text = double.parse(reference).toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _qty.dispose();
    _cost.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _needsCost => _type == MovementType.purchase;
  bool get _allowsCost => _type == MovementType.purchase || _type == MovementType.adjustment;

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final qty = int.parse(_qty.text.trim());
      await ref
          .read(catalogRepositoryProvider)
          .postStock(
            type: _type,
            note: _note.text.trim(),
            lines: [
              StockLineInput(
                productId: widget.variant == null ? widget.product.id : null,
                variantId: widget.variant?.id,
                qty: qty,
                unitCost: _allowsCost && qty > 0 ? _cost.text.trim() : null,
              ),
            ],
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.variant;
    final subtitle = v == null
        ? widget.product.name
        : '${widget.product.name}  SPH ${Powers.format(v.sph)} CYL ${Powers.format(v.cyl)}'
              '${v.add > 0 ? ' ADD ${Powers.format(v.add)}' : ''}';
    return FormDialog(
      title: AppStrings.stockEntry,
      width: 460,
      busy: _busy,
      error: _error == null ? null : errorMessageFor(_error!),
      onSave: _save,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(subtitle, textDirection: TextDirection.ltr, textAlign: TextAlign.right),
            const SizedBox(height: 12),
            DropdownButtonFormField<MovementType>(
              isExpanded: true,
              key: const Key('stock-type'),
              initialValue: _type,
              decoration: const InputDecoration(labelText: AppStrings.movementType),
              items: [
                for (final t in MovementType.manual)
                  DropdownMenuItem(value: t, child: Text(AppStrings.movementTypes[t.value]!)),
              ],
              onChanged: (t) => setState(() => _type = t!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('stock-qty'),
              controller: _qty,
              inputFormatters: _type == MovementType.adjustment
                  ? Inputs.signedInteger
                  : Inputs.integer,
              decoration: InputDecoration(
                labelText: AppStrings.quantity,
                helperText: _type == MovementType.adjustment ? '+ / −' : null,
              ),
              validator: (v) => Inputs.intValidator(v, allowZero: false),
            ),
            if (_allowsCost) ...[
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('stock-cost'),
                controller: _cost,
                inputFormatters: Inputs.money,
                decoration: const InputDecoration(labelText: AppStrings.unitCost),
                validator: (v) => Inputs.moneyValidator(v, required: _needsCost),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              decoration: const InputDecoration(labelText: AppStrings.notes),
            ),
          ],
        ),
      ),
    );
  }
}

/// Creates every SPH × CYL power of a range for a lens product.
class GenerateVariantsDialog extends ConsumerStatefulWidget {
  const GenerateVariantsDialog({super.key, required this.product});

  final Product product;

  @override
  ConsumerState<GenerateVariantsDialog> createState() => _GenerateVariantsDialogState();
}

class _GenerateVariantsDialogState extends ConsumerState<GenerateVariantsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _c = {
    'sph_from': TextEditingController(text: '-6.00'),
    'sph_to': TextEditingController(text: '+4.00'),
    'cyl_from': TextEditingController(text: '0.00'),
    'cyl_to': TextEditingController(text: '-2.00'),
    'add': TextEditingController(text: '0'),
  };
  String _step = '0.25';
  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validate(String key, String? text) {
    final v = Powers.parse(text);
    if (v == null) return AppStrings.required;
    if (key.startsWith('sph') && !Powers.validSph(v)) return AppStrings.invalidPower;
    if (key.startsWith('cyl')) {
      if (!Powers.validCyl(v)) return AppStrings.invalidPower;
      if (v > 0) return AppStrings.minusCylOnly;
    }
    if (key == 'add' && v != 0 && !Powers.validAdd(v)) return AppStrings.invalidPower;
    return null;
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = {
        for (final e in _c.entries) e.key: Powers.parse(e.value.text)!.toStringAsFixed(2),
        'step': _step,
      };
      final result = await ref
          .read(catalogRepositoryProvider)
          .generateVariants(widget.product.id, body);
      if (mounted) {
        Navigator.of(context).pop(true);
        showSnack(context, '${AppStrings.variantsCreated}: ${result.created}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget field(String key, String label) => TextFormField(
      key: Key('gen-$key'),
      controller: _c[key],
      textDirection: TextDirection.ltr,
      inputFormatters: Inputs.power,
      decoration: InputDecoration(labelText: label),
      validator: (v) => _validate(key, v),
    );
    return FormDialog(
      title: AppStrings.generateVariants,
      width: 460,
      busy: _busy,
      error: _error == null ? null : errorMessageFor(_error!),
      onSave: _save,
      child: Form(
        key: _formKey,
        child: FieldGrid(
          children: [
            field('sph_from', AppStrings.sphFrom),
            field('sph_to', AppStrings.sphTo),
            field('cyl_from', AppStrings.cylFrom),
            field('cyl_to', AppStrings.cylTo),
            field('add', AppStrings.addPower),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _step,
              decoration: const InputDecoration(labelText: AppStrings.step),
              items: const [
                DropdownMenuItem(value: '0.25', child: Text('0.25')),
                DropdownMenuItem(value: '0.50', child: Text('0.50')),
              ],
              onChanged: (v) => setState(() => _step = v!),
            ),
          ],
        ),
      ),
    );
  }
}

/// Price / barcode / active flag of one lens power.
class VariantEditDialog extends ConsumerStatefulWidget {
  const VariantEditDialog({super.key, required this.variant});

  final LensVariant variant;

  @override
  ConsumerState<VariantEditDialog> createState() => _VariantEditDialogState();
}

class _VariantEditDialogState extends ConsumerState<VariantEditDialog> {
  late final _price = TextEditingController(text: widget.variant.salePrice ?? '');
  late final _barcode = TextEditingController(text: widget.variant.barcode);
  late bool _active = widget.variant.isActive;
  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    _price.dispose();
    _barcode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(catalogRepositoryProvider).saveVariant(widget.variant.id, {
        'sale_price': _price.text.trim().isEmpty ? null : _price.text.trim(),
        'barcode': _barcode.text.trim(),
        'is_active': _active,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.variant;
    return FormDialog(
      title: 'SPH ${Powers.format(v.sph)}  CYL ${Powers.format(v.cyl)}',
      width: 420,
      busy: _busy,
      error: _error == null ? null : errorMessageFor(_error!),
      onSave: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _price,
            inputFormatters: Inputs.money,
            decoration: const InputDecoration(labelText: AppStrings.variantPrice),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _barcode,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: AppStrings.barcode),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(AppStrings.active),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
        ],
      ),
    );
  }
}
