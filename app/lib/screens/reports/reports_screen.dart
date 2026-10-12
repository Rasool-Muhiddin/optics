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
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
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
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
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
        ),
        const SizedBox(height: 12),
        Expanded(
          child: AsyncView(
            value: ref.watch(reportProvider(_q)),
            onRetry: () => ref.invalidate(reportProvider(_q)),
            builder: (report) => ListView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
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
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('${AppStrings.estimatedCostLines}: ${r.raw['estimated_cost_lines']}'),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) Text(title!, style: theme.textTheme.titleMedium),
            if (rows.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text(AppStrings.noData))
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    for (final c in columns)
                      DataColumn(label: Text(AppStrings.reportColumns[c] ?? c)),
                  ],
                  rows: [
                    for (final row in rows)
                      DataRow(cells: [for (final c in columns) DataCell(Text(cell(c, row[c])))]),
                  ],
                ),
              ),
          ],
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
    return Card(
      key: const Key('report-totals'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 16,
          children: [
            for (final e in totals.entries)
              InfoTile(
                label: AppStrings.reportColumns[e.key] ?? e.key,
                value: ReportTableCard.cell(e.key, e.value),
                width: 170,
              ),
          ],
        ),
      ),
    );
  }
}
