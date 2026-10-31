import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/error_messages.dart';
import '../../core/router/app_routes.dart';
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

/// Icon of each product kind on the kind selector.
const Map<ProductKind, IconData> productKindIcons = {
  ProductKind.frame: Icons.crop_16_9,
  ProductKind.stockLens: Icons.grid_view,
  ProductKind.rxLens: Icons.precision_manufacturing_outlined,
  ProductKind.contactLens: Icons.remove_red_eye_outlined,
  ProductKind.accessory: Icons.shopping_bag_outlined,
  ProductKind.solution: Icons.water_drop_outlined,
  ProductKind.service: Icons.handyman_outlined,
};

/// Create / edit a product of any kind. Returns the saved [Product].
///
/// Order: barcode (focused, so a scanner can be used at once; an already registered code is
/// reported with a button to open that product) → kind → name/brand/group → prices → the
/// kind's details → collapsed "more options" (SKU, track stock, active, notes).
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
  late bool _moreOpen;
  bool _busy = false;
  Object? _error;

  /// Another product already using the typed barcode (checked on Enter / leaving the field).
  Product? _duplicate;
  String _checkedCode = '';

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
    _moreOpen = (p?.sku ?? '').isNotEmpty || (p?.notes ?? '').isNotEmpty;
    _c = {
      'name': TextEditingController(text: p?.name ?? ''),
      'sku': TextEditingController(text: p?.sku ?? ''),
      'barcode': TextEditingController(text: p?.barcode ?? ''),
      'sale_price': TextEditingController(text: _plain(p?.salePrice)),
      'purchase_price': TextEditingController(text: _plain(p?.purchasePrice)),
      'reorder_level': TextEditingController(text: '${p?.reorderLevel ?? 0}'),
      'notes': TextEditingController(text: p?.notes ?? ''),
    };
    _checkedCode = p?.barcode ?? '';
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

  Future<void> _checkBarcode() async {
    final code = _c['barcode']!.text.trim();
    if (code == _checkedCode) return;
    _checkedCode = code;
    if (code.isEmpty) {
      setState(() => _duplicate = null);
      return;
    }
    Product? found;
    try {
      final hit = await ref.read(catalogRepositoryProvider).lookup(code);
      if (hit.product.id != widget.product?.id) found = hit.product;
    } catch (_) {
      // 404 (free code) or offline: nothing to report; the server still enforces uniqueness.
    }
    if (mounted && _c['barcode']!.text.trim() == code) setState(() => _duplicate = found);
  }

  void _openDuplicate(Product product) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go(AppRoutes.productDetail(product.id));
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
      if (mounted) {
        setState(() {
          _error = e;
          // A server error on a field inside the collapsed section must be visible.
          if (fieldErrorFor(e, 'sku') != null || fieldErrorFor(e, 'notes') != null) {
            _moreOpen = true;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seesCosts = ref.watch(sessionProvider)?.membership.canViewCosts ?? false;
    final brands = ref.watch(brandsProvider).value ?? const <Brand>[];
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final lockedStock = _kind.usesVariants || _kind.isNonStock;
    final duplicate = _duplicate;
    final specs = AttributeSpec.byKind[_kind]!;

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
      icon: Icons.inventory_2_outlined,
      width: 680,
      busy: _busy,
      error: _error == null ? null : errorMessageFor(_error!),
      onSave: () => _save(seesCosts),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Barcode first, focused for the scanner.
            Focus(
              onFocusChange: (focused) {
                if (!focused) _checkBarcode();
              },
              child: TextFormField(
                key: const Key('product-barcode'),
                controller: _c['barcode'],
                autofocus: !_editing,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: AppStrings.barcode,
                  prefixIcon: const Icon(Icons.qr_code_scanner),
                  helperText: _kind.usesVariants
                      ? AppStrings.variantBarcodeHint
                      : AppStrings.barcodeHint,
                  helperMaxLines: 2,
                  errorText: fieldErrorFor(_error, 'barcode'),
                ),
                onFieldSubmitted: (_) => _checkBarcode(),
              ),
            ),
            if (duplicate != null)
              Container(
                key: const Key('product-duplicate'),
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${AppStrings.duplicateBarcode} «${duplicate.name}»',
                        style: TextStyle(color: theme.colorScheme.onErrorContainer),
                      ),
                    ),
                    TextButton(
                      key: const Key('product-open-duplicate'),
                      onPressed: () => _openDuplicate(duplicate),
                      child: const Text(AppStrings.openProduct),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            // 2. Kind as icon buttons (fixed once saved).
            Text(AppStrings.productKind, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final k in ProductKind.values)
                  ChoiceChip(
                    key: Key('product-kind-${k.value}'),
                    avatar: Icon(productKindIcons[k], size: 18),
                    label: Text(AppStrings.productKinds[k.value]!),
                    selected: _kind == k,
                    showCheckmark: false,
                    onSelected: _editing ? null : (_) => setState(() => _kind = k),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // 3. Name, brand, group.
            FieldGrid(
              children: [
                text('name', AppStrings.productName, validator: Inputs.requiredText),
                DropdownButtonFormField<int?>(
                  isExpanded: true,
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
                  isExpanded: true,
                  key: const Key('product-category'),
                  initialValue: categories.any((c) => c.id == _categoryId) ? _categoryId : null,
                  decoration: const InputDecoration(labelText: AppStrings.categoryOptional),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text(AppStrings.none)),
                    for (final c in categories.where((c) => c.isActive || c.id == _categoryId))
                      DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 4. Prices and the low-stock alert.
            FieldGrid(
              children: [
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
                if (!_kind.isNonStock && _trackStock)
                  TextFormField(
                    key: const Key('product-reorder_level'),
                    controller: _c['reorder_level'],
                    inputFormatters: Inputs.integer,
                    decoration: const InputDecoration(labelText: AppStrings.reorderLevel),
                  ),
              ],
            ),
            // 5. The kind's own details.
            if (specs.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                AppStrings.attributesTitles[_kind.value] ?? AppStrings.attributes,
                key: const Key('product-attributes-title'),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              FieldGrid(
                children: [for (final s in specs.where((s) => !s.multi)) _attributeField(s)],
              ),
              for (final s in specs.where((s) => s.multi)) ...[
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
            // 6. Collapsed extra options.
            const SizedBox(height: 12),
            const Divider(height: 1),
            ListTile(
              key: const Key('product-more'),
              contentPadding: EdgeInsets.zero,
              title: const Text(AppStrings.moreOptions),
              subtitle: const Text(AppStrings.moreOptionsHint),
              trailing: Icon(_moreOpen ? Icons.expand_less : Icons.expand_more),
              onTap: () => setState(() => _moreOpen = !_moreOpen),
            ),
            if (_moreOpen) ...[
              text('sku', AppStrings.sku, ltr: true),
              const SizedBox(height: 8),
              if (!lockedStock)
                _Switch(
                  label: AppStrings.trackStock,
                  hint: AppStrings.trackStockHint,
                  value: _trackStock,
                  onChanged: (v) => setState(() => _trackStock = v),
                ),
              if (_editing)
                _Switch(
                  label: AppStrings.active,
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
              const SizedBox(height: 8),
              text('notes', AppStrings.notes, maxLines: 2),
            ],
          ],
        ),
      ),
    );
  }

  Widget _attributeField(AttributeSpec s) {
    final label = AppStrings.label(AppStrings.attributeLabels, s.key);
    if (s.choices != null) {
      return DropdownButtonFormField<String?>(
        isExpanded: true,
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
  const _Switch({required this.label, required this.value, required this.onChanged, this.hint});

  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: hint == null ? null : Text(hint!),
    value: value,
    onChanged: onChanged,
  );
}
