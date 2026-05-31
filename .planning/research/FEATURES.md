# Feature Research

**Domain:** F&B all-in-one business management SaaS — Vietnamese market (hộ kinh doanh cá thể)
**Researched:** 2026-05-31
**Confidence:** HIGH

## Feature Landscape

### Orders

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Unified order inbox (all channels) | Sellers switch between 4–6 apps daily; consolidation is the #1 pain | HIGH | Table stakes in VN market |
| Order status lifecycle (new → confirmed → preparing → delivered) | Every POS/delivery app has this | MEDIUM | Must match per-platform states |
| Offline order creation (manual / POS) | Walk-in customers; no dependency on platform | MEDIUM | Requires offline-first sync |
| Order notifications (push) | Time-sensitive — food prep window | LOW | Critical for F&B |
| Order detail view + print receipt | Paper receipt still common in VN | LOW | Thermal printer via BT optional |
| Order search + filter by channel/date/status | Ops review | LOW | — |
| Bulk order actions (confirm/cancel multiple) | High-volume sellers (dinner rush) | MEDIUM | — |
| Order-level notes / special instructions | Customer allergy/customization notes | LOW | Must pass through from platforms |
| Estimated delivery time display | Customer expectation | LOW | Pulled from platform |

### Products & Inventory

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Product catalog with variants (size, topping) | F&B always has combos | MEDIUM | Table stakes |
| Channel-specific price override | ShopeeFood price ≠ direct price | MEDIUM | Per-product per-channel pricing |
| Product availability toggle (soldout per channel) | Items run out mid-service | LOW | Realtime push to platforms |
| Stock tracking (deduct on order) | Prevent overselling | MEDIUM | Critical for limited-batch items |
| Low-stock alert | Proactive restock | LOW | Push notification |
| Inventory adjustment (manual count correction) | Physical stock audits | LOW | With reason code |
| Ingredient-level inventory (recipe costing) | Advanced: deduct ingredients | HIGH | Differentiator — defer to v2 |
| Batch / expiry tracking | Food safety compliance | HIGH | v2 |

### Customer CRM

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Customer profile (name, phone, order history) | Loyalty + repeat business | MEDIUM | Table stakes |
| Customer search + filter | Look up regulars | LOW | — |
| Order-to-customer linking (auto from platform) | Platform orders carry customer data | LOW | — |
| Customer notes (preferences, allergies) | Personalization | LOW | — |
| Basic loyalty / visit count | Simple punch-card equivalent | MEDIUM | Differentiator at this tier |
| Customer segments (top spenders, inactive) | Marketing lists | MEDIUM | Differentiator |
| Messaging (Zalo/Messenger to customer) | Direct re-engagement | HIGH | v2 — separate integration scope |

### Finance / Accounting

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Revenue summary (daily/weekly/monthly) | Every seller tracks this | LOW | Table stakes |
| Income + expense recording | Full cash-basis bookkeeping | MEDIUM | Table stakes |
| Cash flow statement (sổ quỹ tiền mặt) | Standard VN small biz requirement | MEDIUM | Table stakes for compliance |
| P&L report (báo cáo kết quả kinh doanh) | Required for tax filing | MEDIUM | Table stakes |
| Payment method breakdown (cash/MoMo/bank/card) | Reconciliation | LOW | VN-specific |
| Bank transfer auto-detect + match | VN banks send SMS/webhook with ref | HIGH | Strong differentiator — saves hours |
| Debt / receivables tracking (công nợ) | Credit sales to regulars | MEDIUM | Table stakes for food sellers |
| Tax summary for hộ kinh doanh (khoán thuế) | Annual declaration | MEDIUM | Table stakes (compliance) |
| Export to Excel / PDF | Accountant handoff | LOW | — |
| Chart of accounts (full double-entry) | Enterprise accounting | HIGH | Anti-feature for this tier — overwhelms users |
| Payroll | Employee management | HIGH | Out of scope v1 |

### Content / Marketing

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| AI-generated social media captions | Most sellers can't write copy | MEDIUM | Differentiator — core AI feature |
| AI-generated menu descriptions | Improves platform CTR | MEDIUM | Differentiator |
| Promotion / discount creation | Platform promo management | MEDIUM | Table stakes for platform sellers |
| Content calendar | Scheduled posts | HIGH | v2 |
| Image editing / AI image gen | Visual assets | HIGH | v2 |

### AI Agents

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Sales Agent (order recommendations, upsell scripts) | AI-driven revenue | HIGH | Differentiator |
| Content Agent (caption, post, menu copy generation) | Time saver | MEDIUM | Differentiator |
| Finance Agent (explain reports, flag anomalies) | "What happened to revenue this week?" | HIGH | Differentiator |
| Voice input to AI | Hands-free in kitchen | HIGH | v2 |

### E-Invoice

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| E-invoice issuance (hóa đơn điện tử) | NĐ 123/2020 compliance | HIGH | Table stakes for compliance toggle |
| Invoice lookup + reprint | Customer request | LOW | — |
| Invoice cancellation / adjustment (hóa đơn thay thế) | Error correction | MEDIUM | Required by law |
| Invoice series management (ký hiệu hóa đơn) | Per-provider setup | MEDIUM | — |
| Tax authority submission | Digital reporting | HIGH | Depends on provider API |

### Integrations

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| ShopeeFood order sync | #1 delivery platform VN | HIGH | Table stakes |
| GrabFood order sync | #2 delivery platform VN | HIGH | Table stakes |
| TikTok Shop order sync | Fast-growing in VN | HIGH | Table stakes |
| Messenger order handling (manual/chatbot) | Common for home-based sellers | MEDIUM | Table stakes |
| Zalo OA order handling | VN-dominant messaging | MEDIUM | Table stakes |
| MoMo payment | Most popular e-wallet VN | MEDIUM | Table stakes |
| ZaloPay payment | #2 e-wallet VN | MEDIUM | Table stakes |
| VNPAY | Banking gateway VN | MEDIUM | Table stakes |
| TPBank / bank transfer auto-detect | Open banking webhook | HIGH | Differentiator |
| Bluetooth thermal printer | Receipt printing | MEDIUM | Nice-to-have v1 |

## Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Full double-entry accounting | Looks "professional" | Overwhelming for hộ kinh doanh; they use cash-basis | Cash-basis P&L + sổ quỹ |
| Real-time inventory for every ingredient | Restaurant-grade | Complexity/maintenance far exceeds value at this scale | Product-level stock only in v1 |
| Customer loyalty points engine | KiotViet has it | Engineering cost; sellers at this tier use manual punch cards | Simple visit count + CRM notes |
| Integrated live chat (full chatbot) | Automation appeal | High scope; Zalo/Meta APIs change frequently | Show order info in chat thread; full bot v2 |
| Multi-currency support | Seems global | VN food sellers use VND only; confusion risk | VND only |
| Multi-location / franchise | Growth path | Massive schema complexity; adds nothing for hộ kinh doanh | Single workspace = single location in v1 |

## Feature Dependencies

```
Multi-channel Orders
    └──requires──> Platform Webhook Ingestion (Edge Functions)
                       └──requires──> Product Catalog (to map platform SKUs)

Inventory Stock Tracking
    └──requires──> Product Catalog
    └──enhances──> Low-stock Alert

Finance P&L
    └──requires──> Income/Expense Recording
    └──enhances──> Revenue Summary (auto-populated)

Bank Transfer Auto-detect
    └──requires──> Finance module (to match and record)

E-Invoice
    └──requires──> Finance module (invoice = financial document)
    └──requires──> Customer CRM (buyer details on invoice)

AI Content Agent
    └──requires──> Product Catalog (source material for copy)

AI Finance Agent
    └──requires──> Finance module (data to analyze)
```

## MVP Definition

### Launch With (v1)

- [ ] Workspace setup + auth (onboarding < 5 min)
- [ ] Product catalog with variants + channel availability
- [ ] Order inbox: ShopeeFood + GrabFood + manual/offline orders
- [ ] Inventory stock tracking (product-level, not ingredient)
- [ ] Basic customer profiles (auto-created from orders)
- [ ] Revenue summary + income/expense recording + sổ quỹ
- [ ] P&L report (báo cáo kết quả kinh doanh)
- [ ] Tax summary for hộ kinh doanh
- [ ] MoMo + ZaloPay + VNPAY payment recording
- [ ] Bank transfer auto-detect (TPBank)
- [ ] AI Content Agent (captions + menu descriptions)
- [ ] Debt/receivables tracking (công nợ)

### Add After Validation (v1.x)

- [ ] TikTok Shop order sync — trigger: platform grows past GrabFood in active workspaces
- [ ] Messenger + Zalo OA order handling — trigger: > 30% workspaces report using chat channels
- [ ] E-invoice module (toggle) — trigger: compliance requests from users
- [ ] AI Sales Agent — trigger: v1 AI Content adoption > 60%
- [ ] Customer loyalty / visit count — trigger: CRM engagement data

### Future Consideration (v2+)

- [ ] AI Finance Agent — requires sufficient transaction history per workspace
- [ ] Ingredient-level inventory (recipe costing) — full kitchen management
- [ ] Content calendar — requires content creation habit formed
- [ ] Payroll — requires employee management module
- [ ] Multi-location / franchise support

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Multi-channel order inbox | HIGH | HIGH | P1 |
| Product catalog + variants | HIGH | MEDIUM | P1 |
| Revenue summary + P&L | HIGH | MEDIUM | P1 |
| Offline order creation | HIGH | MEDIUM | P1 |
| Inventory stock tracking | HIGH | MEDIUM | P1 |
| AI Content Agent | HIGH | MEDIUM | P1 |
| Bank transfer auto-detect | HIGH | HIGH | P1 |
| Customer CRM (basic) | MEDIUM | LOW | P1 |
| E-invoice | MEDIUM | HIGH | P2 |
| AI Sales Agent | MEDIUM | HIGH | P2 |
| TikTok Shop | MEDIUM | HIGH | P2 |
| Messenger/Zalo orders | MEDIUM | MEDIUM | P2 |
| Bluetooth printer | LOW | MEDIUM | P3 |

## Competitor Feature Analysis

| Feature | KiotViet | Sapo | GoSELL | Our Approach |
|---------|----------|------|--------|--------------|
| Multi-channel orders | Partial (offline-first POS) | Yes | Yes | Unified inbox, realtime |
| AI content | No | No | Limited | Full AI agent |
| Bank transfer auto-detect | No | No | No | Differentiator via open banking |
| E-invoice | Yes | Yes | Yes | Optional toggle |
| Offline-first mobile | POS app | Limited | Limited | Core architecture |
| Finance / P&L | Full | Partial | Partial | Full cash-basis |
| AI Finance Agent | No | No | No | Differentiator |

## Sources

- KiotViet, Sapo, GoSELL product pages + feature matrices (2025–2026)
- Toast POS F&B feature set (global reference)
- Nghị định 123/2020/NĐ-CP (e-invoice requirements)
- Vietnamese F&B seller community feedback (common pain points)

---
*Feature research for: RiMi — Vietnamese F&B all-in-one SaaS*
*Researched: 2026-05-31*
