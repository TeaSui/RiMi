import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/drift/app_database.dart';
import '../realtime/realtime_manager.dart';
import '../realtime/realtime_manager_impl.dart';
import 'connectivity_watcher.dart';
import 'sync_flusher.dart';
import 'sync_operation.dart';
import 'sync_queue.dart';

/// Singleton AppDatabase — opened once per app lifecycle.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// ConnectivityWatcher — emits online/offline.
final connectivityWatcherProvider = Provider<ConnectivityWatcher>((ref) {
  return ConnectivityWatcher();
});

/// SyncQueue wraps the AppDatabase's SyncQueueDao.
final syncQueueProvider = Provider<SyncQueue>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SyncQueue(db);
});

/// RealtimeManager — in-memory channel registry with WS connector.
final realtimeManagerProvider = Provider<RealtimeManager>((ref) {
  final manager = RealtimeManagerImpl(
    connector: (channelKey) async {
      // Phase 2: skeleton — connector validates auth via WS handshake.
      // Phase 4+: subscribe to workspace-scoped topics using dioClientProvider
      // base URL rewritten to ws:// scheme. Channel key format: workspace:<id>:<topic>.
    },
  );
  // RealtimeManagerImpl has no explicit dispose — channels are cleaned up via cancel().
  return manager;
});

/// SyncFlusher — single-flight outbox drainer.
/// Wired to ConnectivityWatcher: flushes on reconnect.
final syncFlusherProvider = Provider<SyncFlusher>((ref) {
  final queue = ref.watch(syncQueueProvider);
  final flusher = SyncFlusher(
    // workspaceId set to empty string for Phase 2; set dynamically when workspace is active.
    workspaceId: '',
    queue: _SyncQueueAdapter(queue),
    client: _NoOpSyncClient(),
    clockMs: () => DateTime.now().millisecondsSinceEpoch,
  );

  // Trigger flush on connectivity change to online.
  final watcher = ref.watch(connectivityWatcherProvider);
  watcher.status.listen((status) {
    if (status == NetworkStatus.online) {
      flusher.flush().ignore();
    }
  });

  return flusher;
});

/// Adapter: [SyncQueue] → [FlushQueue] interface required by [SyncFlusher].
class _SyncQueueAdapter implements FlushQueue {
  _SyncQueueAdapter(this._queue);
  final SyncQueue _queue;

  @override
  Future<int> expireOldPendingOps({required int nowMs, required int maxAgeMs}) =>
      _queue.expireOldPendingOps(nowMs: nowMs, maxAgeMs: maxAgeMs);

  @override
  Future<List<String>> dequeueOpIds(
    String workspaceId, {
    required int nowMs,
    required int limit,
  }) =>
      _queue.dequeueOpIds(workspaceId, nowMs: nowMs, limit: limit);

  @override
  Future<void> markInflight(List<String> opIds, {required int nowMs}) =>
      _queue.markInflight(opIds, nowMs: nowMs);

  @override
  Future<void> markRetry(
    String opId, {
    required int nextRetryAt,
    required int nowMs,
  }) =>
      _queue.markRetry(opId, nextRetryAt: nextRetryAt, nowMs: nowMs);

  @override
  Future<void> markFailed(
    String opId, {
    required String error,
    required int nowMs,
  }) =>
      _queue.markFailed(opId, error: error, nowMs: nowMs);

  @override
  Future<void> deleteDone(String opId) => _queue.deleteDone(opId);
}

/// No-op [SyncClient] for Phase 2 skeleton (replaced with real HTTP client in Phase 3).
class _NoOpSyncClient implements SyncClient {
  @override
  Future<List<SyncOpResult>> postBatch(List<String> opIds) async => [];
}
