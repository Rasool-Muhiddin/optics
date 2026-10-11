import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters/formatters.dart';
import '../../core/router/app_routes.dart';
import '../../core/strings/app_strings.dart';
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
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
        ),
        const SizedBox(height: 12),
        Expanded(
          child: AsyncView(
            value: value,
            onRetry: () => ref.invalidate(jobBoardProvider(_q)),
            builder: (jobs) {
              final today = DateTime.now();
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
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
    return Container(
      key: Key('job-column-$status'),
      width: 270,
      margin: const EdgeInsetsDirectional.only(end: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(4),
            child: Text(
              '${AppStrings.jobStatuses[status]} (${jobs.length})',
              style: theme.textTheme.titleSmall,
            ),
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
    final overdue = job.overdueOn(DateTime.now());
    final next = JobStatuses.next[job.status];
    return Card(
      key: Key('job-card-${job.id}'),
      margin: const EdgeInsets.only(top: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: overdue ? BorderSide(color: theme.colorScheme.error, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => context.go(AppRoutes.jobDetail(job.id)),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('#${job.number}', style: theme.textTheme.titleSmall),
                  const SizedBox(width: 8),
                  Expanded(child: Text(job.patientName, overflow: TextOverflow.ellipsis)),
                  if (overdue)
                    Container(
                      key: Key('job-overdue-${job.id}'),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      color: theme.colorScheme.errorContainer,
                      child: Text(AppStrings.overdue, style: theme.textTheme.labelSmall),
                    ),
                ],
              ),
              if (job.promisedDate != null)
                Text(
                  '${AppStrings.promisedDate}: ${Formatters.date(job.promisedDate)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: overdue ? theme.colorScheme.error : null,
                  ),
                ),
              if (job.lensName.isNotEmpty) Text(job.lensName, style: theme.textTheme.bodySmall),
              if (job.frameSource == 'customer')
                Text(AppStrings.frameSources['customer']!, style: theme.textTheme.bodySmall),
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
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
                  if (next != null)
                    TextButton(
                      key: Key('job-next-${job.id}'),
                      onPressed: () => moveJob(context, ref, job, next),
                      child: Text('${AppStrings.moveTo} ${AppStrings.jobStatuses[next]}'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
