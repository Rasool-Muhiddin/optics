import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters/formatters.dart';
import '../../core/router/app_routes.dart';
import '../../core/strings/app_strings.dart';
import '../../data/cache/json_cache_dao.dart';
import '../../models/patients.dart';
import '../../widgets/common.dart';
import 'patient_form_dialog.dart';
import 'patients_providers.dart';

/// Patient list with search (name / phone) and status filter.
class PatientsScreen extends ConsumerStatefulWidget {
  const PatientsScreen({super.key});

  @override
  ConsumerState<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends ConsumerState<PatientsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  PatientQuery _query = (search: '', status: null);

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final patient = await showDialog<Patient>(
      context: context,
      builder: (_) => PatientFormDialog(initialName: _search.text.trim()),
    );
    if (patient != null && mounted) {
      ref.invalidate(patientListProvider);
      context.go(AppRoutes.patientDetail(patient.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = ref.watch(patientListProvider(_query));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: AppStrings.patientsTitle,
          cacheTables: const [CacheTables.patients],
          actions: [
            FilledButton.icon(
              key: const Key('add-patient'),
              icon: const Icon(Icons.person_add_alt),
              label: const Text(AppStrings.addPatient),
              onPressed: _add,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 320,
                child: TextField(
                  key: const Key('patients-search'),
                  controller: _search,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: '${AppStrings.search} (${AppStrings.name} / ${AppStrings.phone})',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (text) {
                    _debounce?.cancel();
                    _debounce = Timer(
                      const Duration(milliseconds: 350),
                      () => setState(() => _query = (search: text, status: _query.status)),
                    );
                  },
                ),
              ),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: _query.status,
                  decoration: const InputDecoration(labelText: AppStrings.status),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text(AppStrings.all)),
                    for (final s in patientStatuses)
                      DropdownMenuItem<String?>(
                        value: s,
                        child: Text(AppStrings.patientStatuses[s]!),
                      ),
                  ],
                  onChanged: (v) => setState(() => _query = (search: _query.search, status: v)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: AsyncView(
            value: value,
            onRetry: () => ref.invalidate(patientListProvider(_query)),
            builder: (page) {
              if (page.items.isEmpty) return const Center(child: Text(AppStrings.noData));
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                itemCount: page.items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final p = page.items[i];
                  return Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      key: Key('patient-row-${p.id}'),
                      leading: CircleAvatar(child: Text(p.fullName.isEmpty ? '?' : p.fullName[0])),
                      title: Text(p.fullName),
                      subtitle: Text(
                        [
                          if (p.phone.isNotEmpty) p.phone,
                          if (p.age != null) '${AppStrings.age}: ${p.age}',
                          if (p.lastExamDate != null)
                            '${AppStrings.lastExam}: ${Formatters.date(p.lastExamDate)}',
                        ].join('   •   '),
                      ),
                      trailing: Chip(
                        label: Text(AppStrings.patientStatuses[p.status] ?? p.status),
                        backgroundColor: theme.colorScheme.secondaryContainer,
                      ),
                      onTap: () => context.go(AppRoutes.patientDetail(p.id)),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
