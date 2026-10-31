import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters/formatters.dart';
import '../../core/strings/app_strings.dart';
import '../../data/cache/json_cache_dao.dart';
import '../../data/repositories/reports_repository.dart';
import '../../models/reports.dart';
import '../../models/session.dart';
import '../../services/auth_controller.dart';
import '../../widgets/common.dart';

/// Report request (provider key): report name + query parameters.
typedef ReportQuery = ({String name, String from, String to, String group, bool all});

final reportProvider = FutureProvider.autoDispose.family<ReportTable, ReportQuery>(
  (ref, q) => ref.watch(reportsRepositoryProvider).report(q.name, reportParams(q)),
);

Map<String, dynamic> reportParams(ReportQuery q) => {
  if (q.name == 'sales' || q.name == 'profit') ...{
    'date_from': q.from,
    'date_to': q.to,
    'group': q.group,
  },
  if (q.all) 'all': 'true',
};

/// Money-valued columns (formatted as currency).
const _moneyKeys = {
  'subtotal',
  'discount',
  'total',
  'balance',
  'revenue',
  'cost',
  'profit',
  'value',
  'amount',
};

/// Reports (owner / staff with cost permission): sales, profit, credit, low stock, overdue
/// jobs, supplier balances. CSV export when the plan includes `report_export`.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  static String _day(DateTime d) => d.toIso8601String().substring(0, 10);

  late ReportQuery _q = (
    name: 'sales',
    from: _day(DateTime(DateTime.now().year, DateTime.now().month)),
    to: _day(DateTime.now()),
    group: 'day',
    all: false,
  );
  bool _exporting = false;

  void _set({String? name, String? from, String? to, String? group, bool? all}) => setState(
    () => _q = (
      name: name ?? _q.name,
      from: from ?? _q.from,
      to: to ?? _q.to,
      group: group ?? _q.group,
      all: all ?? _q.all,
    ),
  );

  Future<void> _pickDate(bool start) async {
    final current = DateTime.parse(start ? _q.from : _q.to);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) start ? _set(from: _day(picked)) : _set(to: _day(picked));
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final path = await ref.read(reportsRepositoryProvider).exportCsv(_q.name, reportParams(_q));
      if (mounted) showSnack(context, '${AppStrings.exportedTo}: $path');
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final canExport = session?.hasFeature(Features.reportExport) ?? false;
    final dated = _q.name == 'sales' || _q.name == 'profit';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: AppStrings.reportsTitle,
          cacheTables: const [CacheTables.reportResults],
          actions: [
            Tooltip(
              message: canExport ? '' : AppStrings.exportNotInPlan,
              child: OutlinedButton.icon(
                key: const Key('report-export'),
                icon: const Icon(Icons.download_outlined),
                label: const Text(AppStrings.exportCsv),
                onPressed: canExport && !_exporting ? _export : null,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final r in AppStrings.reportNames.entries)
                ChoiceChip(
                  key: Key('report-${r.key}'),
                  label: Text(r.value),
                  selected: _q.name == r.key,
                  onSelected: (_) => _set(name: r.key, all: false),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        FilterBar(
          children: [
            if (dated) ...[
              ActionChip(
                avatar: const Icon(Icons.event, size: 18),
                label: Text('${AppStrings.dateFrom}: ${_q.from}'),
                onPressed: () => _pickDate(true),
              ),
              ActionChip(
                avatar: const Icon(Icons.event, size: 18),
                label: Text('${AppStrings.dateTo}: ${_q.to}'),
                onPressed: () => _pickDate(false),
              ),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'day', label: Text(AppStrings.groupByDay)),
                  ButtonSegment(value: 'month', label: Text(AppStrings.groupByMonth)),
                ],
                selected: {_q.group},
                onSelectionChanged: (v) => _set(group: v.first),
              ),
            ],
            if (_q.name == 'stock' || _q.name == 'suppliers')
              FilterChip(
                key: const Key('report-all'),
                label: const Text(AppStrings.showAll),
                selected: _q.all,
                onSelected: (v) => _set(all: v),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: AsyncView(
            value: ref.watch(reportProvider(_q)),
            skeleton: true,
            onRetry: () => ref.invalidate(reportProvider(_q)),
            builder: (report) => ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                0,
                AppSpacing.page,
                AppSpacing.page,
              ),
              children: [
                ReportTableCard(columns: report.columns, rows: report.rows),
                if (report.totals.isNotEmpty) _Totals(totals: report.totals),
                ..._sections(report),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _sections(ReportTable r) {
    Widget section(String title, String key, List<String> columns) {
      final rows = r.section(key);
      if (rows.isEmpty) return const SizedBox.shrink();
      return ReportTableCard(title: title, columns: columns, rows: rows);
    }

    return switch (_q.name) {
      'sales' => [
        section(AppStrings.paymentsByMethod, 'payments_by_method', ['method', 'count', 'amount']),
        section(AppStrings.topProducts, 'top_products', ['name', 'kind', 'qty', 'revenue']),
      ],
      'profit' => [
        section(AppStrings.byKind, 'by_kind', ['kind', 'revenue', 'cost', 'profit', 'margin']),
        if ((r.raw['estimated_cost_lines'] as num? ?? 0) > 0)
          NoticeBox(
            message: '${AppStrings.estimatedCostLines}: ${r.raw['estimated_cost_lines']}',
            tone: Tone.warning,
          ),
      ],
      'credit' => [
        ReportTableCard(
          title: AppStrings.creditAgeing,
          columns: const ['range', 'customers', 'balance'],
          rows: [
            for (final b in r.section('ageing'))
              {
                'range': b['to_days'] == null
                    ? '+${(b['from_days'] as int) - 1}'
                    : '${b['from_days']}–${b['to_days']}',
                'customers': b['customers'],
                'balance': b['balance'],
              },
          ],
        ),
      ],
      'stock' => [
        section(AppStrings.stockValueByKind, 'value_by_kind', ['kind', 'value']),
      ],
      'jobs' => [
        ReportTableCard(
          title: AppStrings.countsByStatus,
          columns: const ['status', 'count'],
          rows: [
            for (final e in (r.raw['counts'] as Map? ?? const {}).entries)
              {'status': e.key, 'count': e.value},
          ],
        ),
      ],
      _ => const [],
    };
  }
}

/// Generic report table: keys → Arabic headers, money formatted, kinds/statuses labelled.
class ReportTableCard extends StatelessWidget {
  const ReportTableCard({super.key, required this.columns, required this.rows, this.title});

  final String? title;
  final List<String> columns;
  final List<Map<String, dynamic>> rows;

  static String cell(String key, Object? value) {
    if (value == null) return '';
    if (_moneyKeys.contains(key)) return Formatters.money(value);
    return switch (key) {
      'kind' => AppStrings.label(AppStrings.productKinds, '$value'),
      'status' => AppStrings.jobStatuses['$value'] ?? '$value',
      'method' => AppStrings.paymentMethods['$value'] ?? '$value',
      _ => '$value',
    };
  }

  /// Money and plain numbers are aligned to the end of the cell.
  bool _numeric(String key) =>
      _moneyKeys.contains(key) ||
      rows.isNotEmpty && rows.every((r) => r[key] == null || r[key] is num);

  @override
  Widget build(BuildContext context) {
    final cols = [
      for (final c in columns)
        TableCol(AppStrings.reportColumns[c] ?? c, flex: 2, numeric: _numeric(c)),
    ];
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: SectionCard(
        title: title,
        icon: title == null ? null : Icons.table_chart_outlined,
        padding: EdgeInsets.zero,
        child: rows.isEmpty
            ? const EmptyState(icon: Icons.table_chart_outlined, compact: true)
            : LayoutBuilder(
                builder: (context, c) {
                  // Wide reports scroll sideways instead of squeezing the columns.
                  final width = c.maxWidth < columns.length * 140.0
                      ? columns.length * 140.0
                      : c.maxWidth;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: width,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DataTableHeader(columns: cols),
                          for (var i = 0; i < rows.length; i++)
                            DataRowView(
                              columns: cols,
                              index: i,
                              cells: [
                                for (final k in columns)
                                  Text(
                                    cell(k, rows[i][k]),
                                    overflow: TextOverflow.ellipsis,
                                    textDirection: _numeric(k) ? TextDirection.ltr : null,
                                    style: TextStyle(
                                      fontFeatures: AppText.tabular,
                                      fontWeight: k == 'profit' || k == 'total'
                                          ? FontWeight.w600
                                          : null,
                                      color:
                                          k == 'profit' && (num.tryParse('${rows[i][k]}') ?? 0) < 0
                                          ? colors.danger
                                          : null,
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.totals});

  final Map<String, dynamic> totals;

  @override
  Widget build(BuildContext context) {
    Tone tone(String key) => switch (key) {
      'profit' => Tone.success,
      'balance' => Tone.danger,
      'cost' || 'discount' => Tone.warning,
      _ => Tone.primary,
    };
    IconData icon(String key) => switch (key) {
      'profit' => Icons.trending_up,
      'balance' => Icons.account_balance_wallet_outlined,
      'discount' => Icons.percent,
      'cost' => Icons.price_change_outlined,
      _ when _moneyKeys.contains(key) => Icons.payments_outlined,
      _ => Icons.tag,
    };
    return Padding(
      key: const Key('report-totals'),
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [
          for (final e in totals.entries)
            KpiCard(
              width: 220,
              label: AppStrings.reportColumns[e.key] ?? e.key,
              value: ReportTableCard.cell(e.key, e.value),
              icon: icon(e.key),
              tone: tone(e.key),
            ),
        ],
      ),
    );
  }
}
