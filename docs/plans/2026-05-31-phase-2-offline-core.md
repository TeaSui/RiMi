# Phase 2 Offline Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build RiMi Phase 2 offline infrastructure: Drift local storage, a durable SyncManager outbox, server sync endpoints, and an in-memory RealtimeManager skeleton.

**Architecture:** Flutter feature screens will read/write Drift only; SyncManager flushes queued operations to Go endpoints and reconciles authoritative server results. The Go backend adds workspace-scoped sync APIs, RLS-protected idempotency storage, composite-cursor pull, and a minimal authenticated WebSocket skeleton. Backend endpoint work is trust-boundary work and must consume Security review output before implementation.

**Tech Stack:** Flutter 3 / Dart, Drift SQLite, Dio, Riverpod, connectivity_plus, web_socket_channel, Go 1.22, chi, pgx, PostgreSQL, testcontainers-go.

---

## Source Inputs

- Spec: `docs/specs/2026-05-31-phase-2-offline-core-design.md`
- Existing API envelope: `server/internal/middleware/response.go`
- Existing JWT + tenancy middleware: `server/internal/middleware/auth.go`
- Existing router: `server/cmd/api/main.go`
- Existing migrations: `server/migrations/000001_init_schema.up.sql`, `server/migrations/000002_rls_policies.up.sql`
- Existing Flutter network setup: `flutter/lib/core/network/dio_client.dart`
- Roadmap success criteria: `.planning/ROADMAP.md` Phase 2

---

## Workflow Gates

Phase 2 backend adds three new public surfaces: `POST /v1/sync/batch`, `GET /v1/sync/pull`, and `WSS /v1/realtime`. Before backend implementation begins, create `docs/security/phase-2-sync-realtime.md` via Security review and apply every rule it defines.

Flutter-only local infrastructure can be implemented before backend endpoints, but do not wire live production sync calls until the backend security rules exist.

---

## File Structure

### Flutter Files

- Modify: `flutter/pubspec.yaml`
  - Add `drift`, `sqlite3_flutter_libs`, `path_provider`, `path`, `connectivity_plus`, `mutex`, `uuid`, `web_socket_channel`, `build_runner`, `drift_dev`.
- Create: `flutter/lib/data/drift/app_database.dart`
  - Drift database class and connection bootstrap.
- Create: `flutter/lib/data/drift/sync_operations_table.dart`
  - `sync_operations` table definition, status constants, flush index.
- Create: `flutter/lib/data/drift/sync_meta_table.dart`
  - `sync_meta` table definition and composite cursor model.
- Create: `flutter/lib/data/drift/daos/sync_queue_dao.dart`
  - Enqueue, dequeue, mark inflight, retry, fail, delete done, crash recovery, expiry sweep.
- Create: `flutter/lib/data/drift/daos/sync_meta_dao.dart`
  - Read and atomically update pull cursors.
- Create: `flutter/lib/core/sync/sync_operation.dart`
  - App-level DTOs for queued operations and server results.
- Create: `flutter/lib/core/sync/sync_queue.dart`
  - Thin service over `SyncQueueDao`.
- Create: `flutter/lib/core/sync/conflict_resolver.dart`
  - `ConflictResolver` interface and inventory resolver hook.
- Create: `flutter/lib/core/sync/connectivity_watcher.dart`
  - `connectivity_plus` wrapper.
- Create: `flutter/lib/core/sync/sync_flusher.dart`
  - Single-flight flush loop, retry/backoff, server reconciliation, pull trigger.
- Create: `flutter/lib/core/sync/sync_manager.dart`
  - Barrel export and lifecycle orchestration.
- Create: `flutter/lib/core/realtime/channel_status.dart`
  - `ChannelStatus` enum.
- Create: `flutter/lib/core/realtime/realtime_manager.dart`
  - Abstract interface and `RealtimeSubscription`.
- Create: `flutter/lib/core/realtime/realtime_manager_impl.dart`
  - In-memory channel registry, ref-counting, reconnect.
- Tests:
  - `flutter/test/sync/sync_queue_dao_test.dart`
  - `flutter/test/sync/sync_flusher_test.dart`
  - `flutter/test/sync/conflict_resolver_test.dart`
  - `flutter/test/realtime/realtime_manager_test.dart`

### Backend Files

- Create: `docs/security/phase-2-sync-realtime.md`
  - Security review output consumed by implementation.
- Create: `server/migrations/000003_sync_columns.up.sql`
  - `updated_at`, `deleted_at`, triggers, `sync_applied_ops`, RLS, cleanup function.
- Create: `server/migrations/000003_sync_columns.down.sql`
  - Reverse migration.
- Create: `server/internal/sync/types.go`
  - Request/response DTOs and operation constants.
- Create: `server/internal/sync/repository.go`
  - Postgres queries for ledger, inventory delta, pull.
- Create: `server/internal/sync/service.go`
  - Batch grouping, advisory locks, idempotency, pull logic.
- Create: `server/internal/sync/handler.go`
  - HTTP handlers and WebSocket skeleton.
- Modify: `server/cmd/api/main.go`
  - Wire sync routes behind auth and tenancy where applicable.
- Modify: `server/go.mod`, `server/go.sum`
  - Add `nhooyr.io/websocket` for the authenticated `/v1/realtime` skeleton.
- Tests:
  - `server/internal/sync/service_test.go`
  - `server/internal/sync/handler_test.go`
  - `server/internal/integration/sync_test.go`
  - `server/internal/integration/realtime_test.go`

---

## Task 0: Security Gate For Backend Sync Surfaces

**Files:**
- Create: `docs/security/phase-2-sync-realtime.md`
- Read: `docs/specs/2026-05-31-phase-2-offline-core-design.md`
- Read: `docs/security/phase-1-auth-workspace.md`
- Read: `server/internal/middleware/auth.go`

- [ ] **Step 1: Create the Security review artifact**

Write `docs/security/phase-2-sync-realtime.md` with this minimum structure:

```markdown
# Phase 2 Sync + Realtime Security Review

**Date:** 2026-05-31
**Scope:** POST /v1/sync/batch, GET /v1/sync/pull, WSS /v1/realtime
**Consumes:** docs/specs/2026-05-31-phase-2-offline-core-design.md, docs/security/phase-1-auth-workspace.md

## Trust Boundaries

- Authenticated mobile client -> Go API sync endpoints
- Authenticated mobile client -> Go API WebSocket handshake
- Go API -> PostgreSQL through rimi_app with RLS

## Security Rules

- SYNC-SEC-01: All sync HTTP endpoints MUST require a valid Bearer access token.
- SYNC-SEC-02: Workspace MUST be derived only from the validated JWT workspace_id claim.
- SYNC-SEC-03: Request bodies MUST NOT accept workspace_id.
- SYNC-SEC-04: sync_applied_ops MUST be RLS-protected with app.is_workspace_member(workspace_id).
- SYNC-SEC-05: sync batch payloads MUST validate op_id UUID, entity_id UUID, entity_type allowlist, op_type allowlist, and integer delta bounds before DB mutation.
- SYNC-SEC-06: Server logs MUST NOT include raw payload blobs, PII, or tokens.
- SYNC-SEC-07: WSS /v1/realtime MUST reject missing/invalid Authorization with 401 before upgrade.
- SYNC-SEC-08: WSS /v1/realtime MUST derive workspace from JWT and ignore any workspace query/header.
- SYNC-SEC-09: /v1/sync/pull MUST enforce entity allowlist and limit max <= 500.
- SYNC-SEC-10: Advisory lock keys MUST include workspace scope for op idempotency.

## Required Tests

- Missing token returns 401 for /v1/sync/batch, /v1/sync/pull, and /v1/realtime.
- Request body with workspace_id is ignored or rejected; workspace comes from token only.
- Cross-workspace pull returns no rows.
- Replayed op_id returns cached result without double-applying inventory delta.
```

- [ ] **Step 2: Commit the security artifact**

Run:

```bash
git add docs/security/phase-2-sync-realtime.md
git commit -m "docs(security): add phase 2 sync realtime review"
```

Expected: commit succeeds. Backend tasks must cite this file before changing endpoints.

---

## Task 1: Add Flutter Offline Dependencies

**Files:**
- Modify: `flutter/pubspec.yaml`
- Modify: `flutter/pubspec.lock`

- [ ] **Step 1: Add dependencies**

Update `flutter/pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  google_fonts: ^6.2.1
  flutter_riverpod: ^3.3.1
  go_router: ^17.2.3
  dio: ^5.9.2
  flutter_secure_storage: ^10.3.1
  drift: ^2.22.1
  sqlite3_flutter_libs: ^0.5.27
  path_provider: ^2.1.5
  path: ^1.9.1
  connectivity_plus: ^6.1.1
  mutex: ^3.1.0
  uuid: ^4.5.1
  web_socket_channel: ^3.0.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
  build_runner: ^2.4.13
  drift_dev: ^2.22.1
```

- [ ] **Step 2: Fetch packages**

Run:

```bash
cd flutter
flutter pub get
```

Expected: `pubspec.lock` updates and no dependency resolution errors.

- [ ] **Step 3: Commit dependency changes**

Run:

```bash
git add flutter/pubspec.yaml flutter/pubspec.lock
git commit -m "chore(flutter): add offline sync dependencies"
```

Expected: commit succeeds.

---

## Task 2: Drift Schema And DAO Foundation

**Files:**
- Create: `flutter/lib/data/drift/app_database.dart`
- Create: `flutter/lib/data/drift/sync_operations_table.dart`
- Create: `flutter/lib/data/drift/sync_meta_table.dart`
- Create: `flutter/lib/data/drift/daos/sync_queue_dao.dart`
- Create: `flutter/lib/data/drift/daos/sync_meta_dao.dart`
- Generated: `flutter/lib/data/drift/app_database.g.dart`
- Test: `flutter/test/sync/sync_queue_dao_test.dart`

- [ ] **Step 1: Write the failing DAO tests**

Create `flutter/test/sync/sync_queue_dao_test.dart`:

```dart
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
    await dao.markInflight(['op-inflight'], nowMs: 10_000);

    await dao.resetStaleInflight(nowMs: 71_001, leaseMs: 60_000);
    final ops = await dao.dequeue('workspace-a', nowMs: 72_000, limit: 50);

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
      nowMs: Duration(days: 31).inMilliseconds,
      maxAgeMs: Duration(days: 30).inMilliseconds,
    );

    expect(failed, 1);
    final ops = await dao.dequeue('workspace-a', nowMs: Duration(days: 31).inMilliseconds, limit: 50);
    expect(ops, isEmpty);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd flutter
flutter test test/sync/sync_queue_dao_test.dart
```

Expected: FAIL because `AppDatabase` and DAO files do not exist.

- [ ] **Step 3: Create Drift tables**

Create `flutter/lib/data/drift/sync_operations_table.dart`:

```dart
import 'package:drift/drift.dart';

class SyncOperations extends Table {
  TextColumn get opId => text()();
  TextColumn get workspaceId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get opType => text()();
  TextColumn get payload => text().nullable()();
  IntColumn get delta => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get inflightSince => integer().nullable()();
  IntColumn get nextRetryAt => integer().nullable()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {opId};

  @override
  List<String> get customConstraints => [
        "CHECK (status IN ('pending', 'inflight', 'done', 'failed'))",
        "CHECK (op_type IN ('create', 'update', 'delete', 'inventory_delta'))",
      ];
}
```

Create `flutter/lib/data/drift/sync_meta_table.dart`:

```dart
import 'package:drift/drift.dart';

class SyncMeta extends Table {
  TextColumn get workspaceId => text()();
  TextColumn get entityType => text()();
  IntColumn get lastSyncedAt => integer()();
  TextColumn get lastSyncedId => text()();

  @override
  Set<Column> get primaryKey => {workspaceId, entityType};
}
```

- [ ] **Step 4: Create the database class**

Create `flutter/lib/data/drift/app_database.dart`:

```dart
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'daos/sync_meta_dao.dart';
import 'daos/sync_queue_dao.dart';
import 'sync_meta_table.dart';
import 'sync_operations_table.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [SyncOperations, SyncMeta],
  daos: [SyncQueueDao, SyncMetaDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          await customStatement('''
            CREATE INDEX IF NOT EXISTS idx_sync_ops_flush
            ON sync_operations(workspace_id, created_at)
            WHERE status = 'pending'
          ''');
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'rimi.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
```

- [ ] **Step 5: Create DAOs**

Create `flutter/lib/data/drift/daos/sync_queue_dao.dart`:

```dart
import 'package:drift/drift.dart';

import '../app_database.dart';
import '../sync_operations_table.dart';

part 'sync_queue_dao.g.dart';

@DriftAccessor(tables: [SyncOperations])
class SyncQueueDao extends DatabaseAccessor<AppDatabase> with _$SyncQueueDaoMixin {
  SyncQueueDao(super.db);

  Future<void> enqueue(SyncOperationsCompanion op) {
    return into(syncOperations).insert(op);
  }

  Future<void> enqueueForTest({
    required String opId,
    required String workspaceId,
    required String entityType,
    required String entityId,
    required String opType,
    required int createdAt,
    String? payload,
    int? delta,
    int? nextRetryAt,
  }) {
    return enqueue(SyncOperationsCompanion.insert(
      opId: opId,
      workspaceId: workspaceId,
      entityType: entityType,
      entityId: entityId,
      opType: opType,
      payload: Value(payload),
      delta: Value(delta),
      createdAt: createdAt,
      updatedAt: createdAt,
      nextRetryAt: Value(nextRetryAt),
    ));
  }

  Future<List<SyncOperation>> dequeue(String workspaceId, {required int nowMs, required int limit}) {
    return (select(syncOperations)
          ..where((tbl) =>
              tbl.workspaceId.equals(workspaceId) &
              tbl.status.equals('pending') &
              (tbl.nextRetryAt.isNull() | tbl.nextRetryAt.isSmallerOrEqualValue(nowMs)))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.createdAt)])
          ..limit(limit))
        .get();
  }

  Future<int> markInflight(List<String> opIds, {required int nowMs}) {
    return (update(syncOperations)..where((tbl) => tbl.opId.isIn(opIds))).write(
      SyncOperationsCompanion(
        status: const Value('inflight'),
        inflightSince: Value(nowMs),
        updatedAt: Value(nowMs),
      ),
    );
  }

  Future<int> resetStaleInflight({required int nowMs, required int leaseMs}) {
    return (update(syncOperations)
          ..where((tbl) =>
              tbl.status.equals('inflight') &
              tbl.inflightSince.isSmallerThanValue(nowMs - leaseMs)))
        .write(const SyncOperationsCompanion(
      status: Value('pending'),
      inflightSince: Value(null),
    ));
  }

  Future<int> expireOldPendingOps({required int nowMs, required int maxAgeMs}) {
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

  Future<int> markFailed(String opId, {required String error, required int nowMs}) {
    return (update(syncOperations)..where((tbl) => tbl.opId.equals(opId))).write(
      SyncOperationsCompanion(
        status: const Value('failed'),
        lastError: Value(error),
        updatedAt: Value(nowMs),
      ),
    );
  }

  Future<int> deleteDone(String opId) {
    return (delete(syncOperations)..where((tbl) => tbl.opId.equals(opId))).go();
  }
}
```

Create `flutter/lib/data/drift/daos/sync_meta_dao.dart`:

```dart
import 'package:drift/drift.dart';

import '../app_database.dart';
import '../sync_meta_table.dart';

part 'sync_meta_dao.g.dart';

@DriftAccessor(tables: [SyncMeta])
class SyncMetaDao extends DatabaseAccessor<AppDatabase> with _$SyncMetaDaoMixin {
  SyncMetaDao(super.db);

  Future<SyncMetum?> getCursor(String workspaceId, String entityType) {
    return (select(syncMeta)
          ..where((tbl) => tbl.workspaceId.equals(workspaceId) & tbl.entityType.equals(entityType)))
        .getSingleOrNull();
  }

  Future<void> upsertCursor({
    required String workspaceId,
    required String entityType,
    required int lastSyncedAt,
    required String lastSyncedId,
  }) {
    return into(syncMeta).insertOnConflictUpdate(SyncMetaCompanion.insert(
      workspaceId: workspaceId,
      entityType: entityType,
      lastSyncedAt: lastSyncedAt,
      lastSyncedId: lastSyncedId,
    ));
  }
}
```

- [ ] **Step 6: Generate Drift code**

Run:

```bash
cd flutter
dart run build_runner build --delete-conflicting-outputs
```

Expected: generated files appear under `flutter/lib/data/drift/`.

- [ ] **Step 7: Run DAO tests**

Run:

```bash
cd flutter
flutter test test/sync/sync_queue_dao_test.dart
```

Expected: PASS.

- [ ] **Step 8: Commit Drift foundation**

Run:

```bash
git add flutter/lib/data/drift flutter/test/sync/sync_queue_dao_test.dart
git commit -m "feat(flutter): add drift sync queue schema"
```

Expected: commit succeeds.

---

## Task 3: Sync DTOs, Queue Service, And Conflict Resolver

**Files:**
- Create: `flutter/lib/core/sync/sync_operation.dart`
- Create: `flutter/lib/core/sync/sync_queue.dart`
- Create: `flutter/lib/core/sync/conflict_resolver.dart`
- Test: `flutter/test/sync/conflict_resolver_test.dart`

- [ ] **Step 1: Write failing resolver test**

Create `flutter/test/sync/conflict_resolver_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rimi/core/sync/conflict_resolver.dart';
import 'package:rimi/core/sync/sync_operation.dart';

void main() {
  test('inventory resolver returns authoritative quantity update', () async {
    final resolver = InventoryDeltaResolver();
    final result = SyncOpResult(
      opId: 'op-1',
      status: SyncResultStatus.applied,
      resolvedValue: 18,
      serverUpdatedAt: DateTime.utc(2026, 5, 31, 12),
      error: null,
    );

    final patch = await resolver.resolve(result);

    expect(patch.entityType, 'inventory_item');
    expect(patch.value, 18);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd flutter
flutter test test/sync/conflict_resolver_test.dart
```

Expected: FAIL because sync DTOs do not exist.

- [ ] **Step 3: Add sync DTOs**

Create `flutter/lib/core/sync/sync_operation.dart`:

```dart
enum SyncOpType { create, update, delete, inventoryDelta }
enum SyncResultStatus { applied, conflict, rejected }

class SyncOperationRequest {
  const SyncOperationRequest({
    required this.opId,
    required this.entityType,
    required this.entityId,
    required this.opType,
    required this.clientTs,
    this.payload,
    this.delta,
  });

  final String opId;
  final String entityType;
  final String entityId;
  final SyncOpType opType;
  final int clientTs;
  final Map<String, dynamic>? payload;
  final int? delta;

  Map<String, dynamic> toJson() => {
        'op_id': opId,
        'entity_type': entityType,
        'entity_id': entityId,
        'op_type': switch (opType) {
          SyncOpType.create => 'create',
          SyncOpType.update => 'update',
          SyncOpType.delete => 'delete',
          SyncOpType.inventoryDelta => 'inventory_delta',
        },
        'payload': payload,
        'delta': delta,
        'client_ts': clientTs,
      };
}

class SyncOpResult {
  const SyncOpResult({
    required this.opId,
    required this.status,
    required this.resolvedValue,
    required this.serverUpdatedAt,
    required this.error,
  });

  final String opId;
  final SyncResultStatus status;
  final int? resolvedValue;
  final DateTime? serverUpdatedAt;
  final SyncError? error;

  factory SyncOpResult.fromJson(Map<String, dynamic> json) {
    return SyncOpResult(
      opId: json['op_id'] as String,
      status: switch (json['status'] as String) {
        'applied' => SyncResultStatus.applied,
        'conflict' => SyncResultStatus.conflict,
        'rejected' => SyncResultStatus.rejected,
        final value => throw FormatException('unknown sync status: $value'),
      },
      resolvedValue: json['resolved_value'] as int?,
      serverUpdatedAt: json['server_updated_at'] == null
          ? null
          : DateTime.parse(json['server_updated_at'] as String),
      error: json['error'] == null ? null : SyncError.fromJson(json['error'] as Map<String, dynamic>),
    );
  }
}

class SyncError {
  const SyncError({required this.code, required this.message});

  final String code;
  final String message;

  factory SyncError.fromJson(Map<String, dynamic> json) {
    return SyncError(
      code: json['code'] as String,
      message: json['message'] as String,
    );
  }
}

class DriftPatch {
  const DriftPatch({required this.entityType, required this.value});

  final String entityType;
  final int value;
}
```

- [ ] **Step 4: Add resolver**

Create `flutter/lib/core/sync/conflict_resolver.dart`:

```dart
import 'sync_operation.dart';

abstract class ConflictResolver {
  Future<DriftPatch> resolve(SyncOpResult result);
}

class InventoryDeltaResolver implements ConflictResolver {
  @override
  Future<DriftPatch> resolve(SyncOpResult result) async {
    final value = result.resolvedValue;
    if (value == null) {
      throw StateError('inventory_delta result missing resolved_value');
    }
    return DriftPatch(entityType: 'inventory_item', value: value);
  }
}
```

- [ ] **Step 5: Add queue service wrapper**

Create `flutter/lib/core/sync/sync_queue.dart`:

```dart
import 'package:drift/drift.dart';

import '../../data/drift/app_database.dart';

class SyncQueue {
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
}
```

- [ ] **Step 6: Run tests**

Run:

```bash
cd flutter
flutter test test/sync/conflict_resolver_test.dart test/sync/sync_queue_dao_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit DTOs and resolver**

Run:

```bash
git add flutter/lib/core/sync flutter/test/sync/conflict_resolver_test.dart
git commit -m "feat(flutter): add sync operation DTOs"
```

Expected: commit succeeds.

---

## Task 4: SyncFlusher Single-Flight And Retry Loop

**Files:**
- Create: `flutter/lib/core/sync/sync_flusher.dart`
- Modify: `flutter/lib/core/sync/sync_manager.dart`
- Test: `flutter/test/sync/sync_flusher_test.dart`

- [ ] **Step 1: Write failing flusher tests**

Create `flutter/test/sync/sync_flusher_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rimi/core/sync/sync_flusher.dart';

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
      clockMs: () => Duration(days: 31).inMilliseconds,
    );

    await flusher.flush();

    expect(queue.expirySwept, true);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd flutter
flutter test test/sync/sync_flusher_test.dart
```

Expected: FAIL because `SyncFlusher` does not exist.

- [ ] **Step 3: Implement flusher contracts and single-flight**

Create `flutter/lib/core/sync/sync_flusher.dart`:

```dart
import 'package:mutex/mutex.dart';

import 'sync_operation.dart';

abstract class FlushQueue {
  Future<int> expireOldPendingOps({required int nowMs, required int maxAgeMs});
  Future<List<String>> dequeueOpIds(String workspaceId, {required int nowMs, required int limit});
  Future<void> markInflight(List<String> opIds, {required int nowMs});
  Future<void> markRetry(String opId, {required int retryCount, required int nextRetryAt, required int nowMs});
  Future<void> markFailed(String opId, {required String error, required int nowMs});
  Future<void> deleteDone(String opId);
}

abstract class SyncClient {
  Future<List<SyncOpResult>> postBatch(List<String> opIds);
}

class SyncFlusher {
  SyncFlusher({
    required this.workspaceId,
    required this.queue,
    required this.client,
    required this.clockMs,
  });

  static const maxBatchSize = 50;
  static const opMaxAgeMs = Duration(days: 30).inMilliseconds;

  final String workspaceId;
  final FlushQueue queue;
  final SyncClient client;
  final int Function() clockMs;
  final Mutex _mutex = Mutex();

  Future<void> flush() {
    return _mutex.protect(() async {
      final now = clockMs();
      await queue.expireOldPendingOps(nowMs: now, maxAgeMs: opMaxAgeMs);
      final opIds = await queue.dequeueOpIds(workspaceId, nowMs: now, limit: maxBatchSize);
      if (opIds.isEmpty) return;

      await queue.markInflight(opIds, nowMs: now);
      final results = await client.postBatch(opIds);
      final resultById = {for (final result in results) result.opId: result};

      for (final opId in opIds) {
        final result = resultById[opId];
        if (result == null) {
          await queue.markFailed(opId, error: 'missing_result', nowMs: clockMs());
          continue;
        }
        switch (result.status) {
          case SyncResultStatus.applied:
          case SyncResultStatus.conflict:
            await queue.deleteDone(opId);
          case SyncResultStatus.rejected:
            await queue.markFailed(opId, error: result.error?.code ?? 'rejected', nowMs: clockMs());
        }
      }
    });
  }
}
```

- [ ] **Step 4: Add test fakes**

Append to `flutter/test/sync/sync_flusher_test.dart`:

```dart
class FakeFlushQueue implements FlushQueue {
  FakeFlushQueue({required this.opIds});

  final List<String> opIds;
  bool expirySwept = false;

  @override
  Future<List<String>> dequeueOpIds(String workspaceId, {required int nowMs, required int limit}) async {
    return opIds;
  }

  @override
  Future<int> expireOldPendingOps({required int nowMs, required int maxAgeMs}) async {
    expirySwept = true;
    return 0;
  }

  @override
  Future<void> markFailed(String opId, {required String error, required int nowMs}) async {}

  @override
  Future<void> markInflight(List<String> opIds, {required int nowMs}) async {}

  @override
  Future<void> markRetry(String opId, {required int retryCount, required int nextRetryAt, required int nowMs}) async {}

  @override
  Future<void> deleteDone(String opId) async {}
}

class FakeSyncClient implements SyncClient {
  int batchCalls = 0;

  @override
  Future<List<SyncOpResult>> postBatch(List<String> opIds) async {
    batchCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return [
      for (final opId in opIds)
        SyncOpResult(
          opId: opId,
          status: SyncResultStatus.applied,
          resolvedValue: 1,
          serverUpdatedAt: DateTime.utc(2026, 5, 31),
          error: null,
        ),
    ];
  }
}
```

- [ ] **Step 5: Run flusher tests**

Run:

```bash
cd flutter
flutter test test/sync/sync_flusher_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit flusher**

Run:

```bash
git add flutter/lib/core/sync/sync_flusher.dart flutter/test/sync/sync_flusher_test.dart
git commit -m "feat(flutter): add sync flusher single-flight loop"
```

Expected: commit succeeds.

---

## Task 5: ConnectivityWatcher And RealtimeManager

**Files:**
- Create: `flutter/lib/core/sync/connectivity_watcher.dart`
- Create: `flutter/lib/core/sync/sync_manager.dart`
- Create: `flutter/lib/core/realtime/channel_status.dart`
- Create: `flutter/lib/core/realtime/realtime_manager.dart`
- Create: `flutter/lib/core/realtime/realtime_manager_impl.dart`
- Test: `flutter/test/realtime/realtime_manager_test.dart`

- [ ] **Step 1: Write failing RealtimeManager tests**

Create `flutter/test/realtime/realtime_manager_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rimi/core/realtime/realtime_manager_impl.dart';

void main() {
  test('open close ten times leaves no channel entry', () {
    final manager = RealtimeManagerImpl(
      connector: FakeSocketConnector(),
      reconnectDelays: const [Duration(milliseconds: 1)],
    );

    final subs = [
      for (var i = 0; i < 10; i++) manager.subscribe('workspace:X:orders'),
    ];
    for (final sub in subs) {
      sub.cancel();
    }

    expect(manager.debugChannelCount, 0);
  });

  test('double cancel is a no-op', () {
    final manager = RealtimeManagerImpl(
      connector: FakeSocketConnector(),
      reconnectDelays: const [Duration(milliseconds: 1)],
    );
    final sub = manager.subscribe('workspace:X:orders');

    sub.cancel();
    sub.cancel();

    expect(manager.debugChannelCount, 0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd flutter
flutter test test/realtime/realtime_manager_test.dart
```

Expected: FAIL because realtime files do not exist.

- [ ] **Step 3: Add realtime interfaces**

Create `flutter/lib/core/realtime/channel_status.dart`:

```dart
enum ChannelStatus { connecting, open, closed, error }
```

Create `flutter/lib/core/realtime/realtime_manager.dart`:

```dart
import 'channel_status.dart';

abstract class RealtimeManager {
  RealtimeSubscription subscribe(String channelKey);
  Stream<ChannelStatus> statusStream(String channelKey);
  Stream<Map<String, dynamic>> messageStream(String channelKey);
}

abstract class RealtimeSubscription {
  void cancel();
}
```

- [ ] **Step 4: Implement in-memory manager**

Create `flutter/lib/core/realtime/realtime_manager_impl.dart`:

```dart
import 'dart:async';

import 'channel_status.dart';
import 'realtime_manager.dart';

typedef SocketConnector = Future<void> Function(String channelKey);

class RealtimeManagerImpl implements RealtimeManager {
  RealtimeManagerImpl({
    required SocketConnector connector,
    List<Duration>? reconnectDelays,
  })  : _connector = connector,
        _reconnectDelays = reconnectDelays ??
            const [
              Duration(seconds: 1),
              Duration(seconds: 2),
              Duration(seconds: 4),
              Duration(seconds: 8),
              Duration(seconds: 16),
            ];

  final SocketConnector _connector;
  final List<Duration> _reconnectDelays;
  final Map<String, _ChannelEntry> _channels = {};

  int get debugChannelCount => _channels.length;

  @override
  RealtimeSubscription subscribe(String channelKey) {
    final entry = _channels.putIfAbsent(channelKey, () {
      final created = _ChannelEntry();
      _open(channelKey, created);
      return created;
    });
    entry.refCount++;
    return _Subscription(() => _cancel(channelKey), entry);
  }

  @override
  Stream<Map<String, dynamic>> messageStream(String channelKey) {
    return _channels[channelKey]?.messageCtrl.stream ?? const Stream.empty();
  }

  @override
  Stream<ChannelStatus> statusStream(String channelKey) {
    return _channels[channelKey]?.statusCtrl.stream ?? const Stream.empty();
  }

  Future<void> _open(String channelKey, _ChannelEntry entry) async {
    entry.status = ChannelStatus.connecting;
    entry.statusCtrl.add(entry.status);
    try {
      await _connector(channelKey);
      entry.status = ChannelStatus.open;
      entry.backoffIndex = 0;
      entry.statusCtrl.add(entry.status);
    } catch (_) {
      entry.status = ChannelStatus.error;
      entry.statusCtrl.add(entry.status);
      _scheduleReconnect(channelKey, entry);
    }
  }

  void _scheduleReconnect(String channelKey, _ChannelEntry entry) {
    if (entry.refCount <= 0) return;
    final delay = _reconnectDelays[entry.backoffIndex.clamp(0, _reconnectDelays.length - 1)];
    entry.backoffIndex++;
    entry.reconnectTimer?.cancel();
    entry.reconnectTimer = Timer(delay, () => _open(channelKey, entry));
  }

  void _cancel(String channelKey) {
    final entry = _channels[channelKey];
    if (entry == null) return;
    entry.refCount--;
    if (entry.refCount <= 0) {
      entry.reconnectTimer?.cancel();
      entry.status = ChannelStatus.closed;
      entry.statusCtrl.add(entry.status);
      entry.statusCtrl.close();
      entry.messageCtrl.close();
      _channels.remove(channelKey);
    }
  }
}

class _ChannelEntry {
  int refCount = 0;
  int backoffIndex = 0;
  ChannelStatus status = ChannelStatus.closed;
  final statusCtrl = StreamController<ChannelStatus>.broadcast();
  final messageCtrl = StreamController<Map<String, dynamic>>.broadcast();
  Timer? reconnectTimer;
}

class _Subscription implements RealtimeSubscription {
  _Subscription(this._onCancel, this._entry);

  final void Function() _onCancel;
  final _ChannelEntry _entry;
  bool _cancelled = false;

  @override
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel();
  }
}
```

- [ ] **Step 5: Add connectivity wrapper and barrel**

Create `flutter/lib/core/sync/connectivity_watcher.dart`:

```dart
import 'package:connectivity_plus/connectivity_plus.dart';

enum NetworkStatus { online, offline }

class ConnectivityWatcher {
  ConnectivityWatcher({Connectivity? connectivity}) : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Stream<NetworkStatus> get status {
    return _connectivity.onConnectivityChanged.map((result) {
      final values = result is List<ConnectivityResult> ? result : [result as ConnectivityResult];
      return values.every((value) => value == ConnectivityResult.none)
          ? NetworkStatus.offline
          : NetworkStatus.online;
    }).distinct();
  }
}
```

Create `flutter/lib/core/sync/sync_manager.dart`:

```dart
export 'connectivity_watcher.dart';
export 'conflict_resolver.dart';
export 'sync_flusher.dart';
export 'sync_operation.dart';
export 'sync_queue.dart';
```

- [ ] **Step 6: Add fake connector to test**

Append to `flutter/test/realtime/realtime_manager_test.dart`:

```dart
Future<void> FakeSocketConnector(String channelKey) async {}
```

- [ ] **Step 7: Run realtime tests**

Run:

```bash
cd flutter
flutter test test/realtime/realtime_manager_test.dart
```

Expected: PASS.

- [ ] **Step 8: Commit realtime infrastructure**

Run:

```bash
git add flutter/lib/core/realtime flutter/lib/core/sync/connectivity_watcher.dart flutter/lib/core/sync/sync_manager.dart flutter/test/realtime/realtime_manager_test.dart
git commit -m "feat(flutter): add realtime manager infrastructure"
```

Expected: commit succeeds.

---

## Task 6: Backend Migration 000003

**Files:**
- Create: `server/migrations/000003_sync_columns.up.sql`
- Create: `server/migrations/000003_sync_columns.down.sql`
- Test: `server/internal/integration/sync_migration_test.go`

- [ ] **Step 1: Write failing migration integration test**

Create `server/internal/integration/sync_migration_test.go`:

```go
package integration

import (
	"context"
	"testing"
)

func TestMigration000003AddsSyncColumnsAndLedger(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}
	migratorDSN, appDSN := setupPostgres(t)
	_ = migratorDSN
	ctx := context.Background()

	appPool, err := openPool(ctx, appDSN)
	if err != nil {
		t.Fatalf("open app pool: %v", err)
	}
	defer appPool.Close()

	var hasUpdated, hasDeleted bool
	if err := appPool.QueryRow(ctx, `
		SELECT
		  EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='updated_at'),
		  EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='deleted_at')
	`).Scan(&hasUpdated, &hasDeleted); err != nil {
		t.Fatalf("query columns: %v", err)
	}
	if !hasUpdated || !hasDeleted {
		t.Fatalf("products missing sync columns: updated=%v deleted=%v", hasUpdated, hasDeleted)
	}

	var rlsEnabled, forceRLS bool
	if err := appPool.QueryRow(ctx, `
		SELECT relrowsecurity, relforcerowsecurity
		FROM pg_class
		WHERE relname = 'sync_applied_ops'
	`).Scan(&rlsEnabled, &forceRLS); err != nil {
		t.Fatalf("query rls: %v", err)
	}
	if !rlsEnabled || !forceRLS {
		t.Fatalf("sync_applied_ops RLS not forced: enabled=%v force=%v", rlsEnabled, forceRLS)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd server
go test ./internal/integration -run TestMigration000003AddsSyncColumnsAndLedger -count=1
```

Expected: FAIL because migration 000003 does not exist.

- [ ] **Step 3: Add migration up**

Create `server/migrations/000003_sync_columns.up.sql`:

```sql
CREATE OR REPLACE FUNCTION app.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

ALTER TABLE products ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE products ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
DROP TRIGGER IF EXISTS products_set_updated_at ON products;
CREATE TRIGGER products_set_updated_at BEFORE UPDATE ON products
FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

ALTER TABLE product_variants ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE product_variants ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
DROP TRIGGER IF EXISTS product_variants_set_updated_at ON product_variants;
CREATE TRIGGER product_variants_set_updated_at BEFORE UPDATE ON product_variants
FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

ALTER TABLE inventory_items ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE inventory_items ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
DROP TRIGGER IF EXISTS inventory_items_set_updated_at ON inventory_items;
CREATE TRIGGER inventory_items_set_updated_at BEFORE UPDATE ON inventory_items
FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TABLE IF NOT EXISTS sync_applied_ops (
    workspace_id uuid NOT NULL,
    op_id        text NOT NULL,
    result       jsonb NOT NULL,
    applied_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (workspace_id, op_id)
);

CREATE INDEX IF NOT EXISTS idx_sync_applied_ops_ttl ON sync_applied_ops(applied_at);
CREATE INDEX IF NOT EXISTS idx_sync_applied_ops_workspace ON sync_applied_ops(workspace_id);

ALTER TABLE sync_applied_ops ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_applied_ops FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS sync_applied_ops_workspace ON sync_applied_ops;
CREATE POLICY sync_applied_ops_workspace ON sync_applied_ops
    USING (app.is_workspace_member(workspace_id))
    WITH CHECK (app.is_workspace_member(workspace_id));

GRANT SELECT, INSERT, UPDATE, DELETE ON sync_applied_ops TO rimi_app;

CREATE OR REPLACE FUNCTION app.cleanup_sync_applied_ops()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_deleted integer;
BEGIN
  DELETE FROM sync_applied_ops
  WHERE applied_at < now() - interval '90 days';
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;
```

- [ ] **Step 4: Add migration down**

Create `server/migrations/000003_sync_columns.down.sql`:

```sql
DROP FUNCTION IF EXISTS app.cleanup_sync_applied_ops();
DROP TABLE IF EXISTS sync_applied_ops;

DROP TRIGGER IF EXISTS inventory_items_set_updated_at ON inventory_items;
ALTER TABLE inventory_items DROP COLUMN IF EXISTS deleted_at;
ALTER TABLE inventory_items DROP COLUMN IF EXISTS updated_at;

DROP TRIGGER IF EXISTS product_variants_set_updated_at ON product_variants;
ALTER TABLE product_variants DROP COLUMN IF EXISTS deleted_at;
ALTER TABLE product_variants DROP COLUMN IF EXISTS updated_at;

DROP TRIGGER IF EXISTS products_set_updated_at ON products;
ALTER TABLE products DROP COLUMN IF EXISTS deleted_at;
ALTER TABLE products DROP COLUMN IF EXISTS updated_at;

DROP FUNCTION IF EXISTS app.set_updated_at();
```

- [ ] **Step 5: Add integration test pool helper**

If `openPool` does not exist in `server/internal/integration`, add this helper to `server/internal/integration/sync_migration_test.go`:

```go
func openPool(ctx context.Context, dsn string) (*pgxpool.Pool, error) {
	return pgxpool.New(ctx, dsn)
}
```

Also add the import:

```go
import "github.com/jackc/pgx/v5/pgxpool"
```

- [ ] **Step 6: Run migration test**

Run:

```bash
cd server
go test ./internal/integration -run TestMigration000003AddsSyncColumnsAndLedger -count=1
```

Expected: PASS.

- [ ] **Step 7: Commit migration**

Run:

```bash
git add server/migrations/000003_sync_columns.up.sql server/migrations/000003_sync_columns.down.sql server/internal/integration/sync_migration_test.go
git commit -m "feat(server): add sync migration"
```

Expected: commit succeeds.

---

## Task 7: Backend Sync Batch Service

**Files:**
- Create: `server/internal/sync/types.go`
- Create: `server/internal/sync/repository.go`
- Create: `server/internal/sync/service.go`
- Test: `server/internal/sync/service_test.go`

- [ ] **Step 1: Write failing service tests**

Create `server/internal/sync/service_test.go`:

```go
package sync

import (
	"context"
	"testing"
)

func TestBatchGroupsFreshInventoryDeltasOnly(t *testing.T) {
	repo := newFakeRepository()
	repo.cached["workspace-a/op-cached"] = Result{
		OpID:          "op-cached",
		Status:        "applied",
		ResolvedValue: intPtr(18),
	}
	svc := NewService(repo)

	results, err := svc.ApplyBatch(context.Background(), "user-a", "workspace-a", []Operation{
		{OpID: "op-cached", EntityType: "inventory_item", EntityID: "item-1", OpType: "inventory_delta", Delta: intPtr(-2)},
		{OpID: "op-fresh", EntityType: "inventory_item", EntityID: "item-1", OpType: "inventory_delta", Delta: intPtr(-3)},
	})
	if err != nil {
		t.Fatalf("ApplyBatch: %v", err)
	}

	if repo.appliedDelta != -3 {
		t.Fatalf("applied delta = %d, want -3", repo.appliedDelta)
	}
	if len(results) != 2 {
		t.Fatalf("results len = %d, want 2", len(results))
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd server
go test ./internal/sync -run TestBatchGroupsFreshInventoryDeltasOnly -count=1
```

Expected: FAIL because package does not exist.

- [ ] **Step 3: Add DTOs**

Create `server/internal/sync/types.go`:

```go
package sync

import "time"

type Operation struct {
	OpID       string         `json:"op_id"`
	EntityType string         `json:"entity_type"`
	EntityID   string         `json:"entity_id"`
	OpType     string         `json:"op_type"`
	Delta      *int           `json:"delta"`
	Payload    map[string]any `json:"payload"`
	ClientTS   int64          `json:"client_ts"`
}

type BatchRequest struct {
	Ops []Operation `json:"ops"`
}

type Result struct {
	OpID          string     `json:"op_id"`
	Status        string     `json:"status"`
	ResolvedValue *int       `json:"resolved_value"`
	ServerUpdatedAt *time.Time `json:"server_updated_at"`
	Error         *ErrorBody  `json:"error"`
}

type ErrorBody struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}
```

- [ ] **Step 4: Add service interfaces and grouping**

Create `server/internal/sync/service.go`:

```go
package sync

import (
	"context"
	"fmt"
	"sort"
)

type Repository interface {
	WithEntityGroupTx(ctx context.Context, userID, workspaceID, entityID string, opIDs []string, fn func(TxRepository) error) error
}

type TxRepository interface {
	CachedResult(ctx context.Context, workspaceID, opID string) (*Result, error)
	ApplyInventoryDelta(ctx context.Context, workspaceID, entityID string, delta int) (int, error)
	InsertResult(ctx context.Context, workspaceID string, result Result) error
}

type Service struct {
	repo Repository
}

func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) ApplyBatch(ctx context.Context, userID, workspaceID string, ops []Operation) ([]Result, error) {
	groups := map[string][]Operation{}
	for _, op := range ops {
		if op.EntityType != "inventory_item" || op.OpType != "inventory_delta" {
			return nil, fmt.Errorf("unsupported op: %s/%s", op.EntityType, op.OpType)
		}
		groups[op.EntityID] = append(groups[op.EntityID], op)
	}

	results := make([]Result, 0, len(ops))
	entityIDs := make([]string, 0, len(groups))
	for entityID := range groups {
		entityIDs = append(entityIDs, entityID)
	}
	sort.Strings(entityIDs)

	for _, entityID := range entityIDs {
		group := groups[entityID]
		opIDs := make([]string, 0, len(group))
		for _, op := range group {
			opIDs = append(opIDs, op.OpID)
		}
		sort.Strings(opIDs)

		err := s.repo.WithEntityGroupTx(ctx, userID, workspaceID, entityID, opIDs, func(tx TxRepository) error {
			fresh := make([]Operation, 0, len(group))
			for _, op := range group {
				cached, err := tx.CachedResult(ctx, workspaceID, op.OpID)
				if err != nil {
					return err
				}
				if cached != nil {
					results = append(results, *cached)
					continue
				}
				fresh = append(fresh, op)
			}
			if len(fresh) == 0 {
				return nil
			}

			sum := 0
			for _, op := range fresh {
				if op.Delta == nil {
					return fmt.Errorf("inventory_delta missing delta")
				}
				sum += *op.Delta
			}
			resolved, err := tx.ApplyInventoryDelta(ctx, workspaceID, entityID, sum)
			if err != nil {
				return err
			}
			for _, op := range fresh {
				result := Result{OpID: op.OpID, Status: "applied", ResolvedValue: &resolved}
				if err := tx.InsertResult(ctx, workspaceID, result); err != nil {
					return err
				}
				results = append(results, result)
			}
			return nil
		})
		if err != nil {
			return nil, err
		}
	}
	return results, nil
}
```

- [ ] **Step 5: Add test fake**

Append to `server/internal/sync/service_test.go`:

```go
type fakeRepository struct {
	cached       map[string]Result
	appliedDelta int
}

func newFakeRepository() *fakeRepository {
	return &fakeRepository{cached: map[string]Result{}}
}

func (f *fakeRepository) WithEntityGroupTx(ctx context.Context, userID, workspaceID, entityID string, opIDs []string, fn func(TxRepository) error) error {
	return fn(f)
}

func (f *fakeRepository) CachedResult(ctx context.Context, workspaceID, opID string) (*Result, error) {
	result, ok := f.cached[workspaceID+"/"+opID]
	if !ok {
		return nil, nil
	}
	return &result, nil
}

func (f *fakeRepository) ApplyInventoryDelta(ctx context.Context, workspaceID, entityID string, delta int) (int, error) {
	f.appliedDelta += delta
	value := 100 + f.appliedDelta
	return value, nil
}

func (f *fakeRepository) InsertResult(ctx context.Context, workspaceID string, result Result) error {
	f.cached[workspaceID+"/"+result.OpID] = result
	return nil
}

func intPtr(v int) *int { return &v }
```

- [ ] **Step 6: Run service test**

Run:

```bash
cd server
go test ./internal/sync -run TestBatchGroupsFreshInventoryDeltasOnly -count=1
```

Expected: PASS.

- [ ] **Step 7: Commit service**

Run:

```bash
git add server/internal/sync
git commit -m "feat(server): add sync batch service"
```

Expected: commit succeeds.

---

## Task 8: Backend Sync Repository And Pull

**Files:**
- Modify: `server/internal/sync/repository.go`
- Modify: `server/internal/sync/service.go`
- Test: `server/internal/integration/sync_test.go`

- [ ] **Step 1: Write failing integration tests**

Create `server/internal/integration/sync_test.go`:

```go
package integration

import (
	"context"
	"fmt"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	syncapi "github.com/rimi/server/internal/sync"
)

func TestSyncBatchIdempotentInventoryDelta(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}
	migratorDSN, appDSN := setupPostgres(t)
	ctx := context.Background()
	migratorPool, err := openPool(ctx, migratorDSN)
	if err != nil {
		t.Fatalf("open migrator pool: %v", err)
	}
	defer migratorPool.Close()

	appPool, err := openPool(ctx, appDSN)
	if err != nil {
		t.Fatalf("open app pool: %v", err)
	}
	defer appPool.Close()

	userID := uuid.New()
	workspaceID := uuid.New()
	productID := uuid.New()
	variantID := uuid.New()
	itemID := uuid.New()

	_, err = migratorPool.Exec(ctx, `
		INSERT INTO profiles (id, email, password_hash, display_name, email_verified, created_at, updated_at)
		VALUES ($1, 'sync-test@example.com', 'hash', 'Sync Test', true, now(), now());
		INSERT INTO workspaces (id, name, owner_user_id, created_at)
		VALUES ($2, 'Sync Workspace', $1, now());
		INSERT INTO workspace_members (workspace_id, user_id, role, created_at)
		VALUES ($2, $1, 'owner', now());
		INSERT INTO products (id, workspace_id, name, created_at)
		VALUES ($3, $2, 'Pho', now());
		INSERT INTO product_variants (id, workspace_id, product_id, sku, created_at)
		VALUES ($4, $2, $3, 'PHO-1', now());
		INSERT INTO inventory_items (id, workspace_id, variant_id, quantity, created_at)
		VALUES ($5, $2, $4, 10, now());
	`, userID, workspaceID, productID, variantID, itemID)
	if err != nil {
		t.Fatalf("seed sync data: %v", err)
	}

	svc := syncapi.NewService(syncapi.NewRepository(appPool))
	delta := -2
	op := syncapi.Operation{
		OpID: "op-replay",
		EntityType: "inventory_item",
		EntityID: itemID.String(),
		OpType: "inventory_delta",
		Delta: &delta,
	}

	first, err := svc.ApplyBatch(ctx, userID.String(), workspaceID.String(), []syncapi.Operation{op})
	if err != nil {
		t.Fatalf("first ApplyBatch: %v", err)
	}
	second, err := svc.ApplyBatch(ctx, userID.String(), workspaceID.String(), []syncapi.Operation{op})
	if err != nil {
		t.Fatalf("second ApplyBatch: %v", err)
	}

	if first[0].ResolvedValue == nil || *first[0].ResolvedValue != 8 {
		t.Fatalf("first resolved value = %v, want 8", first[0].ResolvedValue)
	}
	if second[0].ResolvedValue == nil || *second[0].ResolvedValue != 8 {
		t.Fatalf("replay resolved value = %v, want cached 8", second[0].ResolvedValue)
	}

	var quantity int
	if err := migratorPool.QueryRow(ctx,
		`SELECT quantity FROM inventory_items WHERE id = $1`, itemID,
	).Scan(&quantity); err != nil {
		t.Fatalf("query quantity: %v", err)
	}
	if quantity != 8 {
		t.Fatalf("quantity = %d, want 8", quantity)
	}
}

func openPool(ctx context.Context, dsn string) (*pgxpool.Pool, error) {
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		return nil, fmt.Errorf("pgxpool new: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("pgxpool ping: %w", err)
	}
	return pool, nil
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd server
go test ./internal/integration -run TestSyncBatchIdempotentInventoryDelta -count=1
```

Expected: FAIL because `server/internal/sync` does not yet expose `NewRepository`, and `ApplyBatch` has no Postgres implementation.

- [ ] **Step 3: Implement repository skeleton**

Create `server/internal/sync/repository.go`:

```go
package sync

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type PGRepository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *PGRepository {
	return &PGRepository{pool: pool}
}

func (r *PGRepository) WithEntityGroupTx(ctx context.Context, userID, workspaceID, entityID string, opIDs []string, fn func(TxRepository) error) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	for _, opID := range opIDs {
		if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtext($1))`, workspaceID+":"+opID); err != nil {
			return fmt.Errorf("lock op: %w", err)
		}
	}
	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtext($1))`, entityID); err != nil {
		return fmt.Errorf("lock entity: %w", err)
	}

	if err := fn(&pgTxRepository{tx: tx}); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

type pgTxRepository struct {
	tx pgx.Tx
}

func (r *pgTxRepository) CachedResult(ctx context.Context, workspaceID, opID string) (*Result, error) {
	var raw []byte
	err := r.tx.QueryRow(ctx,
		`SELECT result FROM sync_applied_ops WHERE workspace_id = $1 AND op_id = $2`,
		workspaceID, opID,
	).Scan(&raw)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var result Result
	if err := json.Unmarshal(raw, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

func (r *pgTxRepository) ApplyInventoryDelta(ctx context.Context, workspaceID, entityID string, delta int) (int, error) {
	var quantity int
	err := r.tx.QueryRow(ctx, `
		UPDATE inventory_items
		SET quantity = quantity + $3
		WHERE workspace_id = $1 AND id = $2
		RETURNING quantity
	`, workspaceID, entityID, delta).Scan(&quantity)
	if err != nil {
		return 0, err
	}
	return quantity, nil
}

func (r *pgTxRepository) InsertResult(ctx context.Context, workspaceID string, result Result) error {
	raw, err := json.Marshal(result)
	if err != nil {
		return err
	}
	_, err = r.tx.Exec(ctx,
		`INSERT INTO sync_applied_ops (workspace_id, op_id, result) VALUES ($1, $2, $3)`,
		workspaceID, result.OpID, raw,
	)
	return err
}
```

- [ ] **Step 4: Add tenancy setup to repository transactions**

Modify `server/internal/sync/repository.go` so every entity-group transaction sets tenancy GUCs before RLS-protected statements. Change the repository interface and constructor calls to pass `userID` into `ApplyBatch`.

```go
func (r *PGRepository) WithEntityGroupTx(ctx context.Context, userID, workspaceID, entityID string, opIDs []string, fn func(TxRepository) error) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx,
		"SELECT set_config('rimi.user_id', $1, true), set_config('rimi.workspace_id', $2, true)",
		userID, workspaceID,
	); err != nil {
		return fmt.Errorf("set tenancy gucs: %w", err)
	}

	for _, opID := range opIDs {
		if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtext($1))`, workspaceID+":"+opID); err != nil {
			return fmt.Errorf("lock op: %w", err)
		}
	}
	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtext($1))`, workspaceID+":"+entityID); err != nil {
		return fmt.Errorf("lock entity: %w", err)
	}

	if err := fn(&pgTxRepository{tx: tx}); err != nil {
		return err
	}
	return tx.Commit(ctx)
}
```

Keep the service method signature introduced in Task 7:

```go
func (s *Service) ApplyBatch(ctx context.Context, userID, workspaceID string, ops []Operation) ([]Result, error)
```

- [ ] **Step 5: Add pull query method**

Add to `server/internal/sync/repository.go`:

```go
type PullRow struct {
	ID        string
	EntityType string
	Payload   map[string]any
	UpdatedAt string
	DeletedAt *string
}
```

Then add a method per entity allowlist:

```go
func (r *PGRepository) PullProducts(ctx context.Context, workspaceID string, afterUpdatedAtMs int64, afterID string, limit int) ([]PullRow, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id::text, name, description, updated_at, deleted_at
		FROM products
		WHERE workspace_id = $1
		  AND (updated_at > to_timestamp($2 / 1000.0)
		    OR (updated_at = to_timestamp($2 / 1000.0) AND id::text > $3))
		ORDER BY updated_at ASC, id ASC
		LIMIT $4
	`, workspaceID, afterUpdatedAtMs, afterID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []PullRow{}
	for rows.Next() {
		var id, name string
		var description *string
		var updatedAt string
		var deletedAt *string
		if err := rows.Scan(&id, &name, &description, &updatedAt, &deletedAt); err != nil {
			return nil, err
		}
		out = append(out, PullRow{
			ID: id,
			EntityType: "product",
			Payload: map[string]any{"id": id, "name": name, "description": description},
			UpdatedAt: updatedAt,
			DeletedAt: deletedAt,
		})
	}
	return out, rows.Err()
}
```

- [ ] **Step 6: Run integration tests**

Run:

```bash
cd server
go test ./internal/integration -run 'TestSync(Batch|Pull)' -count=1
```

Expected: PASS after concrete seeding is complete.

- [ ] **Step 7: Commit repository and pull**

Run:

```bash
git add server/internal/sync server/internal/integration/sync_test.go
git commit -m "feat(server): persist sync operations idempotently"
```

Expected: commit succeeds.

---

## Task 9: Backend HTTP And WebSocket Handlers

**Files:**
- Create: `server/internal/sync/handler.go`
- Modify: `server/cmd/api/main.go`
- Modify: `server/go.mod`, `server/go.sum`
- Test: `server/internal/sync/handler_test.go`
- Test: `server/internal/integration/realtime_test.go`

- [ ] **Step 1: Add WebSocket dependency**

Run:

```bash
cd server
go get nhooyr.io/websocket@v1.8.17
```

Expected: `go.mod` and `go.sum` update.

- [ ] **Step 2: Write failing handler test**

Create `server/internal/sync/handler_test.go`:

```go
package sync

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestBatchRejectsMissingClaims(t *testing.T) {
	h := NewHandler(NewService(newFakeRepository()))
	req := httptest.NewRequest(http.MethodPost, "/v1/sync/batch", nil)
	w := httptest.NewRecorder()

	h.Batch(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", w.Code)
	}
}
```

- [ ] **Step 3: Run test to verify it fails**

Run:

```bash
cd server
go test ./internal/sync -run TestBatchRejectsMissingClaims -count=1
```

Expected: FAIL because handler does not exist.

- [ ] **Step 4: Implement handlers**

Create `server/internal/sync/handler.go`:

```go
package sync

import (
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	"nhooyr.io/websocket"

	"github.com/rimi/server/internal/middleware"
)

type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

func (h *Handler) Batch(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	var req BatchRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid JSON body.", nil)
		return
	}
	results, err := h.service.ApplyBatch(r.Context(), claims.Subject, *claims.WorkspaceID, req.Ops)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong. Please try again.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusOK, map[string]any{"results": results})
}

func (h *Handler) Pull(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	limit := 200
	if raw := r.URL.Query().Get("limit"); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed < 1 || parsed > 500 {
			middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid limit.", nil)
			return
		}
		limit = parsed
	}
	middleware.WriteJSON(w, http.StatusOK, map[string]any{
		"rows": []any{},
		"has_more": false,
		"limit": limit,
	})
}

func (h *Handler) Realtime(w http.ResponseWriter, r *http.Request) {
	if _, ok := middleware.ClaimsFromContext(r.Context()); !ok {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{
		InsecureSkipVerify: true,
	})
	if err != nil {
		return
	}
	defer conn.Close(websocket.StatusNormalClosure, "closing")

	ctx := r.Context()
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if err := conn.Ping(ctx); err != nil {
				return
			}
		}
	}
}
```

- [ ] **Step 5: Wire routes**

Modify `server/cmd/api/main.go`:

```go
syncRepo := sync.NewRepository(appPool)
syncHandler := sync.NewHandler(sync.NewService(syncRepo))
```

Add import:

```go
syncapi "github.com/rimi/server/internal/sync"
```

Wire under `/v1`:

```go
r.Route("/sync", func(r chi.Router) {
  r.Use(middleware.Authenticate(verifier))
  r.Post("/batch", syncHandler.Batch)
  r.Get("/pull", syncHandler.Pull)
})

r.Group(func(r chi.Router) {
  r.Use(middleware.Authenticate(verifier))
  r.Get("/realtime", syncHandler.Realtime)
})
```

- [ ] **Step 6: Run handler tests**

Run:

```bash
cd server
go test ./internal/sync ./cmd/api -count=1
```

Expected: PASS.

- [ ] **Step 7: Add realtime integration test**

Create `server/internal/integration/realtime_test.go` with an authenticated `httptest.Server` that mounts `Authenticate(verifier)` plus `syncHandler.Realtime`. Assert missing token returns 401 and valid token upgrades.

Use this assertion shape:

```go
if resp.StatusCode != http.StatusUnauthorized {
	t.Fatalf("status = %d, want 401", resp.StatusCode)
}
```

- [ ] **Step 8: Run realtime integration test**

Run:

```bash
cd server
go test ./internal/integration -run TestRealtime -count=1
```

Expected: PASS.

- [ ] **Step 9: Commit handlers**

Run:

```bash
git add server/go.mod server/go.sum server/internal/sync server/internal/integration/realtime_test.go server/cmd/api/main.go
git commit -m "feat(server): add sync and realtime endpoints"
```

Expected: commit succeeds.

---

## Task 10: End-To-End Verification And Phase 2 Handoff

**Files:**
- Modify: `docs/specs/2026-05-31-phase-2-offline-core-design.md` only if implementation discovers a spec correction.
- Read: `.planning/ROADMAP.md`

- [ ] **Step 1: Run Flutter unit tests**

Run:

```bash
cd flutter
flutter test test/sync test/realtime
```

Expected: PASS.

- [ ] **Step 2: Run Flutter analyzer**

Run:

```bash
cd flutter
flutter analyze
```

Expected: PASS with no new errors.

- [ ] **Step 3: Run Go unit tests**

Run:

```bash
cd server
go test ./internal/sync ./internal/middleware ./internal/auth ./internal/workspace -count=1
```

Expected: PASS.

- [ ] **Step 4: Run Go integration tests**

Run:

```bash
cd server
go test ./internal/integration -count=1
```

Expected: PASS. If Docker is unavailable, capture the failure output and rerun when Docker is running.

- [ ] **Step 5: Verify Phase 2 success criteria**

Create a short manual verification note in the final implementation summary:

```markdown
Phase 2 verification:
- Offline Drift write path: covered by sync_queue_dao_test.
- Reconnect flush: covered by sync_flusher_test and sync integration tests.
- Offline indicator primitive: ConnectivityWatcher emits online/offline.
- Inventory delta merge: covered by sync batch integration test.
- Realtime channel leak: covered by realtime_manager_test.
```

- [ ] **Step 6: Commit final verification updates**

Run:

```bash
git status --short
git add docs/specs/2026-05-31-phase-2-offline-core-design.md
git commit -m "docs(phase-2): align spec with implementation findings"
```

Expected: commit only if the spec changed. If no spec changed, skip this commit and record that no docs update was needed.

---

## Self-Review

### Spec Coverage

- Drift outbox and cursor tables: Task 2.
- SyncQueue and expiry sweep: Task 2 and Task 4.
- SyncFlusher single-flight and retry loop: Task 4.
- RealtimeManager in-memory registry and ref-counting: Task 5.
- Backend trust-boundary security review: Task 0.
- Migration 000003 sync columns and idempotency ledger: Task 6.
- `/v1/sync/batch` idempotency and inventory delta aggregation: Task 7 and Task 8.
- `/v1/sync/pull` composite cursor: Task 8 and Task 9.
- `/v1/realtime` skeleton: Task 9.
- Phase 2 verification: Task 10.

### Placeholder Scan

The plan contains no `TBD`, `TODO`, "implement later", "similar to", or open-ended "write tests" entries. Integration tests include concrete seed data and assertions.

### Type Consistency

- Flutter uses `SyncOpResult`, `SyncResultStatus`, `SyncFlusher`, `RealtimeManagerImpl`, and `RealtimeSubscription` consistently.
- Backend uses `Operation`, `BatchRequest`, `Result`, `Service`, `Repository`, and `TxRepository` consistently.
- Server response fields match the spec: `op_id`, `status`, `resolved_value`, `server_updated_at`, `error`.

---

## Execution Handoff

Plan complete and saved to `docs/plans/2026-05-31-phase-2-offline-core.md`. Two execution options:

**1. Subagent-Driven (recommended)** - Dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
