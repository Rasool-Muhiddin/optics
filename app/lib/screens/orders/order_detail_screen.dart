import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters/formatters.dart';
import '../../core/router/app_routes.dart';
import '../../core/strings/app_strings.dart';
import '../../data/repositories/purchasing_repository.dart';
import '../../models/purchasing.dart';
import '../../services/auth_controller.dart';
import '../../widgets/common.dart';
import '../patients/exam_dialogs.dart' show askVoidReason;
import '../sales/invoice_actions.dart' show askPayment;
import 'order_form_dialog.dart';
import 'orders_providers.dart';

/// One supplier order: lines with received quantities, receive / send / cancel,
/// payments (cost permission).
class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final canManage = session?.canManageInventory ?? false;
    final seesCosts = session?.membership.canViewCosts ?? false;
    final isOwner = session?.isOwner ?? false;
    final repo = ref.read(purchasingRepositoryProvider);

    Future<void> run(Future<Object?> Function() action) async {
      try {
        await action();
        invalidateOrders(ref, orderId);
      } catch (e) {
        if (context.mounted) showErrorSnack(context, e);
      }
    }

    return AsyncView(
      value: ref.watch(supplierOrderProvider(orderId)),
      onRetry: () => ref.invalidate(supplierOrderProvider(orderId)),
      builder: (o) {
        final theme = Theme.of(context);
        final late = o.lateOn(DateTime.now());
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            PageHeader(
              title: '${AppStrings.orderNumber} #${o.number} — ${o.supplierName}',
              leading: IconButton(
                tooltip: AppStrings.back,
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => context.go(AppRoutes.orders),
              ),
              actions: [
                if (canManage && o.canReceive)
                  FilledButton.icon(
                    key: const Key('order-receive'),
                    icon: const Icon(Icons.move_to_inbox_outlined),
                    label: const Text(AppStrings.receive),
                    onPressed: () async {
                      final lines = await showDialog<Map<int, int>>(
                        context: context,
                        builder: (_) => _ReceiveDialog(order: o),
                      );
                      if (lines != null) await run(() => repo.receive(o.id, lines: lines));
                    },
                  ),
                if (canManage && o.status == OrderStatuses.pending)
                  OutlinedButton(
                    key: const Key('order-mark-ordered'),
                    onPressed: () => run(() => repo.setStatus(o.id, OrderStatuses.ordered)),
                    child: const Text(AppStrings.markOrdered),
                  ),
                if (canManage && seesCosts && o.canEdit)
                  OutlinedButton.icon(
                    key: const Key('order-edit'),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text(AppStrings.edit),
                    onPressed: () async {
                      final saved = await showDialog<SupplierOrder>(
                        context: context,
                        builder: (_) => OrderFormDialog(order: o),
                      );
                      if (saved != null) invalidateOrders(ref, orderId);
                    },
                  ),
                if (canManage && seesCosts && o.status != OrderStatuses.pending && o.hasBalance)
                  OutlinedButton.icon(
                    key: const Key('order-pay'),
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text(AppStrings.addPayment),
                    onPressed: () async {
                      final input = await askPayment(context, maxAmount: o.balance);
                      if (input != null) {
                        await run(
                          () => repo.addPayment(o.id, amount: input.amount, method: input.method),
                        );
                      }
                    },
                  ),
                if (canManage && o.isOpen)
                  TextButton(
                    key: const Key('order-cancel'),
                    onPressed: () async {
                      if (!await confirmDialog(context, AppStrings.cancelOrderConfirm)) return;
                      if (!context.mounted) return;
                      final reason = await askVoidReason(context);
                      if (reason != null) await run(() => repo.cancel(o.id, reason));
                    },
                    child: const Text(AppStrings.cancelOrder),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: late
                      ? BorderSide(color: theme.colorScheme.error, width: 2)
                      : BorderSide.none,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 16,
                    children: [
                      InfoTile(
                        label: AppStrings.status,
                        value:
                            '${AppStrings.label(AppStrings.orderStatuses, o.status)}${late ? ' — ${AppStrings.late}' : ''}',
                      ),
                      InfoTile(
                        label: AppStrings.orderType,
                        value: AppStrings.label(AppStrings.orderTypes, o.type),
                      ),
                      InfoTile(label: AppStrings.orderDate, value: Formatters.date(o.orderDate)),
                      InfoTile(
                        label: AppStrings.expectedDate,
                        value: Formatters.date(o.expectedDate),
                      ),
                      if (o.isOpen)
                        InfoTile(label: AppStrings.ageDays, value: '${o.ageOn(DateTime.now())}'),
                      InfoTile(label: AppStrings.supplierRef, value: o.supplierRef),
                      InfoTile(
                        label: AppStrings.paymentStatus,
                        value: AppStrings.label(AppStrings.orderPaymentStatuses, o.paymentStatus),
                      ),
                      if (o.total != null)
                        InfoTile(label: AppStrings.total, value: Formatters.money(o.total)),
                      if (o.paid != null)
                        InfoTile(label: AppStrings.paid, value: Formatters.money(o.paid)),
                      if (o.balance != null)
                        InfoTile(label: AppStrings.balance, value: Formatters.money(o.balance)),
                      if (o.jobId != null)
                        InkWell(
                          onTap: () => context.go(AppRoutes.jobDetail(o.jobId!)),
                          child: InfoTile(
                            label: AppStrings.job,
                            value: '#${o.jobNumber} ${o.jobPatientName}',
                          ),
                        ),
                      InfoTile(label: AppStrings.byUser, value: o.createdByName),
                      if (o.cancelReason.isNotEmpty)
                        InfoTile(label: AppStrings.voidReason, value: o.cancelReason, width: 400),
                      if (o.notes.isNotEmpty)
                        InfoTile(label: AppStrings.notes, value: o.notes, width: 400),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(AppStrings.orderLines, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      DataTable(
                        columns: [
                          const DataColumn(label: Text(AppStrings.item)),
                          if (o.type == OrderTypes.rxForJob)
                            const DataColumn(label: Text(AppStrings.eye)),
                          const DataColumn(label: Text(AppStrings.quantity), numeric: true),
                          const DataColumn(label: Text(AppStrings.received), numeric: true),
                          const DataColumn(label: Text(AppStrings.remaining), numeric: true),
                          if (seesCosts) ...const [
                            DataColumn(label: Text(AppStrings.unitCost), numeric: true),
                            DataColumn(label: Text(AppStrings.lineTotal), numeric: true),
                          ],
                        ],
                        rows: [
                          for (final l in o.lines)
                            DataRow(
                              key: ValueKey('order-line-${l.id}'),
                              cells: [
                                DataCell(Text(l.label)),
                                if (o.type == OrderTypes.rxForJob)
                                  DataCell(Text(AppStrings.label(AppStrings.eyes, l.eye))),
                                DataCell(Text('${l.qty}')),
                                DataCell(Text('${l.qtyReceived}')),
                                DataCell(Text('${l.qtyRemaining}')),
                                if (seesCosts) ...[
                                  DataCell(Text(Formatters.money(l.unitCost))),
                                  DataCell(Text(Formatters.money(l.lineTotal))),
                                ],
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (seesCosts && o.payments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(AppStrings.payments, style: theme.textTheme.titleMedium),
                      ),
                      for (final p in o.payments)
                        ListTile(
                          dense: true,
                          title: Text(
                            Formatters.money(p.amount),
                            style: p.isVoid
                                ? const TextStyle(decoration: TextDecoration.lineThrough)
                                : null,
                          ),
                          subtitle: Text(
                            '${Formatters.dateTime(p.paidAt)}   •   '
                            '${AppStrings.paymentMethods[p.method] ?? p.method}   •   ${p.paidByName}'
                            '${p.isVoid ? '   •   ${AppStrings.voided}: ${p.voidReason}' : ''}',
                          ),
                          trailing: isOwner && !p.isVoid
                              ? TextButton(
                                  onPressed: () async {
                                    final reason = await askVoidReason(context);
                                    if (reason != null) {
                                      await run(() => repo.voidPayment(p.id, reason));
                                    }
                                  },
                                  child: const Text(AppStrings.voidRecord),
                                )
                              : null,
                        ),
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

/// Quantities to receive now per line (defaults to everything remaining). Returns {lineId: qty}.
class _ReceiveDialog extends StatefulWidget {
  const _ReceiveDialog({required this.order});

  final SupplierOrder order;

  @override
  State<_ReceiveDialog> createState() => _ReceiveDialogState();
}

class _ReceiveDialogState extends State<_ReceiveDialog> {
  late final Map<int, TextEditingController> _qty = {
    for (final l in widget.order.lines)
      if (l.qtyRemaining > 0) l.id: TextEditingController(text: '${l.qtyRemaining}'),
  };
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    for (final c in _qty.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.order.lines.where((l) => l.qtyRemaining > 0).toList();
    return FormDialog(
      title: AppStrings.receiveOrder,
      width: 560,
      saveLabel: AppStrings.receive,
      onSave: () {
        if (!_formKey.currentState!.validate()) return;
        Navigator.of(
          context,
        ).pop({for (final e in _qty.entries) e.key: int.tryParse(e.value.text.trim()) ?? 0});
      },
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(AppStrings.receiveHint),
            const SizedBox(height: 8),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(l.label)),
                    Text('${AppStrings.remaining}: ${l.qtyRemaining}'),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 90,
                      child: TextFormField(
                        key: Key('receive-qty-${l.id}'),
                        controller: _qty[l.id],
                        inputFormatters: Inputs.integer,
                        decoration: const InputDecoration(isDense: true),
                        validator: (v) {
                          final n = int.tryParse(v?.trim() ?? '');
                          return n == null || n < 0 || n > l.qtyRemaining
                              ? AppStrings.invalidNumber
                              : null;
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
