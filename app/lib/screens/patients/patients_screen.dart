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

  static const _columns = [
    TableCol(AppStrings.name, flex: 4),
    TableCol(AppStrings.phone, flex: 2),
    TableCol(AppStrings.age, flex: 1, numeric: true),
    TableCol(AppStrings.lastExam, flex: 2, numeric: true),
    TableCol(AppStrings.status, flex: 2),
  ];

  @override
  Widget build(BuildContext context) {
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
        FilterBar(
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
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              0,
              AppSpacing.page,
              AppSpacing.page,
            ),
            child: AsyncView(
              value: value,
              skeleton: true,
              onRetry: () => ref.invalidate(patientListProvider(_query)),
              builder: (page) {
                if (page.items.isEmpty) {
                  final filtered = _query.search.isNotEmpty || _query.status != null;
                  return EmptyState(
                    icon: Icons.people_outline,
                    message: filtered ? AppStrings.emptyFilteredHint : null,
                    action: filtered
                        ? null
                        : FilledButton.icon(
                            icon: const Icon(Icons.person_add_alt),
                            label: const Text(AppStrings.addPatient),
                            onPressed: _add,
                          ),
                  );
                }
                return AppDataTable<Patient>(
                  columns: _columns,
                  items: page.items,
                  rowKey: (p) => Key('patient-row-${p.id}'),
                  onTap: (p) => context.go(AppRoutes.patientDetail(p.id)),
                  sortKeys: {
                    0: (p) => p.fullName,
                    2: (p) => p.age ?? -1,
                    3: (p) => p.lastExamDate?.millisecondsSinceEpoch ?? 0,
                  },
                  footer: TableFooter(count: page.items.length),
                  cells: (p) => [
                    TwoLineCell(
                      leading: InitialsAvatar(name: p.fullName, size: 34),
                      title: p.fullName,
                    ),
                    p.phone.isEmpty ? const Text(AppStrings.none) : NumText(p.phone),
                    NumText(p.age == null ? AppStrings.none : '${p.age}'),
                    NumText(
                      p.lastExamDate == null ? AppStrings.none : Formatters.date(p.lastExamDate),
                    ),
                    StatusBadge(
                      label: AppStrings.patientStatuses[p.status] ?? p.status,
                      tone: StatusTones.patient(p.status),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
