import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_messages.dart';
import '../../core/formatters/formatters.dart';
import '../../core/strings/app_strings.dart';
import '../../data/repositories/patients_repository.dart';
import '../../models/patients.dart';
import '../../widgets/common.dart';
import '../../widgets/rx_form.dart';

String _isoDate(DateTime d) => d.toIso8601String().substring(0, 10);

Future<DateTime?> _pickDate(BuildContext context, DateTime initial) => showDatePicker(
  context: context,
  initialDate: initial,
  firstDate: DateTime(2000),
  lastDate: DateTime.now().add(const Duration(days: 1)),
);

/// New / edit exam with an optional prescription (saved together, atomically).
class ExamFormDialog extends ConsumerStatefulWidget {
  const ExamFormDialog({super.key, required this.patient, this.exam});

  final Patient patient;
  final EyeExam? exam;

  @override
  ConsumerState<ExamFormDialog> createState() => _ExamFormDialogState();
}

class _ExamFormDialogState extends ConsumerState<ExamFormDialog> {
  late DateTime _date = widget.exam?.examDate ?? DateTime.now();
  late final _c = {
    'examiner_name': TextEditingController(text: widget.exam?.examinerName ?? ''),
    'chief_complaint': TextEditingController(text: widget.exam?.chiefComplaint ?? ''),
    'diagnosis': TextEditingController(text: widget.exam?.diagnosis ?? ''),
    'diagnosis_details': TextEditingController(text: widget.exam?.diagnosisDetails ?? ''),
    'va_od': TextEditingController(text: widget.exam?.vaOd ?? ''),
    'va_os': TextEditingController(text: widget.exam?.vaOs ?? ''),
    'iop_od': TextEditingController(text: widget.exam?.iopOd ?? ''),
    'iop_os': TextEditingController(text: widget.exam?.iopOs ?? ''),
    'notes': TextEditingController(text: widget.exam?.notes ?? ''),
  };
  final _rx = RxFormController();
  late bool _withRx = widget.exam == null || widget.exam!.prescription != null;
  Map<String, String> _rxErrors = const {};
  bool _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _rx.load(widget.exam?.prescription);
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    _rx.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final rxErrors = _withRx ? _rx.validate() : const <String, String>{};
    setState(() => _rxErrors = rxErrors);
    if (rxErrors.isNotEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? decimalOrNull(String key) => _c[key]!.text.trim().isEmpty ? null : _c[key]!.text.trim();
    final body = <String, dynamic>{
      'patient': widget.patient.id,
      'exam_date': _isoDate(_date),
      for (final key in [
        'examiner_name',
        'chief_complaint',
        'diagnosis',
        'diagnosis_details',
        'va_od',
        'va_os',
        'notes',
      ])
        key: _c[key]!.text.trim(),
      'iop_od': decimalOrNull('iop_od'),
      'iop_os': decimalOrNull('iop_os'),
      if (_withRx) 'prescription': {..._rx.toJson(), 'rx_date': _isoDate(_date)},
    };
    try {
      final exam = await ref.read(patientsRepositoryProvider).saveExam(widget.exam?.id, body);
      if (mounted) Navigator.of(context).pop(exam);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    TextField field(String key, String label, {int maxLines = 1, bool ltr = false}) => TextField(
      key: Key('exam-$key'),
      controller: _c[key],
      maxLines: maxLines,
      textDirection: ltr ? TextDirection.ltr : null,
      decoration: InputDecoration(labelText: label, errorText: fieldCodeMessage(_error, [key])),
    );
    return FormDialog(
      title:
          '${widget.exam == null ? AppStrings.newExam : AppStrings.editExam} — ${widget.patient.fullName}',
      width: 820,
      busy: _busy,
      error: _error == null ? null : errorMessageFor(_error!),
      onSave: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldGrid(
            columns: 3,
            children: [
              InkWell(
                onTap: () async {
                  final d = await _pickDate(context, _date);
                  if (d != null) setState(() => _date = d);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: AppStrings.examDate),
                  child: Text(Formatters.date(_date)),
                ),
              ),
              field('examiner_name', AppStrings.examinerName),
              field('chief_complaint', AppStrings.chiefComplaint),
              field('va_od', '${AppStrings.vaUncorrected} OD', ltr: true),
              field('va_os', '${AppStrings.vaUncorrected} OS', ltr: true),
              const SizedBox.shrink(),
              field('iop_od', '${AppStrings.iop} OD', ltr: true),
              field('iop_os', '${AppStrings.iop} OS', ltr: true),
            ],
          ),
          const SizedBox(height: 12),
          field('diagnosis', AppStrings.diagnosis),
          const SizedBox(height: 12),
          field('diagnosis_details', AppStrings.diagnosisDetails, maxLines: 2),
          const SizedBox(height: 12),
          field('notes', AppStrings.notes, maxLines: 2),
          const Divider(height: 32),
          CheckboxListTile(
            key: const Key('exam-with-rx'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              AppStrings.withPrescription,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            value: _withRx,
            onChanged: widget.exam?.prescription != null
                ? null
                : (v) => setState(() => _withRx = v ?? false),
          ),
          if (_withRx)
            RxForm(
              controller: _rx,
              errors: _rxErrors,
              serverError: _error,
              serverPath: const ['prescription'],
            ),
        ],
      ),
    );
  }
}

/// Standalone prescription (e.g. brought from another clinic) or edit of any Rx.
class PrescriptionFormDialog extends ConsumerStatefulWidget {
  const PrescriptionFormDialog({super.key, required this.patient, this.prescription});

  final Patient patient;
  final Prescription? prescription;

  @override
  ConsumerState<PrescriptionFormDialog> createState() => _PrescriptionFormDialogState();
}

class _PrescriptionFormDialogState extends ConsumerState<PrescriptionFormDialog> {
  final _rx = RxFormController();
  late DateTime _date = widget.prescription?.rxDate ?? DateTime.now();
  late final _prescribedBy = TextEditingController(text: widget.prescription?.prescribedBy ?? '');
  Map<String, String> _errors = const {};
  bool _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _rx.load(widget.prescription);
  }

  @override
  void dispose() {
    _rx.dispose();
    _prescribedBy.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final errors = _rx.validate();
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rx = await ref
          .read(patientsRepositoryProvider)
          .savePrescription(widget.prescription?.id, {
            'patient': widget.patient.id,
            'rx_date': _isoDate(_date),
            'prescribed_by': _prescribedBy.text.trim(),
            ..._rx.toJson(),
          });
      if (mounted) Navigator.of(context).pop(rx);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormDialog(
      title:
          '${widget.prescription == null ? AppStrings.newPrescription : AppStrings.editPrescription}'
          ' — ${widget.patient.fullName}',
      width: 820,
      busy: _busy,
      error: _error == null ? null : errorMessageFor(_error!),
      onSave: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldGrid(
            children: [
              InkWell(
                onTap: () async {
                  final d = await _pickDate(context, _date);
                  if (d != null) setState(() => _date = d);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: AppStrings.rxDate),
                  child: Text(Formatters.date(_date)),
                ),
              ),
              TextField(
                controller: _prescribedBy,
                decoration: const InputDecoration(labelText: AppStrings.prescribedBy),
              ),
            ],
          ),
          const SizedBox(height: 16),
          RxForm(controller: _rx, errors: _errors, serverError: _error),
        ],
      ),
    );
  }
}

/// Asks for a void reason; returns it or null.
Future<String?> askVoidReason(BuildContext context) =>
    showDialog<String>(context: context, builder: (_) => const _ReasonDialog());

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog();

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AppStrings.voidRecord),
      content: SizedBox(
        width: 380,
        child: TextField(
          key: const Key('void-reason'),
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: AppStrings.voidReason),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.cancel),
        ),
        FilledButton(
          key: const Key('void-confirm'),
          onPressed: () {
            if (_controller.text.trim().isNotEmpty) {
              Navigator.of(context).pop(_controller.text.trim());
            }
          },
          child: const Text(AppStrings.voidRecord),
        ),
      ],
    );
  }
}
