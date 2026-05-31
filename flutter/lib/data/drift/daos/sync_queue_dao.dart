import 'package:drift/drift.dart';

import '../app_database.dart';
import '../sync_operations_table.dart';

part 'sync_queue_dao.g.dart';

@DriftAccessor(tables: [SyncOperations])
class SyncQueueDao extends DatabaseAccessor<AppDatabase>
    with _$SyncQueueDaoMixin {
  SyncQueueDao(super.db);

  Future<void> enqueue(SyncOperationsCompanion op) {
    return into(syncOperations).insert(op);
  }

  Future<List<SyncOperation>> dequeue(
    String workspaceId, {
    required int nowMs,
    required int limit,
  }) {
    return (select(syncOperations)
          ..where((tbl) =>
              tbl.workspaceId.equals(workspaceId) &
              tbl.status.equals('pending') &
              (tbl.nextRetryAt.isNull() |
                  tbl.nextRetryAt.isSmallerOrEqualValue(nowMs)))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.createdAt)])
          ..limit(limit))
        .get();
  }

  Future<int> markInflight(List<String> opIds, {required int nowMs}) {
    return (update(syncOperations)
          ..where((tbl) => tbl.opId.isIn(opIds)))
        .write(SyncOperationsCompanion(
      status: const Value('inflight'),
      inflightSince: Value(nowMs),
      updatedAt: Value(nowMs),
    ));
  }

  Future<int> resetStaleInflight({required int nowMs, required int leaseMs}) {
    return (update(syncOperations)
          ..where((tbl) =>
              tbl.status.equals('inflight') &
              tbl.inflightSince.isSmallerThanValue(nowMs - leaseMs)))
        .write(SyncOperationsCompanion(
      status: const Value('pending'),
      inflightSince: const Value(null),
      updatedAt: Value(nowMs),
    ));
  }

  Future<int> expireOldPendingOps({
    required int nowMs,
    required int maxAgeMs,
  }) {
    return (update(syncOperations)
          ..where((tbl) =>
              tbl.status.equals('pending') &
              tbl.createdAt.isSmallerThanValue(nowMs - maxAgeMs)))
        .write(SyncOperationsCompanion(
      status: const Value('failed'),
      lastError: const Value('op_expired'),
      updatedAt: Value(nowMs),
    ));
  }

  Future<int> markFailed(
    String opId, {
    required String error,
    required int nowMs,
  }) {
    return (update(syncOperations)..where((tbl) => tbl.opId.equals(opId)))
        .write(SyncOperationsCompanion.custom(
      status: const Constant('failed'),
      lastError: Constant(error),
      updatedAt: Constant(nowMs),
      retryCount: syncOperations.retryCount + const Constant(1),
    ));
  }

  Future<int> deleteDone(String opId) {
    return (delete(syncOperations)..where((tbl) => tbl.opId.equals(opId))).go();
  }
}
