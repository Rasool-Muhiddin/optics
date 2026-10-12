import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../models/json.dart';
import '../../models/sales.dart';
import '../../services/connectivity_service.dart';
import '../api/sales_api_service.dart';
import '../cache/cache_database.dart';
import '../cache/json_cache_dao.dart';
import 'base_repository.dart';

/// Invoice list filters (provider key).
typedef InvoiceQuery = ({String search, String? status, bool onlyBalance, int? patientId});

/// Sales. Selling needs the server (prices, stock, numbering); invoices stay readable and
/// printable offline from the cache.
class SalesRepository extends BaseRepository {
  SalesRepository(super.connectivity, {required this.api, required CacheDatabase cache})
    : invoicesDao = JsonCacheDao(cache, CacheTables.invoices),
      creditDao = JsonCacheDao(cache, CacheTables.creditCustomers);

  final SalesApiService api;
  final JsonCacheDao invoicesDao;
  final JsonCacheDao creditDao;

  /// Server totals for a cart (online only; nothing is saved).
  Future<CartPreview> preview(Map<String, dynamic> cart) =>
      write(() async => CartPreview.fromJson(await api.preview(cart)));

  Future<Invoice> checkout(Map<String, dynamic> cart) => write(() async {
    final json = await api.checkout(cart);
    await invoicesDao.upsertAll([json]);
    return Invoice.fromJson(json);
  });

  Future<PageResult<Invoice>> invoices(InvoiceQuery q, {int page = 1}) => read(
    remote: () async {
      final json = await api.invoices({
        if (q.search.trim().isNotEmpty) 'search': q.search.trim(),
        'status': ?q.status,
        if (q.onlyBalance) 'has_balance': 'true',
        'patient': ?q.patientId,
        'page': page,
        'page_size': 100,
      });
      // List rows have no lines: keep any cached detail (with lines) intact.
      for (final row in PageResult.rows(json)) {
        final cached = await invoicesDao.getById(Json.int0(row['id']));
        await invoicesDao.upsertAll([
          {...?cached, ...row},
        ]);
      }
      return PageResult.fromJson(json, Invoice.fromJson);
    },
    cached: () async {
      final query = q.search.trim().toLowerCase();
      final rows =
          (await invoicesDao.getAll())
              .map(Invoice.fromJson)
              .where(
                (i) =>
                    (query.isEmpty ||
                        '${i.number}' == query ||
                        i.customerLabel.toLowerCase().contains(query) ||
                        i.customerPhone.contains(query)) &&
                    (q.status == null || i.status == q.status) &&
                    (!q.onlyBalance || i.hasBalance) &&
                    (q.patientId == null || i.patientId == q.patientId),
              )
              .toList()
            ..sort((a, b) => b.number.compareTo(a.number));
      return PageResult(items: rows, count: rows.length);
    },
  );

  Future<Invoice> invoice(int id) => read(
    remote: () => api.invoice(id),
    cached: () async {
      final row = await invoicesDao.getById(id);
      if (row == null || row['lines'] == null) throw const NotCachedException();
      return row;
    },
    saveToCache: (json) => invoicesDao.upsertAll([json]),
  ).then(Invoice.fromJson);

  Future<Invoice> addPayment(
    int invoiceId, {
    required String amount,
    required String method,
    String note = '',
  }) => write(() async {
    final json = await api.addPayment(invoiceId, {
      'amount': amount,
      'method': method,
      'note': note,
    });
    await invoicesDao.upsertAll([json]);
    return Invoice.fromJson(json);
  });

  Future<Invoice> cancel(int invoiceId, String reason) => write(() async {
    final json = await api.cancel(invoiceId, reason);
    await invoicesDao.upsertAll([json]);
    return Invoice.fromJson(json);
  });

  Future<void> voidPayment(int paymentId, String reason) =>
      write(() => api.voidPayment(paymentId, reason));

  Future<PageResult<CreditCustomer>> creditCustomers({String search = ''}) => read(
    remote: () async {
      final json = await api.creditCustomers({
        if (search.trim().isNotEmpty) 'search': search.trim(),
        'page_size': 500,
      });
      final rows = PageResult.rows(json).map(CreditCustomer.cacheRow).toList();
      if (search.trim().isEmpty) await creditDao.replaceAll(rows);
      return PageResult.fromJson(json, CreditCustomer.fromJson);
    },
    cached: () async {
      final q = search.trim().toLowerCase();
      final rows = (await creditDao.getAll())
          .map(CreditCustomer.fromJson)
          .where((c) => q.isEmpty || c.name.toLowerCase().contains(q) || c.phone.contains(q))
          .toList();
      return PageResult(items: rows, count: rows.length);
    },
  );

  Future<List<Payment>> payCustomer(
    int patientId, {
    required String amount,
    required String method,
    String note = '',
  }) => write(() async {
    final json = await api.payCustomer(patientId, {
      'amount': amount,
      'method': method,
      'note': note,
    });
    return [for (final p in Json.list(json['payments'])) Payment.fromJson(p)];
  });
}

final salesRepositoryProvider = Provider<SalesRepository>(
  (ref) => SalesRepository(
    ref.watch(connectivityServiceProvider),
    api: ref.watch(salesApiServiceProvider),
    cache: ref.watch(cacheDatabaseProvider),
  ),
);
