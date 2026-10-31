import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters/formatters.dart';
import '../../core/router/app_routes.dart';
import '../../core/strings/app_strings.dart';
import '../../data/cache/json_cache_dao.dart';
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
    final theme = Theme.of(context);
    final expires = session.plan.expiresOn;

    return RefreshIndicator(
      onRefresh: () => ref.refresh(dashboardProvider.future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, 20, AppSpacing.page, AppSpacing.xl),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${AppStrings.welcome}، ${session.user.displayName}',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${AppStrings.overview} — ${Formatters.date(DateTime.now())}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text(AppStrings.retry),
                onPressed: () => ref.invalidate(dashboardProvider),
              ),
            ],
          ),
          const OfflineNotice(tables: [CacheTables.dashboard]),
          if (state is LoggedIn && state.restoredOffline)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: NoticeBox(
                icon: Icons.cloud_off_outlined,
                tone: Tone.warning,
                message: AppStrings.sessionOffline,
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          ref
              .watch(dashboardProvider)
              .when(
                skipLoadingOnRefresh: true,
                data: (d) => _DashboardBody(dashboard: d),
                loading: () => const _DashboardSkeleton(),
                error: (e, _) =>
                    ErrorPanel(error: e, onRetry: () => ref.invalidate(dashboardProvider)),
              ),
          const SizedBox(height: AppSpacing.xl),
          SectionCard(
            title: AppStrings.accountInfo,
            icon: Icons.verified_user_outlined,
            child: Wrap(
              spacing: AppSpacing.xl,
              children: [
                InfoTile(label: AppStrings.homeLab, value: session.lab.name, width: 240),
                InfoTile(label: AppStrings.homeRole, value: Sidebar.roleLabel(session.membership)),
                InfoTile(
                  label: AppStrings.homePlan,
                  width: 320,
                  value: expires == null
                      ? session.plan.name
                      : '${session.plan.name} — ${AppStrings.homePlanExpires} '
                            '${Formatters.date(expires)}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Section title above a group of cards.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

/// Lays children out in equal-width columns that fit the available width.
class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({required this.children});

  final List<Widget> children;
  static const double minWidth = 230;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = AppSpacing.lg;
        final cols = ((c.maxWidth + gap) / (minWidth + gap)).floor().clamp(1, 6);
        final width = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final child in children) SizedBox(width: width, child: child)],
        );
      },
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.dashboard});

  final Dashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final d = dashboard;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel(AppStrings.todayLabel),
        _ResponsiveGrid(
          children: [
            KpiCard(
              key: const Key('kpi-today-sales'),
              width: null,
              label: AppStrings.todaySales,
              value: Formatters.money(d.todaySales),
              hint: '${d.todayInvoices} ${AppStrings.invoicesCountShort}',
              icon: Icons.point_of_sale,
              onTap: () => context.go(AppRoutes.invoices),
            ),
            KpiCard(
              width: null,
              label: AppStrings.todayCollected,
              value: Formatters.money(d.todayCollected),
              icon: Icons.payments_outlined,
              tone: Tone.success,
            ),
            KpiCard(
              width: null,
              label: AppStrings.monthSales,
              value: Formatters.money(d.monthSales),
              hint: '${d.monthInvoices} ${AppStrings.invoicesCountShort}',
              icon: Icons.calendar_month_outlined,
              tone: Tone.info,
            ),
            if (d.monthProfit != null)
              KpiCard(
                key: const Key('kpi-month-profit'),
                width: null,
                label: AppStrings.monthProfit,
                value: Formatters.money(d.monthProfit),
                icon: Icons.trending_up,
                tone: (double.tryParse(d.monthProfit!) ?? 0) < 0 ? Tone.danger : Tone.success,
              ),
            KpiCard(
              width: null,
              label: AppStrings.creditOutstanding,
              value: Formatters.money(d.creditBalance),
              hint: '${d.creditCustomers} ${AppStrings.customer}',
              icon: Icons.account_balance_wallet_outlined,
              tone: Tone.warning,
              onTap: () => context.go(AppRoutes.credit),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (context, c) {
            final chart = _WeekChart(days: d.last7Days);
            final compare = _TodayCompare(sales: d.todaySales, collected: d.todayCollected);
            if (c.maxWidth < 900) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  chart,
                  const SizedBox(height: AppSpacing.lg),
                  compare,
                ],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 3, child: chart),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(flex: 2, child: compare),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.xl),
        const _SectionLabel(AppStrings.openWork),
        _ResponsiveGrid(
          children: [
            KpiCard(
              key: const Key('kpi-jobs'),
              width: null,
              label: AppStrings.openJobs,
              value: '${d.openJobs}',
              hint:
                  '${AppStrings.overdue}: ${d.overdueJobs}   •   ${AppStrings.readyJobs}: ${d.readyJobs}',
              icon: Icons.work_outline,
              alert: d.overdueJobs > 0,
              onTap: () => context.go(AppRoutes.jobs),
            ),
            KpiCard(
              width: null,
              label: AppStrings.lowStockItems,
              value: '${d.lowStock}',
              icon: Icons.inventory_2_outlined,
              tone: Tone.info,
              alert: d.lowStock > 0,
              onTap: () => context.go(AppRoutes.inventory),
            ),
            KpiCard(
              width: null,
              label: AppStrings.openSupplierOrders,
              value: '${d.openOrders}',
              hint: '${AppStrings.late}: ${d.lateOrders}',
              icon: Icons.local_shipping_outlined,
              tone: Tone.info,
              alert: d.lateOrders > 0,
              onTap: () => context.go(AppRoutes.orders),
            ),
            if (d.openReferrals != null)
              KpiCard(
                width: null,
                label: AppStrings.openReferrals,
                value: '${d.openReferrals}',
                icon: Icons.medical_services_outlined,
                tone: Tone.success,
                onTap: () => context.go(AppRoutes.referrals),
              ),
          ],
        ),
      ],
    );
  }
}

/// Today: sales vs collected as two proportional bars (display only).
class _TodayCompare extends StatelessWidget {
  const _TodayCompare({required this.sales, required this.collected});

  final String sales;
  final String collected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final s = double.tryParse(sales) ?? 0;
    final c = double.tryParse(collected) ?? 0;
    final max = s > c ? s : c;

    Widget bar(String label, double value, Color color, IconData icon) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(label, style: theme.textTheme.labelLarge)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: max <= 0 ? 0 : value / max,
              minHeight: 10,
              color: color,
              backgroundColor: colors.surfaceMuted,
            ),
          ),
        ],
      ),
    );

    return SectionCard(
      title: AppStrings.todayLabel,
      subtitle: '${AppStrings.todaySales} / ${AppStrings.todayCollected}',
      icon: Icons.compare_arrows,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          bar(AppStrings.todaySales, s, theme.colorScheme.primary, Icons.point_of_sale),
          bar(AppStrings.todayCollected, c, colors.success, Icons.payments_outlined),
        ],
      ),
    );
  }
}

/// Seven bars with grid lines (display only; the totals come from the server).
class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.days});

  final List<({DateTime? date, double total})> days;

  /// Short axis label: 1,500,000 → "1.5 م", 150,000 → "150 ألف".
  static String _compact(double v) {
    if (v >= 1000000) {
      final m = v / 1000000;
      return '${m.toStringAsFixed(m >= 10 ? 0 : 1)} م';
    }
    if (v >= 1000) return '${(v / 1000).round()} ألف';
    return v.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final max = days.map((d) => d.total).fold<double>(0, (a, b) => a > b ? a : b);
    const chartHeight = 170.0;

    return SectionCard(
      title: AppStrings.last7Days,
      icon: Icons.bar_chart,
      child: days.isEmpty
          ? const EmptyState(icon: Icons.bar_chart, compact: true)
          : SizedBox(
              height: chartHeight + 28,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Y axis labels.
                  SizedBox(
                    width: 52,
                    height: chartHeight,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final f in const [1.0, 0.5, 0.0])
                          Text(
                            _compact(max * f),
                            style: theme.textTheme.labelSmall?.copyWith(color: colors.textMuted),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      children: [
                        SizedBox(
                          height: chartHeight,
                          child: Stack(
                            children: [
                              // Grid lines.
                              Column(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  for (var i = 0; i < 3; i++)
                                    Container(height: 1, color: colors.border),
                                ],
                              ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  for (var i = 0; i < days.length; i++)
                                    Expanded(
                                      child: Tooltip(
                                        message: Formatters.money(days[i].total),
                                        child: Container(
                                          height: max <= 0
                                              ? 3
                                              : 3 + (chartHeight - 10) * days[i].total / max,
                                          margin: const EdgeInsets.symmetric(horizontal: 8),
                                          decoration: BoxDecoration(
                                            color: i == days.length - 1
                                                ? theme.colorScheme.primary
                                                : theme.colorScheme.primary.withValues(alpha: 0.35),
                                            borderRadius: const BorderRadius.vertical(
                                              top: Radius.circular(AppRadius.sm),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            for (final d in days)
                              Expanded(
                                child: Text(
                                  d.date == null ? '' : '${d.date!.day}/${d.date!.month}',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colors.textMuted,
                                    fontFeatures: AppText.tabular,
                                  ),
                                ),
                              ),
                          ],
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

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return _ResponsiveGrid(
      children: [
        for (var i = 0; i < 5; i++)
          SectionCard(
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 110, height: 12),
                SizedBox(height: AppSpacing.md),
                SkeletonBox(width: 150, height: 22),
                SizedBox(height: AppSpacing.sm),
                SkeletonBox(width: 70, height: 10),
              ],
            ),
          ),
      ],
    );
  }
}
