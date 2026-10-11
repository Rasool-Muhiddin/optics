import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters/formatters.dart';
import '../../core/router/app_routes.dart';
import '../../core/strings/app_strings.dart';
import '../../models/jobs.dart';
import '../../widgets/common.dart';
import 'job_actions.dart';
import 'job_form_dialog.dart';
import 'jobs_providers.dart';

/// Job details, status history, status changes, edit and ticket printing.
class JobDetailScreen extends ConsumerWidget {
  const JobDetailScreen({super.key, required this.jobId});

  final int jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView(
      value: ref.watch(jobProvider(jobId)),
      onRetry: () => ref.invalidate(jobProvider(jobId)),
      builder: (job) {
        final theme = Theme.of(context);
        final overdue = job.overdueOn(DateTime.now());
        final rx = job.prescription;
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            PageHeader(
              title: '${AppStrings.job} #${job.number} — ${job.patientName}',
              leading: IconButton(
                tooltip: AppStrings.back,
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => context.go(AppRoutes.jobs),
              ),
              actions: [
                OutlinedButton.icon(
                  key: const Key('job-print'),
                  icon: const Icon(Icons.print_outlined),
                  label: const Text(AppStrings.printJobTicket),
                  onPressed: () => printJobTicket(context, ref, job),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.receipt_outlined),
                  label: const Text('80mm'),
                  onPressed: () => printJobTicket(context, ref, job, thermal: true),
                ),
                if (!job.isFinal) ...[
                  OutlinedButton.icon(
                    key: const Key('job-edit'),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text(AppStrings.edit),
                    onPressed: () async {
                      final saved = await showDialog<Job>(
                        context: context,
                        builder: (_) => JobFormDialog(job: job),
                      );
                      if (saved != null) invalidateJobs(ref, job.id);
                    },
                  ),
                  FilledButton.icon(
                    key: const Key('job-change-status'),
                    icon: const Icon(Icons.sync_alt),
                    label: const Text(AppStrings.changeStatus),
                    onPressed: () => chooseJobStatus(context, ref, job),
                  ),
                ],
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    shape: overdue
                        ? RoundedRectangleBorder(
                            side: BorderSide(color: theme.colorScheme.error, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          )
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                        spacing: 16,
                        children: [
                          InfoTile(
                            label: AppStrings.status,
                            value:
                                '${AppStrings.jobStatuses[job.status] ?? job.status}'
                                '${overdue ? ' — ${AppStrings.overdue}' : ''}',
                          ),
                          InfoTile(
                            label: AppStrings.promisedDate,
                            value: Formatters.date(job.promisedDate),
                          ),
                          InfoTile(label: AppStrings.phone, value: job.patientPhone),
                          InfoTile(
                            label: AppStrings.frame,
                            value: [
                              AppStrings.frameSources[job.frameSource] ?? '',
                              job.frameName,
                              job.frameNotes,
                            ].where((s) => s.isNotEmpty).join(' — '),
                            width: 320,
                          ),
                          InfoTile(label: AppStrings.lens, value: job.lensName),
                          if (job.lensOdLabel.isNotEmpty)
                            InfoTile(label: AppStrings.lensOd, value: job.lensOdLabel),
                          if (job.lensOsLabel.isNotEmpty)
                            InfoTile(label: AppStrings.lensOs, value: job.lensOsLabel),
                          if (job.lensNotes.isNotEmpty)
                            InfoTile(label: AppStrings.lensNotes, value: job.lensNotes),
                          if (job.invoiceNumber != null)
                            InfoTile(
                              label: AppStrings.linkedInvoice,
                              value:
                                  '#${job.invoiceNumber}'
                                  '${(double.tryParse(job.invoiceBalance ?? '') ?? 0) > 0 ? ' — ${AppStrings.balance}: ${Formatters.money(job.invoiceBalance)}' : ''}',
                            ),
                          if (job.deliveredAt != null)
                            InfoTile(
                              label: AppStrings.deliveredAt,
                              value: Formatters.dateTime(job.deliveredAt),
                            ),
                          if (job.notes.isNotEmpty)
                            InfoTile(label: AppStrings.notes, value: job.notes, width: 420),
                        ],
                      ),
                    ),
                  ),
                  if (rx != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        title: const Text(AppStrings.linkedPrescription),
                        subtitle: Text(
                          rx.summary,
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.right,
                        ),
                        trailing: TextButton(
                          onPressed: () => context.go(AppRoutes.patientDetail(job.patientId)),
                          child: const Text(AppStrings.patientsTitle),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(AppStrings.statusHistory, style: theme.textTheme.titleMedium),
                  for (final log in job.logs)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.history),
                      title: Text(
                        log.fromStatus.isEmpty
                            ? AppStrings.jobStatuses[log.toStatus] ?? log.toStatus
                            : '${AppStrings.jobStatuses[log.fromStatus] ?? log.fromStatus} ← '
                                  '${AppStrings.jobStatuses[log.toStatus] ?? log.toStatus}',
                      ),
                      subtitle: Text(
                        [
                          Formatters.dateTime(log.createdAt),
                          log.changedByName,
                          log.note,
                        ].where((s) => s.isNotEmpty).join('   •   '),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
