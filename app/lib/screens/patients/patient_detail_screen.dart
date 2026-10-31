import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';

import '../../core/formatters/formatters.dart';
import '../../core/router/app_routes.dart';
import '../../core/strings/app_strings.dart';
import '../../data/cache/json_cache_dao.dart';
import '../../data/repositories/patients_repository.dart';
import '../../models/jobs.dart';
import '../../models/patients.dart';
import '../../services/printing/patient_pdfs.dart';
import '../../services/printing/print_service.dart';
import '../../widgets/common.dart';
import '../jobs/job_form_dialog.dart';
import '../jobs/jobs_board_screen.dart' show JobCard;
import '../jobs/jobs_providers.dart';
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
    (
      label: AppStrings.newJob,
      icon: Icons.work_outline,
      onTap: (context, patient) async {
        final job = await showDialog<Job>(
          context: context,
          builder: (_) => JobFormDialog(patient: patient),
        );
        if (job != null && context.mounted) context.go(AppRoutes.jobDetail(job.id));
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
        length: 3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: patient.fullName,
              cacheTables: const [
                CacheTables.patients,
                CacheTables.exams,
                CacheTables.prescriptions,
              ],
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
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: SectionCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InitialsAvatar(name: patient.fullName, size: 56),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Wrap(
                        spacing: AppSpacing.xl,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                            child: StatusBadge(
                              label: AppStrings.patientStatuses[patient.status] ?? patient.status,
                              tone: StatusTones.patient(patient.status),
                            ),
                          ),
                          InfoTile(label: AppStrings.phone, value: patient.phone),
                          InfoTile(
                            label: AppStrings.age,
                            value: patient.age == null ? '' : '${patient.age}',
                          ),
                          // Gender/address are no longer asked in the form; shown for older files and referrals.
                          if (patient.gender.isNotEmpty)
                            InfoTile(
                              label: AppStrings.gender,
                              value: AppStrings.genders[patient.gender] ?? '',
                            ),
                          if (patient.address.isNotEmpty)
                            InfoTile(label: AppStrings.address, value: patient.address),
                          if (patient.notes.isNotEmpty)
                            InfoTile(label: AppStrings.notes, value: patient.notes, width: 420),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  _IconTab(icon: Icons.visibility_outlined, text: AppStrings.exams),
                  _IconTab(icon: Icons.description_outlined, text: AppStrings.prescriptions),
                  _IconTab(icon: Icons.work_outline, text: AppStrings.jobsOfPatient),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _ExamsTab(patient: patient),
                  _PrescriptionsTab(patient: patient),
                  _JobsTab(patient: patient),
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
        if (exams.isEmpty) {
          return const EmptyState(icon: Icons.visibility_outlined, title: AppStrings.noExams);
        }
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.page),
          children: [
            for (final exam in exams)
              Card(
                key: Key('exam-${exam.id}'),
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                color: exam.isVoid ? AppColors.of(context).surfaceMuted : null,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.sm,
                    AppSpacing.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const IconTile(icon: Icons.event_note_outlined, size: 34),
                          const SizedBox(width: AppSpacing.md),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                NumText(Formatters.date(exam.examDate), bold: true),
                                if (exam.examinedByName.isNotEmpty)
                                  Text(
                                    '${AppStrings.examinedBy}: ${exam.examinedByName}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                          if (exam.isVoid) ...[
                            const SizedBox(width: AppSpacing.md),
                            Flexible(
                              child: StatusBadge(
                                label: '${AppStrings.voided}: ${exam.voidReason}',
                                tone: Tone.danger,
                                icon: Icons.block,
                              ),
                            ),
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
                      if (exam.prescription != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        RxSummaryBox(text: exam.prescription!.summary),
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

class _PrescriptionsTab extends ConsumerWidget {
  const _PrescriptionsTab({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView(
      value: ref.watch(patientPrescriptionsProvider(patient.id)),
      onRetry: () => ref.invalidate(patientPrescriptionsProvider(patient.id)),
      builder: (list) {
        if (list.isEmpty) {
          return const EmptyState(
            icon: Icons.description_outlined,
            title: AppStrings.noPrescriptions,
          );
        }
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.page),
          children: [
            for (final rx in list)
              Card(
                key: Key('rx-${rx.id}'),
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                color: rx.isVoid ? AppColors.of(context).surfaceMuted : null,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.xs,
                  ),
                  leading: IconTile(
                    icon: Icons.description_outlined,
                    tone: rx.isVoid ? Tone.neutral : Tone.primary,
                    size: 38,
                  ),
                  title: Text(
                    rx.summary,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontFeatures: AppText.tabular,
                      fontWeight: FontWeight.w600,
                    ),
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

class _JobsTab extends ConsumerWidget {
  const _JobsTab({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView(
      value: ref.watch(patientJobsProvider(patient.id)),
      onRetry: () => ref.invalidate(patientJobsProvider(patient.id)),
      builder: (jobs) => jobs.isEmpty
          ? const EmptyState(icon: Icons.work_outline, title: AppStrings.noJobs)
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.page),
              children: [
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: [
                    for (final job in jobs) SizedBox(width: 320, child: JobCard(job: job)),
                  ],
                ),
              ],
            ),
    );
  }
}

/// Tab label with a leading icon (icon and text on one line).
class _IconTab extends StatelessWidget {
  const _IconTab({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Tab(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: AppSpacing.sm),
        Text(text),
      ],
    ),
  );
}

/// Rx summary line (LTR, tabular digits) in a tinted box.
class RxSummaryBox extends StatelessWidget {
  const RxSummaryBox({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
      borderRadius: AppRadius.mdAll,
    ),
    child: Text(
      text,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
      style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: AppText.tabular),
    ),
  );
}
