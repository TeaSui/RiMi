# Phase 2: Offline Core — Design Spec

**Date:** 2026-05-31
**Status:** Approved for implementation planning
**Phase dependency:** Phase 1 (auth gate, workspace tenancy, RLS) complete — commit f6216d8

---

## Context

Phase 1 delivered a Go+Postgres backend with JWT auth, workspace tenancy via RLS, and a Flutter auth gate. Every Phase 3+ feature (products, orders, inventory) will involve staff using mobile devices in kitchens and stockrooms where connectivity is intermittent. Phase 2 establishes the offline-first infrastructure so all subsequent features work without network by default — not as an afterthought.

Three capabilities required before any feature can go offline-first:
1. A local database (Drift/SQLite) that mirrors the Postgres schema
2. A SyncManager that durably queues local writes and flushes them to the server on reconnect, with correct conflict resolution for inventory
3. A RealtimeManager that manages WebSocket channel lifecycle so future features can subscribe to live updates without leaking connections

---

## Architecture

```
Feature Screens
      ↕ DAO
Drift (local SQLite — source of truth for all feature screens)
      ↑↓                          ↑↓
SyncManager                 RealtimeManager
  ConnectivityWatcher         in-memory Map<String, _ChannelEntry>
  SyncQueue (Drift table)     subscribe() → Subscription (disposer)
  SyncFlusher (mutex)         auto-reconnect with backoff
  ConflictResolver            WSS /realtime (Phase 2: skeleton only)
      ↓ POST /sync/batch
Go Backend
  /v1/sync/batch   (new — trust boundary: see §Trust Boundary below)
  /v1/sync/pull    (new — trust boundary)
  /v1/realtime     (new WebSocket — trust boundary)
      ↓ workspace-scoped RLS (existing two-role pattern)
PostgreSQL (existing schema + migration 000003)
```

**Principle:** Feature screens read and write Drift only. They never call the network directly. SyncManager and RealtimeManager work behind the scenes.

---

## Trust Boundary

Three new server endpoints are public surfaces: `/v1/sync/batch`, `/v1/sync/pull`, `/v1/realtime`. Per `workflow-routing.md` rule 4, new external URLs require full-workflow routing including Security review before implementation.

**Required before backend implementation begins:**
- Security subagent threat model for `/v1/sync/batch`, `/v1/sync/pull`, `/v1/realtime`
- Output persisted to `docs/security/phase-2-sync-realtime.md`
- Implementation agents consume those rules

Flutter-side work (Drift schema, SyncManager, RealtimeManager) has no new external surface and can proceed on the fast path in parallel once the Drift schema and Go contracts are locked.

---

## Drift Schema (Flutter — local SQLite)

### `sync_operations` — the outbox

| Column | Type | Notes |
|---|---|---|
| `op_id` | TEXT PK | Client UUID — idempotency key server-side |
| `workspace_id` | TEXT NOT NULL | Workspace scope |
| `entity_type` | TEXT NOT NULL | `'product'`, `'inventory_item'`, etc. |
| `entity_id` | TEXT NOT NULL | UUID of the affected row |
| `op_type` | TEXT NOT NULL | `'create'` \| `'update'` \| `'delete'` \| `'inventory_delta'` |
| `payload` | TEXT NULLABLE | JSON blob for create/update ops |
| `delta` | INTEGER NULLABLE | Only for `inventory_delta`; int not double (schema: `quantity integer`) |
| `created_at` | INTEGER NOT NULL | Unix ms — flush order |
| `updated_at` | INTEGER NOT NULL | Unix ms |
| `status` | TEXT NOT NULL DEFAULT `'pending'` | `'pending'` \| `'inflight'` \| `'done'` \| `'failed'` |
| `inflight_since` | INTEGER NULLABLE | Unix ms — lease timestamp for crash recovery |
| `next_retry_at` | INTEGER NULLABLE | Unix ms — flusher queries `next_retry_at <= now()` |
| `retry_count` | INTEGER NOT NULL DEFAULT 0 | Max 3 retries before `failed` |
| `last_error` | TEXT NULLABLE | Last server error message |

**Status transitions:**
- `pending` → `inflight`: flusher picks up op, sets `inflight_since = now()`
- `inflight` → `done`: server 200 + local reconciliation committed in same Drift transaction
- `inflight` → `pending`: 5xx or network error; `retry_count++`, `next_retry_at = now() + backoff`; backoff: 1s, 2s, 4s
- `inflight` → `failed`: 4xx (non-409); no retry
- `inflight` → `pending` (crash recovery): on app startup, ops where `inflight_since < now() - 60s` are reset

**`done` rows** are deleted immediately after the reconciliation transaction succeeds. No unbounded accumulation.

**Migration rule:** any future Drift migration that changes `sync_operations` row format must either transform all `status = 'pending'` rows in the same migration or gate the flusher (abort flush if migration version mismatch). Never silently process stale-format rows.

### `sync_meta` — pull cursors

| Column | Type | Notes |
|---|---|---|
| `workspace_id` | TEXT | Composite PK |
| `entity_type` | TEXT | Composite PK |
| `last_synced_at` | INTEGER NOT NULL | Unix ms — `after_updated_at` cursor |
| `last_synced_id` | TEXT NOT NULL | UUID — `after_id` cursor (tie-breaking) |

Cursor is committed atomically only after all rows in a pull page are successfully applied to Drift. A crash mid-apply leaves the cursor at the previous checkpoint; next pull re-fetches the partial page (idempotent via upsert).

### `sync_operations` index

```sql
CREATE INDEX idx_sync_ops_flush
  ON sync_operations(workspace_id, created_at)
  WHERE status = 'pending';
```

Index preserves FIFO order: `workspace_id` filters, `created_at` drives the `ORDER BY created_at ASC` sort. The `next_retry_at` eligibility predicate (`IS NULL OR next_retry_at <= now()`) is evaluated as a filter on the already-small pending set — no index needed for this low-cardinality secondary condition.

---

## SyncManager Components

### ConnectivityWatcher
- Wraps `connectivity_plus` package; emits `NetworkStatus` stream (`online` / `offline`)
- Triggers `SyncFlusher.flush()` on `offline → online` transition
- `RealtimeManager` pauses reconnect attempts while `offline`

### SyncQueue
- Thin DAO over `sync_operations` Drift table
- `enqueue(op)`: called inside the same Drift transaction as the local write — atomic
- `dequeue(workspaceId, limit: 50)`: `WHERE status = 'pending' AND (next_retry_at IS NULL OR next_retry_at <= now()) ORDER BY created_at ASC`

### SyncFlusher
- **Single-flight per workspace** via `Mutex` — connectivity restored + timer + `AppLifecycle.resumed` can fire simultaneously; only one flush runs at a time
- Flush triggers: (1) `ConnectivityWatcher` online event, (2) periodic 60s timer while online, (3) `AppLifecycle.resumed`
- Algorithm:
  1. Acquire mutex
  2. Dequeue up to 50 pending ops ordered by `created_at ASC`
  3. Mark batch `inflight` (set `inflight_since`, `status = 'inflight'`)
  4. POST `/v1/sync/batch`
  5. For each op result:
     - `"applied"`: open Drift transaction → write `resolved_value` → mark op `done` → delete op row — commit
     - `"conflict"` (409): apply server-provided `resolved_value` to Drift + mark `done`
     - `"rejected"` (4xx non-409): mark `failed`
     - Network/5xx error: reset to `pending`, increment `retry_count`, set `next_retry_at`
  6. Release mutex
  7. Trigger incremental pull for affected entity types

### ConflictResolver
- Strategy interface; Phase 2 ships one implementation: `InventoryDeltaResolver`
- Applies server `resolved_value` (authoritative integer) back to `inventory_items.quantity` in Drift
- All other entity types: last-write-wins (server `resolved_value` or payload overwrites local)

---

## Incremental Pull

After a flush, pull server-side changes for each entity type in `sync_meta`:

```
GET /v1/sync/pull?entity=<type>&after_updated_at=<unix_ms>&after_id=<uuid>
```

- Workspace derived from JWT claim — never from query params
- Server returns rows where `updated_at >= to_timestamp($after_updated_at / 1000.0) AND (updated_at > to_timestamp($after_updated_at / 1000.0) OR id > $after_id)` — composite cursor handles equal-timestamp ties; default page size 200, max 500
- Flutter upserts rows into Drift; rows with `deleted_at IS NOT NULL` are soft-deleted locally
- Commit cursor to `sync_meta` only after full page applied

---

## Server-Side Additions

### `sync_applied_ops` — server-side idempotency ledger

New table in migration 000003. Keyed by `(workspace_id, op_id)`. Stores the original result payload so a client retry after timeout receives the identical response rather than re-applying.

```sql
CREATE TABLE sync_applied_ops (
    workspace_id  uuid        NOT NULL,
    op_id         text        NOT NULL,
    result        jsonb       NOT NULL,   -- cached per-op result payload
    applied_at    timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (workspace_id, op_id)
);
CREATE INDEX idx_sync_applied_ops_ttl ON sync_applied_ops(applied_at);
CREATE INDEX idx_sync_applied_ops_workspace ON sync_applied_ops(workspace_id);
ALTER TABLE sync_applied_ops ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_applied_ops FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sync_applied_ops_workspace ON sync_applied_ops;
CREATE POLICY sync_applied_ops_workspace ON sync_applied_ops
    USING (app.is_workspace_member(workspace_id))
    WITH CHECK (app.is_workspace_member(workspace_id));
```

`sync_applied_ops` follows the same workspace-scoped RLS conventions as all other Phase 1 workspace tables (`server/migrations/000002_rls_policies.up.sql`): `workspace_id` column, index on `workspace_id`, `ENABLE` + `FORCE ROW LEVEL SECURITY`, `app.is_workspace_member(workspace_id)` policy via the existing `SECURITY DEFINER` helper (fail-closed on unset GUC). Backend accesses it as `rimi_app`, not as a privileged role. Policy goes in migration 000003 alongside the table DDL.

**TTL cleanup:** background job (or pg_cron) deletes rows older than 90 days. Because `sync_applied_ops` has `FORCE ROW LEVEL SECURITY` and `app.is_workspace_member` requires `rimi.workspace_id` to be set, the cleanup job must not run as `rimi_app`. Two acceptable patterns: (a) run as `rimi_migrator` (table owner, bypasses RLS); (b) a tightly scoped `SECURITY DEFINER` cleanup function owned by `rimi_migrator` that executes `DELETE FROM sync_applied_ops WHERE applied_at < now() - interval '90 days'` with no GUC requirement. Either approach avoids granting excess privilege to `rimi_app`.

**Client expiry rule (binding constraint):** before every flush (startup, timer, reconnect, foreground resume), ops with `created_at < now() - 30 days` are auto-failed (`status = 'failed'`, `last_error = 'op_expired'`). The app surfaces a data-check prompt to the user. This sweep runs at the flush callsite, not only on startup, so the invariant is local and obvious: no 30+ day op can ever enter a batch. The 90-day server ledger always covers any possible retry; the dangerous double-apply scenario cannot occur.

**Handler contract — per entity-group transaction:**

Fresh `inventory_delta` ops that share an `entity_id` must be aggregated and applied in one transaction; "per op transaction" would break the delta sum. The unit of atomicity is the entity group (all fresh ops for one `entity_id`), not the individual op.

For each entity group within the batch:
1. **Lock per op (idempotency):** sort op IDs lexicographically before acquiring locks to prevent advisory-lock deadlocks when two concurrent batches contain overlapping ops in different order. Then `pg_advisory_xact_lock(hashtext(workspace_id || ':' || op_id))` for every op in sorted order — serializes concurrent same-op requests before any ledger read
2. Check `sync_applied_ops` for each `(workspace_id, op_id)` — partition into cached and fresh
3. If all ops are cached: return cached results, no DB write
4. **Lock entity:** `pg_advisory_xact_lock(hashtext(entity_id))` — prevents concurrent batches from two devices racing on the same inventory row
5. Sum deltas from fresh ops only; apply the aggregated delta
6. Insert results for fresh ops into `sync_applied_ops`
7. Commit

Cached ops return their stored `result` payload from the ledger unchanged. Their deltas are excluded from the sum.

**Mixed batch example:** batch contains op A (cached, delta=-2) and op B (fresh, delta=-3) for the same `entity_id`. Server applies delta=-3 only; quantity decrements by 3. Response returns cached result for A (from ledger) and new result for B. The -2 is not double-counted.

### Migration 000003 — `updated_at` + soft-delete (Phase 2 scope)

Tables: `products`, `product_variants`, `inventory_items`

```sql
ALTER TABLE products ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE products ADD COLUMN deleted_at TIMESTAMPTZ;
-- UPDATE trigger: SET updated_at = NOW() on every row modification
-- same for product_variants, inventory_items
```

Other tables (orders, customers, etc.) get the same treatment in their respective phases.

### `POST /v1/sync/batch`

**Auth:** Bearer JWT required. `workspace_id` from JWT claim. No client-supplied workspace.

**Request:**
```json
{
  "ops": [
    {
      "op_id": "<client-uuid>",
      "entity_type": "inventory_item",
      "entity_id": "<inventory_items.id-uuid>",
      "op_type": "inventory_delta",
      "delta": -2,
      "payload": null,
      "client_ts": 1780220000000
    }
  ]
}
```

**Idempotency + processing:** ops are grouped by `entity_id`. For each group, the server first acquires per-op advisory locks, checks `sync_applied_ops` to partition cached vs fresh ops, then acquires an entity-level advisory lock, sums fresh deltas only, applies the aggregated delta, and inserts fresh results into the ledger — all in one transaction. Cached ops return their stored result without re-applying. See §`sync_applied_ops` handler contract for the full step sequence.

`entity_id` must be an `inventory_items.id` UUID (not `variant_id` — `quantity` lives on `inventory_items`, see `000001_init_schema.up.sql` line 121).

**Response (envelope):**
```json
{
  "data": {
    "results": [
      {
        "op_id": "<client-uuid>",
        "status": "applied" | "conflict" | "rejected",
        "resolved_value": 18,
        "server_updated_at": "2026-05-31T12:00:01Z",
        "error": null | { "code": "...", "message": "..." }
      }
    ]
  },
  "meta": { "timestamp": "2026-05-31T12:00:01Z" }
}
```

- `"conflict"`: server resolved the conflict; `resolved_value` is authoritative; Flutter applies it
- `"rejected"`: permanent failure (e.g. entity not found, schema violation); Flutter marks op `failed`
- `"applied"`: clean apply

### `GET /v1/sync/pull`

**Auth:** Bearer JWT required. Workspace from JWT.

**Query params:** `entity` (required), `after_updated_at` (unix ms — server casts via `to_timestamp($1 / 1000.0)`), `after_id` (UUID), `limit` (integer, default 200, max 500)

**Response (envelope):**
```json
{
  "data": {
    "rows": [
      {
        "id": "...",
        "entity_type": "product",
        "payload": { /* full row */ },
        "updated_at": "...",
        "deleted_at": null | "..."
      }
    ],
    "has_more": false
  },
  "meta": { "timestamp": "..." }
}
```

### `WSS /v1/realtime` (skeleton)

**Auth:** Bearer token in `Authorization` header at handshake — connection rejected 401 on missing/invalid token. No workspace from query params; workspace resolved from JWT.

**Phase 2:** accepts connection, holds it open, sends periodic ping. No broadcast events wired. Exists to validate the handshake, auth path, and channel registry integration test.

**Phase 4+:** workspace-scoped topic subscriptions added here.

---

## RealtimeManager

Pure abstract interface — injectable and mockable in widget tests.

```dart
abstract class RealtimeManager {
  Subscription subscribe(String channelKey);
  Stream<ChannelStatus> statusStream(String channelKey);
  Stream<Map<String, dynamic>> messageStream(String channelKey);
}

abstract class Subscription {
  void cancel();
}
```

**Channel key format:** `workspace:<workspaceId>:<topic>` (e.g. `workspace:abc123:orders`)
- Workspace segment is for client-side routing only
- Server derives workspace from JWT; never trusts the key string for auth

**Internal state:** `Map<String, _ChannelEntry> _channels` — pure in-memory, no Drift table.

```
_ChannelEntry {
  WebSocket? ws
  int refCount
  ChannelStatus status          // connecting | open | closed | error
  StreamController statusCtrl
  StreamController messageCtrl
  Timer? reconnectTimer
}
```

**`subscribe(channelKey)`:**
1. If entry missing: create entry, `refCount = 1`, open WS
2. If entry exists: `refCount++`
3. Return `Subscription` handle — caller calls `subscription.cancel()` to unsubscribe

**`cancel()` (via Subscription handle):**
1. If `_cancelled == true`: return immediately (idempotent — double-cancel is a no-op)
2. Set `_cancelled = true`
3. `refCount--`
4. If `refCount == 0`: cancel `reconnectTimer`, close WS, close stream controllers, **remove entry from `_channels` map**
5. If `refCount > 0`: no-op on the socket

**Reconnect policy (on unexpected WS close):**
- Only reconnect if `refCount > 0`
- Exponential backoff: 1s → 2s → 4s → 8s → 16s (cap)
- Pause reconnect while `ConnectivityWatcher` reports `offline`
- Reset backoff on successful open

**Lifecycle cleanup test (success criterion from ROADMAP.md line 45):**
```
Open screen subscribed to 'workspace:X:orders' × 10
Close screen × 10
Assert: _channels does not contain 'workspace:X:orders'
Assert: no open WebSocket
Assert: no active reconnect timer
```

---

## File Layout

### Flutter additions (`flutter/lib/core/sync/`)
```
flutter/lib/core/sync/
  sync_manager.dart           // barrel export
  connectivity_watcher.dart   // connectivity_plus wrapper
  sync_queue.dart             // DAO over sync_operations table
  sync_flusher.dart           // single-flight flush loop
  conflict_resolver.dart      // abstract + InventoryDeltaResolver
  sync_meta_dao.dart          // cursor read/write

flutter/lib/core/realtime/
  realtime_manager.dart       // abstract interface + Subscription
  realtime_manager_impl.dart  // _ChannelEntry, reconnect logic
  channel_status.dart         // enum

flutter/lib/data/drift/
  app_database.dart           // Drift database class
  sync_operations_table.dart  // table definition
  sync_meta_table.dart        // table definition
  daos/                       // one DAO per entity type (Phase 3 adds product_dao.dart etc.)
```

### Go backend additions (`server/internal/sync/`)
```
server/internal/sync/
  handler.go          // HTTP + WS handlers for /sync/batch, /sync/pull, /realtime
  service.go          // batch apply logic, advisory lock, conflict resolution
  repository.go       // Postgres queries

server/migrations/
  000003_sync_columns.up.sql    // updated_at, deleted_at, triggers, sync_applied_ops table
  000003_sync_columns.down.sql
```

---

## Testing

### Unit tests (Flutter)
- `SyncFlusher`: mock `SyncQueue` + mock HTTP client; verify single-flight (two concurrent flush() calls → one HTTP request); verify crash recovery resets inflight ops
- `ConflictResolver`: inventory delta applied atomically; `resolved_value` written before op marked `done`
- `RealtimeManager`: open/close 10× → no entry in `_channels`, no leaked timer; double-cancel is a no-op

### Integration tests (Go — testcontainers)
- `/sync/batch`: two concurrent batches with `inventory_delta` on same `entity_id` → final quantity = sum of deltas (no race); idempotent replay of same `op_id` batch
- `/sync/pull`: rows created/updated/deleted after cursor are returned; rows before cursor are excluded
- `/v1/realtime`: unauthenticated handshake → 401; valid token → connection accepted

### Phase 2 success criteria (ROADMAP.md)
1. Create a record in Drift while offline → no crash, row visible in UI
2. Reconnect → flush drains queue, record appears on server
3. App shows offline indicator when `ConnectivityWatcher` emits `offline`
4. Two inventory `delta = -2` and `delta = -3` ops for same item → server quantity = baseline − 5
5. Open/close subscribed screen 10× → exactly 0 active channels in `_channels`, no leaked WS
