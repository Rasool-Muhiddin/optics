import 'json.dart';

/// `GET reports/dashboard/`. Money values are server strings; [monthProfit] is null
/// without the cost permission, [openReferrals] without the doctor-linking plan.
class Dashboard {
  const Dashboard({
    this.todayInvoices = 0,
    this.todaySales = '0',
    this.todayCollected = '0',
    this.monthInvoices = 0,
    this.monthSales = '0',
    this.monthProfit,
    this.creditCustomers = 0,
    this.creditBalance = '0',
    this.openJobs = 0,
    this.overdueJobs = 0,
    this.readyJobs = 0,
    this.lowStock = 0,
    this.openOrders = 0,
    this.lateOrders = 0,
    this.openReferrals,
    this.last7Days = const [],
  });

  factory Dashboard.fromJson(Map<String, dynamic> j) {
    final today = Json.map(j['today']);
    final month = Json.map(j['month']);
    final credit = Json.map(j['credit']);
    final jobs = Json.map(j['jobs']);
    final orders = Json.map(j['orders']);
    return Dashboard(
      todayInvoices: Json.int0(today['invoices']),
      todaySales: Json.str(today['sales_total']),
      todayCollected: Json.str(today['collected']),
      monthInvoices: Json.int0(month['invoices']),
      monthSales: Json.str(month['sales_total']),
      monthProfit: Json.decimal(month['profit']),
      creditCustomers: Json.int0(credit['customers']),
      creditBalance: Json.str(credit['balance']),
      openJobs: Json.int0(jobs['open']),
      overdueJobs: Json.int0(jobs['overdue']),
      readyJobs: Json.int0(jobs['ready']),
      lowStock: Json.int0(Json.map(j['stock'])['low']),
      openOrders: Json.int0(orders['open']),
      lateOrders: Json.int0(orders['late']),
      openReferrals: j['referrals'] is Map ? Json.int0(Json.map(j['referrals'])['open']) : null,
      last7Days: [
        for (final d in Json.list(j['sales_last_7_days']))
          (date: Json.date(d['date']), total: Json.dbl(d['total'])),
      ],
    );
  }

  final int todayInvoices;
  final String todaySales;
  final String todayCollected;
  final int monthInvoices;
  final String monthSales;
  final String? monthProfit;
  final int creditCustomers;
  final String creditBalance;
  final int openJobs;
  final int overdueJobs;
  final int readyJobs;
  final int lowStock;
  final int openOrders;
  final int lateOrders;
  final int? openReferrals;

  /// For the small bar chart only (display, never money arithmetic).
  final List<({DateTime? date, double total})> last7Days;
}

/// Any report: a main table (`columns` keys + `rows`), `totals` and extra sections.
class ReportTable {
  const ReportTable({
    required this.columns,
    required this.rows,
    this.totals = const {},
    this.raw = const {},
  });

  factory ReportTable.fromJson(Map<String, dynamic> j) => ReportTable(
    columns: [for (final c in (j['columns'] as List? ?? const [])) '$c'],
    rows: Json.list(j['rows']),
    totals: Json.map(j['totals']),
    raw: j,
  );

  final List<String> columns;
  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic> totals;

  /// Whole response (extra sections: `payments_by_method`, `by_kind`, `ageing`…).
  final Map<String, dynamic> raw;

  List<Map<String, dynamic>> section(String key) => Json.list(raw[key]);
}
