import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_messages.dart';
import '../../core/formatters/formatters.dart';
import '../../core/optics/powers.dart';
import '../../core/strings/app_strings.dart';
import '../../data/repositories/jobs_repository.dart';
import '../../data/repositories/purchasing_repository.dart';
import '../../models/jobs.dart';
import '../../models/patients.dart';
import '../../models/purchasing.dart';
import '../../widgets/common.dart';
import '../../widgets/product_pickers.dart';
import '../jobs/jobs_providers.dart';
import 'orders_providers.dart';

/// One editable order line (controllers are owned by the dialog state).
class _LineDraft {
  _LineDraft({
    this.productId,
    this.variantId,
    this.label = '',
    String description = '',
    this.eye = '',
    String qty = '1',
    String cost = '',
  }) : description = TextEditingController(text: description),
       qty = TextEditingController(text: qty),
       cost = TextEditingController(text: cost);

  final int? productId;
  final int? variantId;
  final String label;
  final TextEditingController description;
  String eye;
  final TextEditingController qty;
  final TextEditingController cost;

  void dispose() {
    description.dispose();
    qty.dispose();
    cost.dispose();
  }

  Map<String, dynamic> toJson() => {
    'product': variantId == null ? productId : null,
    'variant': variantId,
    'description': description.text.trim(),
    'eye': eye,
    'qty': int.tryParse(qty.text.trim()) ?? 0,
    'unit_cost': cost.text.trim().isEmpty ? '0' : cost.text.trim(),
  };
}

/// New / edit supplier order. With [job] it starts as an Rx order for that job, with one
/// line per eye described from the job's prescription.
class OrderFormDialog extends ConsumerStatefulWidget {
  const OrderFormDialog({super.key, this.order, this.job});

  final SupplierOrder? order;
  final Job? job;

  @override
  ConsumerState<OrderFormDialog> createState() => _OrderFormDialogState();
}

class _OrderFormDialogState extends ConsumerState<OrderFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late int? _supplierId = widget.order?.supplierId;
  late String _type =
      widget.order?.type ?? (widget.job != null ? OrderTypes.rxForJob : OrderTypes.stock);
  late int? _jobId = widget.order?.jobId ?? widget.job?.id;
  late String _jobLabel = widget.job != null
      ? '#${widget.job!.number} ${widget.job!.patientName}'
      : (widget.order?.jobNumber == null
            ? ''
            : '#${widget.order!.jobNumber} ${widget.order!.jobPatientName}');
  late DateTime _orderDate = widget.order?.orderDate ?? DateTime.now();
  late DateTime? _expected = widget.order?.expectedDate;
  bool _sent = true;
  late final _ref = TextEditingController(text: widget.order?.supplierRef ?? '');
  late final _notes = TextEditingController(text: widget.order?.notes ?? '');
  late final List<_LineDraft> _lines = _initialLines();
  bool _busy = false;
  Object? _error;

  bool get _editing => widget.order != null;

  List<_LineDraft> _initialLines() {
    final order = widget.order;
    if (order != null) {
      return [
        for (final l in order.lines)
          _LineDraft(
            productId: l.productId,
            variantId: l.variantId,
            label: [l.productName, l.variantLabel].where((s) => s.isNotEmpty).join(' — '),
            description: l.description,
            eye: l.eye,
            qty: '${l.qty}',
            cost: l.unitCost ?? '',
          ),
      ];
    }
    final job = widget.job;
    if (job == null) return [];
    String eyeRx(EyeRx e) => e.isEmpty
        ? ''
        : [
            'SPH ${Powers.format(e.sph)}',
            if ((double.tryParse(e.cyl ?? '') ?? 0) != 0)
              'CYL ${Powers.format(e.cyl)} × ${e.axis ?? ''}',
            if (e.add != null) 'ADD ${Powers.format(e.add)}',
          ].join(' ');
    final rx = job.prescription;
    return [
      for (final (eye, e) in [('od', rx?.od), ('os', rx?.os)])
        if (rx == null || !(e?.isEmpty ?? true))
          _LineDraft(
            productId: job.lensId,
            label: job.lensName,
            description: e == null ? '' : eyeRx(e),
            eye: eye,
          ),
    ];
  }

  @override
  void dispose() {
    _ref.dispose();
    _notes.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _addProductLine() async {
    final product = await pickProduct(
      context,
      kinds: _type == OrderTypes.stock
          ? 'frame,stock_lens,contact_lens,accessory,solution'
          : 'frame,stock_lens,rx_lens,contact_lens,accessory,solution,service',
      title: AppStrings.addProductLine,
    );
    if (product == null || !mounted) return;
    if (product.usesVariants) {
      final v = await pickLensVariant(context, product);
      if (v == null) return;
      setState(
        () => _lines.add(
          _LineDraft(
            productId: product.id,
            variantId: v.id,
            label:
                '${product.name} — SPH ${Powers.format(v.sph)} CYL ${Powers.format(v.cyl)}'
                '${v.add > 0 ? ' ADD ${Powers.format(v.add)}' : ''}',
          ),
        ),
      );
    } else {
      setState(() => _lines.add(_LineDraft(productId: product.id, label: product.name)));
    }
  }

  Future<void> _pickJob() async {
    final job = await showDialog<Job>(context: context, builder: (_) => const _JobPicker());
    if (job != null) {
      setState(() {
        _jobId = job.id;
        _jobLabel = '#${job.number} ${job.patientName}';
      });
    }
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    if (_lines.isEmpty) {
      setState(() => _error = const _LocalError(AppStrings.linesRequired));
      return;
    }
    if (_type == OrderTypes.rxForJob && _jobId == null) {
      setState(() => _error = const _LocalError(AppStrings.errJobRequired));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    String day(DateTime d) => d.toIso8601String().substring(0, 10);
    final body = <String, dynamic>{
      'supplier': _supplierId,
      'type': _type,
      'job': _type == OrderTypes.rxForJob ? _jobId : null,
      'order_date': day(_orderDate),
      'expected_date': _expected == null ? null : day(_expected!),
      'supplier_ref': _ref.text.trim(),
      'notes': _notes.text.trim(),
      'lines': [for (final l in _lines) l.toJson()],
      if (!_editing) 'status': _sent ? OrderStatuses.ordered : OrderStatuses.pending,
    };
    try {
      final order = await ref.read(purchasingRepositoryProvider).saveOrder(widget.order?.id, body);
      if (mounted) Navigator.of(context).pop(order);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<DateTime?> _date(DateTime? initial) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: now.subtract(const Duration(days: 730)),
      lastDate: now.add(const Duration(days: 365)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(suppliersProvider).value ?? const <Supplier>[];
    final error = _error;
    return FormDialog(
      title: _editing ? '${AppStrings.editOrder} #${widget.order!.number}' : AppStrings.newOrder,
      width: 820,
      busy: _busy,
      error: error is _LocalError ? error.message : (error == null ? null : errorMessageFor(error)),
      onSave: _save,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<String>(
              key: const Key('order-type'),
              segments: [
                for (final t in AppStrings.orderTypes.entries)
                  ButtonSegment(value: t.key, label: Text(t.value)),
              ],
              selected: {_type},
              onSelectionChanged: widget.job != null || _editing
                  ? null
                  : (v) => setState(() => _type = v.first),
            ),
            const SizedBox(height: 12),
            FieldGrid(
              children: [
                DropdownButtonFormField<int>(
                  key: const Key('order-supplier'),
                  isExpanded: true,
                  initialValue: suppliers.any((s) => s.id == _supplierId) ? _supplierId : null,
                  decoration: const InputDecoration(labelText: AppStrings.supplier),
                  items: [
                    for (final s in suppliers.where((s) => s.isActive || s.id == _supplierId))
                      DropdownMenuItem(value: s.id, child: Text(s.name)),
                  ],
                  validator: (v) => v == null ? AppStrings.required : null,
                  onChanged: (v) => setState(() => _supplierId = v),
                ),
                if (_type == OrderTypes.rxForJob)
                  InputDecorator(
                    decoration: const InputDecoration(labelText: AppStrings.job),
                    child: Row(
                      children: [
                        Expanded(child: Text(_jobLabel.isEmpty ? AppStrings.none : _jobLabel)),
                        if (widget.job == null && !_editing)
                          TextButton(
                            key: const Key('order-pick-job'),
                            onPressed: _pickJob,
                            child: const Text(AppStrings.edit),
                          ),
                      ],
                    ),
                  )
                else
                  TextFormField(
                    controller: _ref,
                    decoration: const InputDecoration(labelText: AppStrings.supplierRef),
                  ),
                InkWell(
                  onTap: () async {
                    final d = await _date(_orderDate);
                    if (d != null) setState(() => _orderDate = d);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: AppStrings.orderDate),
                    child: Text(Formatters.date(_orderDate)),
                  ),
                ),
                InkWell(
                  onTap: () async {
                    final d = await _date(_expected);
                    if (d != null) setState(() => _expected = d);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: AppStrings.expectedDate),
                    child: Text(_expected == null ? AppStrings.none : Formatters.date(_expected)),
                  ),
                ),
              ],
            ),
            if (!_editing)
              CheckboxListTile(
                key: const Key('order-sent'),
                contentPadding: EdgeInsets.zero,
                value: _sent,
                title: const Text(AppStrings.markOrdered),
                onChanged: (v) => setState(() => _sent = v ?? true),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(AppStrings.orderLines, style: Theme.of(context).textTheme.titleSmall),
                ),
                TextButton.icon(
                  key: const Key('order-add-product'),
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: const Text(AppStrings.addProductLine),
                  onPressed: _addProductLine,
                ),
                if (_type != OrderTypes.stock)
                  TextButton.icon(
                    key: const Key('order-add-text'),
                    icon: const Icon(Icons.short_text, size: 18),
                    label: const Text(AppStrings.addTextLine),
                    onPressed: () => setState(() => _lines.add(_LineDraft())),
                  ),
              ],
            ),
            for (final (i, line) in _lines.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: TextFormField(
                        key: Key('order-line-desc-$i'),
                        controller: line.description,
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: line.label.isEmpty ? AppStrings.description : line.label,
                        ),
                        validator: (v) => line.productId == null && (v ?? '').trim().isEmpty
                            ? AppStrings.required
                            : null,
                      ),
                    ),
                    if (_type == OrderTypes.rxForJob) ...[
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 120,
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: line.eye,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: AppStrings.eye,
                          ),
                          items: [
                            for (final e in AppStrings.eyes.entries)
                              DropdownMenuItem(value: e.key, child: Text(e.value)),
                          ],
                          onChanged: (v) => setState(() => line.eye = v ?? ''),
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 80,
                      child: TextFormField(
                        key: Key('order-line-qty-$i'),
                        controller: line.qty,
                        inputFormatters: Inputs.integer,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: AppStrings.quantity,
                        ),
                        validator: (v) => Inputs.intValidator(v, allowZero: false),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 120,
                      child: TextFormField(
                        key: Key('order-line-cost-$i'),
                        controller: line.cost,
                        inputFormatters: Inputs.money,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: AppStrings.unitCost,
                        ),
                        validator: (v) => Inputs.moneyValidator(v, required: false),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() => _lines.removeAt(i).dispose()),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: AppStrings.notes),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalError {
  const _LocalError(this.message);

  final String message;
}

/// Open customer jobs to link an Rx order to.
class _JobPicker extends ConsumerStatefulWidget {
  const _JobPicker();

  @override
  ConsumerState<_JobPicker> createState() => _JobPickerState();
}

class _JobPickerState extends ConsumerState<_JobPicker> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final JobQuery q = (search: _search, patientId: null, overdueOnly: false);
    return AlertDialog(
      title: const Text(AppStrings.chooseJob),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: AppStrings.search,
              ),
              onSubmitted: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: AsyncView(
                value: ref.watch(jobBoardProvider(q)),
                builder: (jobs) => ListView(
                  children: [
                    for (final j in jobs.where((j) => !j.isFinal))
                      ListTile(
                        key: Key('pick-job-${j.id}'),
                        dense: true,
                        title: Text('#${j.number} ${j.patientName}'),
                        subtitle: Text('${AppStrings.jobStatuses[j.status]}   •   ${j.lensName}'),
                        onTap: () => Navigator.of(context).pop(j),
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
