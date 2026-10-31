import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/cache/json_cache_dao.dart';
import '../../core/formatters/formatters.dart';
import '../../core/router/app_routes.dart';
import '../../core/strings/app_strings.dart';
import '../../models/jobs.dart';
import '../../models/purchasing.dart';
import '../../services/auth_controller.dart';
import '../orders/order_form_dialog.dart';
import '../orders/orders_providers.dart';
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
    final canManageInventory = ref.watch(sessionProvider)?.canManageInventory ?? false;
    return AsyncView(
      value: ref.watch(jobProvider(jobId)),
      onRetry: () => ref.invalidate(jobProvider(jobId)),
      builder: (job) {
        final overdue = job.overdueOn(DateTime.now());
        final rx = job.prescription;
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            PageHeader(
              title: '${AppStrings.job} #${job.number} — ${job.patientName}',
              cacheTables: const [CacheTables.jobs],
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
                if (!job.isFinal && canManageInventory)
                  OutlinedButton.icon(
                    key: const Key('job-order-lens'),
                    icon: const Icon(Icons.local_shipping_outlined),
                    label: const Text(AppStrings.orderForJob),
                    onPressed: () async {
                      final order = await showDialog<SupplierOrder>(
                        context: context,
                        builder: (_) => OrderFormDialog(job: job),
                      );
                      if (order != null) {
                        invalidateJobs(ref, job.id);
                        invalidateOrders(ref);
                      }
                    },
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
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionCard(
                    title: '${AppStrings.job} #${job.number}',
                    icon: Icons.work_outline,
                    borderColor: overdue ? AppColors.of(context).danger : null,
                    actions: [
                      if (overdue)
                        const StatusBadge(
                          label: AppStrings.overdue,
                          tone: Tone.danger,
                          icon: Icons.schedule,
                        ),
                      StatusBadge(
                        label: AppStrings.jobStatuses[job.status] ?? job.status,
                        tone: StatusTones.job(job.status),
                      ),
                    ],
                    child: Padding(
                      padding: EdgeInsets.zero,
                      child: Wrap(
                        spacing: AppSpacing.lg,
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
                          if (job.frameSource == 'lab' && job.invoiceId == null && !job.isFinal)
                            const Padding(
                              key: Key('job-frame-no-invoice'),
                              padding: EdgeInsets.only(top: AppSpacing.sm),
                              child: NoticeBox(
                                message: AppStrings.frameNoInvoiceWarning,
                                tone: Tone.danger,
                                icon: Icons.warning_amber_outlined,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (rx != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    SectionCard(
                      title: AppStrings.linkedPrescription,
                      icon: Icons.description_outlined,
                      actions: [
                        TextButton.icon(
                          icon: const Icon(Icons.folder_shared_outlined, size: 18),
                          onPressed: () => context.go(AppRoutes.patientDetail(job.patientId)),
                          label: const Text(AppStrings.patientsTitle),
                        ),
                      ],
                      child: Text(
                        rx.summary,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontFeatures: AppText.tabular,
                        ),
                      ),
                    ),
                  ],
                  if (job.supplierOrders.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    SectionCard(
                      title: AppStrings.supplierOrdersOfJob,
                      icon: Icons.local_shipping_outlined,
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                      child: Column(
                        children: [
                          for (final o in job.supplierOrders)
                            ListTile(
                              trailing: StatusBadge(
                                label: AppStrings.label(AppStrings.orderStatuses, o.status),
                                tone: StatusTones.order(o.status),
                                dense: true,
                              ),
                              key: Key('job-order-${o.id}'),
                              dense: true,
                              leading: const Icon(Icons.local_shipping_outlined),
                              title: Text('#${o.number} — ${o.supplierName}'),
                              subtitle: Text(
                                [
                                  AppStrings.label(AppStrings.orderStatuses, o.status),
                                  if (o.expectedDate != null)
                                    '${AppStrings.expectedDate}: ${Formatters.date(o.expectedDate)}',
                                ].join('   •   '),
                              ),
                              onTap: () => context.go(AppRoutes.orderDetail(o.id)),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  SectionCard(
                    title: AppStrings.statusHistory,
                    icon: Icons.history,
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Column(
                      children: [
                        for (final log in job.logs)
                          ListTile(
                            dense: true,
                            leading: IconTile(
                              icon: Icons.arrow_back,
                              tone: StatusTones.job(log.toStatus),
                              size: 30,
                            ),
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
              ),
            ),
          ],
        );
      },
    );
  }
}
