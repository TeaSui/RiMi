# Stack Research

**Domain:** Flutter + Supabase all-in-one business management app (Vietnamese food sellers)
**Researched:** 2026-05-31
**Confidence:** HIGH (versions verified live from pub.dev + GitHub releases)

---

## Platform Baseline

| Platform | Version | Notes |
|----------|---------|-------|
| Flutter (stable) | 3.44.0 | Dart 3.12.0 ships with it |
| Dart SDK | 3.12.0 | Required for null safety, records, patterns |
| Supabase CLI | v2.102.0 | Local dev, migrations, Edge Function deploy |
| Node.js (Edge Functions dev) | 20 LTS | Supabase Edge Functions runtime is Deno 1.x; Node for tooling only |

---

## Recommended Stack

### 1. Flutter Core Framework

| Package | Version | Purpose | Why Recommended |
|---------|---------|---------|-----------------|
| `flutter_riverpod` | 3.3.1 | State management | 2026 standard for Flutter; code-gen providers, async notifiers, offline-aware stream providers. Replaces BLoC for most use cases. |
| `riverpod` | 3.2.1 | Riverpod core (pulled by flutter_riverpod) | Required peer dependency |
| `go_router` | 17.2.3 | Navigation / deep-linking | Declarative, type-safe routes; Flutter team endorsed; supports redirects for auth guards |
| `freezed` | 3.2.5 | Immutable data models + union types | Required for safe offline state modeling (pending/synced/conflict) |
| `json_annotation` | 4.12.0 | JSON serialization | Pairs with freezed; compile-time safe |
| `build_runner` | 2.15.0 | Code generation | Required for freezed, drift, riverpod_generator |

### 2. Supabase Integration

| Package | Version | Purpose | Why Recommended |
|---------|---------|---------|-----------------|
| `supabase_flutter` | 2.12.4 | Main Supabase client | Auth, DB queries, Realtime, Storage, Edge Functions; single dependency |
| Supabase Realtime (built-in) | via 2.12.4 | Live order + inventory updates | `onPostgresChanges` for orders/inventory tables; `onPresence` for multi-device |
| Supabase Auth (built-in) | via 2.12.4 | Authentication | Phone OTP (for Vietnamese market); magic link; workspace isolation via JWT |
| Supabase Edge Functions | TypeScript/Deno | Webhook ingestion, AI orchestration | All 3rd-party webhooks (ShopeeFood, GrabFood, TikTok Shop) receive here; normalize to internal format before writing to DB |

### 3. Offline-First / Local Database

| Package | Version | Purpose | Why Recommended |
|---------|---------|---------|-----------------|
| `drift` | 2.33.0 | Local SQLite ORM (primary offline store) | Type-safe, code-gen, reactive streams, migration support. Best choice for relational offline-first data (orders, inventory, products). Active development. |
| `drift_dev` | 2.33.0 | Drift code generation (dev dependency) | Generates type-safe query builders from schema |
| `sqflite` | 2.4.2+1 | Raw SQLite (fallback / migration utility) | Only use if drift is too heavy for a specific lightweight table; prefer drift |
| `path_provider` | 2.1.5 | Filesystem paths for drift DB files | Required by drift on mobile |
| `shared_preferences` | 2.5.5 | Simple key-value flags | Sync cursors, last-sync timestamps, feature flags — NOT for entity data |
| `flutter_secure_storage` | 10.3.1 | Encrypted key-value store | JWT tokens, refresh tokens, workspace credentials — never plaintext |

**Offline sync pattern:** client-generated UUIDs (`uuid: 4.5.3`) on all entities. Mutations write to local Drift DB immediately (optimistic). Background sync task reads pending records and upserts to Supabase. Conflict resolution: server timestamp wins (last-write-wins is acceptable for v1 food-seller scale).

### 4. Background Tasks / Sync

| Package | Version | Purpose | Why Recommended |
|---------|---------|---------|-----------------|
| `workmanager` | 0.9.0+3 | Periodic background sync (Android WorkManager + iOS BGTaskScheduler) | Industry standard for deferred offline sync; network-constrained tasks; exponential backoff on failure |
| `flutter_background_service` | 5.1.0 | Long-running foreground service | Use for continuous realtime channel maintenance when app is backgrounded; heavier than workmanager, use only for POS / always-on mode |
| `connectivity_plus` | 7.1.1 | Network state detection | Gate sync attempts; trigger immediate sync on reconnect |

**Background sync architecture:** `workmanager` fires every 15 min (Android minimum) for batch sync of accumulated offline mutations. `connectivity_plus` triggers an immediate one-off workmanager task on `ConnectivityResult.wifi/mobile` transition to minimize lag.

### 5. HTTP & API Clients

| Package | Version | Purpose | Why Recommended |
|---------|---------|---------|-----------------|
| `dio` | 5.9.2 | HTTP client for 3rd-party APIs | Interceptors for retry, auth token injection, logging. Use for payment gateways and any non-Supabase REST call |
| `retrofit` | 4.9.2 | Type-safe REST client (code-gen over dio) | Use for well-defined 3rd-party APIs (ShopeeFood/GrabFood partner APIs if they expose REST) |
| `http` | 1.6.0 | Lightweight HTTP (Dart stdlib wrapper) | Use only in Edge Functions; on Flutter prefer dio |

### 6. AI Integration (Claude API)

| Package | Version | Purpose | Why Recommended |
|---------|---------|---------|-----------------|
| `anthropic_sdk_dart` | 4.0.0 | Official-adjacent Claude API client for Dart | Type-safe access to Claude models; streaming, tool use, batch processing. Maintained by the community but tracks the Anthropic API closely. |
| `langchain_anthropic` | 0.3.1 | LangChain wrapper for Claude (optional) | Use if building chains/agents in Dart; otherwise use anthropic_sdk_dart directly for simpler use cases |

**AI architecture recommendation:** Run AI agents (Sales, Content, Finance) in Supabase Edge Functions (TypeScript), not in Flutter directly. Flutter calls Edge Function endpoints; Edge Functions hold the Claude API key and prompt logic. This keeps secrets off device, enables server-side caching, and allows prompt updates without app releases. `anthropic_sdk_dart` is useful for on-device Claude calls in offline/low-latency scenarios only (e.g., quick content suggestions) — these should be stateless and not depend on server context.

### 7. Vietnamese Payment SDKs

| Package | Version | Purpose | Notes |
|---------|---------|---------|-------|
| `momo_payment_flutter` | 1.0.2 | MoMo payment integration | Community package; integrates via MoMo REST API + app linking. **Verify against MoMo's latest partner API before using.** |
| `vnpay_flutter` | 2.0.0 | VNPAY payment integration | Uses WebView to render VNPAY payment page; Android + iOS + Web support |
| ZaloPay | — | ZaloPay integration | **No Flutter package found on pub.dev.** Implement via ZaloPay REST API directly using `dio` + app-link deeplink. Use ZaloPay's official SDK (Android/iOS native) via Flutter platform channels if needed. |

**Payment architecture:** All payment initiation and verification should go through Supabase Edge Functions (never expose payment credentials in Flutter app). Flutter → Edge Function → payment provider API → webhook back to Edge Function → update order in DB → Realtime push to Flutter.

### 8. Channel Integrations (ShopeeFood, GrabFood, TikTok Shop, Messenger, Zalo)

**There are no stable Flutter pub.dev packages for these integrations.** All channel integrations are webhook-based and belong entirely in Supabase Edge Functions.

| Channel | Integration Pattern |
|---------|-------------------|
| ShopeeFood | Register webhook URL (Edge Function) in ShopeeFood partner portal. Edge Function receives `POST /webhooks/shopeefood`, validates HMAC signature, normalizes to internal `orders` schema, inserts to Supabase DB. |
| GrabFood | Same pattern: `POST /webhooks/grabfood`, GrabFood HMAC validation, normalize + insert. |
| TikTok Shop | TikTok Shop Open Platform webhook: `POST /webhooks/tiktokshop`, validate using TikTok's HMAC-SHA256 header, normalize order + product sync. |
| Messenger | Meta Webhooks: verify token + `POST /webhooks/messenger`. Parse message objects for order intents; optionally feed to Claude Sales Agent. |
| Zalo OA | Zalo OA webhook: `POST /webhooks/zalo`. Parse Zalo message types; route to Sales Agent. |
| TPBank | TPBank Smart Banking webhook or polling: detect bank transfer events, match to pending orders by amount + reference code. |

**Edge Function webhook pattern (TypeScript):**
```typescript
// supabase/functions/webhooks-shopeefood/index.ts
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  // 1. Validate HMAC signature
  // 2. Parse order payload
  // 3. Normalize to internal OrderInsert schema
  // 4. Upsert to orders table (workspace_id via lookup of channel credential)
  // 5. Return 200 immediately (async processing)
})
```

### 9. E-Invoice (Hóa đơn điện tử)

**No stable Flutter pub.dev package for Vietnamese e-invoice providers (Viettel-S, MISA, VNPT, etc.).** This is a REST API integration, not a native SDK.

| Provider | Integration Method |
|----------|-------------------|
| Viettel-S | REST API (SOAP/REST hybrid); integrate via Supabase Edge Function. Credentials stored in Supabase Vault. |
| MISA | REST API; same Edge Function pattern. |
| VNPT E-Invoice | REST API; same pattern. |

**Recommendation:** Build a provider-agnostic `EInvoiceService` Edge Function that accepts an internal invoice model and translates to the selected provider's API format. Store the provider selection per workspace in the `workspace_settings` table. This allows users to switch providers without app updates.

**Compliance reference:** Nghị định 123/2020/NĐ-CP, Thông tư 78/2021/TT-BTC. E-invoice is an optional toggle per workspace — default OFF for new workspaces.

### 10. UI & Visual

| Package | Version | Purpose | Notes |
|---------|---------|---------|-------|
| `fl_chart` | 1.2.0 | Charts for Finance module (P&L, revenue trends) | Lightweight, Flutter-native; good for bar/line/pie charts |
| `cached_network_image` | 3.4.1 | Product images with caching | Pairs with flutter_cache_manager |
| `flutter_cache_manager` | 3.4.1 | Network resource caching | Used by cached_network_image; also for menu images |
| `lottie` | 3.3.3 | Loading animations / empty states | Keep bundle size in check; use sparingly |
| `shimmer` | 3.0.0 | Skeleton loading states | Use while Supabase queries load |
| `flutter_local_notifications` | 21.0.0 | Local order alerts (offline/background) | New order notifications when app is backgrounded |
| `firebase_messaging` | 16.2.2 | Push notifications (FCM) | Required for remote push; Supabase does not provide push natively — use FCM via Edge Function trigger |

---

## Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Supabase CLI v2.102.0 | Local dev, migrations, Edge Function deploy | `supabase start` for local stack; `supabase db push` for migrations |
| `build_runner` 2.15.0 | Code generation (freezed, drift, riverpod_generator) | Run: `dart run build_runner build --delete-conflicting-outputs` |
| Flutter DevTools | Performance profiling, widget inspector | Built into VS Code / Android Studio |
| `very_good_analysis` or `flutter_lints` | Static analysis | Enforce consistent code style |
| Deno (for Edge Functions local dev) | TypeScript Edge Function runtime | Bundled with Supabase CLI |

---

## Database Schema Patterns

### Multi-Tenant Offline-First (PostgreSQL / Supabase)

```sql
-- Every table includes workspace_id for RLS isolation
-- Every entity uses client-generated UUID as primary key

CREATE TABLE orders (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),  -- overridden by client UUID on insert
  workspace_id UUID NOT NULL REFERENCES workspaces(id),
  channel     TEXT NOT NULL,  -- 'shopeefood' | 'grabfood' | 'tiktok' | 'messenger' | 'zalo' | 'offline'
  status      TEXT NOT NULL DEFAULT 'pending',
  total_amount NUMERIC(15,2) NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  synced_at   TIMESTAMPTZ,   -- NULL = not yet synced from offline
  client_created_at TIMESTAMPTZ  -- original device timestamp for offline orders
);

-- RLS: workspace isolation
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "workspace_isolation" ON orders
  USING (workspace_id = (auth.jwt() -> 'app_metadata' ->> 'workspace_id')::uuid);

-- Realtime: enable for orders and inventory_items
ALTER PUBLICATION supabase_realtime ADD TABLE orders;
ALTER PUBLICATION supabase_realtime ADD TABLE inventory_items;
```

**Key patterns:**
- `workspace_id` on every table, indexed: `CREATE INDEX ON orders(workspace_id)`
- Client-generated UUIDs: Flutter generates `uuid.v4()` before any network call
- Offline queue table: `CREATE TABLE sync_queue (id UUID, table_name TEXT, operation TEXT, payload JSONB, created_at TIMESTAMPTZ)` — accumulates mutations offline; Workmanager drains this on connectivity
- Supabase Vault for secrets: payment credentials, channel API keys stored in `vault.secrets`, never in app code

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Drift (local DB) | Isar | Isar is archived/discontinued as of 2024 — do NOT use for new projects |
| Drift (local DB) | SQLite (raw sqflite) | Only for extremely simple use cases; drift's type safety is worth the code-gen overhead |
| flutter_riverpod | BLoC / flutter_bloc | BLoC is acceptable but more boilerplate; Riverpod's code-gen providers are cleaner for 2026 |
| flutter_riverpod | Provider (package) | Provider is effectively superseded by Riverpod; do not use for new projects |
| Supabase Realtime | Firebase Realtime DB | Would require adding a second backend — stay in Supabase |
| Supabase Edge Functions | AWS Lambda | Only if Supabase limits are hit at scale; overkill for v1 |
| AI in Edge Functions | AI in Flutter (anthropic_sdk_dart) | On-device only for fast, stateless suggestions; never for agentic flows that need server context |
| go_router | auto_route | go_router is now Flutter team-maintained; auto_route for very complex navigation that go_router can't handle |
| workmanager | flutter_background_service | flutter_background_service for always-on foreground POS mode only; workmanager for periodic sync |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `isar` | Archived / discontinued by maintainer in 2024; no security patches | `drift` |
| `hive_flutter` | Not suitable for relational data; weak query support; largely superseded | `drift` for relational, `shared_preferences` for simple KV |
| `GetX` | Anti-pattern for large apps; mixes routing, state, DI in ways that resist testing | `flutter_riverpod` + `go_router` + `get_it` |
| `Provider` package | Superseded by Riverpod; no code-gen support; verbose for complex state | `flutter_riverpod` |
| Storing API keys in Flutter app | Trivially extractable from APK/IPA; violates security rules | Supabase Edge Functions hold all third-party credentials |
| Supabase client-side admin key | `service_role` key bypasses RLS; catastrophic if leaked | Use `anon` key on client; `service_role` only in Edge Functions via env vars |
| Direct ZaloPay SDK (no Flutter package) | No official Flutter package exists; native bridges are fragile | `dio` + ZaloPay REST API via Edge Function; deep-link for payment redirect |
| Multiple local DB solutions | Drift + Hive + sqflite simultaneously = sync nightmare | Single source of truth: Drift for all relational local data |
| `syncfusion_flutter_charts` | Community license cost; overkill for v1 finance charts | `fl_chart` (MIT, free) |

---

## Version Compatibility Matrix

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| `supabase_flutter: 2.12.4` | Dart ≥3.0, Flutter ≥3.19 | Requires `supabase_flutter: ^2.0.0` in pubspec for patch updates |
| `flutter_riverpod: 3.3.1` | Dart ≥3.0 | Must align `riverpod: 3.2.1` peer dep |
| `drift: 2.33.0` | Dart ≥3.0, `drift_dev: 2.33.0` | Versions must match exactly |
| `freezed: 3.2.5` | `build_runner: ^2.15`, `json_annotation: ^4.12` | Run code-gen after each model change |
| `workmanager: 0.9.0+3` | Flutter ≥3.10, Dart ≥3.0, Android API ≥23, iOS ≥13 | iOS background fetch limited to system-scheduled intervals |
| `flutter_local_notifications: 21.0.0` | Flutter ≥3.16 | Breaking changes at major versions; test on both platforms |
| `go_router: 17.2.3` | Flutter ≥3.19 | Major version bumps frequently; pin minor |

---

## pubspec.yaml Starter (key dependencies)

```yaml
dependencies:
  flutter:
    sdk: flutter

  # Backend
  supabase_flutter: ^2.12.4

  # State management
  flutter_riverpod: ^3.3.1
  riverpod: ^3.2.1
  riverpod_annotation: ^3.3.1  # for @riverpod code-gen

  # Navigation
  go_router: ^17.2.3

  # Local DB (offline-first)
  drift: ^2.33.0
  sqlite3_flutter_libs: ^0.5.0   # required by drift on mobile
  path_provider: ^2.1.5

  # Sync helpers
  workmanager: ^0.9.0+3
  connectivity_plus: ^7.1.1
  uuid: ^4.5.3

  # Models
  freezed_annotation: ^3.2.5
  json_annotation: ^4.12.0

  # HTTP
  dio: ^5.9.2

  # Storage
  flutter_secure_storage: ^10.3.1
  shared_preferences: ^2.5.5

  # AI (on-device, optional)
  anthropic_sdk_dart: ^4.0.0

  # Payments
  momo_payment_flutter: ^1.0.2
  vnpay_flutter: ^2.0.0
  # ZaloPay: implement via dio + REST API

  # UI
  fl_chart: ^1.2.0
  cached_network_image: ^3.4.1
  flutter_cache_manager: ^3.4.1
  flutter_local_notifications: ^21.0.0
  firebase_messaging: ^16.2.2
  shimmer: ^3.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.15.0
  drift_dev: ^2.33.0
  freezed: ^3.2.5
  json_serializable: ^6.9.0
  riverpod_generator: ^3.3.1
  custom_lint: ^0.7.5
  riverpod_lint: ^3.3.1
```

---

## Sources

- `pub.dev` live API — all package versions verified 2026-05-31
- `/supabase/supabase-flutter` (Context7) — Realtime channels, presence, onPostgresChanges patterns
- `/supabase/supabase` (Context7) — RLS multi-tenant patterns, Edge Functions
- `/fluttercommunity/flutter_workmanager` (Context7) — background task dispatch, iOS/Android constraints
- GitHub `supabase/cli` releases API — Supabase CLI v2.102.0 confirmed
- Flutter stable releases JSON — Flutter 3.44.0 / Dart 3.12.0 confirmed
- Isar GitHub: archived/discontinued status from maintainer announcement (2024)
- ZaloPay pub.dev search: no official Flutter package found as of 2026-05-31

---

*Stack research for: Flutter + Supabase all-in-one business management — Vietnamese food sellers (RiMi)*
*Researched: 2026-05-31*
