# Architecture Research

**Domain:** Flutter + Supabase offline-first multi-tenant F&B SaaS
**Researched:** 2026-05-31
**Confidence:** HIGH

## Standard Architecture

### System Overview

```
┌──────────────────────────────────────────────────────────────┐
│                    Flutter Mobile App                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    │
│  │ Orders   │  │Products  │  │ Finance  │  │ AI Chat  │    │
│  │  Screen  │  │/Inventory│  │ Module   │  │ (Agents) │    │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘    │
│       │              │              │              │         │
│  ┌────┴──────────────┴──────────────┴──────────────┴──────┐  │
│  │              Riverpod State Layer (Providers)           │  │
│  └────┬──────────────────────────────────────────────┬────┘  │
│       │                                              │        │
│  ┌────┴──────┐                              ┌────────┴─────┐  │
│  │  Drift DB │  ← offline queue + cache     │ Supabase FL  │  │
│  │ (SQLite)  │  ← client-generated UUIDs    │   Client     │  │
│  └────┬──────┘                              └────────┬─────┘  │
│       │ SyncManager (WorkManager)                    │        │
└───────┴──────────────────────────────────────────────┴────────┘
                              │
                    ┌─────────┴──────────┐
                    │   Supabase Cloud   │
          ┌─────────┴─────────────────────┴─────────┐
          │                                          │
    ┌─────┴──────┐  ┌──────────┐  ┌────────────────┐│
    │ PostgreSQL │  │ Realtime │  │ Edge Functions ││
    │ + RLS      │  │ Channels │  │ (TypeScript)   ││
    └─────┬──────┘  └──────────┘  └────────┬───────┘│
          │                                │         │
    ┌─────┴──────────────────────────────────┐       │
    │         Storage (receipts, avatars)     │       │
    └────────────────────────────────────────┘       │
                                          ┌──────────┴──────┐
                                          │ External APIs   │
                                          │ ShopeeFood      │
                                          │ GrabFood        │
                                          │ TikTok Shop     │
                                          │ Zalo OA         │
                                          │ Meta (Messenger)│
                                          │ MoMo/ZaloPay    │
                                          │ VNPAY/TPBank    │
                                          │ E-Invoice prov. │
                                          │ Claude API      │
                                          └─────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| Flutter UI | Screen rendering, user input, local feedback | Feature-first folder structure |
| Riverpod Providers | State management, dependency injection, async data | AsyncNotifierProvider per feature |
| Drift (SQLite) | Offline storage, write-ahead queue, local cache | Tables mirror Supabase schema |
| SyncManager | Flush offline queue to Supabase on reconnect | WorkManager + connectivity_plus |
| Supabase Flutter Client | Auth, realtime subscriptions, remote CRUD | supabase_flutter 2.x |
| Supabase PostgreSQL + RLS | Multi-tenant data isolation, ACID guarantees | Every table has workspace_id |
| Supabase Realtime | Push order/inventory changes to subscribed clients | Phoenix channels over WebSocket |
| Edge Functions (TypeScript) | Webhook ingestion, payment verification, AI proxy | Deno runtime, HMAC validation |
| Claude API (via Edge Fn) | AI agents: Sales, Content, Finance | Tool-use pattern, context per agent |
| E-Invoice Edge Fn | Wrap Viettel-S/MISA REST API | Provider-agnostic adapter |

## Recommended Project Structure

```
lib/
├── core/
│   ├── auth/                  # Auth state, session management
│   ├── database/              # Drift database, DAOs, migrations
│   ├── sync/                  # SyncManager, offline queue
│   ├── realtime/              # Realtime subscription manager
│   ├── network/               # Dio client, interceptors
│   └── config/                # Environment, feature flags
├── features/
│   ├── workspace/             # Workspace setup, settings
│   ├── orders/                # Order inbox, detail, creation
│   ├── products/              # Product catalog, variants
│   ├── inventory/             # Stock tracking, adjustments
│   ├── customers/             # CRM, profiles
│   ├── finance/               # Income, expense, P&L, cash flow
│   ├── content/               # AI content generation
│   ├── ai_agents/             # Sales, Content, Finance agents
│   └── einvoice/              # E-invoice module (optional)
├── integrations/
│   ├── shopeefood/            # ShopeeFood order models + mappers
│   ├── grabfood/              # GrabFood order models + mappers
│   ├── tiktokshop/            # TikTok Shop models + mappers
│   ├── payments/              # MoMo, ZaloPay, VNPAY, bank
│   └── messenger_zalo/        # Chat order handling
└── shared/
    ├── widgets/               # Design system components
    ├── utils/                 # Formatters (VND, dates, VN phone)
    ├── models/                # Shared domain models
    └── router/                # go_router configuration

supabase/
├── migrations/                # SQL migration files (numbered)
├── functions/
│   ├── webhook-shopeefood/    # ShopeeFood webhook ingestion
│   ├── webhook-grabfood/      # GrabFood webhook ingestion
│   ├── webhook-tiktokshop/    # TikTok Shop webhook ingestion
│   ├── webhook-payment/       # MoMo/ZaloPay/VNPAY callbacks
│   ├── bank-transfer-detect/  # TPBank webhook + matching
│   ├── ai-agent/              # Claude API proxy (Sales/Content/Finance)
│   └── einvoice/              # E-invoice provider adapter
└── seed/                      # Dev seed data
```

## Architectural Patterns

### Pattern 1: Workspace-Scoped RLS

**What:** Every table has `workspace_id uuid NOT NULL REFERENCES workspaces(id)`. RLS policies gate all reads/writes on `auth.uid()` membership in that workspace.

**When to use:** Always — day one. Never add workspace_id retroactively.

**Trade-offs:** Slight query overhead; prevents all cross-tenant leaks.

**Example:**
```sql
-- Enable RLS on every table
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- Policy: workspace members can see their workspace's orders
CREATE POLICY "workspace_members_orders"
ON orders
USING (
  workspace_id IN (
    SELECT workspace_id FROM workspace_members
    WHERE user_id = auth.uid()
  )
);
```

**Critical:** never use a recursive policy (workspace_members referencing itself). Use a flat `workspace_members(workspace_id, user_id)` table.

### Pattern 2: Offline-First with Client-Generated UUIDs

**What:** Flutter generates `uuid_v4()` on the client before writing. Drift stores the record immediately. SyncManager upserts to Supabase when connectivity returns.

**When to use:** All entities (orders, products, inventory_items, transactions).

**Trade-offs:** Occasional `uuid` collision risk (negligible with v4); requires idempotent upserts on server.

**Example:**
```dart
// In OrderRepository
Future<Order> createOrder(OrderCreateInput input) async {
  final order = Order(
    id: const Uuid().v4(),          // client-generated
    workspaceId: input.workspaceId,
    status: OrderStatus.pending,
    createdAt: DateTime.now(),
    // ...
  );
  await _localDb.insertOrder(order);        // write locally first
  _syncManager.enqueue(SyncItem.upsert(order)); // queue for sync
  return order;
}
```

### Pattern 3: Realtime Subscription Manager

**What:** Central class in `core/realtime/` manages all Supabase Realtime subscriptions. Screens subscribe/unsubscribe via a ref-counting mechanism to prevent leaks.

**When to use:** Orders screen, Inventory screen — anything needing live push.

**Trade-offs:** Central manager adds indirection; prevents duplicate channel registrations.

**Example:**
```dart
class RealtimeManager {
  final Map<String, RealtimeChannel> _channels = {};

  RealtimeChannel subscribeOrders(String workspaceId) {
    final key = 'orders:$workspaceId';
    return _channels.putIfAbsent(key, () =>
      supabase.channel(key)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'workspace_id',
            value: workspaceId,
          ),
          callback: _onOrderChange,
        )
        ..subscribe()
    );
  }

  void unsubscribe(String key) {
    _channels.remove(key)?.unsubscribe();
  }
}
```

### Pattern 4: Edge Function Webhook Ingestion

**What:** All external platform webhooks hit a Supabase Edge Function. The function validates the HMAC signature, normalises the payload to the internal `orders` schema, and upserts with idempotency (platform_order_id is the dedup key).

**When to use:** ShopeeFood, GrabFood, TikTok Shop, payment callbacks.

**Trade-offs:** Edge Function cold starts add ~100ms; acceptable for async webhook processing.

**Example:**
```typescript
// supabase/functions/webhook-shopeefood/index.ts
Deno.serve(async (req) => {
  const signature = req.headers.get('X-ShopeeFood-Signature');
  if (!verifyHmac(await req.clone().text(), signature, Deno.env.get('SHOPEEFOOD_SECRET'))) {
    return new Response('Unauthorized', { status: 401 });
  }

  const payload = await req.json();
  const order = mapShopeeFoodOrder(payload);  // normalise to internal schema

  const { error } = await supabase
    .from('orders')
    .upsert(order, { onConflict: 'platform_order_id' });

  return new Response(JSON.stringify({ ok: !error }), { status: error ? 500 : 200 });
});
```

### Pattern 5: AI Agent via Edge Function Proxy

**What:** Flutter calls a Supabase Edge Function (authenticated via JWT). The Edge Function holds the Claude API key, builds the prompt with workspace context, calls Claude with tool_use, and streams the response back.

**When to use:** All AI agent interactions (Sales, Content, Finance).

**Why:** API key never touches the Flutter app; prompts can be updated without app release.

```typescript
// supabase/functions/ai-agent/index.ts
Deno.serve(async (req) => {
  const { agentType, userMessage, workspaceId } = await req.json();
  const context = await loadWorkspaceContext(workspaceId, agentType);

  const response = await anthropic.messages.create({
    model: 'claude-opus-4-7',
    max_tokens: 1024,
    system: buildSystemPrompt(agentType, context),
    messages: [{ role: 'user', content: userMessage }],
  });

  return new Response(JSON.stringify(response), {
    headers: { 'Content-Type': 'application/json' },
  });
});
```

## Data Flow

### Order Ingestion (Platform Webhook)

```
Platform (ShopeeFood/GrabFood/TikTok)
    ↓ HTTP POST with HMAC signature
Edge Function (validate → normalise → upsert)
    ↓ INSERT/UPDATE orders table
Supabase Realtime (postgres_changes)
    ↓ WebSocket push to subscribed Flutter clients
Flutter RealtimeManager → Riverpod Provider invalidate
    ↓
Orders Screen updates instantly
```

### Offline Order Creation

```
Flutter UI (user creates order)
    ↓ client UUID generated
Drift (local SQLite insert)
    ↓ SyncQueue.enqueue(upsert)
UI shows order immediately (optimistic)
    ↓ [when connectivity restored]
SyncManager flush: Supabase upsert (idempotent)
    ↓ Server triggers Realtime push to other devices
```

### Finance Record

```
User enters expense/income
    ↓
Drift (local write)
    ↓ SyncQueue.enqueue
    ↓ [sync]
Supabase transactions table
    ↓ finance_summary view auto-aggregates
Flutter Finance Provider reads view → renders P&L
```

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| 0–500 workspaces | Supabase free/pro tier; single region (ap-southeast-1) |
| 500–5k workspaces | Supabase Pro; add read replicas; index workspace_id on all hot tables |
| 5k+ workspaces | Supabase Enterprise or self-host; partition orders by workspace; consider queue (pg_cron / Redis) for webhook ingestion |

### Scaling Priorities

1. **First bottleneck:** Realtime connections (Supabase Pro: 500 concurrent). Mitigation: lazy subscribe (only active screen subscribes).
2. **Second bottleneck:** Edge Function cold starts under high webhook volume. Mitigation: dedicated webhook processing queue.

## Anti-Patterns

### Anti-Pattern 1: Using `service_role` Key in Flutter

**What people do:** Put the Supabase service role key in Flutter for "convenience" to bypass RLS during development.
**Why it's wrong:** Service role bypasses all RLS; if leaked via APK decompilation, entire database is exposed.
**Do this instead:** Always use `anon` key in Flutter; use service role only in Edge Functions with Deno.env.

### Anti-Pattern 2: Recursive RLS Policies

**What people do:** `workspace_members` policy references `workspace_members` to check membership.
**Why it's wrong:** Infinite recursion → query timeout / Supabase error.
**Do this instead:** Use a flat, non-recursive membership check. If needed, use a security definer function.

### Anti-Pattern 3: Per-Screen Realtime Channel Registration

**What people do:** Subscribe to a channel in `initState`, forget to unsubscribe in `dispose`.
**Why it's wrong:** WebSocket connections accumulate; memory leak + Supabase connection limit hit.
**Do this instead:** Central RealtimeManager with ref counting; Riverpod provider lifecycle handles subscribe/unsubscribe.

### Anti-Pattern 4: Syncing Timestamps from Client

**What people do:** Use Flutter `DateTime.now()` as `created_at` and trust it for ordering.
**Why it's wrong:** Device clocks can be wrong (especially older Android devices); creates phantom ordering bugs.
**Do this instead:** Use `now()` as Supabase DEFAULT on `created_at`. Store `client_created_at` separately for offline UX.

### Anti-Pattern 5: Storing Platform Tokens in Flutter Secure Storage

**What people do:** Store ShopeeFood/GrabFood API tokens in `flutter_secure_storage` on device.
**Why it's wrong:** Platform tokens are workspace credentials, not user credentials; they shouldn't travel to every user's device.
**Do this instead:** Store platform tokens in Supabase (encrypted column or Vault); Edge Functions use them server-side.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| ShopeeFood | Webhook → Edge Function → upsert orders | HMAC-SHA256 signature |
| GrabFood | Webhook → Edge Function → upsert orders | Bearer token validation |
| TikTok Shop | Webhook → Edge Function → upsert orders | HMAC signature per TikTok docs |
| MoMo | Webhook → Edge Function → record payment | ipn_url callback |
| ZaloPay | Webhook → Edge Function → record payment | HMAC-SHA256 |
| VNPAY | Redirect + IPN → Edge Function | checksum validation |
| TPBank | Webhook → Edge Function → match transfer | Open Banking API |
| Claude API | Edge Function → Claude messages API | Keep key in Deno.env |
| E-Invoice | Edge Function → Viettel-S/MISA REST | Provider adapter pattern |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Flutter ↔ Supabase | supabase_flutter SDK + Realtime | JWT auth on every request |
| Flutter ↔ Edge Functions | Authenticated POST via supabase.functions.invoke() | Same JWT |
| Edge Fn ↔ PostgreSQL | supabase-js with service role (Deno.env only) | Never expose to client |
| Orders → Inventory | DB trigger on order status change | Deduct stock on confirmed |
| Orders → Finance | DB trigger / Edge Function | Create revenue record on delivered |

## Build Order Recommendation

1. **Foundation first:** Supabase schema (all tables, RLS, indexes) + Flutter auth + workspace setup
2. **Offline core:** Drift local schema mirrors Supabase; SyncManager; UUID generation
3. **Product catalog:** Before any orders (orders reference products)
4. **Orders (manual/offline):** Before platform integrations (test the flow first)
5. **Realtime subscriptions:** Orders + inventory channels
6. **Platform webhooks:** ShopeeFood first (highest volume), then GrabFood, TikTok Shop
7. **Finance module:** After orders (revenue auto-populated from orders)
8. **AI agents:** After product + finance data exists (agents need context)
9. **E-invoice:** Late — requires Finance + Customer data; optional toggle

## Sources

- Supabase official docs: RLS patterns, Realtime, Edge Functions
- Flutter architecture guides: feature-first structure, Riverpod patterns
- Offline-first sync: Supabase community patterns, Delta sync approaches
- Supabase Realtime documentation (Phoenix channels)

---
*Architecture research for: RiMi — Flutter + Supabase F&B SaaS*
*Researched: 2026-05-31*
