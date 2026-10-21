import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';

import '../../core/formatters/formatters.dart';
import '../../core/strings/app_strings.dart';
import '../../data/repositories/jobs_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../models/jobs.dart';
import '../../services/printing/job_ticket_pdf.dart';
import '../../services/printing/print_service.dart';
import '../../widgets/common.dart';
import '../sales/sales_providers.dart';
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
  if (to == JobStatuses.delivered && !await _confirmDelivery(context, ref, job)) return;
  if (!context.mounted) return;
  try {
    await ref.read(jobsRepositoryProvider).changeStatus(job.id, to, note: note);
    invalidateJobs(ref, job.id);
  } catch (e) {
    if (context.mounted) showErrorSnack(context, e);
  }
}

/// Before delivering: an unpaid invoice balance can be collected in the same step (or the
/// glasses delivered without it); a lab frame with no invoice was never taken out of stock.
/// Returns false when the user backs out (or the payment failed).
Future<bool> _confirmDelivery(BuildContext context, WidgetRef ref, Job job) async {
  final invoiceId = job.invoiceId;
  if (invoiceId == null) {
    if (job.frameSource != 'lab') return true;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${AppStrings.changeStatus} — #${job.number}'),
        content: const Text(AppStrings.frameNoInvoiceWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            key: const Key('deliver-anyway'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AppStrings.deliverAnyway),
          ),
        ],
      ),
    );
    return go ?? false;
  }
  final balance = double.tryParse(job.invoiceBalance ?? '') ?? 0;
  if (balance <= 0) return true;
  final choice = await showDialog<({String amount, String method})?>(
    context: context,
    builder: (_) => _DeliveryPaymentDialog(job: job),
  );
  if (choice == null) return false; // cancelled
  if (choice.amount.isEmpty) return true; // deliver without payment
  try {
    await ref
        .read(salesRepositoryProvider)
        .addPayment(invoiceId, amount: choice.amount, method: choice.method);
    ref.invalidate(invoiceProvider(invoiceId));
    ref.invalidate(invoiceListProvider);
    ref.invalidate(creditCustomersProvider);
    return true;
  } catch (e) {
    if (context.mounted) showErrorSnack(context, e);
    return false;
  }
}

/// Returns null = cancel, amount '' = deliver without paying, else the payment to record.
class _DeliveryPaymentDialog extends StatefulWidget {
  const _DeliveryPaymentDialog({required this.job});

  final Job job;

  @override
  State<_DeliveryPaymentDialog> createState() => _DeliveryPaymentDialogState();
}

class _DeliveryPaymentDialogState extends State<_DeliveryPaymentDialog> {
  late final _amount = TextEditingController(text: _plain(widget.job.invoiceBalance ?? ''));
  String _method = 'cash';
  final _formKey = GlobalKey<FormState>();

  static String _plain(String money) {
    final n = double.tryParse(money);
    if (n == null) return money;
    return n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toString();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AppStrings.unpaidOnDelivery),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${AppStrings.unpaidOnDeliveryHint} #${widget.job.invoiceNumber ?? ''}: '
                '${Formatters.money(widget.job.invoiceBalance)}',
                key: const Key('delivery-balance'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('delivery-amount'),
                controller: _amount,
                inputFormatters: Inputs.money,
                decoration: const InputDecoration(labelText: AppStrings.amount),
                validator: Inputs.moneyValidator,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _method,
                decoration: const InputDecoration(labelText: AppStrings.paymentMethod),
                items: [
                  for (final m in AppStrings.paymentMethods.entries)
                    DropdownMenuItem(value: m.key, child: Text(m.value)),
                ],
                onChanged: (v) => setState(() => _method = v ?? 'cash'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.cancel),
        ),
        OutlinedButton(
          key: const Key('deliver-without-payment'),
          onPressed: () => Navigator.of(context).pop((amount: '', method: _method)),
          child: const Text(AppStrings.deliverWithoutPayment),
        ),
        FilledButton(
          key: const Key('pay-and-deliver'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop((amount: _amount.text.trim(), method: _method));
          },
          child: const Text(AppStrings.payAndDeliver),
        ),
      ],
    );
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
