import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_messages.dart';
import '../../core/formatters/formatters.dart';
import '../../core/strings/app_strings.dart';
import '../../data/cache/json_cache_dao.dart';
import '../../data/repositories/doctors_repository.dart';
import '../../models/doctors.dart';
import '../../widgets/common.dart';
import '../../widgets/referral_view.dart';
import '../../widgets/rx_form.dart';
import 'doctor_providers.dart';

/// Doctor mode home: the doctor's referrals and their status at the lab.
class DoctorReferralsScreen extends ConsumerStatefulWidget {
  const DoctorReferralsScreen({super.key});

  @override
  ConsumerState<DoctorReferralsScreen> createState() => _DoctorReferralsScreenState();
}

class _DoctorReferralsScreenState extends ConsumerState<DoctorReferralsScreen> {
  String? _status;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: AppStrings.navDoctorReferrals,
          cacheTables: const [CacheTables.doctorSideReferrals],
          actions: [
            FilledButton.icon(
              key: const Key('new-referral'),
              icon: const Icon(Icons.add),
              label: const Text(AppStrings.newReferral),
              onPressed: () async {
                final sent = await showDialog<Referral>(
                  context: context,
                  builder: (_) => const ReferralFormDialog(),
                );
                if (sent != null && context.mounted) {
                  invalidateDoctor(ref);
                  showSnack(context, AppStrings.referralSent);
                }
              },
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text(AppStrings.all),
                selected: _status == null,
                onSelected: (_) => setState(() => _status = null),
              ),
              for (final s in AppStrings.referralStatuses.entries)
                ChoiceChip(
                  label: Text(s.value),
                  selected: _status == s.key,
                  onSelected: (_) => setState(() => _status = s.key),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: AsyncView(
            value: ref.watch(doctorReferralsProvider(_status)),
            onRetry: () => ref.invalidate(doctorReferralsProvider(_status)),
            builder: (refs) => refs.isEmpty
                ? const Center(child: Text(AppStrings.noReferrals))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    children: [
                      for (final r in refs)
                        Card(
                          key: Key('doctor-referral-${r.id}'),
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ExpansionTile(
                            title: Text('${r.patientName} — ${r.labName}'),
                            subtitle: Text(
                              '${Formatters.dateTime(r.createdAt)}   •   '
                              '${AppStrings.label(AppStrings.referralStatuses, r.status)}',
                            ),
                            childrenPadding: const EdgeInsets.all(16),
                            children: [ReferralView(referral: r)],
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

/// New referral: lab (accepted links only), patient snapshot, exam and Rx (OD/OS form).
class ReferralFormDialog extends ConsumerStatefulWidget {
  const ReferralFormDialog({super.key});

  @override
  ConsumerState<ReferralFormDialog> createState() => _ReferralFormDialogState();
}

class _ReferralFormDialogState extends ConsumerState<ReferralFormDialog> {
  final _formKey = GlobalKey<FormState>();
  int? _labId;
  String _gender = '';
  bool _withRx = true;
  final _name = TextEditingController();
  final _age = TextEditingController();
  final _phone = TextEditingController();
  final _complaint = TextEditingController();
  final _diagnosis = TextEditingController();
  final _details = TextEditingController();
  final _vaOd = TextEditingController();
  final _vaOs = TextEditingController();
  final _notes = TextEditingController();
  final _rx = RxFormController();
  Map<String, String> _rxErrors = const {};
  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    for (final c in [_name, _age, _phone, _complaint, _diagnosis, _details, _vaOd, _vaOs, _notes]) {
      c.dispose();
    }
    _rx.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final rxErrors = _withRx ? _rx.validate() : const <String, String>{};
    setState(() => _rxErrors = rxErrors);
    if (rxErrors.isNotEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final rx = _rx.toJson();
    try {
      final sent = await ref.read(doctorRepositoryProvider).send({
        'lab': _labId,
        'patient_name': _name.text.trim(),
        'patient_age': int.tryParse(_age.text.trim()),
        'patient_gender': _gender,
        'patient_phone': _phone.text.trim(),
        'chief_complaint': _complaint.text.trim(),
        'diagnosis': _diagnosis.text.trim(),
        'diagnosis_details': _details.text.trim(),
        'va_od': _vaOd.text.trim(),
        'va_os': _vaOs.text.trim(),
        'notes': _notes.text.trim(),
        'prescription': _withRx ? rx : null,
      });
      if (mounted) Navigator.of(context).pop(sent);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final labs = (ref.watch(doctorLinksProvider).value ?? const <DoctorLink>[])
        .where((l) => l.status == LinkStatuses.accepted && l.labId != null)
        .toList();
    return FormDialog(
      title: AppStrings.newReferral,
      width: 820,
      busy: _busy,
      saveLabel: AppStrings.sendReferral,
      error: _error == null ? null : errorMessageFor(_error!),
      onSave: labs.isEmpty ? null : _save,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (labs.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(AppStrings.noLinkedLabs),
              ),
            FieldGrid(
              children: [
                DropdownButtonFormField<int>(
                  key: const Key('referral-lab'),
                  isExpanded: true,
                  initialValue: labs.any((l) => l.labId == _labId) ? _labId : null,
                  decoration: const InputDecoration(labelText: AppStrings.chooseLab),
                  items: [
                    for (final l in labs)
                      DropdownMenuItem(value: l.labId, child: Text(l.otherName)),
                  ],
                  validator: (v) => v == null ? AppStrings.required : null,
                  onChanged: (v) => setState(() => _labId = v),
                ),
                TextFormField(
                  key: const Key('referral-patient-name'),
                  controller: _name,
                  decoration: const InputDecoration(labelText: AppStrings.patientName),
                  validator: Inputs.requiredText,
                ),
                TextFormField(
                  controller: _age,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: AppStrings.age),
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
                  controller: _phone,
                  decoration: const InputDecoration(labelText: AppStrings.phone),
                ),
                TextFormField(
                  controller: _complaint,
                  decoration: const InputDecoration(labelText: AppStrings.chiefComplaint),
                ),
                TextFormField(
                  controller: _diagnosis,
                  decoration: const InputDecoration(labelText: AppStrings.diagnosis),
                ),
                TextFormField(
                  controller: _details,
                  decoration: const InputDecoration(labelText: AppStrings.diagnosisDetails),
                ),
                TextFormField(
                  controller: _vaOd,
                  decoration: const InputDecoration(labelText: 'VA OD'),
                ),
                TextFormField(
                  controller: _vaOs,
                  decoration: const InputDecoration(labelText: 'VA OS'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              key: const Key('referral-with-rx'),
              contentPadding: EdgeInsets.zero,
              value: _withRx,
              title: const Text(AppStrings.withPrescription),
              onChanged: (v) => setState(() => _withRx = v),
            ),
            if (_withRx)
              RxForm(
                controller: _rx,
                errors: _rxErrors,
                serverError: _error,
                serverPath: const ['prescription'],
              ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('referral-notes'),
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: AppStrings.doctorNote),
            ),
          ],
        ),
      ),
    );
  }
}
