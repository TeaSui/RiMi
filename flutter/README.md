# RiMi — Flutter UI

A faithful Flutter implementation of the approved RiMi designs (mobile **and** tablet),
built straight from `RiMi Prototype.html` / `RiMi Design System.html`.

- **Self-contained & runnable** — in-file mock data, no backend, no auth gate. Launches
  straight into the bottom-nav shell.
- **Responsive** — every screen renders a phone layout (< 700 dp wide) or an iPad layout
  (≥ 700 dp). Rotate / resize to switch.
- **Working interactions** — tab switching, channel/status/category/tier filters, search,
  order status advance, availability toggles, the New-order / Add-dish / Add-customer
  composers, period switching on Finance, platform selection on Content, and the
  draggable AI orb.

## Run it

The folder ships `lib/` + `pubspec.yaml` only. Generate the platform scaffolding once:

```bash
cd mobile            # wherever you drop this folder
flutter create --platforms=android,ios,web .
flutter pub get
flutter run
```

Requires Flutter (Dart SDK ≥ 3.8). Fonts (Bricolage Grotesque + Be Vietnam Pro) are
fetched at runtime via `google_fonts`.

## Structure

```
lib/
  main.dart                  app entry
  app.dart                   RiMiApp + RootShell (responsive nav) + AppNav controller
  theme/
    tokens.dart              RM colours, type scale (RMType), vnd() formatter
    app_theme.dart           ThemeData + rmToast()
  core/
    app_icons.dart           semantic icon name → Material icon (RmIcon)
    responsive.dart          isTablet() breakpoint
  data/
    mock_data.dart           models, ChangeNotifier stores, style maps, seed data
  widgets/
    primitives.dart          RiMiMark, Avatar, FoodSlot, BotIconView, SoftCard, SectionHead, StatusDot
    navigation.dart          RiMiBottomNav, TabletRail, DraggableAiOrb
    forms.dart               PillChip, RmToggle, RmTextField, SheetHeader, SheetSubmit
  features/
    home/home_page.dart      HomeMobile / HomeTablet
    orders/orders_page.dart  OrdersMobile / OrdersTablet / OrderDetailPage / composer
    products/products_page.dart   ProductsMobile / ProductsTablet / add-dish
    content/content_page.dart     ContentMobile / ContentTablet
    finance/finance_page.dart     FinanceMobile / FinanceTablet (+ BarChart)
    customers/customers_page.dart CustomersPage (+ split-view, add-customer)
    ai/ai_page.dart          AiTeamPage / AiChatPage (+ tablet split)
```

## Screen ↔ design reference

Compare each screen against the matching file in the **screen reference set**
(`design/screens/…` in the design workspace):

| Reference | Flutter |
|---|---|
| `01-home` / `10-home-tablet` | `features/home/home_page.dart` |
| `02-orders` / `11-orders-tablet` | `features/orders/orders_page.dart` |
| `03-order-detail` | `OrderDetailPage` (orders_page.dart) |
| `04-products` / `12-products-tablet` | `features/products/products_page.dart` |
| `05-content` / `13-content-tablet` | `features/content/content_page.dart` |
| `06-finance` / `14-finance-tablet` | `features/finance/finance_page.dart` |
| `07-customers` / `15-customers-tablet` | `features/customers/customers_page.dart` |
| `08-ai-team` / `16-ai-tablet` | `AiTeamPage` (ai_page.dart) |
| `09-ai-chat` | `AiChatPage` (ai_page.dart) |

## Deliberate adaptations (design → Flutter)

- **Icons** — the design's custom 24×24 stroke set is mapped to the nearest Material icon
  (`core/app_icons.dart`) so there's no SVG asset pipeline. Swap in real assets later if
  pixel-exact icons are required.
- **Status bar** — the web mocks draw a faux iOS status bar (9:41). The Flutter app uses
  the real device status bar via `SafeArea`, so that strip is intentionally absent.
- **Data** — all content is seeded in `data/mock_data.dart`. Swap the `ChangeNotifier`
  stores for your real data source; the widgets read them through `ListenableBuilder`.
