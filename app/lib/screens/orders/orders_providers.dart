import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/purchasing_repository.dart';
import '../../models/purchasing.dart';

final supplierOrdersProvider = FutureProvider.autoDispose.family<List<SupplierOrder>, OrderQuery>(
  (ref, q) => ref.watch(purchasingRepositoryProvider).orders(q),
);

final supplierOrderProvider = FutureProvider.autoDispose.family<SupplierOrder, int>(
  (ref, id) => ref.watch(purchasingRepositoryProvider).order(id),
);

final ordersSummaryProvider = FutureProvider.autoDispose<OrdersSummary>(
  (ref) => ref.watch(purchasingRepositoryProvider).summary(),
);

final suppliersProvider = FutureProvider.autoDispose<List<Supplier>>(
  (ref) => ref.watch(purchasingRepositoryProvider).suppliers(),
);

void invalidateOrders(WidgetRef ref, [int? orderId]) {
  if (orderId != null) ref.invalidate(supplierOrderProvider(orderId));
  ref.invalidate(supplierOrdersProvider);
  ref.invalidate(ordersSummaryProvider);
  ref.invalidate(suppliersProvider);
}
