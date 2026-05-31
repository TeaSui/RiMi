import 'package:drift/drift.dart';

import '../../data/drift/app_database.dart';
import 'sync_flusher.dart';

class SyncQueue implements FlushQueue {
  SyncQueue(this.db);

  final AppDatabase db;

  Future<void> enqueueInventoryDelta({
    required String opId,
    required String workspaceId,
    required String inventoryItemId,
    required int delta,
    required int nowMs,
  }) {
    return db.syncQueueDao.enqueue(SyncOperationsCompanion.insert(
      opId: opId,
      workspaceId: workspaceId,
      entityType: 'inventory_item',
      entityId: inventoryItemId,
      opType: 'inventory_delta',
      delta: Value(delta),
      payload: const Value(null),
      createdAt: nowMs,
      updatedAt: nowMs,
    ));
  }

  /// Returns the opIds of pending operations eligible for flushing.
  @override
  Future<List<String>> dequeueOpIds(
    String workspaceId, {
    required int nowMs,
    required int limit,
  }) async {
    final ops = await db.syncQueueDao.dequeue(
      workspaceId,
      nowMs: nowMs,
      limit: limit,
    );
    return ops.map((op) => op.opId).toList();
  }

  @override
  Future<int> expireOldPendingOps({
    required int nowMs,
    required int maxAgeMs,
  }) {
    return db.syncQueueDao
        .expireOldPendingOps(nowMs: nowMs, maxAgeMs: maxAgeMs);
  }

  @override
  Future<void> markInflight(List<String> opIds, {required int nowMs}) {
    return db.syncQueueDao.markInflight(opIds, nowMs: nowMs);
  }

  @override
  Future<void> markFailed(
    String opId, {
    required String error,
    required int nowMs,
  }) {
    return db.syncQueueDao.markFailed(opId, error: error, nowMs: nowMs);
  }

  @override
  Future<void> markRetry(
    String opId, {
    required int retryCount,
    required int nextRetryAt,
    required int nowMs,
  }) {
    return db.syncQueueDao
        .markRetry(opId, retryCount: retryCount, nextRetryAt: nextRetryAt, nowMs: nowMs);
  }

  @override
  Future<void> deleteDone(String opId) {
    return db.syncQueueDao.deleteDone(opId);
  }
}
