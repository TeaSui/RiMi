import 'package:flutter_test/flutter_test.dart';
import 'package:rimi/data/drift/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.memory();
  });

  tearDown(() async {
    await db.close();
  });

  test('dequeue returns pending eligible ops in FIFO order', () async {
    final dao = db.syncQueueDao;
    await dao.enqueueForTest(
      opId: 'op-2',
      workspaceId: 'workspace-a',
      entityType: 'inventory_item',
      entityId: 'item-2',
      opType: 'inventory_delta',
      delta: -2,
      createdAt: 2000,
    );
    await dao.enqueueForTest(
      opId: 'op-1',
      workspaceId: 'workspace-a',
      entityType: 'inventory_item',
      entityId: 'item-1',
      opType: 'inventory_delta',
      delta: -1,
      createdAt: 1000,
    );
    await dao.enqueueForTest(
      opId: 'op-later',
      workspaceId: 'workspace-a',
      entityType: 'inventory_item',
      entityId: 'item-3',
      opType: 'inventory_delta',
      delta: -3,
      createdAt: 500,
      nextRetryAt: 999999,
    );

    final ops = await dao.dequeue('workspace-a', nowMs: 3000, limit: 50);

    expect(ops.map((op) => op.opId), ['op-1', 'op-2']);
  });

  test('crash recovery resets stale inflight ops', () async {
    final dao = db.syncQueueDao;
    await dao.enqueueForTest(
      opId: 'op-inflight',
      workspaceId: 'workspace-a',
      entityType: 'inventory_item',
      entityId: 'item-1',
      opType: 'inventory_delta',
      delta: -1,
      createdAt: 1000,
    );
    await dao.markInflight(['op-inflight'], nowMs: 10000);

    await dao.resetStaleInflight(nowMs: 71001, leaseMs: 60000);
    final ops = await dao.dequeue('workspace-a', nowMs: 72000, limit: 50);

    expect(ops.single.opId, 'op-inflight');
    expect(ops.single.status, 'pending');
    expect(ops.single.inflightSince, isNull);
  });

  test('expiry sweep fails old pending ops before flush', () async {
    final dao = db.syncQueueDao;
    await dao.enqueueForTest(
      opId: 'op-old',
      workspaceId: 'workspace-a',
      entityType: 'inventory_item',
      entityId: 'item-1',
      opType: 'inventory_delta',
      delta: -1,
      createdAt: 1,
    );

    final failed = await dao.expireOldPendingOps(
      nowMs: const Duration(days: 31).inMilliseconds,
      maxAgeMs: const Duration(days: 30).inMilliseconds,
    );

    expect(failed, 1);
    final ops = await dao.dequeue(
      'workspace-a',
      nowMs: const Duration(days: 31).inMilliseconds,
      limit: 50,
    );
    expect(ops, isEmpty);
  });
}
