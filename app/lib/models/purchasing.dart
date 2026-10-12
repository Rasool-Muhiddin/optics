import 'json.dart';

/// Supplier-order statuses / types (must match `purchasing.SupplierOrder`).
class OrderStatuses {
  const OrderStatuses._();

  static const pending = 'pending';
  static const ordered = 'ordered';
  static const partiallyReceived = 'partially_received';
  static const received = 'received';
  static const cancelled = 'cancelled';

  static const open = [pending, ordered, partiallyReceived];
  static const all = [pending, ordered, partiallyReceived, received, cancelled];
}

class OrderTypes {
  const OrderTypes._();

  static const stock = 'stock';
  static const rxForJob = 'rx_for_job';
  static const other = 'other';

  static const all = [stock, rxForJob, other];
}

class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    this.phone = '',
    this.address = '',
    this.notes = '',
    this.isActive = true,
    this.balance,
    this.openOrders = 0,
  });

  factory Supplier.fromJson(Map<String, dynamic> j) => Supplier(
    id: Json.int0(j['id']),
    name: Json.str(j['name']),
    phone: Json.str(j['phone']),
    address: Json.str(j['address']),
    notes: Json.str(j['notes']),
    isActive: Json.boolean(j['is_active'], fallback: true),
    balance: Json.decimal(j['balance']),
    openOrders: Json.int0(j['open_orders']),
  );

  final int id;
  final String name;
  final String phone;
  final String address;
  final String notes;
  final bool isActive;

  /// What the lab owes; null when the user may not see costs.
  final String? balance;
  final int openOrders;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty || name.toLowerCase().contains(q) || phone.contains(q);
  }
}

class SupplierOrderLine {
  const SupplierOrderLine({
    required this.id,
    this.productId,
    this.productName = '',
    this.productKind = '',
    this.variantId,
    this.variantLabel = '',
    this.description = '',
    this.eye = '',
    required this.qty,
    this.unitCost,
    this.lineTotal,
    this.qtyReceived = 0,
    this.qtyRemaining = 0,
  });

  factory SupplierOrderLine.fromJson(Map<String, dynamic> j) => SupplierOrderLine(
    id: Json.int0(j['id']),
    productId: Json.intOrNull(j['product']),
    productName: Json.str(j['product_name']),
    productKind: Json.str(j['product_kind']),
    variantId: Json.intOrNull(j['variant']),
    variantLabel: Json.str(j['variant_label']),
    description: Json.str(j['description']),
    eye: Json.str(j['eye']),
    qty: Json.int0(j['qty']),
    unitCost: Json.decimal(j['unit_cost']),
    lineTotal: Json.decimal(j['line_total']),
    qtyReceived: Json.int0(j['qty_received']),
    qtyRemaining: Json.int0(j['qty_remaining']),
  );

  final int id;
  final int? productId;
  final String productName;
  final String productKind;
  final int? variantId;
  final String variantLabel;
  final String description;
  final String eye;
  final int qty;
  final String? unitCost;
  final String? lineTotal;
  final int qtyReceived;
  final int qtyRemaining;

  String get label {
    final parts = [
      if (productName.isNotEmpty) productName,
      if (variantLabel.isNotEmpty) variantLabel,
      if (description.isNotEmpty) description,
    ];
    return parts.join(' — ');
  }
}

class SupplierPayment {
  const SupplierPayment({
    required this.id,
    required this.amount,
    this.method = 'cash',
    this.paidAt,
    this.paidByName = '',
    this.orderNumber,
    this.note = '',
    this.isVoid = false,
    this.voidReason = '',
  });

  factory SupplierPayment.fromJson(Map<String, dynamic> j) => SupplierPayment(
    id: Json.int0(j['id']),
    amount: Json.str(j['amount']),
    method: Json.str(j['method']),
    paidAt: Json.date(j['paid_at']),
    paidByName: Json.str(j['paid_by_name']),
    orderNumber: Json.intOrNull(j['order_number']),
    note: Json.str(j['note']),
    isVoid: Json.boolean(j['is_void']),
    voidReason: Json.str(j['void_reason']),
  );

  final int id;
  final String amount;
  final String method;
  final DateTime? paidAt;
  final String paidByName;
  final int? orderNumber;
  final String note;
  final bool isVoid;
  final String voidReason;
}

class SupplierOrder {
  const SupplierOrder({
    required this.id,
    required this.number,
    required this.supplierId,
    this.supplierName = '',
    this.type = OrderTypes.stock,
    this.jobId,
    this.jobNumber,
    this.jobPatientName = '',
    this.status = OrderStatuses.ordered,
    this.paymentStatus = 'unpaid',
    this.orderDate,
    this.expectedDate,
    this.supplierRef = '',
    this.notes = '',
    this.total,
    this.paid,
    this.balance,
    this.ageDays = 0,
    this.isLate = false,
    this.receivedAt,
    this.cancelReason = '',
    this.lines = const [],
    this.payments = const [],
    this.createdByName = '',
  });

  factory SupplierOrder.fromJson(Map<String, dynamic> j) => SupplierOrder(
    id: Json.int0(j['id']),
    number: Json.int0(j['number']),
    supplierId: Json.int0(j['supplier']),
    supplierName: Json.str(j['supplier_name']),
    type: Json.str(j['type']),
    jobId: Json.intOrNull(j['job']),
    jobNumber: Json.intOrNull(j['job_number']),
    jobPatientName: Json.str(j['job_patient_name']),
    status: Json.str(j['status']),
    paymentStatus: Json.str(j['payment_status']),
    orderDate: Json.date(j['order_date']),
    expectedDate: Json.date(j['expected_date']),
    supplierRef: Json.str(j['supplier_ref']),
    notes: Json.str(j['notes']),
    total: Json.decimal(j['total']),
    paid: Json.decimal(j['paid']),
    balance: Json.decimal(j['balance']),
    ageDays: Json.int0(j['age_days']),
    isLate: Json.boolean(j['is_late']),
    receivedAt: Json.date(j['received_at']),
    cancelReason: Json.str(j['cancel_reason']),
    lines: [for (final l in Json.list(j['lines'])) SupplierOrderLine.fromJson(l)],
    payments: [for (final p in Json.list(j['payments'])) SupplierPayment.fromJson(p)],
    createdByName: Json.str(j['created_by_name']),
  );

  final int id;
  final int number;
  final int supplierId;
  final String supplierName;
  final String type;
  final int? jobId;
  final int? jobNumber;
  final String jobPatientName;
  final String status;
  final String paymentStatus;
  final DateTime? orderDate;
  final DateTime? expectedDate;
  final String supplierRef;
  final String notes;

  /// Money fields are null when the user may not see costs.
  final String? total;
  final String? paid;
  final String? balance;

  /// Days since the order date (from the server; see [ageOn] for cached rows).
  final int ageDays;
  final bool isLate;
  final DateTime? receivedAt;
  final String cancelReason;
  final List<SupplierOrderLine> lines;
  final List<SupplierPayment> payments;
  final String createdByName;

  bool get isOpen => OrderStatuses.open.contains(status);
  bool get canEdit =>
      (status == OrderStatuses.pending || status == OrderStatuses.ordered) &&
      lines.every((l) => l.qtyReceived == 0);
  bool get canReceive => isOpen;
  bool get hasBalance => (double.tryParse(balance ?? '') ?? 0) > 0;

  /// Offline re-evaluation of [ageDays] / [isLate] (cached rows may be days old).
  int ageOn(DateTime today) {
    final d = orderDate;
    if (d == null) return ageDays;
    return DateTime(
      today.year,
      today.month,
      today.day,
    ).difference(DateTime(d.year, d.month, d.day)).inDays;
  }

  bool lateOn(DateTime today) {
    final e = expectedDate;
    if (e == null || !isOpen) return false;
    return DateTime(e.year, e.month, e.day).isBefore(DateTime(today.year, today.month, today.day));
  }
}

/// `GET purchasing/orders/summary/`.
class OrdersSummary {
  const OrdersSummary({
    this.counts = const {},
    this.open = 0,
    this.late = 0,
    this.ageing = const [],
    this.owed,
  });

  factory OrdersSummary.fromJson(Map<String, dynamic> j) => OrdersSummary(
    counts: {for (final e in Json.map(j['counts']).entries) e.key: Json.int0(e.value)},
    open: Json.int0(j['open']),
    late: Json.int0(j['late']),
    ageing: [
      for (final b in Json.list(j['ageing']))
        (
          from: Json.int0(b['from_days']),
          to: Json.intOrNull(b['to_days']),
          count: Json.int0(b['count']),
        ),
    ],
    owed: Json.decimal(j['owed']),
  );

  final Map<String, int> counts;
  final int open;
  final int late;
  final List<({int from, int? to, int count})> ageing;
  final String? owed;
}
