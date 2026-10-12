import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters/formatters.dart';
import '../../core/router/app_routes.dart';
import '../../core/strings/app_strings.dart';
import '../../data/repositories/sales_repository.dart';
import '../../services/auth_controller.dart';
import '../../widgets/common.dart';
import '../patients/exam_dialogs.dart' show askVoidReason;
import 'invoice_actions.dart';
import 'sales_providers.dart';

/// Invoice: lines, totals, payments; take a payment, cancel (owner), print.
class InvoiceDetailScreen extends ConsumerWidget {
  const InvoiceDetailScreen({super.key, required this.invoiceId});

  final int invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final isOwner = session?.isOwner ?? false;
    final seesCosts = session?.membership.canViewCosts ?? false;
    return AsyncView(
      value: ref.watch(invoiceProvider(invoiceId)),
      onRetry: () => ref.invalidate(invoiceProvider(invoiceId)),
      builder: (inv) {
        Future<void> pay() async {
          final input = await askPayment(context, maxAmount: inv.balance);
          if (input == null) return;
          try {
            await ref
                .read(salesRepositoryProvider)
                .addPayment(inv.id, amount: input.amount, method: input.method);
            invalidateSales(ref, inv.id);
          } catch (e) {
            if (context.mounted) showErrorSnack(context, e);
          }
        }

        Future<void> cancel() async {
          if (!await confirmDialog(context, AppStrings.cancelInvoiceConfirm)) return;
          if (!context.mounted) return;
          final reason = await askVoidReason(context);
          if (reason == null) return;
          try {
            await ref.read(salesRepositoryProvider).cancel(inv.id, reason);
            invalidateSales(ref, inv.id);
          } catch (e) {
            if (context.mounted) showErrorSnack(context, e);
          }
        }

        final theme = Theme.of(context);
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            PageHeader(
              title: '${AppStrings.invoice} #${inv.number}',
              leading: IconButton(
                tooltip: AppStrings.back,
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => context.go(AppRoutes.invoices),
              ),
              actions: [
                if (inv.hasBalance)
                  FilledButton.icon(
                    key: const Key('invoice-pay'),
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text(AppStrings.addPayment),
                    onPressed: pay,
                  ),
                if (isOwner && !inv.isCancelled)
                  OutlinedButton.icon(
                    key: const Key('invoice-cancel'),
                    icon: const Icon(Icons.block),
                    label: const Text(AppStrings.cancelInvoice),
                    onPressed: cancel,
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                        spacing: 16,
                        children: [
                          InfoTile(label: AppStrings.customer, value: inv.customerLabel),
                          InfoTile(label: AppStrings.phone, value: inv.customerPhone),
                          InfoTile(
                            label: AppStrings.date,
                            value: Formatters.dateTime(inv.createdAt),
                          ),
                          InfoTile(
                            label: AppStrings.paymentType,
                            value: AppStrings.paymentTypes[inv.paymentType] ?? inv.paymentType,
                          ),
                          InfoTile(
                            label: AppStrings.status,
                            value: AppStrings.invoiceStatuses[inv.status] ?? inv.status,
                          ),
                          InfoTile(label: AppStrings.cashier, value: inv.cashierName),
                          if (inv.isCancelled)
                            InfoTile(label: AppStrings.voidReason, value: inv.cancelReason),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final l in inv.lines)
                            ListTile(
                              dense: true,
                              title: Text(l.description),
                              subtitle: Text(
                                '${l.qty} × ${Formatters.money(l.unitPrice)}'
                                '${(double.tryParse(l.discount) ?? 0) > 0 ? '   −${Formatters.money(l.discount)}' : ''}'
                                '${seesCosts && l.unitCost != null ? '   •   ${AppStrings.unitCost}: ${Formatters.money(l.unitCost)}' : ''}',
                              ),
                              trailing: Text(Formatters.money(l.lineTotal)),
                            ),
                          const Divider(),
                          _row(AppStrings.subtotal, inv.subtotal),
                          if ((double.tryParse(inv.discountTotal) ?? 0) > 0)
                            _row(AppStrings.discount, inv.discountTotal),
                          _row(AppStrings.total, inv.total, style: theme.textTheme.titleMedium),
                          _row(AppStrings.paid, inv.paid),
                          _row(
                            AppStrings.balance,
                            inv.balance,
                            style: TextStyle(
                              color: inv.hasBalance ? theme.colorScheme.error : null,
                            ),
                          ),
                          if (seesCosts && inv.profit != null) ...[
                            _row(AppStrings.costTotal, inv.costTotal!),
                            _row(AppStrings.profit, inv.profit!),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(AppStrings.payments, style: theme.textTheme.titleMedium),
                  for (final p in inv.payments)
                    ListTile(
                      dense: true,
                      leading: Icon(p.isVoid ? Icons.block : Icons.check_circle_outline),
                      title: Text(
                        '${Formatters.money(p.amount)} — ${AppStrings.paymentMethods[p.method] ?? p.method}',
                        style: p.isVoid
                            ? const TextStyle(decoration: TextDecoration.lineThrough)
                            : null,
                      ),
                      subtitle: Text(
                        '${Formatters.dateTime(p.paidAt)}   •   ${p.receivedByName}'
                        '${p.isVoid ? '   •   ${AppStrings.voided}: ${p.voidReason}' : ''}',
                      ),
                      trailing: isOwner && !p.isVoid && !inv.isCancelled
                          ? IconButton(
                              tooltip: AppStrings.voidRecord,
                              icon: const Icon(Icons.block),
                              onPressed: () async {
                                final reason = await askVoidReason(context);
                                if (reason == null) return;
                                try {
                                  await ref.read(salesRepositoryProvider).voidPayment(p.id, reason);
                                  invalidateSales(ref, inv.id);
                                } catch (e) {
                                  if (context.mounted) showErrorSnack(context, e);
                                }
                              },
                            )
                          : null,
                    ),
                  const SizedBox(height: 16),
                  InvoicePrintButtons(invoice: inv),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static Widget _row(String label, String value, {TextStyle? style}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(Formatters.money(value), style: style),
      ],
    ),
  );
}
