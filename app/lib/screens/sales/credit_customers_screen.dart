import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters/formatters.dart';
import '../../core/router/app_routes.dart';
import '../../core/strings/app_strings.dart';
import '../../data/repositories/sales_repository.dart';
import '../../widgets/common.dart';
import 'invoice_actions.dart';
import 'invoices_screen.dart';
import 'sales_providers.dart';

/// Credit (آجل) customers: who owes what; receive a payment spread over oldest invoices.
class CreditCustomersScreen extends ConsumerStatefulWidget {
  const CreditCustomersScreen({super.key});

  @override
  ConsumerState<CreditCustomersScreen> createState() => _CreditCustomersScreenState();
}

class _CreditCustomersScreenState extends ConsumerState<CreditCustomersScreen> {
  String _search = '';
  int? _expanded;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(creditCustomersProvider(_search));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(title: AppStrings.navCredit),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(
              width: 320,
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '${AppStrings.name} / ${AppStrings.phone}',
                ),
                onChanged: (text) {
                  _debounce?.cancel();
                  _debounce = Timer(
                    const Duration(milliseconds: 300),
                    () => setState(() => _search = text),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: AsyncView(
            value: value,
            onRetry: () => ref.invalidate(creditCustomersProvider(_search)),
            builder: (page) {
              if (page.items.isEmpty) return const Center(child: Text(AppStrings.noData));
              final total = page.items.fold<double>(
                0,
                (sum, c) => sum + (double.tryParse(c.balance) ?? 0),
              );
              return ListView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                children: [
                  Text(
                    // Display-only sum of server balances.
                    '${AppStrings.totalCredit}: ${Formatters.money(total)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final c in page.items)
                    Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: Column(
                        children: [
                          ListTile(
                            key: Key('credit-row-${c.patientId}'),
                            title: Text(c.name),
                            subtitle: Text(
                              '${c.phone}   •   ${AppStrings.invoicesCount}: ${c.invoices}'
                              '   •   ${AppStrings.oldestInvoice}: ${Formatters.date(c.oldest)}',
                            ),
                            trailing: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              children: [
                                Text(
                                  Formatters.money(c.balance),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                                FilledButton.tonal(
                                  key: Key('credit-pay-${c.patientId}'),
                                  onPressed: () async {
                                    final input = await askPayment(
                                      context,
                                      maxAmount: c.balance,
                                      hint: AppStrings.paymentsSpread,
                                    );
                                    if (input == null) return;
                                    try {
                                      await ref
                                          .read(salesRepositoryProvider)
                                          .payCustomer(
                                            c.patientId,
                                            amount: input.amount,
                                            method: input.method,
                                          );
                                      invalidateSales(ref);
                                      if (context.mounted) showSnack(context, AppStrings.saved);
                                    } catch (e) {
                                      if (context.mounted) showErrorSnack(context, e);
                                    }
                                  },
                                  child: const Text(AppStrings.receivePayment),
                                ),
                                IconButton(
                                  tooltip: AppStrings.patientsTitle,
                                  icon: const Icon(Icons.person_outline),
                                  onPressed: () => context.go(AppRoutes.patientDetail(c.patientId)),
                                ),
                              ],
                            ),
                            onTap: () => setState(
                              () => _expanded = _expanded == c.patientId ? null : c.patientId,
                            ),
                          ),
                          if (_expanded == c.patientId) _CustomerInvoices(patientId: c.patientId),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CustomerInvoices extends ConsumerWidget {
  const _CustomerInvoices({required this.patientId});

  final int patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final InvoiceQuery q = (search: '', status: null, onlyBalance: true, patientId: patientId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: AsyncView(
        value: ref.watch(invoiceListProvider(q)),
        builder: (page) =>
            Column(children: [for (final inv in page.items) InvoiceTile(invoice: inv)]),
      ),
    );
  }
}
