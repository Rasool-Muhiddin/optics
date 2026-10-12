import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../models/json.dart';
import '../../models/purchasing.dart';
import '../../services/connectivity_service.dart';
import '../api/purchasing_api_service.dart';
import '../cache/cache_database.dart';
import '../cache/json_cache_dao.dart';
import 'base_repository.dart';

/// Orders screen filters (provider key). [minAge] = open for at least N days.
typedef OrderQuery = ({
  String search,
  String? status,
  String? type,
  int? supplierId,
  bool openOnly,
  bool lateOnly,
  int? minAge,
  int? jobId,
});

const OrderQuery pendingOrdersQuery = (
  search: '',
  status: null,
  type: null,
  supplierId: null,
  openOnly: true,
  lateOnly: false,
  minAge: null,
  jobId: null,
);

/// Supplier orders. Ordering / receiving / paying need the server; lists and details stay
/// readable from the cache while offline.
class PurchasingRepository extends BaseRepository {
  PurchasingRepository(super.connectivity, {required this.api, required CacheDatabase cache})
    : ordersDao = JsonCacheDao(cache, CacheTables.supplierOrders),
      suppliersDao = JsonCacheDao(cache, CacheTables.suppliers);

  final PurchasingApiService api;
  final JsonCacheDao ordersDao;
  final JsonCacheDao suppliersDao;

  Future<List<Supplier>> suppliers({String search = ''}) => read(
    remote: () async {
      final json = await api.suppliers({
        if (search.trim().isNotEmpty) 'search': search.trim(),
        'page_size': 500,
      });
      final rows = PageResult.rows(json);
      if (search.trim().isEmpty) {
        await suppliersDao.replaceAll(rows);
      } else {
        await suppliersDao.upsertAll(rows);
      }
      return rows.map(Supplier.fromJson).toList();
    },
    cached: () async => (await suppliersDao.getAll())
        .map(Supplier.fromJson)
        .where((s) => s.matches(search))
        .toList(),
  );

  Future<Supplier> saveSupplier(int? id, Map<String, dynamic> body) => write(() async {
    final json = await api.saveSupplier(id, body);
    await suppliersDao.upsertAll([json]);
    return Supplier.fromJson(json);
  });

  Future<void> paySupplier(int id, {required String amount, required String method}) =>
      write(() => api.paySupplier(id, {'amount': amount, 'method': method}));

  Future<List<SupplierOrder>> orders(OrderQuery q) => read(
    remote: () async {
      final json = await api.orders({
        if (q.search.trim().isNotEmpty) 'search': q.search.trim(),
        'status': ?q.status,
        'type': ?q.type,
        'supplier': ?q.supplierId,
        if (q.openOnly) 'open': 'true',
        if (q.lateOnly) 'late': 'true',
        'min_age': ?q.minAge,
        'job': ?q.jobId,
        'ordering': 'order_date',
        'page_size': 500,
      });
      final rows = PageResult.rows(json);
      await ordersDao.upsertAll(rows);
      return rows.map(SupplierOrder.fromJson).toList();
    },
    cached: () async {
      final now = DateTime.now();
      final query = q.search.trim().toLowerCase();
      return (await ordersDao.getAll()).map(SupplierOrder.fromJson).where((o) {
        return (query.isEmpty ||
                '${o.number}' == query ||
                o.supplierName.toLowerCase().contains(query) ||
                o.supplierRef.toLowerCase().contains(query) ||
                o.jobPatientName.toLowerCase().contains(query)) &&
            (q.status == null || q.status!.split(',').contains(o.status)) &&
            (q.type == null || o.type == q.type) &&
            (q.supplierId == null || o.supplierId == q.supplierId) &&
            (q.jobId == null || o.jobId == q.jobId) &&
            (!q.openOnly || o.isOpen) &&
            (!q.lateOnly || o.lateOn(now)) &&
            (q.minAge == null || o.ageOn(now) >= q.minAge!);
      }).toList()..sort((a, b) => (a.orderDate ?? now).compareTo(b.orderDate ?? now));
    },
  );

  Future<SupplierOrder> order(int id) => read(
    remote: () => api.order(id),
    cached: () async => await ordersDao.getById(id) ?? (throw const NotCachedException()),
    saveToCache: (json) => ordersDao.upsertAll([json]),
  ).then(SupplierOrder.fromJson);

  /// Online only (counts must be live); offline it is rebuilt from cached orders.
  Future<OrdersSummary> summary() => read(
    remote: () async => OrdersSummary.fromJson(await api.summary()),
    cached: () async {
      final now = DateTime.now();
      final open = (await ordersDao.getAll())
          .map(SupplierOrder.fromJson)
          .where((o) => o.isOpen)
          .toList();
      int bucket(int from, int? to) =>
          open.where((o) => o.ageOn(now) >= from && (to == null || o.ageOn(now) <= to)).length;
      return OrdersSummary(
        open: open.length,
        late: open.where((o) => o.lateOn(now)).length,
        ageing: [
          for (final (from, to) in const [(0, 7), (8, 14), (15, 30), (31, null)])
            (from: from, to: to, count: bucket(from, to)),
        ],
      );
    },
  );

  Future<SupplierOrder> _store(Map<String, dynamic> json) async {
    await ordersDao.upsertAll([json]);
    return SupplierOrder.fromJson(json);
  }

  Future<SupplierOrder> saveOrder(int? id, Map<String, dynamic> body) =>
      write(() async => _store(await api.saveOrder(id, body)));

  Future<SupplierOrder> setStatus(int id, String status) =>
      write(() async => _store(await api.action(id, 'status', {'status': status})));

  /// [lines] = {lineId: qty}; null receives everything remaining.
  Future<SupplierOrder> receive(int id, {Map<int, int>? lines, String supplierRef = ''}) =>
      write(() async {
        final body = <String, dynamic>{
          if (lines != null)
            'lines': [
              for (final e in lines.entries)
                if (e.value > 0) {'line': e.key, 'qty': e.value},
            ],
          if (supplierRef.trim().isNotEmpty) 'supplier_ref': supplierRef.trim(),
        };
        return _store(await api.action(id, 'receive', body));
      });

  Future<SupplierOrder> cancel(int id, String reason) =>
      write(() async => _store(await api.action(id, 'cancel', {'reason': reason})));

  Future<SupplierOrder> addPayment(int id, {required String amount, required String method}) =>
      write(
        () async => _store(await api.action(id, 'payments', {'amount': amount, 'method': method})),
      );

  Future<void> voidPayment(int paymentId, String reason) =>
      write(() => api.voidPayment(paymentId, reason));
}

final purchasingRepositoryProvider = Provider<PurchasingRepository>(
  (ref) => PurchasingRepository(
    ref.watch(connectivityServiceProvider),
    api: ref.watch(purchasingApiServiceProvider),
    cache: ref.watch(cacheDatabaseProvider),
  ),
);
