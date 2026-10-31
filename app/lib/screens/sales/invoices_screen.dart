import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters/formatters.dart';
import '../../core/router/app_routes.dart';
import '../../core/strings/app_strings.dart';
import '../../data/cache/json_cache_dao.dart';
import '../../data/repositories/sales_repository.dart';
import '../../models/sales.dart';
import '../../widgets/common.dart';
import 'sales_providers.dart';

/// Invoice list: search by number / customer, status filter, unpaid only.
class InvoicesScreen extends ConsumerStatefulWidget {
  const InvoicesScreen({super.key});

  @override
  ConsumerState<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends ConsumerState<InvoicesScreen> {
  InvoiceQuery _q = (search: '', status: null, onlyBalance: false, patientId: null);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: AppStrings.invoices,
          cacheTables: const [CacheTables.invoices],
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.point_of_sale, size: 18),
              label: const Text(AppStrings.navPos),
              onPressed: () => context.go(AppRoutes.pos),
            ),
          ],
        ),
        FilterBar(
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                key: const Key('invoices-search'),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '${AppStrings.invoiceNumber} / ${AppStrings.customer}',
                ),
                onChanged: (text) {
                  _debounce?.cancel();
                  _debounce = Timer(
                    const Duration(milliseconds: 300),
                    () => setState(
                      () => _q = (
                        search: text,
                        status: _q.status,
                        onlyBalance: _q.onlyBalance,
                        patientId: null,
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _q.status,
                decoration: const InputDecoration(labelText: AppStrings.status),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text(AppStrings.all)),
                  for (final s in AppStrings.invoiceStatuses.entries)
                    DropdownMenuItem<String?>(value: s.key, child: Text(s.value)),
                ],
                onChanged: (v) => setState(
                  () => _q = (
                    search: _q.search,
                    status: v,
                    onlyBalance: _q.onlyBalance,
                    patientId: null,
                  ),
                ),
              ),
            ),
            FilterChip(
              label: const Text(AppStrings.onlyWithBalance),
              selected: _q.onlyBalance,
              onSelected: (v) => setState(
                () => _q = (search: _q.search, status: _q.status, onlyBalance: v, patientId: null),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              0,
              AppSpacing.page,
              AppSpacing.page,
            ),
            child: AsyncView(
              value: ref.watch(invoiceListProvider(_q)),
              skeleton: true,
              onRetry: () => ref.invalidate(invoiceListProvider(_q)),
              builder: (page) => page.items.isEmpty
                  ? EmptyState(
                      icon: Icons.receipt_long_outlined,
                      message: _q.search.isNotEmpty || _q.status != null || _q.onlyBalance
                          ? AppStrings.emptyFilteredHint
                          : null,
                    )
                  : AppDataTable<Invoice>(
                      columns: invoiceColumns,
                      items: page.items,
                      rowKey: (inv) => Key('invoice-row-${inv.id}'),
                      onTap: (inv) => context.go(AppRoutes.invoiceDetail(inv.id)),
                      muted: (inv) => inv.isCancelled,
                      sortKeys: {
                        0: (inv) => inv.number,
                        2: (inv) => inv.createdAt?.millisecondsSinceEpoch ?? 0,
                        4: (inv) => double.tryParse(inv.total) ?? 0,
                        5: (inv) => inv.hasBalance ? (double.tryParse(inv.balance) ?? 0) : 0,
                      },
                      footer: TableFooter(count: page.items.length),
                      cells: (inv) => invoiceCells(context, inv),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Invoice table columns (shared by the invoices list and the credit customer rows).
const List<TableCol> invoiceColumns = [
  TableCol(AppStrings.invoiceNumber, flex: 1),
  TableCol(AppStrings.customer, flex: 4),
  TableCol(AppStrings.date, flex: 2),
  TableCol(AppStrings.cashier, flex: 2),
  TableCol(AppStrings.total, flex: 2, numeric: true),
  TableCol(AppStrings.balance, flex: 2, numeric: true),
  TableCol(AppStrings.status, flex: 2, center: true),
];

List<Widget> invoiceCells(BuildContext context, Invoice inv) => [
  NumText('#${inv.number}', bold: true),
  TwoLineCell(
    title: inv.customerLabel.isEmpty ? AppStrings.walkIn : inv.customerLabel,
    subtitle: AppStrings.paymentTypes[inv.paymentType] ?? inv.paymentType,
  ),
  NumText(Formatters.dateTime(inv.createdAt)),
  Text(inv.cashierName, overflow: TextOverflow.ellipsis),
  MoneyText(inv.total, bold: true),
  inv.hasBalance ? MoneyText(inv.balance, tone: Tone.danger) : const Text(AppStrings.none),
  StatusBadge(
    label: AppStrings.invoiceStatuses[inv.status] ?? inv.status,
    tone: StatusTones.invoice(inv.status),
    dense: true,
  ),
];

/// One invoice as a table row (used where invoices are listed inside another card).
class InvoiceTile extends StatelessWidget {
  const InvoiceTile({super.key, required this.invoice, this.index = 0});

  final Invoice invoice;
  final int index;

  @override
  Widget build(BuildContext context) {
    final inv = invoice;
    return DataRowView(
      key: Key('invoice-row-${inv.id}'),
      columns: invoiceColumns,
      index: index,
      muted: inv.isCancelled,
      cells: invoiceCells(context, inv),
      onTap: () => context.go(AppRoutes.invoiceDetail(inv.id)),
    );
  }
}
