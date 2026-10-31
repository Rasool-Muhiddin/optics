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

  static const _columns = [
    TableCol(AppStrings.customer, flex: 4),
    TableCol(AppStrings.invoicesCount, flex: 2, numeric: true),
    TableCol(AppStrings.oldestInvoice, flex: 2, numeric: true),
    TableCol(AppStrings.balance, flex: 3, numeric: true),
    TableCol('', width: 280),
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _pay(CreditCustomer c) async {
    final input = await askPayment(context, maxAmount: c.balance, hint: AppStrings.paymentsSpread);
    if (input == null) return;
    try {
      await ref
          .read(salesRepositoryProvider)
          .payCustomer(c.patientId, amount: input.amount, method: input.method);
      invalidateSales(ref);
      if (mounted) showSnack(context, AppStrings.saved);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(creditCustomersProvider(_search));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(title: AppStrings.navCredit, cacheTables: [CacheTables.creditCustomers]),
        FilterBar(
          children: [
            SizedBox(
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
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: AsyncView(
            value: value,
            skeleton: true,
            onRetry: () => ref.invalidate(creditCustomersProvider(_search)),
            builder: (page) {
              if (page.items.isEmpty) {
                return EmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  message: _search.isNotEmpty ? AppStrings.emptyFilteredHint : null,
                );
              }
              // Display-only sum of server balances.
              final total = page.items.fold<double>(
                0,
                (sum, c) => sum + (double.tryParse(c.balance) ?? 0),
              );
              return ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  0,
                  AppSpacing.page,
                  AppSpacing.page,
                ),
                children: [
                  Wrap(
                    spacing: AppSpacing.lg,
                    runSpacing: AppSpacing.lg,
                    children: [
                      KpiCard(
                        label: AppStrings.totalCredit,
                        value: Formatters.money(total),
                        icon: Icons.account_balance_wallet_outlined,
                        tone: Tone.danger,
                        width: 280,
                      ),
                      KpiCard(
                        label: AppStrings.customer,
                        value: '${page.items.length}',
                        icon: Icons.people_outline,
                        width: 200,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TableFrame(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const DataTableHeader(columns: _columns),
                        for (var i = 0; i < page.items.length; i++)
                          _CustomerRow(
                            customer: page.items[i],
                            index: i,
                            columns: _columns,
                            expanded: _expanded == page.items[i].patientId,
                            onToggle: () => setState(
                              () => _expanded = _expanded == page.items[i].patientId
                                  ? null
                                  : page.items[i].patientId,
                            ),
                            onPay: () => _pay(page.items[i]),
                          ),
                        TableFooter(count: page.items.length),
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

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({
    required this.customer,
    required this.index,
    required this.columns,
    required this.expanded,
    required this.onToggle,
    required this.onPay,
  });

  final CreditCustomer customer;
  final int index;
  final List<TableCol> columns;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    final colors = AppColors.of(context);
    final dataColumns = columns.sublist(0, columns.length - 1);
    final cells = <Widget>[
      Row(
        children: [
          Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: colors.textMuted),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: TwoLineCell(
              leading: InitialsAvatar(name: c.name, size: 32, tone: Tone.warning),
              title: c.name,
              subtitle: c.phone,
            ),
          ),
        ],
      ),
      NumText('${c.invoices}'),
      NumText(Formatters.date(c.oldest)),
      MoneyText(c.balance, tone: Tone.danger, bold: true),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: expanded
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.05)
              : (index.isOdd ? colors.zebra : Colors.transparent),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  key: Key('credit-row-${c.patientId}'),
                  onTap: onToggle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    child: Row(
                      children: [
                        for (var i = 0; i < dataColumns.length; i++)
                          Expanded(
                            flex: dataColumns[i].flex,
                            child: Align(alignment: dataColumns[i].alignment, child: cells[i]),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: columns.last.width,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerEnd,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton.tonalIcon(
                          key: Key('credit-pay-${c.patientId}'),
                          icon: const Icon(Icons.payments_outlined, size: 18),
                          onPressed: onPay,
                          label: const Text(AppStrings.receivePayment),
                        ),
                        IconButton(
                          tooltip: AppStrings.patientsTitle,
                          icon: const Icon(Icons.person_outline),
                          onPressed: () => context.go(AppRoutes.patientDetail(c.patientId)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (expanded) _CustomerInvoices(patientId: c.patientId),
        Divider(height: 1, color: colors.border.withValues(alpha: 0.7)),
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
    return Container(
      color: AppColors.of(context).surfaceMuted,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.md,
      ),
      child: AsyncView(
        value: ref.watch(invoiceListProvider(q)),
        builder: (page) => TableFrame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DataTableHeader(columns: invoiceColumns),
              for (var i = 0; i < page.items.length; i++)
                InvoiceTile(invoice: page.items[i], index: i),
            ],
          ),
        ),
      ),
    );
  }
}
