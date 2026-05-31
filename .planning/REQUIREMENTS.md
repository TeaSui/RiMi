# Requirements: RiMi

**Defined:** 2026-05-31
**Core Value:** RiMi lets Vietnamese food sellers run their entire business from one app — orders from every channel, inventory, finances, and customer relationships — so they spend time cooking, not reconciling.

## v1 Requirements

### Authentication & Workspace (AUTH)

- [ ] **AUTH-01**: User can sign up with email and password
- [ ] **AUTH-02**: User receives email verification after signup
- [ ] **AUTH-03**: User can reset password via email link
- [ ] **AUTH-04**: User session persists across app restarts
- [ ] **AUTH-05**: User can create a new workspace (business profile) after signup
- [ ] **AUTH-06**: User can switch between workspaces they belong to
- [ ] **AUTH-07**: Workspace data is fully isolated from other workspaces (RLS)

### Products & Catalog (PROD)

- [ ] **PROD-01**: User can create a product with name, description, price, and category
- [ ] **PROD-02**: User can add variants to a product (e.g., size: S/M/L, topping: extra/no)
- [ ] **PROD-03**: User can set a channel-specific price override per product per channel
- [ ] **PROD-04**: User can toggle a product's availability per channel (available / sold-out)
- [ ] **PROD-05**: User can upload a product image
- [ ] **PROD-06**: User can edit and delete products
- [ ] **PROD-07**: User can search and filter products by category

### Inventory (INV)

- [ ] **INV-01**: System tracks stock quantity for each product (product-level, not ingredient-level)
- [ ] **INV-02**: Stock is automatically decremented when an order is confirmed
- [ ] **INV-03**: User receives a push notification when a product falls below a configurable low-stock threshold
- [ ] **INV-04**: User can manually adjust stock quantity with a reason code (restock, damage, audit)
- [ ] **INV-05**: User can view current stock levels for all products in a list

### Orders (ORD)

- [ ] **ORD-01**: User can create a manual (offline/walk-in) order with products and quantities
- [ ] **ORD-02**: Manual orders are created offline and sync when connectivity is restored
- [ ] **ORD-03**: Orders from ShopeeFood appear automatically in the unified inbox
- [ ] **ORD-04**: Orders from GrabFood appear automatically in the unified inbox
- [ ] **ORD-05**: User sees a push notification for each new incoming order
- [ ] **ORD-06**: User can view order details: items, quantities, customer info, channel, notes
- [ ] **ORD-07**: User can advance an order through status lifecycle: new → confirmed → preparing → ready → delivered
- [ ] **ORD-08**: User can cancel an order with a reason
- [ ] **ORD-09**: User can search and filter orders by channel, date range, and status
- [ ] **ORD-10**: User can view the unified order inbox in real-time (live updates without manual refresh)
- [ ] **ORD-11**: Platform order IDs are deduplicated (same order never appears twice despite webhook retries)

### Customer CRM (CRM)

- [ ] **CRM-01**: System automatically creates a customer profile when an order is placed (name + phone from platform data)
- [ ] **CRM-02**: User can view a customer's full order history
- [ ] **CRM-03**: User can add notes to a customer profile (preferences, allergies)
- [ ] **CRM-04**: User can search customers by name or phone number
- [ ] **CRM-05**: User can see a customer's total spend and order count

### Finance (FIN)

- [ ] **FIN-01**: System automatically creates a revenue record when an order is marked delivered
- [ ] **FIN-02**: User can manually record an income entry (amount, category, note, date)
- [ ] **FIN-03**: User can manually record an expense entry (amount, category, note, date)
- [ ] **FIN-04**: User can view a daily revenue summary on the dashboard
- [ ] **FIN-05**: User can view a P&L report (báo cáo kết quả kinh doanh) for a selected date range
- [ ] **FIN-06**: User can view a cash ledger (sổ quỹ tiền mặt) showing running balance
- [ ] **FIN-07**: User can record a receivable (công nợ phải thu) — credit sale to a customer
- [ ] **FIN-08**: User can mark a receivable as paid
- [ ] **FIN-09**: User can view a tax summary report for hộ kinh doanh (income breakdown for khoán thuế declaration)
- [ ] **FIN-10**: User can record which payment method was used for each transaction (cash, MoMo, ZaloPay, VNPAY, bank transfer)
- [ ] **FIN-11**: User can export financial reports to PDF

### Payments (PAY)

- [ ] **PAY-01**: System can detect incoming bank transfers from TPBank and display them as "unmatched transfers"
- [ ] **PAY-02**: User can manually match an unmatched bank transfer to an order or income record
- [ ] **PAY-03**: System auto-matches a bank transfer to an order when the payment reference matches the order's unique code
- [ ] **PAY-04**: User can record a MoMo, ZaloPay, or VNPAY payment confirmation against an order

### Dashboard (DASH)

- [ ] **DASH-01**: User can view today's order count and revenue at a glance on the dashboard
- [ ] **DASH-02**: User can see active orders requiring attention (new/confirmed status) on the dashboard
- [ ] **DASH-03**: User can see low-stock alerts on the dashboard

### AI Content Agent (AI)

- [ ] **AI-01**: User can request AI-generated social media captions for a product or promotion
- [ ] **AI-02**: User can request AI-generated menu descriptions for a product
- [ ] **AI-03**: AI responses are generated in Vietnamese
- [ ] **AI-04**: User can edit and save generated content before posting
- [ ] **AI-05**: Per-workspace AI usage is capped to prevent runaway costs

### Offline & Sync (SYNC)

- [ ] **SYNC-01**: User can create orders when the device has no internet connectivity
- [ ] **SYNC-02**: Offline-created orders automatically sync to the server when connectivity is restored
- [ ] **SYNC-03**: User sees a clear indicator when the app is in offline mode
- [ ] **SYNC-04**: Inventory adjustments made offline sync without conflicting with concurrent server-side changes (atomic reconciliation)

## v2 Requirements

### Extended Channels

- **CHAN-01**: TikTok Shop orders appear in the unified inbox
- **CHAN-02**: Messenger chat orders can be captured and added to the order inbox
- **CHAN-03**: Zalo OA chat orders can be captured and added to the order inbox

### E-Invoice (optional toggle)

- **EINV-01**: User can enable the e-invoice module per workspace (optional compliance toggle)
- **EINV-02**: User can issue a hóa đơn điện tử for an order (compliant with NĐ 123/2020)
- **EINV-03**: User can cancel and replace an issued invoice (hóa đơn thay thế / hóa đơn điều chỉnh)
- **EINV-04**: User can look up and reprint a previously issued invoice
- **EINV-05**: System validates all required NĐ 123/2020 fields before submission

### AI Agents (extended)

- **AIEXT-01**: AI Sales Agent can suggest upsell/cross-sell recommendations for active orders
- **AIEXT-02**: AI Finance Agent can explain revenue anomalies in plain Vietnamese

### CRM Extended

- **CRMX-01**: User can segment customers (top spenders, inactive > 30 days)
- **CRMX-02**: System tracks customer visit count and flags loyalty milestones

### Content

- **CONT-01**: User can schedule content posts to a calendar
- **CONT-02**: User can generate AI-assisted promotion campaign copy

## Out of Scope

| Feature | Reason |
|---------|--------|
| Full double-entry accounting (debit/credit ledger) | Overwhelming for hộ kinh doanh; cash-basis P&L is sufficient |
| Ingredient-level inventory / recipe costing | High complexity; exceeds value for this tier in v1 |
| Payroll / employee management | Out of scope for hộ kinh doanh primary persona |
| Multi-location / franchise support | Schema complexity; single location per workspace in v1 |
| Multi-currency | VND only; no cross-border sellers in target market |
| Multi-language UI | Vietnamese only in v1 |
| Web dashboard / desktop app | Mobile-first; no web in v1 |
| Integrated live chatbot (full automation) | High scope; Zalo/Meta APIs change frequently; defer to v2 |
| Customer loyalty points engine | Manual punch-card equivalent sufficient; CRM notes cover this |
| Video content generation | Storage/bandwidth costs; defer to v2+ |

## Traceability

*Populated during roadmap creation.*

| Requirement | Phase | Status |
|-------------|-------|--------|
| AUTH-01 | Phase 1 | Pending |
| AUTH-02 | Phase 1 | Pending |
| AUTH-03 | Phase 1 | Pending |
| AUTH-04 | Phase 1 | Pending |
| AUTH-05 | Phase 1 | Pending |
| AUTH-06 | Phase 1 | Pending |
| AUTH-07 | Phase 1 | Pending |
| SYNC-01 | Phase 2 | Pending |
| SYNC-02 | Phase 2 | Pending |
| SYNC-03 | Phase 2 | Pending |
| SYNC-04 | Phase 2 | Pending |
| PROD-01 | Phase 3 | Pending |
| PROD-02 | Phase 3 | Pending |
| PROD-03 | Phase 3 | Pending |
| PROD-04 | Phase 3 | Pending |
| PROD-05 | Phase 3 | Pending |
| PROD-06 | Phase 3 | Pending |
| PROD-07 | Phase 3 | Pending |
| INV-01 | Phase 3 | Pending |
| INV-02 | Phase 3 | Pending |
| INV-03 | Phase 3 | Pending |
| INV-04 | Phase 3 | Pending |
| INV-05 | Phase 3 | Pending |
| ORD-01 | Phase 4 | Pending |
| ORD-02 | Phase 4 | Pending |
| ORD-03 | Phase 4 | Pending |
| ORD-04 | Phase 4 | Pending |
| ORD-05 | Phase 4 | Pending |
| ORD-06 | Phase 4 | Pending |
| ORD-07 | Phase 4 | Pending |
| ORD-08 | Phase 4 | Pending |
| ORD-09 | Phase 4 | Pending |
| ORD-10 | Phase 4 | Pending |
| ORD-11 | Phase 4 | Pending |
| CRM-01 | Phase 5 | Pending |
| CRM-02 | Phase 5 | Pending |
| CRM-03 | Phase 5 | Pending |
| CRM-04 | Phase 5 | Pending |
| CRM-05 | Phase 5 | Pending |
| DASH-01 | Phase 5 | Pending |
| DASH-02 | Phase 5 | Pending |
| DASH-03 | Phase 5 | Pending |
| FIN-01 | Phase 6 | Pending |
| FIN-02 | Phase 6 | Pending |
| FIN-03 | Phase 6 | Pending |
| FIN-04 | Phase 6 | Pending |
| FIN-05 | Phase 6 | Pending |
| FIN-06 | Phase 6 | Pending |
| FIN-07 | Phase 6 | Pending |
| FIN-08 | Phase 6 | Pending |
| FIN-09 | Phase 6 | Pending |
| FIN-10 | Phase 6 | Pending |
| FIN-11 | Phase 6 | Pending |
| PAY-01 | Phase 6 | Pending |
| PAY-02 | Phase 6 | Pending |
| PAY-03 | Phase 6 | Pending |
| PAY-04 | Phase 6 | Pending |
| AI-01 | Phase 7 | Pending |
| AI-02 | Phase 7 | Pending |
| AI-03 | Phase 7 | Pending |
| AI-04 | Phase 7 | Pending |
| AI-05 | Phase 7 | Pending |

**Coverage:**
- v1 requirements: 58 total
- Mapped to phases: 58
- Unmapped: 0 ✓

---
*Requirements defined: 2026-05-31*
*Last updated: 2026-05-31 after initial definition*
