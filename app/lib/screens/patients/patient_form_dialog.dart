import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_messages.dart';
import '../../core/formatters/formatters.dart';
import '../../core/strings/app_strings.dart';
import '../../data/repositories/patients_repository.dart';
import '../../models/patients.dart';
import '../../widgets/common.dart';

/// Create / edit a patient. Age may be typed instead of a birth date. Returns the [Patient].
class PatientFormDialog extends ConsumerStatefulWidget {
  const PatientFormDialog({super.key, this.patient, this.initialName = ''});

  final Patient? patient;
  final String initialName;

  @override
  ConsumerState<PatientFormDialog> createState() => _PatientFormDialogState();
}

class _PatientFormDialogState extends ConsumerState<PatientFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.patient?.fullName ?? widget.initialName);
  late final _age = TextEditingController(text: widget.patient?.age?.toString() ?? '');
  late final _phone = TextEditingController(text: widget.patient?.phone ?? '');
  late final _address = TextEditingController(text: widget.patient?.address ?? '');
  late final _notes = TextEditingController(text: widget.patient?.notes ?? '');
  late DateTime? _birthDate = widget.patient?.birthDateEstimated == true
      ? null
      : widget.patient?.birthDate;
  late String _gender = widget.patient?.gender ?? '';
  late String _status = widget.patient?.status ?? 'new';
  late bool _archived = widget.patient?.isArchived ?? false;
  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    for (final c in [_name, _age, _phone, _address, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 30),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _birthDate = picked;
        _age.clear();
      });
    }
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = <String, dynamic>{
      'full_name': _name.text.trim(),
      'gender': _gender,
      'phone': _phone.text.trim(),
      'address': _address.text.trim(),
      'notes': _notes.text.trim(),
      if (_birthDate != null)
        'birth_date': _birthDate!.toIso8601String().substring(0, 10)
      else if (_age.text.trim().isNotEmpty)
        'age': int.parse(_age.text.trim()),
      if (widget.patient != null) 'status': _status,
      if (widget.patient != null) 'is_archived': _archived,
    };
    try {
      final saved = await ref.read(patientsRepositoryProvider).save(widget.patient?.id, body);
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.patient != null;
    return FormDialog(
      title: editing ? AppStrings.editPatient : AppStrings.addPatient,
      busy: _busy,
      error: _error == null ? null : errorMessageFor(_error!),
      onSave: _save,
      child: Form(
        key: _formKey,
        child: FieldGrid(
          children: [
            TextFormField(
              key: const Key('patient-name'),
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: AppStrings.patientName),
              validator: Inputs.requiredText,
            ),
            TextFormField(
              key: const Key('patient-phone'),
              controller: _phone,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: AppStrings.phone),
            ),
            TextFormField(
              key: const Key('patient-age'),
              controller: _age,
              inputFormatters: Inputs.integer,
              decoration: const InputDecoration(labelText: AppStrings.age),
              onChanged: (_) => setState(() => _birthDate = null),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final n = int.tryParse(v);
                return n == null || n > 130 ? AppStrings.invalidNumber : null;
              },
            ),
            InkWell(
              onTap: _pickBirthDate,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: AppStrings.birthDate),
                child: Text(_birthDate == null ? AppStrings.none : Formatters.date(_birthDate)),
              ),
            ),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _gender,
              decoration: const InputDecoration(labelText: AppStrings.gender),
              items: [
                const DropdownMenuItem(value: '', child: Text(AppStrings.none)),
                for (final g in AppStrings.genders.entries)
                  DropdownMenuItem(value: g.key, child: Text(g.value)),
              ],
              onChanged: (v) => setState(() => _gender = v ?? ''),
            ),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(labelText: AppStrings.address),
            ),
            if (editing)
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _status,
                decoration: const InputDecoration(labelText: AppStrings.status),
                items: [
                  for (final s in patientStatuses)
                    DropdownMenuItem(value: s, child: Text(AppStrings.patientStatuses[s]!)),
                ],
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
            if (editing)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(AppStrings.archived),
                value: _archived,
                onChanged: (v) => setState(() => _archived = v),
              ),
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
