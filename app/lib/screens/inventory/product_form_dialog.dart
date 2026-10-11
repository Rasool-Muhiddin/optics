import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_messages.dart';
import '../../core/strings/app_strings.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../models/catalog.dart';
import '../../services/auth_controller.dart';
import '../../widgets/common.dart';
import 'inventory_providers.dart';

/// Kind-specific attribute fields (must match `apps/catalog/attributes.py`).
class AttributeSpec {
  const AttributeSpec(this.key, {this.choices, this.multi = false, this.numeric = false});

  final String key;
  final List<String>? choices;
  final bool multi;
  final bool numeric;

  static const lensIndexes = ['1.50', '1.53', '1.56', '1.59', '1.60', '1.67', '1.74'];
  static const _lens = [
    AttributeSpec('material'),
    AttributeSpec('index', choices: lensIndexes),
    AttributeSpec('design', choices: ['single_vision', 'bifocal', 'progressive', 'office']),
    AttributeSpec('diameter', numeric: true),
    AttributeSpec(
      'coatings',
      multi: true,
      choices: [
        'ar',
        'blue_cut',
        'photochromic',
        'hard_coat',
        'uv',
        'polarized',
        'hydrophobic',
        'mirror',
        'tint',
      ],
    ),
  ];

  static const Map<ProductKind, List<AttributeSpec>> byKind = {
    ProductKind.frame: [
      AttributeSpec('model'),
      AttributeSpec('color'),
      AttributeSpec('size'),
      AttributeSpec('material'),
      AttributeSpec('gender', choices: ['men', 'women', 'unisex', 'kids']),
      AttributeSpec('shape'),
      AttributeSpec('frame_type', choices: ['full_rim', 'semi_rimless', 'rimless']),
    ],
    ProductKind.stockLens: _lens,
    ProductKind.rxLens: _lens,
    ProductKind.contactLens: [
      AttributeSpec(
        'replacement',
        choices: ['daily', 'biweekly', 'monthly', 'quarterly', 'yearly'],
      ),
      AttributeSpec('base_curve', numeric: true),
      AttributeSpec('diameter', numeric: true),
      AttributeSpec('material'),
      AttributeSpec('color'),
      AttributeSpec('pack_size', numeric: true),
    ],
    ProductKind.accessory: [AttributeSpec('material'), AttributeSpec('color')],
    ProductKind.solution: [AttributeSpec('volume_ml', numeric: true)],
    ProductKind.service: [],
  };

  /// Human-readable value for detail screens.
  static String display(Object? value) {
    if (value is List) {
      return value.map((v) => AppStrings.label(AppStrings.choiceLabels, '$v')).join('، ');
    }
    return AppStrings.label(AppStrings.choiceLabels, '${value ?? ''}');
  }
}

/// Create / edit a product of any kind. Returns the saved [Product].
class ProductFormDialog extends ConsumerStatefulWidget {
  const ProductFormDialog({super.key, this.product});

  final Product? product;

  @override
  ConsumerState<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends ConsumerState<ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late ProductKind _kind;
  int? _brandId;
  int? _categoryId;
  late bool _trackStock;
  late bool _isActive;
  late final Map<String, TextEditingController> _c;
  final Map<String, TextEditingController> _attr = {};
  final Map<String, String?> _choice = {};
  final Map<String, Set<String>> _multi = {};
  bool _busy = false;
  Object? _error;

  bool get _editing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _kind = p?.kind ?? ProductKind.frame;
    _brandId = p?.brandId;
    _categoryId = p?.categoryId;
    _trackStock = p?.trackStock ?? true;
    _isActive = p?.isActive ?? true;
    _c = {
      'name': TextEditingController(text: p?.name ?? ''),
      'sku': TextEditingController(text: p?.sku ?? ''),
      'barcode': TextEditingController(text: p?.barcode ?? ''),
      'sale_price': TextEditingController(text: _plain(p?.salePrice)),
      'purchase_price': TextEditingController(text: _plain(p?.purchasePrice)),
      'reorder_level': TextEditingController(text: '${p?.reorderLevel ?? 0}'),
      'notes': TextEditingController(text: p?.notes ?? ''),
    };
    final attrs = p?.attributes ?? const {};
    for (final specs in AttributeSpec.byKind.values) {
      for (final s in specs) {
        final v = attrs[s.key];
        if (s.multi) {
          _multi[s.key] = {if (v is List) ...v.map((e) => '$e')};
        } else if (s.choices != null) {
          _choice[s.key] = v?.toString();
        } else {
          _attr.putIfAbsent(s.key, () => TextEditingController(text: v?.toString() ?? ''));
        }
      }
    }
  }

  static String _plain(String? money) {
    if (money == null) return '';
    final n = double.tryParse(money);
    if (n == null) return money;
    return n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toString();
  }

  @override
  void dispose() {
    for (final c in [..._c.values, ..._attr.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _attributes() {
    final out = <String, dynamic>{};
    for (final s in AttributeSpec.byKind[_kind]!) {
      if (s.multi) {
        if (_multi[s.key]!.isNotEmpty) out[s.key] = _multi[s.key]!.toList();
      } else if (s.choices != null) {
        if (_choice[s.key] != null) out[s.key] = _choice[s.key];
      } else {
        final text = _attr[s.key]!.text.trim();
        if (text.isNotEmpty) out[s.key] = text;
      }
    }
    return out;
  }

  Future<void> _save(bool seesCosts) async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = <String, dynamic>{
      'kind': _kind.value,
      'name': _c['name']!.text.trim(),
      'brand': _brandId,
      'category': _categoryId,
      'sku': _c['sku']!.text.trim(),
      'barcode': _c['barcode']!.text.trim(),
      'sale_price': _c['sale_price']!.text.trim(),
      if (seesCosts && _c['purchase_price']!.text.trim().isNotEmpty)
        'purchase_price': _c['purchase_price']!.text.trim(),
      'reorder_level': int.tryParse(_c['reorder_level']!.text.trim()) ?? 0,
      'track_stock': _trackStock,
      'is_active': _isActive,
      'notes': _c['notes']!.text.trim(),
      'attributes': _attributes(),
    };
    try {
      final saved = await ref.read(catalogRepositoryProvider).saveProduct(widget.product?.id, body);
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final seesCosts = ref.watch(sessionProvider)?.membership.canViewCosts ?? false;
    final brands = ref.watch(brandsProvider).value ?? const <Brand>[];
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final lockedStock = _kind.usesVariants || _kind.isNonStock;

    TextFormField text(
      String key,
      String label, {
      String? Function(String?)? validator,
      bool ltr = false,
      int maxLines = 1,
    }) => TextFormField(
      key: Key('product-$key'),
      controller: _c[key],
      maxLines: maxLines,
      textDirection: ltr ? TextDirection.ltr : null,
      decoration: InputDecoration(labelText: label, errorText: fieldErrorFor(_error, key)),
      validator: validator,
    );

    return FormDialog(
      title: _editing ? AppStrings.editProduct : AppStrings.addProduct,
      width: 680,
      busy: _busy,
      error: _error == null ? null : errorMessageFor(_error!),
      onSave: () => _save(seesCosts),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FieldGrid(
              children: [
                DropdownButtonFormField<ProductKind>(
                  key: const Key('product-kind'),
                  initialValue: _kind,
                  decoration: const InputDecoration(labelText: AppStrings.productKind),
                  items: [
                    for (final k in ProductKind.values)
                      DropdownMenuItem(value: k, child: Text(AppStrings.productKinds[k.value]!)),
                  ],
                  onChanged: _editing ? null : (k) => setState(() => _kind = k!),
                ),
                text('name', AppStrings.productName, validator: Inputs.requiredText),
                DropdownButtonFormField<int?>(
                  initialValue: brands.any((b) => b.id == _brandId) ? _brandId : null,
                  decoration: const InputDecoration(labelText: AppStrings.brand),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text(AppStrings.none)),
                    for (final b in brands.where((b) => b.isActive || b.id == _brandId))
                      DropdownMenuItem<int?>(value: b.id, child: Text(b.name)),
                  ],
                  onChanged: (v) => setState(() => _brandId = v),
                ),
                DropdownButtonFormField<int?>(
                  initialValue: categories.any((c) => c.id == _categoryId) ? _categoryId : null,
                  decoration: const InputDecoration(labelText: AppStrings.category),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text(AppStrings.none)),
                    for (final c in categories.where((c) => c.isActive || c.id == _categoryId))
                      DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
                text('sku', AppStrings.sku, ltr: true),
                text('barcode', AppStrings.barcode, ltr: true),
                TextFormField(
                  key: const Key('product-sale_price'),
                  controller: _c['sale_price'],
                  inputFormatters: Inputs.money,
                  decoration: const InputDecoration(labelText: AppStrings.salePrice),
                  validator: Inputs.moneyValidator,
                ),
                if (seesCosts)
                  TextFormField(
                    key: const Key('product-purchase_price'),
                    controller: _c['purchase_price'],
                    inputFormatters: Inputs.money,
                    decoration: const InputDecoration(labelText: AppStrings.purchasePrice),
                    validator: (v) => Inputs.moneyValidator(v, required: false),
                  ),
                if (!_kind.isNonStock)
                  TextFormField(
                    controller: _c['reorder_level'],
                    inputFormatters: Inputs.integer,
                    decoration: const InputDecoration(labelText: AppStrings.reorderLevel),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 24,
              children: [
                if (!lockedStock)
                  _Switch(
                    label: AppStrings.trackStock,
                    value: _trackStock,
                    onChanged: (v) => setState(() => _trackStock = v),
                  ),
                if (_editing)
                  _Switch(
                    label: AppStrings.active,
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                  ),
              ],
            ),
            if (AttributeSpec.byKind[_kind]!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(AppStrings.attributes, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              FieldGrid(
                children: [
                  for (final s in AttributeSpec.byKind[_kind]!.where((s) => !s.multi))
                    _attributeField(s),
                ],
              ),
              for (final s in AttributeSpec.byKind[_kind]!.where((s) => s.multi)) ...[
                const SizedBox(height: 12),
                Text(AppStrings.label(AppStrings.attributeLabels, s.key)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final option in s.choices!)
                      FilterChip(
                        label: Text(AppStrings.label(AppStrings.choiceLabels, option)),
                        selected: _multi[s.key]!.contains(option),
                        onSelected: (on) => setState(
                          () => on ? _multi[s.key]!.add(option) : _multi[s.key]!.remove(option),
                        ),
                      ),
                  ],
                ),
              ],
            ],
            const SizedBox(height: 12),
            text('notes', AppStrings.notes, maxLines: 2),
          ],
        ),
      ),
    );
  }

  Widget _attributeField(AttributeSpec s) {
    final label = AppStrings.label(AppStrings.attributeLabels, s.key);
    if (s.choices != null) {
      return DropdownButtonFormField<String?>(
        key: Key('attr-${s.key}'),
        initialValue: s.choices!.contains(_choice[s.key]) ? _choice[s.key] : null,
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text(AppStrings.none)),
          for (final o in s.choices!)
            DropdownMenuItem<String?>(
              value: o,
              child: Text(AppStrings.label(AppStrings.choiceLabels, o)),
            ),
        ],
        onChanged: (v) => setState(() => _choice[s.key] = v),
      );
    }
    final attrErrors = _attributeError(s.key);
    return TextFormField(
      key: Key('attr-${s.key}'),
      controller: _attr[s.key],
      textDirection: s.numeric || s.key == 'size' ? TextDirection.ltr : null,
      inputFormatters: s.numeric ? Inputs.money : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: s.key == 'size' ? '52-18-140' : null,
        errorText: attrErrors,
      ),
    );
  }

  String? _attributeError(String key) {
    final raw = errorFields(_error)?['attributes'];
    return raw is Map && raw.containsKey(key) ? AppStrings.errValidation : null;
  }
}

class _Switch extends StatelessWidget {
  const _Switch({required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Switch(value: value, onChanged: onChanged),
      const SizedBox(width: 6),
      Text(label),
    ],
  );
}
