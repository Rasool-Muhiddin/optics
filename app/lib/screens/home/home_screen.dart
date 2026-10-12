import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters/formatters.dart';
import '../../core/router/app_routes.dart';
import '../../core/strings/app_strings.dart';
import '../../data/repositories/reports_repository.dart';
import '../../models/reports.dart';
import '../../services/auth_controller.dart';
import '../../widgets/common.dart';
import '../shell/main_shell.dart';

final dashboardProvider = FutureProvider.autoDispose<Dashboard>(
  (ref) => ref.watch(reportsRepositoryProvider).dashboard(),
);

/// Landing page: the dashboard (today, this month, open work) + session info.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final state = ref.watch(authControllerProvider).value;
    if (session == null) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    final expires = session.plan.expiresOn;

    return RefreshIndicator(
      onRefresh: () => ref.refresh(dashboardProvider.future),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${AppStrings.welcome}، ${session.user.displayName}',
                  style: textTheme.headlineMedium,
                ),
              ),
              IconButton(
                tooltip: AppStrings.retry,
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(dashboardProvider),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (state is LoggedIn && state.restoredOffline)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(AppStrings.sessionOffline, style: textTheme.bodyMedium),
            ),
          ref
              .watch(dashboardProvider)
              .when(
                skipLoadingOnRefresh: true,
                data: (d) => _DashboardBody(dashboard: d),
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) =>
                    ErrorPanel(error: e, onRetry: () => ref.invalidate(dashboardProvider)),
              ),
          const SizedBox(height: 24),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.store_outlined),
                  title: const Text(AppStrings.homeLab),
                  subtitle: Text(session.lab.name),
                ),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text(AppStrings.homeRole),
                  subtitle: Text(Sidebar.roleLabel(session.membership)),
                ),
                ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined),
                  title: const Text(AppStrings.homePlan),
                  subtitle: Text(
                    expires == null
                        ? session.plan.name
                        : '${session.plan.name} — ${AppStrings.homePlanExpires} '
                              '${Formatters.date(expires)}',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.dashboard});

  final Dashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final d = dashboard;
    final error = Theme.of(context).colorScheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Kpi(
              key: const Key('kpi-today-sales'),
              label: AppStrings.todaySales,
              value: Formatters.money(d.todaySales),
              hint: '${d.todayInvoices} ${AppStrings.invoicesCountShort}',
              icon: Icons.point_of_sale,
              path: AppRoutes.invoices,
            ),
            _Kpi(
              label: AppStrings.todayCollected,
              value: Formatters.money(d.todayCollected),
              icon: Icons.payments_outlined,
            ),
            _Kpi(
              label: AppStrings.monthSales,
              value: Formatters.money(d.monthSales),
              hint: '${d.monthInvoices} ${AppStrings.invoicesCountShort}',
              icon: Icons.calendar_month_outlined,
            ),
            if (d.monthProfit != null)
              _Kpi(
                key: const Key('kpi-month-profit'),
                label: AppStrings.monthProfit,
                value: Formatters.money(d.monthProfit),
                icon: Icons.trending_up,
              ),
            _Kpi(
              label: AppStrings.creditOutstanding,
              value: Formatters.money(d.creditBalance),
              hint: '${d.creditCustomers} ${AppStrings.customer}',
              icon: Icons.account_balance_wallet_outlined,
              path: AppRoutes.credit,
            ),
            _Kpi(
              key: const Key('kpi-jobs'),
              label: AppStrings.openJobs,
              value: '${d.openJobs}',
              hint:
                  '${AppStrings.overdue}: ${d.overdueJobs}   •   ${AppStrings.readyJobs}: ${d.readyJobs}',
              icon: Icons.work_outline,
              alert: d.overdueJobs > 0 ? error : null,
              path: AppRoutes.jobs,
            ),
            _Kpi(
              label: AppStrings.lowStockItems,
              value: '${d.lowStock}',
              icon: Icons.inventory_2_outlined,
              alert: d.lowStock > 0 ? error : null,
              path: AppRoutes.inventory,
            ),
            _Kpi(
              label: AppStrings.openSupplierOrders,
              value: '${d.openOrders}',
              hint: '${AppStrings.late}: ${d.lateOrders}',
              icon: Icons.local_shipping_outlined,
              alert: d.lateOrders > 0 ? error : null,
              path: AppRoutes.orders,
            ),
            if (d.openReferrals != null)
              _Kpi(
                label: AppStrings.openReferrals,
                value: '${d.openReferrals}',
                icon: Icons.medical_services_outlined,
                path: AppRoutes.referrals,
              ),
          ],
        ),
        const SizedBox(height: 16),
        _WeekChart(days: d.last7Days),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.hint,
    this.alert,
    this.path,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? hint;
  final Color? alert;
  final String? path;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 230,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: alert == null ? BorderSide.none : BorderSide(color: alert!, width: 1.5),
        ),
        child: InkWell(
          onTap: path == null ? null : () => context.go(path!),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 20, color: alert ?? theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(label, style: theme.textTheme.labelLarge)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(value, style: theme.textTheme.titleLarge),
                if (hint != null) Text(hint!, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Seven bars (display only; the totals come from the server).
class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.days});

  final List<({DateTime? date, double total})> days;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final max = days.map((d) => d.total).fold<double>(0, (a, b) => a > b ? a : b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(AppStrings.last7Days, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final d in days)
                    Expanded(
                      child: Tooltip(
                        message: Formatters.money(d.total),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              height: max <= 0 ? 2 : 2 + 110 * d.total / max,
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              d.date == null ? '' : '${d.date!.day}/${d.date!.month}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
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
