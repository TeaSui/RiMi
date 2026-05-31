import 'package:flutter_test/flutter_test.dart';
import 'package:rimi/core/sync/sync_flusher.dart';
import 'package:rimi/core/sync/sync_operation.dart';

void main() {
  test('two concurrent flushes issue one network call', () async {
    final client = FakeSyncClient();
    final flusher = SyncFlusher(
      workspaceId: 'workspace-a',
      queue: FakeFlushQueue(opIds: ['op-1']),
      client: client,
      clockMs: () => 1000,
    );

    await Future.wait([flusher.flush(), flusher.flush()]);

    expect(client.batchCalls, 1);
  });

  test('flush expires old ops before dequeue', () async {
    final queue = FakeFlushQueue(opIds: const []);
    final flusher = SyncFlusher(
      workspaceId: 'workspace-a',
      queue: queue,
      client: FakeSyncClient(),
      clockMs: () => const Duration(days: 31).inMilliseconds,
    );

    await flusher.flush();

    expect(queue.expirySwept, true);
  });

  test('flush marks ops inflight and deletes applied results', () async {
    final queue = FakeFlushQueue(opIds: ['op-a', 'op-b']);
    final client = FakeSyncClient();
    final flusher = SyncFlusher(
      workspaceId: 'workspace-a',
      queue: queue,
      client: client,
      clockMs: () => 1000,
    );

    await flusher.flush();

    expect(queue.inflightMarked, containsAll(['op-a', 'op-b']));
    expect(queue.deletedDone, containsAll(['op-a', 'op-b']));
  });

  test('flush marks rejected ops as failed', () async {
    final queue = FakeFlushQueue(opIds: ['op-reject']);
    final client = FakeSyncClient(rejectOpIds: {'op-reject'});
    final flusher = SyncFlusher(
      workspaceId: 'workspace-a',
      queue: queue,
      client: client,
      clockMs: () => 1000,
    );

    await flusher.flush();

    expect(queue.failedOps.keys, contains('op-reject'));
  });

  test('network error calls markRetry for inflight ops', () async {
    final queue = FakeFlushQueue(opIds: ['op-1']);
    final flusher = SyncFlusher(
      workspaceId: 'workspace-a',
      queue: queue,
      client: ThrowingSyncClient(),
      clockMs: () => 5000,
    );

    await flusher.flush();

    expect(queue.retryCalledFor, contains('op-1'));
  });

  test('conflict result calls deleteDone same as applied', () async {
    final queue = FakeFlushQueue(opIds: ['op-conflict']);
    final flusher = SyncFlusher(
      workspaceId: 'workspace-a',
      queue: queue,
      client: ConflictSyncClient(),
      clockMs: () => 1000,
    );

    await flusher.flush();

    expect(queue.doneDeletedFor, contains('op-conflict'));
  });

  test('missing result from server calls markFailed with missing_result', () async {
    final queue = FakeFlushQueue(opIds: ['op-missing']);
    final flusher = SyncFlusher(
      workspaceId: 'workspace-a',
      queue: queue,
      client: EmptyResultSyncClient(),
      clockMs: () => 1000,
    );

    await flusher.flush();

    expect(queue.failedFor['op-missing'], 'missing_result');
  });
}

class FakeFlushQueue implements FlushQueue {
  FakeFlushQueue({required this.opIds});

  final List<String> opIds;
  bool expirySwept = false;
  final List<String> inflightMarked = [];
  final List<String> deletedDone = [];
  final List<String> doneDeletedFor = [];
  final Map<String, String> failedOps = {};
  final Map<String, String> failedFor = {};
  final List<String> retryCalledFor = [];

  @override
  Future<List<String>> dequeueOpIds(
    String workspaceId, {
    required int nowMs,
    required int limit,
  }) async {
    return List.of(opIds);
  }

  @override
  Future<int> expireOldPendingOps({
    required int nowMs,
    required int maxAgeMs,
  }) async {
    expirySwept = true;
    return 0;
  }

  @override
  Future<void> markInflight(List<String> opIds, {required int nowMs}) async {
    inflightMarked.addAll(opIds);
  }

  @override
  Future<void> markFailed(
    String opId, {
    required String error,
    required int nowMs,
  }) async {
    failedOps[opId] = error;
    failedFor[opId] = error;
  }

  @override
  Future<void> markRetry(
    String opId, {
    required int nextRetryAt,
    required int nowMs,
  }) async {
    retryCalledFor.add(opId);
  }

  @override
  Future<void> deleteDone(String opId) async {
    deletedDone.add(opId);
    doneDeletedFor.add(opId);
  }
}

class FakeSyncClient implements SyncClient {
  FakeSyncClient({this.rejectOpIds = const {}});

  final Set<String> rejectOpIds;
  int batchCalls = 0;

  @override
  Future<List<SyncOpResult>> postBatch(List<String> opIds) async {
    batchCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return [
      for (final opId in opIds)
        SyncOpResult(
          opId: opId,
          status: rejectOpIds.contains(opId)
              ? SyncResultStatus.rejected
              : SyncResultStatus.applied,
          resolvedValue: rejectOpIds.contains(opId) ? null : 1,
          serverUpdatedAt: DateTime.utc(2026, 5, 31),
          error: rejectOpIds.contains(opId)
              ? const SyncError(code: 'rejected', message: 'rejected')
              : null,
        ),
    ];
  }
}

class ThrowingSyncClient implements SyncClient {
  @override
  Future<List<SyncOpResult>> postBatch(List<String> opIds) async {
    throw Exception('network error');
  }
}

class ConflictSyncClient implements SyncClient {
  @override
  Future<List<SyncOpResult>> postBatch(List<String> opIds) async {
    return [
      SyncOpResult(
        opId: opIds.first,
        status: SyncResultStatus.conflict,
        resolvedValue: 5,
        serverUpdatedAt: DateTime.utc(2026, 5, 31),
        error: null,
      ),
    ];
  }
}

class EmptyResultSyncClient implements SyncClient {
  @override
  Future<List<SyncOpResult>> postBatch(List<String> opIds) async {
    return []; // returns no results — triggers missing_result path
  }
}
