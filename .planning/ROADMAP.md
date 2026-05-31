# Roadmap: RiMi

## Overview

RiMi is built in 8 phases, ordered by strict dependency: foundation → offline infrastructure → products → orders → CRM/dashboard → finance → AI → e-invoice. The first two phases produce no user-visible features — they are architectural prerequisites that cannot be retrofitted. From Phase 3 onward, each phase ships a complete, usable module. Phases 3–4 are the MVP validation checkpoint; if order management works well, the remaining phases build the full stack.

## Phases

- [x] **Phase 1: Foundation** — Go+Postgres schema, RLS, Flutter auth + workspace setup
- [ ] **Phase 2: Offline Core** — Drift local DB, SyncManager, Realtime infrastructure
- [ ] **Phase 3: Products & Inventory** — Product catalog, variants, stock tracking
- [ ] **Phase 4: Orders** — Unified inbox, offline POS, ShopeeFood + GrabFood webhook ingestion
- [ ] **Phase 5: CRM & Dashboard** — Customer profiles, dashboard overview
- [ ] **Phase 6: Finance & Payments** — P&L, cash ledger, payment recording, bank transfer auto-detect
- [ ] **Phase 7: AI Content Agent** — Caption/menu copy generation, cost controls
- [ ] **Phase 8: E-Invoice** — Optional compliance toggle, hóa đơn điện tử

## Phase Details

### Phase 1: Foundation
**Goal**: Establish the Supabase database schema with workspace-scoped RLS on every table, and the Flutter auth + workspace setup flow. Nothing else can be built safely without this.
**Depends on**: Nothing
**Requirements**: AUTH-01, AUTH-02, AUTH-03, AUTH-04, AUTH-05, AUTH-06, AUTH-07
**Success Criteria** (what must be TRUE):
  1. User can sign up, verify email, log in, and log out
  2. User can create a workspace and name it
  3. User can switch between two workspaces without seeing the other's data
  4. A CI query confirms every public table has `rowsecurity = true`
  5. No `service_role` key exists in any Flutter source file
**Plans**: TBD

Plans:
- [x] 01-01: Go+Postgres schema — all tables, indexes, RLS policies, CI gate (server/migrations/)
- [x] 01-02: Flutter auth flow — signup, email verify, login, session persistence (flutter/lib/core/auth/, flutter/lib/features/auth/)
- [x] 01-03: Workspace creation and switching UI (flutter/lib/features/workspace/)

### Phase 2: Offline Core
**Goal**: Scaffold the offline-first infrastructure: Drift local DB (mirroring Supabase schema), background SyncManager, central RealtimeManager, and connectivity awareness. Every subsequent feature will use these primitives.
**Depends on**: Phase 1
**Requirements**: SYNC-01, SYNC-02, SYNC-03, SYNC-04
**Success Criteria** (what must be TRUE):
  1. Putting device in airplane mode and creating a record in Drift does not crash the app
  2. Reconnecting causes the record to appear in Supabase (sync queue flushes)
  3. App displays an offline indicator when device has no connectivity
  4. Inventory conflict scenario: two local decrément deltas merge correctly via atomic RPC on sync
  5. Opening and closing the Orders screen 10× results in exactly 1 active Realtime channel
**Plans**: TBD

Plans:
- [ ] 02-01: Drift schema + DAOs (mirrors all Supabase tables)
- [ ] 02-02: SyncManager — offline queue, background flush, conflict handling
- [ ] 02-03: RealtimeManager — central channel registry, ref-counting, reconnect

### Phase 3: Products & Inventory
**Goal**: Give sellers a product catalog they can manage, with channel-specific availability and stock tracking. This is the prerequisite for all order-related phases.
**Depends on**: Phase 2
**Requirements**: PROD-01, PROD-02, PROD-03, PROD-04, PROD-05, PROD-06, PROD-07, INV-01, INV-02, INV-03, INV-04, INV-05
**Success Criteria** (what must be TRUE):
  1. User can create a product with variants and see it in the catalog
  2. User can mark a product as sold-out on ShopeeFood without affecting its offline availability
  3. Creating an order (even a test order) decrements the product's stock by the ordered quantity
  4. User receives a push notification when stock falls below the configured threshold
  5. User can manually adjust stock and the change syncs offline-first
**Plans**: TBD

Plans:
- [ ] 03-01: Product catalog — CRUD, variants, image upload, Drift + Supabase sync
- [ ] 03-02: Channel availability + pricing overrides
- [ ] 03-03: Inventory tracking — stock deduction trigger, low-stock alert, manual adjustment

### Phase 4: Orders
**Goal**: The core product: a unified real-time order inbox for offline/manual orders plus ShopeeFood and GrabFood. Sellers can manage the full order lifecycle, all offline-capable.
**Depends on**: Phase 3
**Requirements**: ORD-01, ORD-02, ORD-03, ORD-04, ORD-05, ORD-06, ORD-07, ORD-08, ORD-09, ORD-10, ORD-11
**Success Criteria** (what must be TRUE):
  1. Creating a manual order offline appears in the inbox immediately; syncs when online
  2. A new ShopeeFood order appears in the Flutter inbox within 3 seconds of platform webhook receipt
  3. Sending the same ShopeeFood webhook twice results in exactly one order row
  4. User can advance an order from "new" to "delivered" and see status update in real-time on another device
  5. User receives a push notification for every new incoming order
**Plans**: TBD

Plans:
- [ ] 04-01: Manual order creation — offline POS flow, client UUID, Drift sync
- [ ] 04-02: Order inbox UI — real-time list, status filters, search
- [ ] 04-03: Order detail + lifecycle (status transitions, cancel)
- [ ] 04-04: ShopeeFood webhook Edge Function — HMAC, normalise, upsert with idempotency
- [ ] 04-05: GrabFood webhook Edge Function — HMAC, normalise, upsert with idempotency
- [ ] 04-06: Push notifications (new order, status change)

### Phase 5: CRM & Dashboard
**Goal**: Auto-build customer profiles from order data and give sellers an at-a-glance business overview on the dashboard.
**Depends on**: Phase 4
**Requirements**: CRM-01, CRM-02, CRM-03, CRM-04, CRM-05, DASH-01, DASH-02, DASH-03
**Success Criteria** (what must be TRUE):
  1. Placing an order automatically creates or updates the customer's profile
  2. User can find a customer by phone number and see their full order history
  3. Dashboard shows today's order count, revenue, and active orders without manual refresh
  4. Low-stock products are visible on the dashboard
**Plans**: TBD

Plans:
- [ ] 05-01: Customer CRM — profile auto-creation, order history, notes, search
- [ ] 05-02: Dashboard — revenue summary, active orders, low-stock alerts (real-time)

### Phase 6: Finance & Payments
**Goal**: Full Vietnamese cash-basis accounting: P&L, cash ledger, receivables, tax summary, payment method tracking, and TPBank transfer auto-detect.
**Depends on**: Phase 5
**Requirements**: FIN-01, FIN-02, FIN-03, FIN-04, FIN-05, FIN-06, FIN-07, FIN-08, FIN-09, FIN-10, FIN-11, PAY-01, PAY-02, PAY-03, PAY-04
**Success Criteria** (what must be TRUE):
  1. Marking an order as delivered automatically creates a revenue record in the Finance module
  2. User can view a P&L report for the current month showing income, expenses, and net
  3. User can see a running cash ledger (sổ quỹ) for the current day
  4. TPBank transfer detection: a transfer with the correct reference code auto-matches to an order
  5. A transfer with ambiguous reference appears in the manual review queue, not auto-confirmed
  6. User can export a monthly P&L report as PDF
**Plans**: TBD

Plans:
- [ ] 06-01: Finance data model — transactions, categories, receivables (Drift + Supabase)
- [ ] 06-02: Income/expense recording UI + P&L report + cash ledger
- [ ] 06-03: Receivables (công nợ) — create, track, mark paid
- [ ] 06-04: Tax summary report for hộ kinh doanh + PDF export
- [ ] 06-05: Payment method recording (MoMo, ZaloPay, VNPAY, cash, bank)
- [ ] 06-06: TPBank transfer auto-detect Edge Function + matching logic + manual review queue

### Phase 7: AI Content Agent
**Goal**: Let sellers generate Vietnamese social media captions and menu copy via Claude, with strict per-workspace cost controls.
**Depends on**: Phase 3 (product data as source material)
**Requirements**: AI-01, AI-02, AI-03, AI-04, AI-05
**Success Criteria** (what must be TRUE):
  1. User can request a Vietnamese caption for a product and receive a response within 5 seconds
  2. User can edit the generated content and save it
  3. When a workspace exceeds its monthly AI call cap, the next call returns a clear error, not an expensive API call
  4. No prompt injection via product names/descriptions can cause the AI to return data from other workspaces
  5. Every AI call is logged to `ai_usage` with token count and workspace ID
**Plans**: TBD

Plans:
- [ ] 07-01: AI Edge Function proxy — Claude API, system prompt, input sanitisation, token logging
- [ ] 07-02: Content Agent UI — product selector, caption/description generator, edit + save
- [ ] 07-03: Per-workspace AI usage cap + enforcement

### Phase 8: E-Invoice (Optional Module)
**Goal**: Optional compliance toggle for sellers who need to issue hóa đơn điện tử per NĐ 123/2020/NĐ-CP.
**Depends on**: Phase 6 (Finance) + Phase 5 (CRM — buyer details)
**Requirements**: (v2 EINV-01 through EINV-05 promoted to implementation target)
**Success Criteria** (what must be TRUE):
  1. User can enable the e-invoice module via a toggle in workspace settings
  2. User can issue a hóa đơn điện tử for a completed order; invoice contains all NĐ 123/2020 required fields
  3. Attempting to issue an invoice with missing required fields is blocked by client-side validation
  4. User can cancel an issued invoice and issue a replacement (hóa đơn thay thế)
  5. Raw provider response including `ma_tra_cuu` is stored per invoice
**Plans**: TBD

Plans:
- [ ] 08-01: E-invoice data model + workspace toggle
- [ ] 08-02: E-invoice Edge Function — provider adapter (Viettel-S / MISA), field validation, submission
- [ ] 08-03: Invoice issuance UI + cancellation/replacement flow
- [ ] 08-04: Invoice lookup + reprint

## Progress

**Execution Order:** 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation | 3/3 | Complete | 2026-05-31 |
| 2. Offline Core | 0/3 | Not started | - |
| 3. Products & Inventory | 0/3 | Not started | - |
| 4. Orders | 0/6 | Not started | - |
| 5. CRM & Dashboard | 0/2 | Not started | - |
| 6. Finance & Payments | 0/6 | Not started | - |
| 7. AI Content Agent | 0/3 | Not started | - |
| 8. E-Invoice | 0/4 | Not started | - |
