import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/optics/powers.dart';
import '../../data/repositories/sales_repository.dart';
import '../../models/catalog.dart';
import '../../models/patients.dart';
import '../../models/sales.dart';

/// One cart line. Prices are NOT kept here: the server prices the cart (preview).
class CartLine {
  const CartLine({required this.product, this.variant, this.qty = 1, this.discount = ''});

  final Product product;
  final LensVariant? variant;
  final int qty;

  /// Requested discount amount for the whole line ('' = none).
  final String discount;

  String get label {
    final v = variant;
    if (v == null) return product.name;
    return '${product.name}  SPH ${Powers.format(v.sph)} CYL ${Powers.format(v.cyl)}'
        '${v.add > 0 ? ' ADD ${Powers.format(v.add)}' : ''}';
  }

  bool sameItem(Product p, LensVariant? v) => product.id == p.id && variant?.id == v?.id;

  CartLine copyWith({int? qty, String? discount}) => CartLine(
    product: product,
    variant: variant,
    qty: qty ?? this.qty,
    discount: discount ?? this.discount,
  );

  Map<String, dynamic> toJson() => {
    if (variant != null) 'variant': variant!.id else 'product': product.id,
    'qty': qty,
    if (discount.trim().isNotEmpty) 'discount': discount.trim(),
  };
}

class PosState {
  const PosState({
    this.lines = const [],
    this.patient,
    this.customerName = '',
    this.customerPhone = '',
    this.paymentType = 'cash',
    this.discountType = 'amount',
    this.discountValue = '',
    this.paymentAmount = '',
    this.paymentMethod = 'cash',
    this.notes = '',
  });

  final List<CartLine> lines;
  final Patient? patient;
  final String customerName;
  final String customerPhone;
  final String paymentType;
  final String discountType;
  final String discountValue;

  /// Down payment for credit sales (cash sales are always paid in full).
  final String paymentAmount;
  final String paymentMethod;
  final String notes;

  bool get isEmpty => lines.isEmpty;

  PosState copyWith({
    List<CartLine>? lines,
    Patient? Function()? patient,
    String? customerName,
    String? customerPhone,
    String? paymentType,
    String? discountType,
    String? discountValue,
    String? paymentAmount,
    String? paymentMethod,
    String? notes,
  }) => PosState(
    lines: lines ?? this.lines,
    patient: patient != null ? patient() : this.patient,
    customerName: customerName ?? this.customerName,
    customerPhone: customerPhone ?? this.customerPhone,
    paymentType: paymentType ?? this.paymentType,
    discountType: discountType ?? this.discountType,
    discountValue: discountValue ?? this.discountValue,
    paymentAmount: paymentAmount ?? this.paymentAmount,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    notes: notes ?? this.notes,
  );

  /// The checkout request: items, quantities and requested discounts only.
  Map<String, dynamic> toJson() => {
    'lines': [for (final l in lines) l.toJson()],
    'patient': patient?.id,
    if (patient == null) 'customer_name': customerName.trim(),
    if (patient == null) 'customer_phone': customerPhone.trim(),
    'payment_type': paymentType,
    'invoice_discount_type': discountType,
    'invoice_discount_value': discountValue.trim().isEmpty ? '0' : discountValue.trim(),
    'payment': {
      'method': paymentMethod,
      if (paymentType == 'credit')
        'amount': paymentAmount.trim().isEmpty ? '0' : paymentAmount.trim(),
    },
    'notes': notes.trim(),
  };
}

/// The cart survives navigation (not autoDispose) until checkout or "new sale".
class PosController extends Notifier<PosState> {
  @override
  PosState build() => const PosState();

  void add(Product product, {LensVariant? variant}) {
    final lines = [...state.lines];
    final i = lines.indexWhere((l) => l.sameItem(product, variant));
    if (i >= 0) {
      lines[i] = lines[i].copyWith(qty: lines[i].qty + 1);
    } else {
      lines.add(CartLine(product: product, variant: variant));
    }
    state = state.copyWith(lines: lines);
  }

  void setQty(int index, int qty) {
    final lines = [...state.lines];
    if (qty <= 0) {
      lines.removeAt(index);
    } else {
      lines[index] = lines[index].copyWith(qty: qty);
    }
    state = state.copyWith(lines: lines);
  }

  void setLineDiscount(int index, String discount) {
    final lines = [...state.lines];
    lines[index] = lines[index].copyWith(discount: discount);
    state = state.copyWith(lines: lines);
  }

  void remove(int index) => setQty(index, 0);

  void setPatient(Patient? patient) => state = state.copyWith(
    patient: () => patient,
    paymentType: patient == null ? 'cash' : state.paymentType,
  );

  void update(PosState Function(PosState s) change) => state = change(state);

  void clear() => state = const PosState();
}

final posControllerProvider = NotifierProvider<PosController, PosState>(PosController.new);

/// Server-priced totals for the current cart (re-fetched on every cart change).
final cartPreviewProvider = FutureProvider.autoDispose<CartPreview?>((ref) async {
  final cart = ref.watch(posControllerProvider);
  if (cart.isEmpty) return null;
  return ref.watch(salesRepositoryProvider).preview(cart.toJson());
});
