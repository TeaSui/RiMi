# RiMi — Screen Reference Set

Canonical design screenshots for build comparison. Each image is a **1:1 native-resolution** render of the approved design (no device bezel, no prototype chrome) so you can diff it directly against the running Flutter screen.

- **Mobile** frames are `390 × 844` (iPhone logical px).
- **Tablet** frames are `1112 × 834` (iPad landscape logical px).
- Source of truth: `RiMi Prototype.html` / `RiMi Design System.html`.

## Mobile

| # | Screenshot | Flutter screen | Route |
|---|---|---|---|
| 01 | `01-home.png` | `features/home/home_screen.dart` | `/home` |
| 02 | `02-orders.png` | `features/orders/orders_screen.dart` | `/orders` |
| 03 | `03-order-detail.png` | `features/orders/orders_screen.dart` (detail) | `/orders` → detail |
| 04 | `04-products.png` | `features/products/products_screen.dart` | `/products` |
| 05 | `05-content.png` | `features/customers/content_screen.dart` | `/content` |
| 06 | `06-finance.png` | `features/finance/finance_screen.dart` | `/finance` |
| 07 | `07-customers.png` | `features/customers/customers_screen.dart` | `/customers` |
| 08 | `08-ai-team.png` | `features/ai_team/ai_team_screen.dart` | `/ai-team` |
| 09 | `09-ai-chat.png` | `features/ai_team/ai_chat_screen.dart` | `/ai-team/chat/:botId` |

## Tablet (iPad · landscape)

| # | Screenshot | Flutter screen |
|---|---|---|
| 10 | `10-home-tablet.png` | `features/home/home_screen.dart` (wide layout) |
| 11 | `11-orders-tablet.png` | `features/orders/orders_screen.dart` (split-view) |
| 12 | `12-products-tablet.png` | `features/products/products_screen.dart` (grid) |
| 13 | `13-content-tablet.png` | `features/customers/content_screen.dart` (studio) |
| 14 | `14-finance-tablet.png` | `features/finance/finance_screen.dart` (reports) |
| 15 | `15-customers-tablet.png` | `features/customers/customers_screen.dart` |
| 16 | `16-ai-tablet.png` | `features/ai_team/ai_team_screen.dart` (team + chat) |

> The `auth_screen.dart` has no design reference — it is a functional gate, not part of the design set.
