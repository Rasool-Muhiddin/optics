import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_messages.dart';
import '../../core/formatters/formatters.dart';
import '../../core/optics/powers.dart';
import '../../core/strings/app_strings.dart';
import '../../data/repositories/jobs_repository.dart';
import '../../data/repositories/sales_repository.dart' show InvoiceQuery;
import '../../models/catalog.dart';
import '../../models/jobs.dart';
import '../../models/patients.dart';
import '../../widgets/common.dart';
import '../../widgets/patient_picker.dart';
import '../../widgets/product_pickers.dart';
import '../inventory/inventory_providers.dart';
import '../patients/patients_providers.dart';
import '../sales/sales_providers.dart';

/// New / edit job: patient, prescription, frame (lab / customer's own / none), lens + powers,
/// linked invoice, promised date. Returns the saved [Job].
class JobFormDialog extends ConsumerStatefulWidget {
  const JobFormDialog({super.key, this.job, this.patient});

  final Job? job;
  final Patient? patient;

  @override
  ConsumerState<JobFormDialog> createState() => _JobFormDialogState();
}

class _JobFormDialogState extends ConsumerState<JobFormDialog> {
  late int? _patientId = widget.job?.patientId ?? widget.patient?.id;
  late String _patientName = widget.job?.patientName ?? widget.patient?.fullName ?? '';
  late int? _prescriptionId = widget.job?.prescriptionId;
  late int? _invoiceId = widget.job?.invoiceId;
  late String _frameSource = widget.job?.frameSource ?? 'lab';
  late int? _frameId = widget.job?.frameId;
  late String _frameName = widget.job?.frameName ?? '';
  late int? _lensId = widget.job?.lensId;
  late String _lensName = widget.job?.lensName ?? '';
  Product? _lensProduct;
  late int? _lensOdId = widget.job?.lensOdId;
  late String _lensOdLabel = widget.job?.lensOdLabel ?? '';
  late int? _lensOsId = widget.job?.lensOsId;
  late String _lensOsLabel = widget.job?.lensOsLabel ?? '';
  late DateTime? _promised =
      widget.job?.promisedDate ?? DateTime.now().add(const Duration(days: 3));
  late final _frameNotes = TextEditingController(text: widget.job?.frameNotes ?? '');
  late final _lensNotes = TextEditingController(text: widget.job?.lensNotes ?? '');
  late final _notes = TextEditingController(text: widget.job?.notes ?? '');
  bool _busy = false;
  Object? _error;

  bool get _editing => widget.job != null;

  @override
  void dispose() {
    _frameNotes.dispose();
    _lensNotes.dispose();
    _notes.dispose();
    super.dispose();
  }

  static String _variantLabel(LensVariant v) =>
      'SPH ${Powers.format(v.sph)} CYL ${Powers.format(v.cyl)}${v.add > 0 ? ' ADD ${Powers.format(v.add)}' : ''}';

  Future<void> _save() async {
    if (_busy) return;
    if (_patientId == null) {
      setState(() => _error = const _LocalError());
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = <String, dynamic>{
      if (!_editing) 'patient': _patientId,
      'prescription': _prescriptionId,
      'invoice': _invoiceId,
      'frame_source': _frameSource,
      'frame': _frameSource == 'lab' ? _frameId : null,
      'frame_notes': _frameNotes.text.trim(),
      'lens': _lensId,
      'lens_od': _lensOdId,
      'lens_os': _lensOsId,
      'lens_notes': _lensNotes.text.trim(),
      'promised_date': _promised?.toIso8601String().substring(0, 10),
      'notes': _notes.text.trim(),
    };
    try {
      final job = await ref.read(jobsRepositoryProvider).save(widget.job?.id, body);
      if (mounted) Navigator.of(context).pop(job);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientId = _patientId;
    final prescriptions = patientId == null
        ? const <Prescription>[]
        : (ref.watch(patientPrescriptionsProvider(patientId)).value ?? const <Prescription>[])
              .where((rx) => !rx.isVoid || rx.id == _prescriptionId)
              .toList();
    final InvoiceQuery invoiceQuery = (
      search: '',
      status: null,
      onlyBalance: false,
      patientId: patientId ?? -1,
    );
    final invoices = patientId == null
        ? const []
        : (ref.watch(invoiceListProvider(invoiceQuery)).value?.items ?? const [])
              .where((i) => !i.isCancelled || i.id == _invoiceId)
              .toList();
    // When editing, the lens product is loaded to know whether it has power variants.
    final lensId = _lensId;
    final lensProduct =
        _lensProduct ?? (lensId == null ? null : ref.watch(productProvider(lensId)).value);
    final lensUsesVariants = lensProduct?.usesVariants ?? (_lensOdId != null || _lensOsId != null);

    Widget picked(
      String label,
      String value,
      VoidCallback onPick, {
      VoidCallback? onClear,
      Key? key,
    }) => InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Row(
        children: [
          Expanded(child: Text(value.isEmpty ? AppStrings.none : value)),
          if (onClear != null && value.isNotEmpty)
            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onClear),
          TextButton(key: key, onPressed: onPick, child: const Text(AppStrings.edit)),
        ],
      ),
    );

    return FormDialog(
      title: _editing ? '${AppStrings.editJob} #${widget.job!.number}' : AppStrings.newJob,
      width: 760,
      busy: _busy,
      error: _error is _LocalError
          ? '${AppStrings.choosePatient}: ${AppStrings.required}'
          : _error == null
          ? null
          : errorMessageFor(_error!),
      onSave: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldGrid(
            children: [
              _editing || widget.patient != null
                  ? InputDecorator(
                      decoration: const InputDecoration(labelText: AppStrings.patientName),
                      child: Text(_patientName),
                    )
                  : picked(AppStrings.patientName, _patientName, () async {
                      final p = await pickPatient(context);
                      if (p != null) {
                        setState(() {
                          _patientId = p.id;
                          _patientName = p.fullName;
                          _prescriptionId = null;
                          _invoiceId = null;
                        });
                      }
                    }, key: const Key('job-pick-patient')),
              InkWell(
                onTap: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _promised ?? now,
                    firstDate: now.subtract(const Duration(days: 365)),
                    lastDate: now.add(const Duration(days: 365)),
                  );
                  if (d != null) setState(() => _promised = d);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: AppStrings.promisedDate),
                  child: Text(Formatters.date(_promised)),
                ),
              ),
              DropdownButtonFormField<int?>(
                key: const Key('job-prescription'),
                isExpanded: true,
                initialValue: prescriptions.any((r) => r.id == _prescriptionId)
                    ? _prescriptionId
                    : null,
                decoration: const InputDecoration(labelText: AppStrings.linkedPrescription),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text(AppStrings.none)),
                  for (final rx in prescriptions)
                    DropdownMenuItem<int?>(
                      value: rx.id,
                      child: Text(
                        '${Formatters.date(rx.rxDate)}  ${rx.summary}',
                        textDirection: TextDirection.ltr,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _prescriptionId = v),
              ),
              DropdownButtonFormField<int?>(
                key: const Key('job-invoice'),
                isExpanded: true,
                initialValue: invoices.any((i) => i.id == _invoiceId) ? _invoiceId : null,
                decoration: const InputDecoration(labelText: AppStrings.linkedInvoice),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text(AppStrings.none)),
                  for (final inv in invoices)
                    DropdownMenuItem<int?>(
                      value: inv.id,
                      child: Text('#${inv.number} — ${Formatters.money(inv.total)}'),
                    ),
                ],
                onChanged: (v) => setState(() => _invoiceId = v),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(AppStrings.frameSource, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            key: const Key('job-frame-source'),
            segments: [
              for (final s in AppStrings.frameSources.entries)
                ButtonSegment(value: s.key, label: Text(s.value)),
            ],
            selected: {_frameSource},
            onSelectionChanged: (v) => setState(() => _frameSource = v.first),
          ),
          const SizedBox(height: 8),
          FieldGrid(
            children: [
              if (_frameSource == 'lab')
                picked(
                  AppStrings.frame,
                  _frameName,
                  () async {
                    final p = await pickProduct(
                      context,
                      kinds: 'frame',
                      title: AppStrings.chooseFrame,
                    );
                    if (p != null) {
                      setState(() {
                        _frameId = p.id;
                        _frameName = p.name;
                      });
                    }
                  },
                  onClear: () => setState(() {
                    _frameId = null;
                    _frameName = '';
                  }),
                  key: const Key('job-pick-frame'),
                ),
              TextField(
                key: const Key('job-frame-notes'),
                controller: _frameNotes,
                decoration: const InputDecoration(labelText: AppStrings.frameNotes),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FieldGrid(
            children: [
              picked(
                AppStrings.lens,
                _lensName,
                () async {
                  final p = await pickProduct(
                    context,
                    kinds: 'stock_lens,rx_lens,contact_lens',
                    title: AppStrings.chooseLens,
                  );
                  if (p != null) {
                    setState(() {
                      _lensProduct = p;
                      _lensId = p.id;
                      _lensName = p.name;
                      _lensOdId = _lensOsId = null;
                      _lensOdLabel = _lensOsLabel = '';
                    });
                  }
                },
                onClear: () => setState(() {
                  _lensProduct = null;
                  _lensId = _lensOdId = _lensOsId = null;
                  _lensName = _lensOdLabel = _lensOsLabel = '';
                }),
                key: const Key('job-pick-lens'),
              ),
              TextField(
                controller: _lensNotes,
                decoration: const InputDecoration(labelText: AppStrings.lensNotes),
              ),
              if (_lensId != null && lensUsesVariants) ...[
                picked(AppStrings.lensOd, _lensOdLabel, () async {
                  final v = await _pickPower();
                  if (v != null) {
                    setState(() {
                      _lensOdId = v.id;
                      _lensOdLabel = _variantLabel(v);
                    });
                  }
                }, key: const Key('job-pick-od')),
                picked(AppStrings.lensOs, _lensOsLabel, () async {
                  final v = await _pickPower();
                  if (v != null) {
                    setState(() {
                      _lensOsId = v.id;
                      _lensOsLabel = _variantLabel(v);
                    });
                  }
                }, key: const Key('job-pick-os')),
              ],
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('job-notes'),
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(labelText: AppStrings.notes),
          ),
        ],
      ),
    );
  }

  Future<LensVariant?> _pickPower() async {
    final product =
        _lensProduct ?? Product(id: _lensId!, kind: ProductKind.stockLens, name: _lensName);
    return pickLensVariant(context, product);
  }
}

class _LocalError {
  const _LocalError();
}
