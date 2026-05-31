import 'dart:async';

import 'sync_operation.dart';

/// Abstraction over [SyncQueue] for flush-loop use.
/// Allows injecting fakes in tests without pulling in Drift.
abstract class FlushQueue {
  Future<int> expireOldPendingOps({required int nowMs, required int maxAgeMs});
  Future<List<String>> dequeueOpIds(
    String workspaceId, {
    required int nowMs,
    required int limit,
  });
  Future<void> markInflight(List<String> opIds, {required int nowMs});
  Future<void> markRetry(
    String opId, {
    required int retryCount,
    required int nextRetryAt,
    required int nowMs,
  });
  Future<void> markFailed(
    String opId, {
    required String error,
    required int nowMs,
  });
  Future<void> deleteDone(String opId);
}

/// Abstraction over the network sync endpoint.
abstract class SyncClient {
  Future<List<SyncOpResult>> postBatch(List<String> opIds);
}

/// Single-flight flush loop: concurrent [flush] calls share one in-flight
/// network call. When the call returns all waiting callers get the same result.
/// After the in-flight call completes, the next [flush] starts fresh.
class SyncFlusher {
  SyncFlusher({
    required this.workspaceId,
    required this.queue,
    required this.client,
    required this.clockMs,
  });

  static const maxBatchSize = 50;

  /// 30 days in milliseconds. Duration.inMilliseconds is not a const expression
  /// in Dart, so we use the literal value.
  static const opMaxAgeMs = 30 * 24 * 60 * 60 * 1000;

  final String workspaceId;
  final FlushQueue queue;
  final SyncClient client;
  final int Function() clockMs;

  Future<void>? _inFlight;

  /// Starts a flush if none is in progress; otherwise joins the current one.
  Future<void> flush() {
    return _inFlight ??= _doFlush().whenComplete(() => _inFlight = null);
  }

  Future<void> _doFlush() async {
    final now = clockMs();

    // Always expire stale pending ops before dequeuing.
    await queue.expireOldPendingOps(nowMs: now, maxAgeMs: opMaxAgeMs);

    final opIds = await queue.dequeueOpIds(
      workspaceId,
      nowMs: now,
      limit: maxBatchSize,
    );
    if (opIds.isEmpty) return;

    await queue.markInflight(opIds, nowMs: now);

    List<SyncOpResult> results;
    try {
      results = await client.postBatch(opIds);
    } catch (_) {
      final nowMs2 = clockMs();
      for (final opId in opIds) {
        await queue.markRetry(
          opId,
          retryCount: 1,
          nextRetryAt: nowMs2 + 4000,
          nowMs: nowMs2,
        );
      }
      return;
    }
    final resultById = {for (final result in results) result.opId: result};

    for (final opId in opIds) {
      final result = resultById[opId];
      if (result == null) {
        await queue.markFailed(
          opId,
          error: 'missing_result',
          nowMs: clockMs(),
        );
        continue;
      }
      switch (result.status) {
        case SyncResultStatus.applied:
        case SyncResultStatus.conflict:
          await queue.deleteDone(opId);
        case SyncResultStatus.rejected:
          await queue.markFailed(
            opId,
            error: result.error?.code ?? 'rejected',
            nowMs: clockMs(),
          );
      }
    }
  }
}
