import 'json.dart';

class InvoiceLine {
  const InvoiceLine({
    required this.id,
    required this.productId,
    this.variantId,
    required this.description,
    required this.qty,
    required this.unitPrice,
    this.discount = '0',
    required this.lineTotal,
    this.unitCost,
  });

  factory InvoiceLine.fromJson(Map<String, dynamic> j) => InvoiceLine(
    id: Json.int0(j['id']),
    productId: Json.int0(j['product']),
    variantId: Json.intOrNull(j['variant']),
    description: Json.str(j['description']),
    qty: Json.int0(j['qty']),
    unitPrice: Json.str(j['unit_price']),
    discount: Json.str(j['discount']),
    lineTotal: Json.str(j['line_total']),
    unitCost: Json.decimal(j['unit_cost']),
  );

  final int id;
  final int productId;
  final int? variantId;
  final String description;
  final int qty;
  final String unitPrice;
  final String discount;
  final String lineTotal;
  final String? unitCost;
}

class Payment {
  const Payment({
    required this.id,
    required this.invoiceId,
    this.invoiceNumber,
    required this.amount,
    this.method = 'cash',
    this.paidAt,
    this.receivedByName = '',
    this.note = '',
    this.isVoid = false,
    this.voidReason = '',
  });

  factory Payment.fromJson(Map<String, dynamic> j) => Payment(
    id: Json.int0(j['id']),
    invoiceId: Json.int0(j['invoice']),
    invoiceNumber: Json.intOrNull(j['invoice_number']),
    amount: Json.str(j['amount']),
    method: Json.str(j['method']),
    paidAt: Json.date(j['paid_at']),
    receivedByName: Json.str(j['received_by_name']),
    note: Json.str(j['note']),
    isVoid: Json.boolean(j['is_void']),
    voidReason: Json.str(j['void_reason']),
  );

  final int id;
  final int invoiceId;
  final int? invoiceNumber;
  final String amount;
  final String method;
  final DateTime? paidAt;
  final String receivedByName;
  final String note;
  final bool isVoid;
  final String voidReason;
}

class Invoice {
  const Invoice({
    required this.id,
    required this.number,
    this.patientId,
    this.patientName = '',
    this.customerName = '',
    this.customerPhone = '',
    this.paymentType = 'cash',
    this.status = 'open',
    this.subtotal = '0',
    this.linesDiscount = '0',
    this.invoiceDiscount = '0',
    this.discountTotal = '0',
    this.total = '0',
    this.paid = '0',
    this.balance = '0',
    this.costTotal,
    this.profit,
    this.cashierName = '',
    this.notes = '',
    this.lines = const [],
    this.payments = const [],
    this.cancelReason = '',
    this.createdAt,
  });

  factory Invoice.fromJson(Map<String, dynamic> j) => Invoice(
    id: Json.int0(j['id']),
    number: Json.int0(j['number']),
    patientId: Json.intOrNull(j['patient']),
    patientName: Json.str(j['patient_name']),
    customerName: Json.str(j['customer_name']),
    customerPhone: Json.str(j['customer_phone']),
    paymentType: Json.str(j['payment_type']),
    status: Json.str(j['status']),
    subtotal: Json.str(j['subtotal']),
    linesDiscount: Json.str(j['lines_discount']),
    invoiceDiscount: Json.str(j['invoice_discount']),
    discountTotal: Json.str(j['discount_total']),
    total: Json.str(j['total']),
    paid: Json.str(j['paid']),
    balance: Json.str(j['balance']),
    costTotal: Json.decimal(j['cost_total']),
    profit: Json.decimal(j['profit']),
    cashierName: Json.str(j['cashier_name']),
    notes: Json.str(j['notes']),
    lines: [for (final l in Json.list(j['lines'])) InvoiceLine.fromJson(l)],
    payments: [for (final p in Json.list(j['payments'])) Payment.fromJson(p)],
    cancelReason: Json.str(j['cancel_reason']),
    createdAt: Json.date(j['created_at']),
  );

  final int id;
  final int number;
  final int? patientId;
  final String patientName;
  final String customerName;
  final String customerPhone;
  final String paymentType;
  final String status;
  final String subtotal;
  final String linesDiscount;
  final String invoiceDiscount;
  final String discountTotal;
  final String total;
  final String paid;
  final String balance;
  final String? costTotal;
  final String? profit;
  final String cashierName;
  final String notes;
  final List<InvoiceLine> lines;
  final List<Payment> payments;
  final String cancelReason;
  final DateTime? createdAt;

  bool get isCancelled => status == 'cancelled';

  /// Display only — the balance comes from the server.
  bool get hasBalance => !isCancelled && (double.tryParse(balance) ?? 0) > 0;

  String get customerLabel => customerName.isNotEmpty ? customerName : patientName;
}

/// Server-priced cart (`sales/checkout/preview/`).
class CartPreview {
  const CartPreview({
    required this.lines,
    required this.subtotal,
    required this.linesDiscount,
    required this.invoiceDiscount,
    required this.discountTotal,
    required this.discountPercent,
    required this.total,
    required this.maxDiscountPercent,
    required this.requiresOwner,
  });

  factory CartPreview.fromJson(Map<String, dynamic> j) => CartPreview(
    lines: [for (final l in Json.list(j['lines'])) PreviewLine.fromJson(l)],
    subtotal: Json.str(j['subtotal']),
    linesDiscount: Json.str(j['lines_discount']),
    invoiceDiscount: Json.str(j['invoice_discount']),
    discountTotal: Json.str(j['discount_total']),
    discountPercent: Json.str(j['discount_percent']),
    total: Json.str(j['total']),
    maxDiscountPercent: Json.str(j['max_discount_percent']),
    requiresOwner: Json.boolean(j['requires_owner']),
  );

  final List<PreviewLine> lines;
  final String subtotal;
  final String linesDiscount;
  final String invoiceDiscount;
  final String discountTotal;
  final String discountPercent;
  final String total;
  final String maxDiscountPercent;
  final bool requiresOwner;
}

class PreviewLine {
  const PreviewLine({
    required this.description,
    required this.qty,
    required this.unitPrice,
    required this.discount,
    required this.lineTotal,
    this.available,
  });

  factory PreviewLine.fromJson(Map<String, dynamic> j) => PreviewLine(
    description: Json.str(j['description']),
    qty: Json.int0(j['qty']),
    unitPrice: Json.str(j['unit_price']),
    discount: Json.str(j['discount']),
    lineTotal: Json.str(j['line_total']),
    available: Json.intOrNull(j['available']),
  );

  final String description;
  final int qty;
  final String unitPrice;
  final String discount;
  final String lineTotal;

  /// Stock on hand (null = not stock-tracked).
  final int? available;

  bool get shortOfStock => available != null && available! < qty;
}

class CreditCustomer {
  const CreditCustomer({
    required this.patientId,
    required this.name,
    this.phone = '',
    required this.balance,
    this.invoices = 0,
    this.oldest,
  });

  factory CreditCustomer.fromJson(Map<String, dynamic> j) => CreditCustomer(
    patientId: Json.int0(j['patient']),
    name: Json.str(j['name']),
    phone: Json.str(j['phone']),
    balance: Json.str(j['balance']),
    invoices: Json.int0(j['invoices']),
    oldest: Json.date(j['oldest']),
  );

  final int patientId;
  final String name;
  final String phone;
  final String balance;
  final int invoices;
  final DateTime? oldest;

  /// Cache rows are keyed by `id`.
  static Map<String, dynamic> cacheRow(Map<String, dynamic> j) => {...j, 'id': j['patient']};
}
