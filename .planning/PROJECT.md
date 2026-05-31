# Project: RiMi

## Overview

**One-liner:** All-in-One business management app for Vietnamese food sellers — online and offline.

**Problem:** Food sellers (hộ kinh doanh cá thể) managing multiple sales channels (ShopeeFood, GrabFood, TikTok Shop, Messenger, Zalo, offline) have no unified tool. They manually reconcile orders, track inventory in spreadsheets, issue paper invoices, and have zero visibility into their finances.

**Solution:** RiMi unifies all channels into one workspace: multi-channel order management, product & inventory control, customer CRM, AI-powered content, full accounting + financial reports, and optional e-invoice compliance — all in a single Flutter app backed by Supabase.

**Target Users:**
- Primary: Hộ kinh doanh cá thể (individual household food businesses) selling food online + offline in Vietnam
- Near-term expansion: Small food stores (cửa hàng nhỏ)

## Core Value

**One sentence:** RiMi lets Vietnamese food sellers run their entire business from one app — orders from every channel, inventory, finances, and customer relationships — so they spend time cooking, not reconciling.

## Modules

| Module | Description |
|--------|-------------|
| Workspace > Dashboard | Real-time business overview: revenue, orders, low-stock alerts |
| Workspace > Orders | Multi-channel order inbox (ShopeeFood, GrabFood, TikTok Shop, Messenger, Zalo, offline POS) |
| Workspace > Products | Product catalog with variants, pricing, channel-specific availability |
| Workspace > Inventory | Stock tracking, low-stock alerts, offline-first sync |
| Workspace > Customer CRM | Customer profiles, order history, loyalty |
| Content (AI-supported) | Social media post generation, menu copy, promotion content |
| Finance | Full accounting: income/expense tracking, P&L, cash flow, báo cáo tài chính |
| AI Team | Multiple agents: Sales Agent, Content Agent, Finance Agent |
| E-Invoice (optional) | Hóa đơn điện tử compliant with Nghị định 123/2020/NĐ-CP (toggle on/off) |

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Backend | Go + Postgres (self-hosted); chi router; golang-migrate; pgx |
| Frontend | Flutter (iOS + Android) |
| Offline sync | Offline-first with client-generated UUIDs; Drift local DB (Phase 2) |
| Realtime | TBD — WebSocket/SSE (Phase 4); Postgres LISTEN/NOTIFY or dedicated service |
| AI | Claude API via Supabase Edge Functions or Go proxy (decided in Phase 7) |

## Key Integrations

| Integration | Type |
|------------|------|
| ShopeeFood | Order webhook + menu sync |
| GrabFood | Order webhook + menu sync |
| TikTok Shop | Order webhook + product sync |
| Messenger | Chat orders via Meta API |
| Zalo | Chat orders via Zalo OA API |
| TPBank | Bank transfer auto-detect (webhook / polling) |
| MoMo | Payment gateway |
| ZaloPay | Payment gateway |
| VNPAY | Payment gateway |
| E-Invoice provider | Viettel-S / MISA or equivalent |

## Architecture Constraints

- **Workspace-scoped RLS** from day one — every table has `workspace_id`
- **Client-generated UUIDs** for all entities (offline-first)
- **Realtime** on `orders` and `inventory_items` tables
- **TypeScript** for all Edge Functions
- **Offline-first** — orders and inventory mutations work without network, sync on reconnect

## Vietnamese Compliance

| Requirement | Detail |
|------------|--------|
| E-Invoice | Nghị định 123/2020/NĐ-CP, Thông tư 78/2021/TT-BTC — optional toggle per workspace |
| Tax | Hỗ trợ báo cáo thuế hộ kinh doanh (lump-sum tax / khoán thuế) |
| Financial reports | Báo cáo kết quả kinh doanh (P&L), sổ quỹ tiền mặt, công nợ |
| Payment | VND as sole currency; local payment methods (MoMo, ZaloPay, VNPAY, bank transfer) |

## Requirements

### Active (Hypotheses — ship to validate)

- Users will manage all channels from one inbox rather than switching between apps
- Offline-first is critical — many food stalls have intermittent connectivity
- AI content generation saves meaningful time for non-tech-savvy sellers
- Finance module is used daily (not just at month-end)
- E-invoice toggle is essential for compliance-forward users

### Validated

*(None yet — ship to validate)*

## Key Decisions

| # | Decision | Rationale | Date |
|---|----------|-----------|------|
| 1 | Go + Postgres as backend (self-hosted) | Best fit for per-request Postgres RLS via SET LOCAL, webhook/offline-sync surface, and ops simplicity. Supersedes the initial Supabase decision. See docs/contracts/README.md ADR-002. | 2026-05-31 |
| 2 | Flutter for mobile | Cross-platform iOS + Android; strong offline support; single codebase | 2026-05-31 |
| 3 | Client-generated UUIDs | Required for offline-first — creates before sync | 2026-05-31 |
| 4 | Workspace-scoped RLS + app-layer guard | Defense-in-depth tenancy: Postgres RLS via SET LOCAL GUC + repository-layer scoping. Two DB roles: rimi_migrator (owner) + rimi_app (NOSUPERUSER NOBYPASSRLS). See docs/security/phase-1-auth-workspace.md TENANCY rules. | 2026-05-31 |
| 5 | All-tables-upfront schema | Full 8-phase schema created in Phase 1 with workspace_id + RLS on every table; later phases add columns/logic via ALTER TABLE | 2026-05-31 |
| 6 | E-invoice as optional module | Not all sellers need compliance immediately; reduces onboarding friction | 2026-05-31 |
| 7 | Active workspace as signed JWT claim | Workspace_id carried in RS256 access token, re-issued at /workspaces/{id}/switch (sole membership gate). NOT a client header. See docs/contracts/README.md ADR-001. | 2026-05-31 |

## Constraints

- VND currency only (for v1)
- Vietnam market only (for v1)
- Mobile-first (Flutter); no web dashboard in v1
- Self-hosted Go+Postgres; no vendor BaaS lock-in
- No multi-currency, no multi-language (Vietnamese UI only in v1)

## Success Metrics

| Metric | Target |
|--------|--------|
| Time to first order managed | < 5 minutes after signup |
| Channel integrations connected per workspace | ≥ 2 on average |
| Daily active use | Finance or Orders module opened daily |
| Offline order creation | Works with 0% connectivity |
| RLS isolation | Zero cross-workspace data leaks |

---
*Last updated: 2026-05-31 after initialization*
