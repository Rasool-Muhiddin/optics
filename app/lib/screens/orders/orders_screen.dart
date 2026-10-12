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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
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
        ),
        const SizedBox(height: 12),
        Expanded(
          child: AsyncView(
            value: ref.watch(supplierOrdersProvider(_q)),
            onRetry: () => ref.invalidate(supplierOrdersProvider(_q)),
            builder: (orders) => orders.isEmpty
                ? const Center(child: Text(AppStrings.noOrders))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    children: [for (final o in orders) OrderTile(order: o)],
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
    if (summary == null) return const SizedBox(height: 8);
    final theme = Theme.of(context);
    String bucket(({int from, int? to, int count}) b) =>
        b.to == null ? '+${b.from - 1}' : '${b.from}–${b.to}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Chip(label: Text('${AppStrings.pendingOrders}: ${summary.open}')),
          Chip(
            key: const Key('orders-late-count'),
            backgroundColor: summary.late > 0 ? theme.colorScheme.errorContainer : null,
            label: Text('${AppStrings.late}: ${summary.late}'),
          ),
          Text('${AppStrings.ageing}:', style: theme.textTheme.labelLarge),
          for (final b in summary.ageing)
            ActionChip(
              key: Key('ageing-${b.from}'),
              label: Text('${bucket(b)} ${AppStrings.daysOld}: ${b.count}'),
              onPressed: () => onAge(b.from),
            ),
          if (summary.owed != null)
            Chip(label: Text('${AppStrings.totalOwed}: ${Formatters.money(summary.owed)}')),
        ],
      ),
    );
  }
}

class OrderTile extends StatelessWidget {
  const OrderTile({super.key, required this.order});

  final SupplierOrder order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final o = order;
    final now = DateTime.now();
    final late = o.lateOn(now);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: late ? BorderSide(color: theme.colorScheme.error, width: 2) : BorderSide.none,
      ),
      child: ListTile(
        key: Key('order-row-${o.id}'),
        leading: CircleAvatar(child: Text('${o.number}', style: const TextStyle(fontSize: 12))),
        title: Row(
          children: [
            Expanded(child: Text(o.supplierName, overflow: TextOverflow.ellipsis)),
            if (late)
              Container(
                key: Key('order-late-${o.id}'),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                color: theme.colorScheme.errorContainer,
                child: Text(AppStrings.late, style: theme.textTheme.labelSmall),
              ),
          ],
        ),
        subtitle: Text(
          [
            AppStrings.label(AppStrings.orderTypes, o.type),
            if (o.jobNumber != null) '${AppStrings.job} #${o.jobNumber} ${o.jobPatientName}',
            '${AppStrings.orderDate}: ${Formatters.date(o.orderDate)}',
            if (o.isOpen) '${o.ageOn(now)} ${AppStrings.daysOld}',
            if (o.expectedDate != null)
              '${AppStrings.expectedDate}: ${Formatters.date(o.expectedDate)}',
          ].join('   •   '),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              AppStrings.label(AppStrings.orderStatuses, o.status),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              o.total == null
                  ? AppStrings.label(AppStrings.orderPaymentStatuses, o.paymentStatus)
                  : '${Formatters.money(o.total)} • '
                        '${AppStrings.label(AppStrings.orderPaymentStatuses, o.paymentStatus)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        onTap: () => context.go(AppRoutes.orderDetail(o.id)),
      ),
    );
  }
}
