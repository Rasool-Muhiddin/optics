import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters/formatters.dart';
import '../../core/router/app_routes.dart';
import '../../core/strings/app_strings.dart';
import '../../data/cache/json_cache_dao.dart';
import '../../data/repositories/jobs_repository.dart';
import '../../models/jobs.dart';
import '../../widgets/common.dart';
import 'job_actions.dart';
import 'job_form_dialog.dart';
import 'jobs_providers.dart';

/// Kanban board of customer jobs; overdue cards are highlighted.
class JobsBoardScreen extends ConsumerStatefulWidget {
  const JobsBoardScreen({super.key});

  @override
  ConsumerState<JobsBoardScreen> createState() => _JobsBoardScreenState();
}

class _JobsBoardScreenState extends ConsumerState<JobsBoardScreen> {
  JobQuery _q = (search: '', patientId: null, overdueOnly: false);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(jobBoardProvider(_q));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: AppStrings.jobsTitle,
          cacheTables: const [CacheTables.jobs],
          actions: [
            FilledButton.icon(
              key: const Key('new-job'),
              icon: const Icon(Icons.add),
              label: const Text(AppStrings.newJob),
              onPressed: () async {
                final job = await showDialog<Job>(
                  context: context,
                  builder: (_) => const JobFormDialog(),
                );
                if (job != null) invalidateJobs(ref);
              },
            ),
          ],
        ),
        FilterBar(
          children: [
            SizedBox(
              width: 300,
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '${AppStrings.jobNumber} / ${AppStrings.name} / ${AppStrings.phone}',
                ),
                onChanged: (text) {
                  _debounce?.cancel();
                  _debounce = Timer(
                    const Duration(milliseconds: 300),
                    () => setState(
                      () => _q = (search: text, patientId: null, overdueOnly: _q.overdueOnly),
                    ),
                  );
                },
              ),
            ),
            FilterChip(
              key: const Key('jobs-overdue-only'),
              label: const Text(AppStrings.overdueOnly),
              selected: _q.overdueOnly,
              onSelected: (v) =>
                  setState(() => _q = (search: _q.search, patientId: null, overdueOnly: v)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: AsyncView(
            value: value,
            skeleton: true,
            onRetry: () => ref.invalidate(jobBoardProvider(_q)),
            builder: (jobs) {
              final today = DateTime.now();
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  0,
                  AppSpacing.page,
                  AppSpacing.page,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final status in JobStatuses.board)
                      _Column(
                        status: status,
                        jobs: jobs.where((j) => j.status == status).toList()
                          ..sort((a, b) {
                            final ao = a.overdueOn(today), bo = b.overdueOn(today);
                            if (ao != bo) return ao ? -1 : 1;
                            return (a.promisedDate ?? DateTime(9999)).compareTo(
                              b.promisedDate ?? DateTime(9999),
                            );
                          }),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.status, required this.jobs});

  final String status;
  final List<Job> jobs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final tone = StatusTones.job(status);
    final c = colors.tone(tone, theme.colorScheme);
    return Container(
      key: Key('job-column-$status'),
      width: 284,
      margin: const EdgeInsetsDirectional.only(end: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.fg, width: 3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${AppStrings.jobStatuses[status]} (${jobs.length})',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: c.fg, shape: BoxShape.circle),
                ),
              ],
            ),
          ),
          if (jobs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Icon(Icons.inbox_outlined, color: colors.textMuted.withValues(alpha: 0.5)),
            ),
          for (final job in jobs) JobCard(job: job),
        ],
      ),
    );
  }
}

class JobCard extends ConsumerWidget {
  const JobCard({super.key, required this.job});

  final Job job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final overdue = job.overdueOn(DateTime.now());
    final next = JobStatuses.next[job.status];
    return Container(
      key: Key('job-card-${job.id}'),
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: overdue ? colors.danger : colors.border,
          width: overdue ? 1.5 : 1,
        ),
        boxShadow: colors.cardShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: AppRadius.mdAll,
          onTap: () => context.go(AppRoutes.jobDetail(job.id)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    NumText('#${job.number}', bold: true, color: theme.colorScheme.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        job.patientName,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (overdue)
                      StatusBadge(
                        key: Key('job-overdue-${job.id}'),
                        label: AppStrings.overdue,
                        tone: Tone.danger,
                        icon: Icons.schedule,
                        dense: true,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                if (job.promisedDate != null)
                  Row(
                    children: [
                      Icon(
                        Icons.event_outlined,
                        size: 14,
                        color: overdue ? colors.danger : colors.textMuted,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          '${AppStrings.promisedDate}: ${Formatters.date(job.promisedDate)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: overdue ? colors.danger : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                if (job.lensName.isNotEmpty)
                  Text(
                    job.lensName,
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (job.frameSource == 'customer')
                  Text(AppStrings.frameSources['customer']!, style: theme.textTheme.bodySmall),
                const SizedBox(height: AppSpacing.xs),
                const Divider(),
                Row(
                  children: [
                    IconButton(
                      tooltip: AppStrings.printJobTicket,
                      icon: const Icon(Icons.print_outlined, size: 18),
                      onPressed: () => printJobTicket(context, ref, job),
                    ),
                    if (!job.isFinal)
                      IconButton(
                        tooltip: AppStrings.changeStatus,
                        icon: const Icon(Icons.more_horiz, size: 18),
                        onPressed: () => chooseJobStatus(context, ref, job),
                      ),
                    const Spacer(),
                    if (next != null)
                      Flexible(
                        flex: 4,
                        child: TextButton.icon(
                          key: Key('job-next-${job.id}'),
                          onPressed: () => moveJob(context, ref, job, next),
                          icon: const Icon(Icons.arrow_back, size: 16),
                          label: Text(
                            '${AppStrings.moveTo} ${AppStrings.jobStatuses[next]}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
