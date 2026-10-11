import '../../core/errors/app_exception.dart';
import '../../services/connectivity_service.dart';

/// Base class for every domain repository — the only layer screens call.
///
/// Online-first rules (CLAUDE.md §2):
/// - read: online → API, then refresh cache; offline (or network failure) → cache.
/// - write: online → API; offline → [OfflineWriteException]. No local write queue.
abstract class BaseRepository {
  BaseRepository(this.connectivity);

  final ConnectivityService connectivity;

  /// Reads from the server when reachable (refreshing the cache), else from cache.
  Future<T> read<T>({
    required Future<T> Function() remote,
    required Future<T> Function() cached,
    Future<void> Function(T value)? saveToCache,
  }) async {
    if (connectivity.isOffline) return cached();
    try {
      final value = await remote();
      if (saveToCache != null) await saveToCache(value);
      return value;
    } on NetworkException {
      connectivity.markOffline();
      return cached();
    }
  }

  /// Sends a write to the server; refuses immediately when offline.
  Future<T> write<T>(Future<T> Function() remote) async {
    if (connectivity.isOffline) throw const OfflineWriteException();
    try {
      return await remote();
    } on NetworkException {
      connectivity.markOffline();
      rethrow;
    }
  }
}
