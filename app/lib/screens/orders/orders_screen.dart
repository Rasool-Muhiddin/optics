import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters/formatters.dart';
import '../../core/router/app_routes.dart';
import '../../core/strings/app_strings.dart';
import '../../data/cache/json_cache_dao.dart';
import '../../data/repositories/purchasing_repository.dart';
import '../../models/purchasing.dart';
import '../../services/auth_controller.dart';
import '../../widgets/common.dart';
import 'order_form_dialog.dart';
import 'orders_providers.dart';
import 'suppliers_dialog.dart';

/// Supplier orders (نافذة الطلبات): open orders first, filters by status / type / supplier,
/// late only and ageing (open for at least N days).
class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  OrderQuery _q = pendingOrdersQuery;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _set({
    String? search,
    Object? status = _keep,
    Object? type = _keep,
    Object? supplierId = _keep,
    bool? openOnly,
    bool? lateOnly,
    Object? minAge = _keep,
  }) {
    setState(
      () => _q = (
        search: search ?? _q.search,
        status: status == _keep ? _q.status : status as String?,
        type: type == _keep ? _q.type : type as String?,
        supplierId: supplierId == _keep ? _q.supplierId : supplierId as int?,
        openOnly: openOnly ?? _q.openOnly,
        lateOnly: lateOnly ?? _q.lateOnly,
        minAge: minAge == _keep ? _q.minAge : minAge as int?,
        jobId: null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final canManage = session?.canManageInventory ?? false;
    final suppliers = ref.watch(suppliersProvider).value ?? const <Supplier>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: AppStrings.ordersTitle,
          cacheTables: const [CacheTables.supplierOrders, CacheTables.suppliers],
          actions: [
            OutlinedButton.icon(
              key: const Key('manage-suppliers'),
              icon: const Icon(Icons.store_outlined),
              label: const Text(AppStrings.suppliers),
              onPressed: () async {
                await showDialog<void>(context: context, builder: (_) => const SuppliersDialog());
                invalidateOrders(ref);
              },
            ),
            if (canManage)
              FilledButton.icon(
                key: const Key('new-order'),
                icon: const Icon(Icons.add),
                label: const Text(AppStrings.newOrder),
                onPressed: () async {
                  final order = await showDialog<SupplierOrder>(
                    context: context,
                    builder: (_) => const OrderFormDialog(),
                  );
                  if (order != null && context.mounted) {
                    invalidateOrders(ref);
                    context.go(AppRoutes.orderDetail(order.id));
                  }
                },
              ),
          ],
        ),
        _SummaryBar(onAge: (days) => _set(minAge: days, openOnly: true)),
        FilterBar(
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                key: const Key('orders-search'),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '${AppStrings.orderNumber} / ${AppStrings.supplier}',
                ),
                onChanged: (text) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), () => _set(search: text));
                },
              ),
            ),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String?>(
                key: const Key('orders-status'),
                isExpanded: true,
                initialValue: _q.status,
                decoration: const InputDecoration(labelText: AppStrings.status),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text(AppStrings.all)),
                  for (final s in AppStrings.orderStatuses.entries)
                    DropdownMenuItem<String?>(value: s.key, child: Text(s.value)),
                ],
                onChanged: (v) => _set(status: v, openOnly: v == null ? _q.openOnly : false),
              ),
            ),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _q.type,
                decoration: const InputDecoration(labelText: AppStrings.orderType),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text(AppStrings.all)),
                  for (final t in AppStrings.orderTypes.entries)
                    DropdownMenuItem<String?>(value: t.key, child: Text(t.value)),
                ],
                onChanged: (v) => _set(type: v),
              ),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<int?>(
                isExpanded: true,
                initialValue: suppliers.any((s) => s.id == _q.supplierId) ? _q.supplierId : null,
                decoration: const InputDecoration(labelText: AppStrings.supplier),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text(AppStrings.all)),
                  for (final s in suppliers)
                    DropdownMenuItem<int?>(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => _set(supplierId: v),
              ),
            ),
            FilterChip(
              key: const Key('orders-open-only'),
              label: const Text(AppStrings.openOnly),
              selected: _q.openOnly,
              onSelected: (v) => _set(openOnly: v, status: v ? null : _q.status),
            ),
            FilterChip(
              key: const Key('orders-late-only'),
              label: const Text(AppStrings.lateOnly),
              selected: _q.lateOnly,
              onSelected: (v) => _set(lateOnly: v),
            ),
            if (_q.minAge != null)
              InputChip(
                key: const Key('orders-min-age'),
                label: Text('${AppStrings.minAge}: ${_q.minAge}'),
                onDeleted: () => _set(minAge: null),
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
              value: ref.watch(supplierOrdersProvider(_q)),
              skeleton: true,
              onRetry: () => ref.invalidate(supplierOrdersProvider(_q)),
              builder: (orders) {
                if (orders.isEmpty) {
                  return const EmptyState(
                    icon: Icons.local_shipping_outlined,
                    title: AppStrings.noOrders,
                  );
                }
                final now = DateTime.now();
                final showTotal = orders.any((o) => o.total != null);
                final columns = OrderTile.columnsFor(showTotal: showTotal);
                return AppDataTable<SupplierOrder>(
                  columns: columns,
                  items: orders,
                  rowKey: (o) => Key('order-row-${o.id}'),
                  onTap: (o) => context.go(AppRoutes.orderDetail(o.id)),
                  muted: (o) => o.status == 'cancelled',
                  accent: (o) => o.lateOn(now) ? AppColors.of(context).danger : null,
                  sortKeys: {
                    0: (o) => o.number,
                    1: (o) => o.supplierName,
                    2: (o) => o.orderDate?.millisecondsSinceEpoch ?? 0,
                    if (showTotal) 4: (o) => double.tryParse(o.total ?? '') ?? 0,
                  },
                  footer: TableFooter(count: orders.length),
                  cells: (o) => OrderTile.cellsFor(context, o, now: now, showTotal: showTotal),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

const Object _keep = Object();

/// Open / late counts and ageing buckets (tap a bucket to filter by age).
class _SummaryBar extends ConsumerWidget {
  const _SummaryBar({required this.onAge});

  final void Function(int days) onAge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(ordersSummaryProvider).value;
    if (summary == null) return const SizedBox(height: AppSpacing.sm);
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    String bucket(({int from, int? to, int count}) b) =>
        b.to == null ? '+${b.from - 1}' : '${b.from}–${b.to}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.lg),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _Stat(
            label: AppStrings.pendingOrders,
            value: '${summary.open}',
            icon: Icons.pending_actions_outlined,
            tone: Tone.info,
          ),
          _Stat(
            key: const Key('orders-late-count'),
            label: AppStrings.late,
            value: '${summary.late}',
            icon: Icons.schedule,
            tone: summary.late > 0 ? Tone.danger : Tone.neutral,
          ),
          if (summary.owed != null)
            _Stat(
              label: AppStrings.totalOwed,
              value: Formatters.money(summary.owed),
              icon: Icons.account_balance_outlined,
              tone: Tone.warning,
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: AppRadius.lgAll,
              border: Border.all(color: colors.border),
            ),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${AppStrings.ageing}:', style: theme.textTheme.labelLarge),
                for (final b in summary.ageing)
                  ActionChip(
                    key: Key('ageing-${b.from}'),
                    label: Text('${bucket(b)} ${AppStrings.daysOld}: ${b.count}'),
                    onPressed: () => onAge(b.from),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact metric (icon + "label: value") for summary strips.
class _Stat extends StatelessWidget {
  const _Stat({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.tone = Tone.primary,
  });

  final String label;
  final String value;
  final IconData icon;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: tone == Tone.danger ? colors.danger : colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconTile(icon: icon, tone: tone, size: 34),
          const SizedBox(width: AppSpacing.md),
          Text('$label: $value', style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
}

/// Supplier-order table row content (columns + cells).
class OrderTile {
  const OrderTile._();

  static List<TableCol> columnsFor({required bool showTotal}) => [
    const TableCol(AppStrings.orderNumber, flex: 1),
    const TableCol(AppStrings.supplier, flex: 4),
    const TableCol(AppStrings.orderDate, flex: 2),
    const TableCol(AppStrings.expectedDate, flex: 2),
    if (showTotal) const TableCol(AppStrings.total, flex: 2, numeric: true),
    const TableCol(AppStrings.paymentStatus, flex: 2, center: true),
    const TableCol(AppStrings.status, flex: 2, center: true),
  ];

  static List<Widget> cellsFor(
    BuildContext context,
    SupplierOrder o, {
    required DateTime now,
    required bool showTotal,
  }) {
    final late = o.lateOn(now);
    final colors = AppColors.of(context);
    return [
      NumText('#${o.number}', bold: true),
      TwoLineCell(
        title: o.supplierName,
        subtitle: [
          AppStrings.label(AppStrings.orderTypes, o.type),
          if (o.jobNumber != null) '${AppStrings.job} #${o.jobNumber} ${o.jobPatientName}',
        ].join('   •   '),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          NumText(Formatters.date(o.orderDate)),
          if (o.isOpen)
            Text(
              '${o.ageOn(now)} ${AppStrings.daysOld}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
      o.expectedDate == null
          ? const Text(AppStrings.none)
          : NumText(Formatters.date(o.expectedDate), color: late ? colors.danger : null),
      if (showTotal) o.total == null ? const Text(AppStrings.none) : MoneyText(o.total),
      StatusBadge(
        label: AppStrings.label(AppStrings.orderPaymentStatuses, o.paymentStatus),
        tone: StatusTones.payment(o.paymentStatus),
        dense: true,
      ),
      Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        alignment: WrapAlignment.center,
        children: [
          StatusBadge(
            label: AppStrings.label(AppStrings.orderStatuses, o.status),
            tone: StatusTones.order(o.status),
            dense: true,
          ),
          if (late)
            StatusBadge(
              key: Key('order-late-${o.id}'),
              label: AppStrings.late,
              tone: Tone.danger,
              icon: Icons.schedule,
              dense: true,
            ),
        ],
      ),
    ];
  }
}
