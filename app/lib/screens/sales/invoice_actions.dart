import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/strings/app_strings.dart';
import '../../models/sales.dart';
import '../../services/printing/invoice_pdf.dart';
import '../../services/printing/print_service.dart';
import '../../widgets/common.dart';

Future<void> printInvoice(
  BuildContext context,
  WidgetRef ref,
  Invoice invoice,
  InvoicePaper paper,
) async {
  try {
    final service = ref.read(printServiceProvider);
    final bytes = await InvoicePdf(await service.kit()).build(invoice, paper);
    await service.printPdf(
      bytes,
      name: '${AppStrings.invoice} ${invoice.number}',
      format: paper.format,
    );
  } catch (e) {
    if (context.mounted) showErrorSnack(context, e);
  }
}

/// A4 / A5 / thermal print buttons.
class InvoicePrintButtons extends ConsumerWidget {
  const InvoicePrintButtons({super.key, required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (paper, label) in const [
          (InvoicePaper.thermal80, AppStrings.printThermal),
          (InvoicePaper.a5, AppStrings.printA5),
          (InvoicePaper.a4, AppStrings.printA4),
        ])
          OutlinedButton.icon(
            key: Key('print-invoice-${paper.name}'),
            icon: const Icon(Icons.print_outlined),
            label: Text(label),
            onPressed: () => printInvoice(context, ref, invoice, paper),
          ),
      ],
    );
  }
}

/// Amount + method dialog. Returns `(amount, method)` or null.
Future<({String amount, String method})?> askPayment(
  BuildContext context, {
  String? maxAmount,
  String? hint,
}) => showDialog<({String amount, String method})>(
  context: context,
  builder: (_) =>
      _PaymentDialog(initialAmount: maxAmount == null ? '' : _plain(maxAmount), hint: hint),
);

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.initialAmount, this.hint});

  final String initialAmount;
  final String? hint;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final _amount = TextEditingController(text: widget.initialAmount);
  final _formKey = GlobalKey<FormState>();
  String _method = 'cash';

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormDialog(
      title: AppStrings.receivePayment,
      width: 380,
      onSave: () {
        if (_formKey.currentState!.validate()) {
          Navigator.of(context).pop((amount: _amount.text.trim(), method: _method));
        }
      },
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.hint != null)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(widget.hint!)),
            TextFormField(
              key: const Key('payment-amount'),
              controller: _amount,
              autofocus: true,
              inputFormatters: Inputs.money,
              decoration: const InputDecoration(labelText: AppStrings.amount),
              validator: (v) {
                final n = double.tryParse(v?.trim() ?? '');
                return n == null || n <= 0 ? AppStrings.invalidNumber : null;
              },
            ),
            const SizedBox(height: 12),
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
    );
  }
}

String _plain(String money) {
  final n = double.tryParse(money);
  if (n == null) return money;
  return n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(2);
}
