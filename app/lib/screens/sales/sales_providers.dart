import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/sales_repository.dart';
import '../../models/json.dart';
import '../../models/sales.dart';

final invoiceListProvider = FutureProvider.autoDispose.family<PageResult<Invoice>, InvoiceQuery>(
  (ref, q) => ref.watch(salesRepositoryProvider).invoices(q),
);

final invoiceProvider = FutureProvider.autoDispose.family<Invoice, int>(
  (ref, id) => ref.watch(salesRepositoryProvider).invoice(id),
);

final creditCustomersProvider = FutureProvider.autoDispose
    .family<PageResult<CreditCustomer>, String>(
      (ref, search) => ref.watch(salesRepositoryProvider).creditCustomers(search: search),
    );

void invalidateSales(WidgetRef ref, [int? invoiceId]) {
  if (invoiceId != null) ref.invalidate(invoiceProvider(invoiceId));
  ref.invalidate(invoiceListProvider);
  ref.invalidate(creditCustomersProvider);
}
