import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';

import '../../core/strings/app_strings.dart';
import '../../data/repositories/jobs_repository.dart';
import '../../models/jobs.dart';
import '../../services/printing/job_ticket_pdf.dart';
import '../../services/printing/print_service.dart';
import '../../widgets/common.dart';
import 'jobs_providers.dart';

Future<void> printJobTicket(
  BuildContext context,
  WidgetRef ref,
  Job job, {
  bool thermal = false,
}) async {
  try {
    final service = ref.read(printServiceProvider);
    final bytes = await JobTicketPdf(await service.kit()).build(job, thermal: thermal);
    await service.printPdf(
      bytes,
      name: '${AppStrings.jobTicket} ${job.number}',
      format: thermal ? PdfPageFormat.roll80 : PdfPageFormat.a5,
    );
  } catch (e) {
    if (context.mounted) showErrorSnack(context, e);
  }
}

Future<void> moveJob(
  BuildContext context,
  WidgetRef ref,
  Job job,
  String to, {
  String note = '',
}) async {
  try {
    await ref.read(jobsRepositoryProvider).changeStatus(job.id, to, note: note);
    invalidateJobs(ref, job.id);
  } catch (e) {
    if (context.mounted) showErrorSnack(context, e);
  }
}

/// Lets the user pick any allowed status (with an optional note).
Future<void> chooseJobStatus(BuildContext context, WidgetRef ref, Job job) async {
  final options = JobStatuses.transitions[job.status] ?? const <String>[];
  if (options.isEmpty) return;
  final result = await showDialog<({String status, String note})>(
    context: context,
    builder: (_) => _StatusDialog(job: job, options: options),
  );
  if (result != null && context.mounted) {
    await moveJob(context, ref, job, result.status, note: result.note);
  }
}

class _StatusDialog extends StatefulWidget {
  const _StatusDialog({required this.job, required this.options});

  final Job job;
  final List<String> options;

  @override
  State<_StatusDialog> createState() => _StatusDialogState();
}

class _StatusDialogState extends State<_StatusDialog> {
  late String _status = JobStatuses.next[widget.job.status] ?? widget.options.first;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormDialog(
      title: '${AppStrings.changeStatus} — #${widget.job.number}',
      width: 380,
      onSave: () => Navigator.of(context).pop((status: _status, note: _note.text.trim())),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RadioGroup<String>(
            groupValue: _status,
            onChanged: (v) => setState(() => _status = v ?? _status),
            child: Column(
              children: [
                for (final s in widget.options)
                  RadioListTile<String>(
                    key: Key('status-option-$s'),
                    value: s,
                    title: Text(AppStrings.jobStatuses[s] ?? s),
                  ),
              ],
            ),
          ),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: AppStrings.statusNote),
          ),
        ],
      ),
    );
  }
}
