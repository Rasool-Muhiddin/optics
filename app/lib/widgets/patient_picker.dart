import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/strings/app_strings.dart';
import '../models/patients.dart';
import '../screens/patients/patient_form_dialog.dart';
import '../screens/patients/patients_providers.dart';
import 'common.dart';

/// Search-and-pick a patient (or create one). Returns the chosen [Patient].
Future<Patient?> pickPatient(BuildContext context) =>
    showDialog<Patient>(context: context, builder: (_) => const _PatientPicker());

class _PatientPicker extends ConsumerStatefulWidget {
  const _PatientPicker();

  @override
  ConsumerState<_PatientPicker> createState() => _PatientPickerState();
}

class _PatientPickerState extends ConsumerState<_PatientPicker> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(patientListProvider((search: _query, status: null)));
    return AlertDialog(
      title: const Text(AppStrings.choosePatient),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(
          children: [
            TextField(
              key: const Key('picker-search'),
              controller: _search,
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '${AppStrings.name} / ${AppStrings.phone}',
              ),
              onChanged: (text) {
                _debounce?.cancel();
                _debounce = Timer(
                  const Duration(milliseconds: 300),
                  () => setState(() => _query = text),
                );
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: AsyncView(
                value: value,
                builder: (page) => ListView(
                  children: [
                    for (final p in page.items)
                      ListTile(
                        key: Key('pick-patient-${p.id}'),
                        title: Text(p.fullName),
                        subtitle: Text(p.phone),
                        onTap: () => Navigator.of(context).pop(p),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.person_add_alt),
          label: const Text(AppStrings.addPatient),
          onPressed: () async {
            final created = await showDialog<Patient>(
              context: context,
              builder: (_) => PatientFormDialog(initialName: _search.text.trim()),
            );
            if (created != null && context.mounted) Navigator.of(context).pop(created);
          },
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.cancel),
        ),
      ],
    );
  }
}
