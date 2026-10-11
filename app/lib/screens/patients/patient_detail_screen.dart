import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';

import '../../core/formatters/formatters.dart';
import '../../core/router/app_routes.dart';
import '../../core/strings/app_strings.dart';
import '../../data/repositories/patients_repository.dart';
import '../../models/patients.dart';
import '../../services/printing/patient_pdfs.dart';
import '../../services/printing/print_service.dart';
import '../../widgets/common.dart';
import '../pos/pos_controller.dart';
import 'exam_dialogs.dart';
import 'patient_form_dialog.dart';
import 'patients_providers.dart';

/// Extra actions other phases add to the patient profile (e.g. "new sale", "new job").
typedef PatientAction = ({String label, IconData icon, void Function(BuildContext, Patient) onTap});

final patientExtraActionsProvider = Provider<List<PatientAction>>(
  (ref) => [
    (
      label: AppStrings.sell,
      icon: Icons.point_of_sale,
      onTap: (context, patient) {
        ref.read(posControllerProvider.notifier).setPatient(patient);
        context.go(AppRoutes.pos);
      },
    ),
  ],
);

/// Patient profile: details, exam history (with Rx) and prescriptions; printing works offline.
class PatientDetailScreen extends ConsumerWidget {
  const PatientDetailScreen({super.key, required this.patientId});

  final int patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView(
      value: ref.watch(patientProvider(patientId)),
      onRetry: () => invalidatePatient(ref, patientId),
      builder: (patient) => DefaultTabController(
        length: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: patient.fullName,
              leading: IconButton(
                tooltip: AppStrings.back,
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => context.go(AppRoutes.patients),
              ),
              actions: [
                for (final a in ref.watch(patientExtraActionsProvider))
                  OutlinedButton.icon(
                    icon: Icon(a.icon),
                    label: Text(a.label),
                    onPressed: () => a.onTap(context, patient),
                  ),
                OutlinedButton.icon(
                  key: const Key('edit-patient'),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text(AppStrings.edit),
                  onPressed: () async {
                    final saved = await showDialog<Patient>(
                      context: context,
                      builder: (_) => PatientFormDialog(patient: patient),
                    );
                    if (saved != null) invalidatePatient(ref, patientId);
                  },
                ),
                OutlinedButton.icon(
                  key: const Key('new-rx'),
                  icon: const Icon(Icons.description_outlined),
                  label: const Text(AppStrings.newPrescription),
                  onPressed: () async {
                    final rx = await showDialog<Prescription>(
                      context: context,
                      builder: (_) => PrescriptionFormDialog(patient: patient),
                    );
                    if (rx != null) invalidatePatient(ref, patientId);
                  },
                ),
                FilledButton.icon(
                  key: const Key('new-exam'),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text(AppStrings.newExam),
                  onPressed: () async {
                    final exam = await showDialog<EyeExam>(
                      context: context,
                      builder: (_) => ExamFormDialog(patient: patient),
                    );
                    if (exam != null) invalidatePatient(ref, patientId);
                  },
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 16,
                    children: [
                      InfoTile(label: AppStrings.phone, value: patient.phone),
                      InfoTile(
                        label: AppStrings.age,
                        value: patient.age == null ? '' : '${patient.age}',
                      ),
                      InfoTile(
                        label: AppStrings.gender,
                        value: AppStrings.genders[patient.gender] ?? '',
                      ),
                      InfoTile(
                        label: AppStrings.status,
                        value: AppStrings.patientStatuses[patient.status] ?? patient.status,
                      ),
                      InfoTile(label: AppStrings.address, value: patient.address),
                      if (patient.notes.isNotEmpty)
                        InfoTile(label: AppStrings.notes, value: patient.notes, width: 420),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const TabBar(
              tabs: [
                Tab(text: AppStrings.exams),
                Tab(text: AppStrings.prescriptions),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _ExamsTab(patient: patient),
                  _PrescriptionsTab(patient: patient),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _print(
  BuildContext context,
  WidgetRef ref,
  Future<Uint8List> Function(PatientPdfs pdfs) build,
  String name,
  PdfPageFormat format,
) async {
  try {
    final service = ref.read(printServiceProvider);
    final pdfs = PatientPdfs(await service.kit());
    final bytes = await build(pdfs);
    await service.printPdf(bytes, name: name, format: format);
  } catch (e) {
    if (context.mounted) showErrorSnack(context, e);
  }
}

class _ExamsTab extends ConsumerWidget {
  const _ExamsTab({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView(
      value: ref.watch(patientExamsProvider(patient.id)),
      onRetry: () => ref.invalidate(patientExamsProvider(patient.id)),
      builder: (exams) {
        if (exams.isEmpty) return const Center(child: Text(AppStrings.noExams));
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            for (final exam in exams)
              Card(
                key: Key('exam-${exam.id}'),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(
                            Formatters.date(exam.examDate),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(width: 12),
                          if (exam.examinedByName.isNotEmpty)
                            Text('${AppStrings.examinedBy}: ${exam.examinedByName}'),
                          if (exam.isVoid) ...[
                            const SizedBox(width: 12),
                            Chip(label: Text('${AppStrings.voided}: ${exam.voidReason}')),
                          ],
                          const Spacer(),
                          IconButton(
                            key: Key('print-report-${exam.id}'),
                            tooltip: AppStrings.printExamReport,
                            icon: const Icon(Icons.print_outlined),
                            onPressed: () => _print(
                              context,
                              ref,
                              (pdfs) => pdfs.examReport(patient: patient, exam: exam),
                              AppStrings.examReportTitle,
                              PdfPageFormat.a4,
                            ),
                          ),
                          if (exam.prescription != null)
                            IconButton(
                              tooltip: AppStrings.printPrescription,
                              icon: const Icon(Icons.receipt_long_outlined),
                              onPressed: () => _print(
                                context,
                                ref,
                                (pdfs) =>
                                    pdfs.prescription(patient: patient, rx: exam.prescription!),
                                AppStrings.prescriptionTitle,
                                PdfPageFormat.a5,
                              ),
                            ),
                          if (!exam.isVoid) ...[
                            IconButton(
                              tooltip: AppStrings.edit,
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () async {
                                final saved = await showDialog<EyeExam>(
                                  context: context,
                                  builder: (_) => ExamFormDialog(patient: patient, exam: exam),
                                );
                                if (saved != null) invalidatePatient(ref, patient.id);
                              },
                            ),
                            IconButton(
                              tooltip: AppStrings.voidRecord,
                              icon: const Icon(Icons.block),
                              onPressed: () async {
                                final reason = await askVoidReason(context);
                                if (reason == null) return;
                                try {
                                  await ref
                                      .read(patientsRepositoryProvider)
                                      .voidExam(exam.id, reason);
                                  invalidatePatient(ref, patient.id);
                                } catch (e) {
                                  if (context.mounted) showErrorSnack(context, e);
                                }
                              },
                            ),
                          ],
                        ],
                      ),
                      if (exam.diagnosis.isNotEmpty)
                        Text('${AppStrings.diagnosis}: ${exam.diagnosis}'),
                      if (exam.vaOd.isNotEmpty || exam.vaOs.isNotEmpty)
                        Text(
                          'VA  OD ${exam.vaOd}  |  OS ${exam.vaOs}',
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.right,
                        ),
                      if (exam.prescription != null)
                        Text(
                          exam.prescription!.summary,
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PrescriptionsTab extends ConsumerWidget {
  const _PrescriptionsTab({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView(
      value: ref.watch(patientPrescriptionsProvider(patient.id)),
      onRetry: () => ref.invalidate(patientPrescriptionsProvider(patient.id)),
      builder: (list) {
        if (list.isEmpty) return const Center(child: Text(AppStrings.noPrescriptions));
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            for (final rx in list)
              Card(
                key: Key('rx-${rx.id}'),
                child: ListTile(
                  title: Text(
                    rx.summary,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.right,
                  ),
                  subtitle: Text(
                    [
                      Formatters.date(rx.rxDate),
                      AppStrings.usages[rx.usage] ?? rx.usage,
                      if (rx.prescribedBy.isNotEmpty) rx.prescribedBy,
                      if (rx.isVoid) '${AppStrings.voided}: ${rx.voidReason}',
                    ].join('   •   '),
                  ),
                  trailing: Wrap(
                    children: [
                      IconButton(
                        key: Key('print-rx-${rx.id}'),
                        tooltip: AppStrings.printPrescription,
                        icon: const Icon(Icons.print_outlined),
                        onPressed: () => _print(
                          context,
                          ref,
                          (pdfs) => pdfs.prescription(patient: patient, rx: rx),
                          AppStrings.prescriptionTitle,
                          PdfPageFormat.a5,
                        ),
                      ),
                      if (!rx.isVoid && rx.examId == null) ...[
                        IconButton(
                          tooltip: AppStrings.edit,
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () async {
                            final saved = await showDialog<Prescription>(
                              context: context,
                              builder: (_) =>
                                  PrescriptionFormDialog(patient: patient, prescription: rx),
                            );
                            if (saved != null) invalidatePatient(ref, patient.id);
                          },
                        ),
                        IconButton(
                          tooltip: AppStrings.voidRecord,
                          icon: const Icon(Icons.block),
                          onPressed: () async {
                            final reason = await askVoidReason(context);
                            if (reason == null) return;
                            try {
                              await ref
                                  .read(patientsRepositoryProvider)
                                  .voidPrescription(rx.id, reason);
                              invalidatePatient(ref, patient.id);
                            } catch (e) {
                              if (context.mounted) showErrorSnack(context, e);
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
