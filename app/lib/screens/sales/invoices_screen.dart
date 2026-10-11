import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters/formatters.dart';
import '../../core/router/app_routes.dart';
import '../../core/strings/app_strings.dart';
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
        const PageHeader(title: AppStrings.invoices),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
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
                  () =>
                      _q = (search: _q.search, status: _q.status, onlyBalance: v, patientId: null),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: AsyncView(
            value: ref.watch(invoiceListProvider(_q)),
            onRetry: () => ref.invalidate(invoiceListProvider(_q)),
            builder: (page) => page.items.isEmpty
                ? const Center(child: Text(AppStrings.noData))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    children: [for (final inv in page.items) InvoiceTile(invoice: inv)],
                  ),
          ),
        ),
      ],
    );
  }
}

class InvoiceTile extends StatelessWidget {
  const InvoiceTile({super.key, required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inv = invoice;
    final color = switch (inv.status) {
      'cancelled' => theme.colorScheme.surfaceContainerHigh,
      'paid' => Colors.green.shade50,
      _ => Colors.amber.shade50,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        key: Key('invoice-row-${inv.id}'),
        leading: CircleAvatar(child: Text('${inv.number}', style: const TextStyle(fontSize: 12))),
        title: Text(inv.customerLabel.isEmpty ? AppStrings.walkIn : inv.customerLabel),
        subtitle: Text(
          '${Formatters.dateTime(inv.createdAt)}   •   '
          '${AppStrings.paymentTypes[inv.paymentType] ?? inv.paymentType}   •   ${inv.cashierName}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(Formatters.money(inv.total), style: const TextStyle(fontWeight: FontWeight.bold)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              color: color,
              child: Text(
                inv.hasBalance
                    ? '${AppStrings.balance}: ${Formatters.money(inv.balance)}'
                    : AppStrings.invoiceStatuses[inv.status] ?? inv.status,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
        onTap: () => context.go(AppRoutes.invoiceDetail(inv.id)),
      ),
    );
  }
}
