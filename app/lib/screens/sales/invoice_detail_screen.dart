import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters/formatters.dart';
import '../../core/router/app_routes.dart';
import '../../core/strings/app_strings.dart';
import '../../data/cache/json_cache_dao.dart';
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

        final hasDiscount = (double.tryParse(inv.discountTotal) ?? 0) > 0;
        final lineColumns = [
          const TableCol(AppStrings.productName, flex: 5),
          const TableCol(AppStrings.quantity, flex: 1, numeric: true),
          const TableCol(AppStrings.unitPrice, flex: 2, numeric: true),
          const TableCol(AppStrings.discount, flex: 2, numeric: true),
          if (seesCosts) const TableCol(AppStrings.unitCost, flex: 2, numeric: true),
          const TableCol(AppStrings.total, flex: 2, numeric: true),
        ];

        final info = SectionCard(
          title: '${AppStrings.invoice} #${inv.number}',
          icon: Icons.receipt_long_outlined,
          actions: [
            StatusBadge(
              label: AppStrings.invoiceStatuses[inv.status] ?? inv.status,
              tone: StatusTones.invoice(inv.status),
            ),
          ],
          child: Wrap(
            spacing: AppSpacing.lg,
            children: [
              InfoTile(label: AppStrings.customer, value: inv.customerLabel),
              InfoTile(label: AppStrings.phone, value: inv.customerPhone),
              InfoTile(label: AppStrings.date, value: Formatters.dateTime(inv.createdAt)),
              InfoTile(
                label: AppStrings.paymentType,
                value: AppStrings.paymentTypes[inv.paymentType] ?? inv.paymentType,
              ),
              InfoTile(
                label: AppStrings.status,
                value: AppStrings.invoiceStatuses[inv.status] ?? inv.status,
              ),
              InfoTile(label: AppStrings.cashier, value: inv.cashierName),
              if (inv.isCancelled) InfoTile(label: AppStrings.voidReason, value: inv.cancelReason),
            ],
          ),
        );

        final lines = SectionCard(
          title: AppStrings.lines,
          icon: Icons.list_alt_outlined,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DataTableHeader(columns: lineColumns),
              for (var i = 0; i < inv.lines.length; i++)
                DataRowView(
                  columns: lineColumns,
                  index: i,
                  cells: [
                    Text(inv.lines[i].description, overflow: TextOverflow.ellipsis),
                    NumText('${inv.lines[i].qty}'),
                    MoneyText(inv.lines[i].unitPrice),
                    (double.tryParse(inv.lines[i].discount) ?? 0) > 0
                        ? MoneyText(inv.lines[i].discount, tone: Tone.danger)
                        : const Text(AppStrings.none),
                    if (seesCosts)
                      inv.lines[i].unitCost == null
                          ? const Text(AppStrings.none)
                          : MoneyText(inv.lines[i].unitCost, tone: Tone.neutral),
                    MoneyText(inv.lines[i].lineTotal, bold: true),
                  ],
                ),
            ],
          ),
        );

        final totals = SectionCard(
          title: AppStrings.total,
          icon: Icons.calculate_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AmountRow(label: AppStrings.subtotal, value: inv.subtotal),
              if (hasDiscount)
                AmountRow(label: AppStrings.discount, value: inv.discountTotal, tone: Tone.danger),
              const Divider(height: AppSpacing.lg),
              AmountRow(label: AppStrings.total, value: inv.total, emphasize: true),
              AmountRow(label: AppStrings.paid, value: inv.paid, tone: Tone.success),
              AmountRow(
                label: AppStrings.balance,
                value: inv.balance,
                tone: inv.hasBalance ? Tone.danger : null,
              ),
              if (seesCosts && inv.profit != null) ...[
                const Divider(height: AppSpacing.lg),
                AmountRow(label: AppStrings.costTotal, value: inv.costTotal!),
                AmountRow(
                  label: AppStrings.profit,
                  value: inv.profit!,
                  tone: (double.tryParse(inv.profit!) ?? 0) < 0 ? Tone.danger : Tone.success,
                ),
              ],
            ],
          ),
        );

        final payments = SectionCard(
          title: AppStrings.payments,
          icon: Icons.payments_outlined,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: inv.payments.isEmpty
              ? const EmptyState(icon: Icons.payments_outlined, compact: true)
              : Column(
                  children: [
                    for (final p in inv.payments)
                      ListTile(
                        dense: true,
                        leading: IconTile(
                          icon: p.isVoid ? Icons.block : Icons.check,
                          tone: p.isVoid ? Tone.neutral : Tone.success,
                          size: 32,
                        ),
                        title: Text(
                          '${Formatters.money(p.amount)} — ${AppStrings.paymentMethods[p.method] ?? p.method}',
                          style: p.isVoid
                              ? const TextStyle(decoration: TextDecoration.lineThrough)
                              : const TextStyle(fontFeatures: AppText.tabular),
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
                                    await ref
                                        .read(salesRepositoryProvider)
                                        .voidPayment(p.id, reason);
                                    invalidateSales(ref, inv.id);
                                  } catch (e) {
                                    if (context.mounted) showErrorSnack(context, e);
                                  }
                                },
                              )
                            : null,
                      ),
                  ],
                ),
        );

        final printCard = SectionCard(
          title: AppStrings.sectionPrinting,
          icon: Icons.print_outlined,
          child: InvoicePrintButtons(invoice: inv),
        );

        return ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: [
            PageHeader(
              title: '${AppStrings.invoice} #${inv.number}',
              cacheTables: const [CacheTables.invoices],
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
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: LayoutBuilder(
                builder: (context, c) {
                  const gap = SizedBox(height: AppSpacing.lg, width: AppSpacing.lg);
                  if (c.maxWidth < 980) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [info, gap, lines, gap, totals, gap, payments, gap, printCard],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [info, gap, lines, gap, payments],
                        ),
                      ),
                      gap,
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [totals, gap, printCard],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
