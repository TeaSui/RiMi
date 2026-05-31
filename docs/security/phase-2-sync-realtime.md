# Phase 2 Sync + Realtime Security Review

**Date:** 2026-05-31
**Scope:** POST /v1/sync/batch, GET /v1/sync/pull, WSS /v1/realtime
**Consumes:** docs/specs/2026-05-31-phase-2-offline-core-design.md, docs/security/phase-1-auth-workspace.md
**Status:** Approved — implementers must follow all SYNC-SEC-XX rules below

---

## Trust Boundaries

| Boundary | Description |
|---|---|
| Mobile client → Go API | Authenticated mobile device submits offline ops or requests pull over HTTPS/WSS |
| Go API → PostgreSQL (rimi_app) | rimi_app role, NOSUPERUSER NOBYPASSRLS; workspace RLS enforced per-transaction via GUCs |
| Go API → PostgreSQL (rimi_migrator) | Privileged role for DDL and TTL cleanup only; never used in request path |

The workspace identity is the primary trust anchor. Every request must derive workspace from the validated JWT claim — never from client-supplied values.

---

## STRIDE Analysis

### POST /v1/sync/batch

| Threat | Category | Control |
|---|---|---|
| Client forges workspace_id in request body to write to another tenant's inventory | Spoofing / Tampering | SYNC-SEC-02: workspace from JWT only; SYNC-SEC-03: reject body workspace_id |
| Client replays a previously applied op_id to double-apply an inventory delta | Tampering / Repudiation | SYNC-SEC-11: idempotency ledger; op lock + check + apply + insert in one tx |
| Two concurrent batches race on same entity_id, both read stock=10, both apply delta=-5, stock ends at 5 not 0 | Tampering | SYNC-SEC-10: pg_advisory_xact_lock(ws:entityId) serialises concurrent entity writes |
| Two concurrent batches with same op_ids in different order deadlock on op-level advisory locks | Denial of Service | SYNC-SEC-09: op_ids sorted before lock acquisition |
| Client sends 10,000 ops per batch to exhaust DB connections / advisory locks | Denial of Service | SYNC-SEC-06: max 50 ops per batch; reject with 400 if exceeded |
| Unauthenticated client accesses sync endpoint | Spoofing | SYNC-SEC-01: Bearer JWT required; 401 on missing/invalid |
| Payload contains SQL injection via entity_id or payload JSON | Tampering | SYNC-SEC-04: parameterised queries only; entity_id/op_id UUID format validated |
| Server logs raw payload blobs exposing product/customer PII | Information Disclosure | SYNC-SEC-12: logs MUST NOT contain payload blobs, delta values, or op_ids in bulk |
| Malformed delta (float, overflow) corrupts inventory quantity | Tampering | SYNC-SEC-05: delta must be a non-zero integer within ±10,000 |
| Client submits op for entity_type not in allowlist to probe internal tables | Elevation of Privilege | SYNC-SEC-04: entity_type and op_type allowlist enforced before DB access |

### GET /v1/sync/pull

| Threat | Category | Control |
|---|---|---|
| Unauthenticated pull reads another tenant's product data | Spoofing / Information Disclosure | SYNC-SEC-01, SYNC-SEC-02: auth + workspace from JWT |
| Client passes workspace_id as query param to pull cross-tenant data | Tampering | SYNC-SEC-03: workspace_id query param ignored; workspace from JWT claim |
| Client requests entity=internal_table to probe undocumented tables | Information Disclosure | SYNC-SEC-07: entity allowlist enforced; unknown entity returns 400 |
| Client requests limit=99999 to exhaust DB query and memory | Denial of Service | SYNC-SEC-08: max limit=500; default 200; reject values > 500 with 400 |
| Cursor values contain SQL injection | Tampering | SYNC-SEC-04: after_updated_at is integer (cast to timestamp server-side); after_id is UUID; both validated before use |
| RLS bypass via missing GUC setup | Elevation of Privilege | Existing TenantTx middleware sets rimi.workspace_id per transaction; sync pull handler must use the same middleware chain |

### WSS /v1/realtime

| Threat | Category | Control |
|---|---|---|
| Unauthenticated WebSocket upgrade | Spoofing | SYNC-SEC-13: auth validated before websocket.Accept; 401 sent as HTTP response if invalid |
| Client passes workspace_id in WS query param or custom header | Tampering / Elevation of Privilege | SYNC-SEC-14: workspace from JWT only; query params and non-standard headers ignored |
| Slow-loris or large-frame DoS on WS connection | Denial of Service | SYNC-SEC-15: connection-level read deadline and max message size set before entering read loop |
| Token rotated mid-session; stale workspace claim used for subsequent broadcasts | Elevation of Privilege | Phase 2 scope: no broadcasts. Phase 4+: implement JWT expiry re-validation on subscription events |
| WS path accessible without Authenticate middleware | Spoofing | SYNC-SEC-13: Authenticate middleware MUST wrap the /realtime route, not just be called inside the handler |

---

## Security Rules

Implementers MUST comply with every rule. Rules marked `[BLOCKER]` will cause Security to reject the PR.

### Authentication and Authorization

**SYNC-SEC-01 [BLOCKER]:** All three endpoints (`/v1/sync/batch`, `/v1/sync/pull`, `/v1/realtime`) MUST require a valid Bearer RS256 access token in the `Authorization` header. Missing or invalid tokens MUST return HTTP 401 before any DB or WS operation.

**SYNC-SEC-02 [BLOCKER]:** `workspace_id` MUST be derived exclusively from the validated JWT `workspace_id` claim. The value from `ClaimsFromContext(r.Context())` is the only authoritative source.

**SYNC-SEC-03 [BLOCKER]:** Request bodies for `/v1/sync/batch` MUST NOT contain a `workspace_id` field that is read or used. If present, ignore it. Implementing code MUST NOT read `req.WorkspaceID` or any equivalent from the parsed body.

**SYNC-SEC-13 [BLOCKER]:** For `WSS /v1/realtime`, the `Authenticate(verifier)` middleware MUST be applied at the router level wrapping the route — not only inside the handler function. This ensures the 401 is returned as an HTTP response before the WebSocket upgrade handshake.

**SYNC-SEC-14:** For `WSS /v1/realtime`, workspace MUST be derived from the JWT claim only. The handler MUST NOT read `r.URL.Query().Get("workspace_id")` or any custom header for workspace identity.

### Input Validation

**SYNC-SEC-04 [BLOCKER]:** Before any DB mutation in `/v1/sync/batch`, each operation MUST be validated:
- `op_id`: valid UUID v4 format (reject non-UUID strings)
- `entity_id`: valid UUID v4 format
- `entity_type`: MUST be in allowlist `["product", "inventory_item"]`; reject with 400 for unknown values
- `op_type`: MUST be in allowlist `["create", "update", "delete", "inventory_delta"]`; reject with 400

**SYNC-SEC-05:** `delta` field on `inventory_delta` ops MUST be a non-zero integer in the range `[-10_000, +10_000]`. Zero delta, non-integer (float), or out-of-range values MUST be rejected with 400.

**SYNC-SEC-07:** `GET /v1/sync/pull` MUST validate the `entity` query parameter against an allowlist `["product", "inventory_item"]`. Unknown entity values MUST return 400.

For cursor params: `after_updated_at` MUST be parsed as int64 (reject non-numeric); `after_id` MUST be a valid UUID if provided (reject non-UUID).

### Rate and Size Limits

**SYNC-SEC-06:** `POST /v1/sync/batch` MUST reject requests with more than 50 ops with HTTP 400. This check MUST occur before any DB access.

**SYNC-SEC-08:** `GET /v1/sync/pull` MUST cap `limit` at 500. Requests with `limit > 500` MUST be rejected with 400. Default limit when not provided: 200.

### Concurrency and Idempotency

**SYNC-SEC-09:** Before acquiring per-op advisory locks in `/v1/sync/batch`, op_ids for each entity group MUST be sorted lexicographically. This prevents deadlock when two concurrent batches contain overlapping op_ids in different order.

**SYNC-SEC-10:** Entity-level advisory locks MUST use workspace-scoped keys: `pg_advisory_xact_lock(hashtext(workspaceID + ":" + entityID))`. Using bare `entityID` as the lock key is insufficient and MUST NOT be used.

**SYNC-SEC-11 [BLOCKER]:** The idempotency check on `sync_applied_ops` MUST occur inside the same transaction as the inventory delta application. The sequence is: acquire op locks (sorted) → acquire entity lock → check ledger → apply delta → insert ledger row → commit. Checking the ledger outside the transaction is not acceptable.

### Data Access and RLS

**SYNC-SEC-15 (implied from Phase 1 pattern):** The `/v1/sync/batch` and `/v1/sync/pull` handlers MUST execute DB queries through the `TenantTx` middleware (or equivalent) that calls `set_config('rimi.workspace_id', wsID, true)` at transaction start. Without this, RLS on `sync_applied_ops` will fail closed (no rows visible), breaking idempotency lookups for legitimate requests.

### Logging and Information Disclosure

**SYNC-SEC-12:** Server logs MUST NOT include:
- Raw `payload` JSON blobs from sync operations
- Individual `delta` numeric values
- Lists of `op_id` UUIDs in bulk
- Any field classified as PII in `docs/security/phase-1-auth-workspace.md` (email, phone, display_name, addresses)
- Raw JWT strings

Log entries for sync endpoints MUST be limited to: HTTP method, path, workspace_id (masked to first 8 chars), op count, response status, duration.

### TTL Cleanup Privilege

**SYNC-SEC-16:** The TTL cleanup function `app.cleanup_sync_applied_ops()` is defined as `SECURITY DEFINER` owned by `rimi_migrator`. It MUST be invoked from a scheduled job running as `rimi_migrator` (or the function itself), never from application code running as `rimi_app`. Application code MUST NOT call `DELETE FROM sync_applied_ops WHERE applied_at < ...` directly.

---

## Required Test Cases

The following tests MUST pass before the backend endpoints are merged:

### Authentication
- `POST /v1/sync/batch` with no Authorization header → HTTP 401
- `GET /v1/sync/pull` with no Authorization header → HTTP 401
- `GET /v1/realtime` with no Authorization header → HTTP 401 (HTTP response, not WS error)
- All three endpoints with an expired JWT → HTTP 401

### Workspace Isolation
- `POST /v1/sync/batch` with valid JWT for workspace A cannot write to workspace B's inventory_items even if entity_id belongs to workspace B (RLS blocks it)
- `GET /v1/sync/pull` with valid JWT for workspace A returns zero rows for workspace B's products

### Input Validation
- Batch with `entity_type = "transactions"` (not allowlisted) → HTTP 400
- Batch with `op_type = "nuke"` → HTTP 400
- Batch with `delta = 0` on inventory_delta op → HTTP 400
- Batch with 51 ops → HTTP 400
- Pull with `entity = "workspace_members"` → HTTP 400
- Pull with `limit = 501` → HTTP 400

### Idempotency
- Replay of same `op_id` batch → second call returns cached result, inventory quantity unchanged (no double-apply)

### Concurrency
- Two concurrent batches with `inventory_delta` on same `entity_id` from same workspace → final quantity = baseline + sum of both deltas (no race, no double-count)

---

## Relationship to Phase 1 Security Rules

The Phase 1 security rules in `docs/security/phase-1-auth-workspace.md` continue to apply in full. The Phase 2 rules above are additive — they address threats specific to the sync and realtime surfaces. In particular:

- AUTH-10/11 (JWT verification, alg pinning) applies to all three Phase 2 endpoints
- TENANCY-05/06/07 (GUC setup, fail-closed RLS) applies to sync batch and pull
- NET-02 (request timeouts) applies to the WS connection lifecycle

*Last updated: 2026-05-31*
