# Project Research Summary

**Project:** RiMi
**Domain:** Flutter + Supabase offline-first multi-tenant F&B business management SaaS — Vietnamese market
**Researched:** 2026-05-31
**Confidence:** HIGH

## Executive Summary

RiMi is a category-creating product in the Vietnamese F&B micro-business space. Competitors (KiotViet, Sapo, GoSELL) cover parts of the feature set but none unify multi-channel delivery orders, AI agents, and Vietnamese accounting compliance in a mobile-first, offline-capable app. The recommended architecture is Flutter + Supabase with workspace-scoped RLS from day one, Drift for offline SQLite, Riverpod for state, and all external integrations routed through Supabase Edge Functions (TypeScript).

The highest-risk areas are: (1) multi-platform webhook idempotency — delivery platforms retry aggressively; (2) offline inventory conflicts — two devices can decrement the same stock; (3) RLS policy gaps — missing policies silently expose cross-workspace data. All three must be addressed in Phase 1 and Phase 3 respectively, not retrofitted.

The strongest differentiators vs. competition are: bank transfer auto-detection, the AI agent trio (Sales/Content/Finance), and the offline-first mobile UX. These should be preserved in the MVP even at the cost of simplifying the feature set elsewhere.

## Key Findings

### Recommended Stack

Flutter 3.44.0 / Dart 3.12.0 forms the mobile layer. `flutter_riverpod 3.3.1` handles state management; `drift 2.33.0` (SQLite) provides offline storage with a sync queue pattern; `supabase_flutter 2.12.4` connects to the backend. All external integrations (ShopeeFood, GrabFood, TikTok Shop, payments, AI, e-invoice) live exclusively in Supabase Edge Functions (TypeScript / Deno) — the Flutter app never holds any third-party API keys.

**Core technologies:**
- `flutter_riverpod 3.3.1`: state management, dependency injection — industry standard for Flutter in 2026
- `drift 2.33.0`: local SQLite ORM, replaces discontinued `isar`; supports migrations and DAOs
- `supabase_flutter 2.12.4`: auth, realtime, storage, remote CRUD
- `workmanager 0.9.0+3`: background sync on iOS + Android
- `anthropic_sdk_dart 4.0.0` (optional): direct Claude calls in dev; production routes through Edge Function proxy
- `go_router 17.2.3`: declarative routing with deep-link support

**Do NOT use:** `isar` (discontinued), `hive_flutter` (not relational), `GetX`/`Provider` (superseded), `service_role` key in Flutter (security catastrophe).

### Expected Features

**Must have (table stakes in VN market):**
- Unified order inbox: ShopeeFood + GrabFood + offline (manual POS)
- Product catalog with variants + channel-specific availability/pricing
- Real-time inventory stock tracking (product-level)
- Revenue summary + income/expense recording + P&L (báo cáo kết quả kinh doanh)
- Cash flow ledger (sổ quỹ tiền mặt) + debt tracking (công nợ)
- Tax summary for hộ kinh doanh (khoán thuế)
- Payment recording: MoMo, ZaloPay, VNPAY, cash, bank transfer
- Basic customer CRM (auto-created from orders)
- Push notifications for new orders

**Should have (competitive differentiators):**
- Bank transfer auto-detect + matching (TPBank) — nobody else has this
- AI Content Agent (caption + menu copy generation)
- Customer loyalty / visit count
- TikTok Shop + Messenger + Zalo OA order handling

**Defer (v2+):**
- AI Sales Agent, AI Finance Agent (needs data history to be useful)
- Ingredient-level inventory / recipe costing
- E-invoice module (compliance toggle — v1.x after initial launch validation)
- Content calendar, full chatbot

### Architecture Approach

Supabase is the entire backend: PostgreSQL with workspace-scoped RLS on every table, Realtime channels for live order/inventory push, Edge Functions (TypeScript) for all external API calls. Flutter connects via `supabase_flutter`; offline writes land in Drift (SQLite) first, then sync via a background queue. AI agents are Edge Function proxies — the Claude API key never leaves the server.

**Major components:**
1. Flutter UI — feature-first structure, Riverpod providers, Drift local DB
2. SyncManager — WorkManager background task; flushes offline queue on reconnect
3. RealtimeManager — central channel registry with ref-counting to prevent subscription leaks
4. Supabase PostgreSQL + RLS — workspace isolation; atomic inventory functions
5. Edge Functions — webhook ingestion, payment verification, AI proxy, e-invoice adapter

### Critical Pitfalls

1. **RLS missing on new tables** — add `ENABLE ROW LEVEL SECURITY` + policy in same migration as `CREATE TABLE`; add CI check
2. **Recursive RLS policies** — use a flat `workspace_members` table + `SECURITY DEFINER` function for membership checks
3. **Offline inventory conflict** — use atomic server-side `rpc('adjust_inventory')` with row lock; never direct UPDATE from client
4. **Duplicate orders from webhook retries** — `UNIQUE` constraint on `platform_order_id`; always `upsert` in webhook Edge Functions
5. **Realtime subscription leaks** — central RealtimeManager with ref-counting; never subscribe inside widget `initState`
6. **`service_role` key in Flutter** — pre-commit hook to grep for it; use only in Deno.env
7. **Payment HMAC not verified** — signature check is the first line of every payment Edge Function
8. **AI token blowup** — pre-aggregate data before sending to Claude; enforce `max_tokens` + per-workspace call cap

## Implications for Roadmap

### Phase 1: Foundation & Auth
**Rationale:** Everything else depends on workspace-scoped RLS and auth. Get this right first; it cannot be retrofitted.
**Delivers:** Supabase schema (all tables with RLS), Flutter auth flow, workspace creation/switching, CI RLS check
**Addresses:** WORKSPACE, AUTH requirements
**Avoids:** RLS pitfalls, service_role exposure

### Phase 2: Core Infrastructure (Offline + Realtime)
**Rationale:** Offline-first is a core architectural constraint, not a feature. Drift DB, SyncManager, and RealtimeManager must be scaffolded before any feature uses them.
**Delivers:** Drift local schema, SyncManager, RealtimeManager, connectivity handling
**Avoids:** Realtime subscription leaks, offline sync failures

### Phase 3: Product Catalog & Inventory
**Rationale:** Orders reference products; inventory deducts on order. Products must exist before orders.
**Delivers:** Product catalog with variants, channel availability/pricing, stock tracking, low-stock alerts
**Avoids:** Offline inventory conflict (atomic adjust_inventory RPC)

### Phase 4: Orders — Manual & Platform Webhooks
**Rationale:** Core value proposition. Manual/offline orders first to validate the UX; then platform webhooks.
**Delivers:** Offline order creation, order lifecycle, ShopeeFood + GrabFood webhook ingestion with idempotency, Realtime order push
**Avoids:** Duplicate orders, webhook retry floods

### Phase 5: Finance & Payments
**Rationale:** Revenue flows from orders; needs order data to be meaningful. Payment verification is security-critical.
**Delivers:** Income/expense recording, P&L, sổ quỹ, công nợ, tax summary, MoMo/ZaloPay/VNPAY recording, bank transfer auto-detect
**Avoids:** Payment signature bypass, bank transfer false positives

### Phase 6: Customer CRM & Extended Integrations
**Rationale:** CRM enriches existing order data; TikTok Shop + Messenger + Zalo expand reach.
**Delivers:** Customer profiles, order history, loyalty tracking, TikTok Shop + Messenger + Zalo order handling
**Addresses:** CRM, extended channel requirements

### Phase 7: AI Agents
**Rationale:** AI needs real product/finance data to be useful. Build after Phases 3–5 have populated the database.
**Delivers:** AI Content Agent (captions, menu copy), AI Sales Agent, Edge Function proxy with token/cost controls
**Avoids:** Prompt injection, AI cost blowup

### Phase 8: E-Invoice Module
**Rationale:** Complex compliance feature; optional toggle. Build last — requires Finance + CRM data.
**Delivers:** E-invoice issuance, cancellation/adjustment, provider adapter (Viettel-S / MISA), tax authority submission
**Avoids:** Invalid invoice fields, missing cancellation flow

### Phase Ordering Rationale

- Foundation before features — RLS and offline infrastructure cannot be retrofitted
- Products before orders — foreign key dependency
- Orders before Finance — revenue auto-populated from orders
- Finance before AI Finance Agent — agent needs data context
- E-invoice last — optional compliance module; all other modules feed it

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 4:** ShopeeFood/GrabFood webhook authentication specifics change; verify current HMAC scheme before implementing
- **Phase 5:** TPBank Open Banking API availability and webhook format — confirm current API docs
- **Phase 7:** Claude API tool_use patterns for Finance Agent — complex multi-turn context management
- **Phase 8:** Viettel-S vs MISA API — research current integration complexity and sandbox availability

Phases with standard patterns (skip research phase):
- **Phase 1:** Well-documented Supabase RLS + Flutter auth patterns
- **Phase 2:** Drift + WorkManager patterns are mature and well-documented
- **Phase 3:** Standard CRUD + offline-first patterns from Phase 2 infrastructure

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All library versions verified on pub.dev + Supabase docs |
| Features | HIGH | Based on VN market competitor analysis + NĐ 123/2020 |
| Architecture | HIGH | Standard Supabase patterns; well-documented |
| Pitfalls | HIGH | Based on known Supabase/Flutter community issues |

**Overall confidence:** HIGH

### Gaps to Address

- **ShopeeFood/GrabFood API docs:** Exact webhook schema and authentication headers need verification with current (2026) API docs before Phase 4 implementation.
- **TPBank Open Banking:** Confirm webhook availability and whether it requires separate business account registration.
- **E-invoice provider choice:** Viettel-S vs MISA — get sandbox credentials and test API before Phase 8 planning.
- **TikTok Shop API stability:** TikTok Shop VN API has changed significantly in 2024–2025; research current webhook format before Phase 6.

## Sources

### Primary (HIGH confidence)
- pub.dev — Flutter package versions (flutter_riverpod, drift, supabase_flutter, workmanager, go_router, freezed)
- Supabase documentation — RLS, Realtime, Edge Functions, supabase-js
- Nghị định 123/2020/NĐ-CP — e-invoice required fields
- KiotViet, Sapo, GoSELL product pages — feature matrix

### Secondary (MEDIUM confidence)
- Vietnamese F&B developer community — VN payment integration notes
- Supabase community forum — Realtime subscription patterns, RLS gotchas
- Toast POS / Square feature set — global F&B SaaS reference

### Tertiary (LOW confidence)
- ShopeeFood/GrabFood webhook schema — based on 2024 docs; verify before Phase 4
- TPBank Open Banking availability — needs direct confirmation
- TikTok Shop VN API — subject to change; re-research before Phase 6

---
*Research completed: 2026-05-31*
*Ready for roadmap: yes*
