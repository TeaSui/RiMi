# Codebase Structure

**Analysis Date:** 2026-05-31

## Directory Layout

```
RiMi/
├── flutter/                # Flutter application (primary codebase)
│   ├── lib/                # Dart source code
│   │   ├── main.dart       # Entry point — runApp(RiMiApp())
│   │   ├── app.dart        # RiMiApp, RootShell, AppNav controller
│   │   ├── core/           # Cross-cutting utilities (no UI)
│   │   ├── data/           # Mock models + ChangeNotifier stores
│   │   ├── features/       # One sub-directory per screen domain
│   │   │   ├── ai/
│   │   │   ├── content/
│   │   │   ├── customers/
│   │   │   ├── finance/
│   │   │   ├── home/
│   │   │   ├── orders/
│   │   │   └── products/
│   │   ├── theme/          # Design tokens, typography, MaterialTheme
│   │   └── widgets/        # Shared reusable widgets
│   ├── android/            # Android platform host
│   ├── ios/                # iOS platform host
│   ├── macos/              # macOS platform host
│   ├── linux/              # Linux platform host
│   ├── windows/            # Windows platform host
│   ├── web/                # Web platform host
│   ├── test/               # Flutter widget tests
│   ├── pubspec.yaml        # Package manifest
│   └── analysis_options.yaml  # Dart linter config
├── design/                 # Design reference assets
│   ├── screens/            # PNG screen exports (01-home.png … 16-ai-tablet.png)
│   ├── export/             # Additional exported assets
│   └── Screen Reference.html  # Design overview page
├── docs/
│   └── plans/              # Planning documents
└── .planning/
    └── codebase/           # Codebase analysis documents (this directory)
```

## Directory Purposes

**`flutter/lib/`:**
- Purpose: All Dart/Flutter application source
- Contains: Entry point, app shell, feature pages, widgets, theme, data
- Key files: `main.dart` (entry), `app.dart` (root shell + navigation)

**`flutter/lib/core/`:**
- Purpose: Stateless utilities with no widget dependencies beyond Flutter core
- Contains: `responsive.dart` (breakpoint helper), `app_icons.dart` (icon name map)
- Key files:
  - `flutter/lib/core/responsive.dart` — `isTablet(context)` and `screenW(context)`
  - `flutter/lib/core/app_icons.dart` — `AppIcons.of(name)`, `RmIcon` widget

**`flutter/lib/data/`:**
- Purpose: Application data layer — all models, stores, and style maps
- Contains: `mock_data.dart` (single file holds everything)
- Key files:
  - `flutter/lib/data/mock_data.dart` — `Order`, `Product`, `Customer`, `Bot` models; `OrderStore`, `ProductStore`, `CustomerStore` singletons; `statusStyle`, `channelColor`, `tiers` maps; `bots` list; `finance` map

**`flutter/lib/features/<domain>/`:**
- Purpose: One Dart file per screen domain; contains both mobile and tablet layouts plus all in-feature sub-widgets
- Key files:
  - `flutter/lib/features/home/home_page.dart` — dashboard: revenue hero, quick actions, active orders, top products
  - `flutter/lib/features/orders/orders_page.dart` — order list with status tabs + channel filter; `OrderDetailPage`
  - `flutter/lib/features/products/products_page.dart` — menu/stock list with category filter; add-dish composer
  - `flutter/lib/features/content/content_page.dart` — social-post composer with platform picker
  - `flutter/lib/features/finance/finance_page.dart` — bar chart, spend breakdown, period toggle
  - `flutter/lib/features/customers/customers_page.dart` — CRM list with tier filter; customer detail; add-customer composer; `CustomerDetail`
  - `flutter/lib/features/ai/ai_page.dart` — AI Team roster page (`AiTeamPage`); chat screen (`AiChatPage`); scripted bot responses

**`flutter/lib/theme/`:**
- Purpose: All design-token and theme definitions
- Contains: `tokens.dart` (RM colors, RMType typography, vnd formatter), `app_theme.dart` (MaterialTheme build, rmToast)
- Key files:
  - `flutter/lib/theme/tokens.dart` — `RM` color constants, `RMType` text style factory, `vnd(n)` currency formatter
  - `flutter/lib/theme/app_theme.dart` — `AppTheme.light` ThemeData, `rmToast(context, message)` helper

**`flutter/lib/widgets/`:**
- Purpose: Shared, brand-consistent UI primitives used across multiple features
- Contains: `primitives.dart` (structural/display atoms), `forms.dart` (inputs and sheet chrome), `navigation.dart` (nav bar, rail, AI orb)
- Key files:
  - `flutter/lib/widgets/primitives.dart` — `SoftCard`, `Avatar`, `FoodSlot`, `BotIconView`, `StatusDot`, `RiMiMark`, `SectionHead`
  - `flutter/lib/widgets/forms.dart` — `PillChip`, `RmToggle`, `RmTextField`, `SheetHeader`, `SheetSubmit`
  - `flutter/lib/widgets/navigation.dart` — `RiMiBottomNav`, `TabletRail`, `DraggableAiOrb`

**`design/screens/`:**
- Purpose: PNG reference images for all 16 screens (mobile + tablet variants)
- Contents: `01-home.png` through `16-ai-tablet.png` plus `INDEX.md`
- Committed: Yes (reference assets)

## Key File Locations

**Entry Points:**
- `flutter/lib/main.dart` — Flutter app entry (`runApp`)
- `flutter/lib/app.dart` — `RiMiApp`, `RootShell`, `AppNav`

**Configuration:**
- `flutter/pubspec.yaml` — Dependencies (`google_fonts ^6.2.1`, `cupertino_icons ^1.0.8`), SDK constraint (`^3.8.0`)
- `flutter/analysis_options.yaml` — Dart linter rules
- `.env*` — Not present (no backend; no secrets required)

**Core Logic:**
- `flutter/lib/data/mock_data.dart` — All models, stores, and static data
- `flutter/lib/app.dart` — Navigation and app shell

**Theme / Tokens:**
- `flutter/lib/theme/tokens.dart` — Design token constants
- `flutter/lib/theme/app_theme.dart` — MaterialTheme and toast utility

**Testing:**
- `flutter/test/widget_test.dart` — Placeholder widget test (boilerplate only; references `MyApp` which does not exist — test is broken)

**Design Reference:**
- `design/screens/` — Annotated PNGs for all screens
- `design/Screen Reference.html` — HTML overview

## Naming Conventions

**Files:**
- `snake_case.dart` for all Dart source files (e.g., `home_page.dart`, `mock_data.dart`, `app_theme.dart`)
- `<domain>_page.dart` for feature screen files

**Directories:**
- `snake_case` for all directories
- Singular names for feature directories (`home`, `orders`, `finance`) — not plural
- Plural for shared-collection directories (`widgets`, `features`)

**Classes:**
- `PascalCase` for all Dart classes
- `*Mobile` / `*Tablet` suffix pattern for dual-layout widget pairs (e.g., `HomeMobile`, `HomeTablet`)
- `*Store` suffix for `ChangeNotifier` state classes (e.g., `OrderStore`)
- `*Page` suffix for full-screen navigated pages (e.g., `OrderDetailPage`, `AiTeamPage`, `CustomersPage`)
- Private widget classes within a file are prefixed with `_` (e.g., `_RevenueHero`, `_QuickActions`)
- Composer show-functions: `showAdd<Entity>Composer(context)` pattern

**Constants / Token Classes:**
- `abstract final class` with `static const` fields: `RM` (colors), `RMType` (typography), `AppIcons` (icons), `AppNav` (navigation), `AppTheme` (theme)

**Special Patterns:**
- `isTablet(context)` — breakpoint check before choosing Mobile vs Tablet widget
- `Store.instance` — singleton access pattern for all state stores

## Where to Add New Code

**New feature screen (e.g., "Reservations"):**
- Create: `flutter/lib/features/reservations/reservations_page.dart`
- Export two widgets: `ReservationsMobile` and `ReservationsTablet`
- Add model + store to: `flutter/lib/data/mock_data.dart`
- Register in `RootShell`: add to `_mobile` and `_tablet` lists in `flutter/lib/app.dart`
- Add nav tab to `navTabs` in `flutter/lib/widgets/navigation.dart`

**New shared widget:**
- If it is structural/display: add to `flutter/lib/widgets/primitives.dart`
- If it is a form input or sheet component: add to `flutter/lib/widgets/forms.dart`
- If it is a navigation component: add to `flutter/lib/widgets/navigation.dart`

**New design token (color, typography variant):**
- Add `static const` field to `RM` class in `flutter/lib/theme/tokens.dart`

**New icon mapping:**
- Add entry to `_map` in `AppIcons` in `flutter/lib/core/app_icons.dart`

**New model or data store:**
- Add model class to `flutter/lib/data/mock_data.dart` (Models section)
- Add `ChangeNotifier` singleton class to `flutter/lib/data/mock_data.dart` (Stores section)

**New navigated route (push, not tab):**
- Define the page widget in the relevant feature file (e.g., `flutter/lib/features/orders/orders_page.dart`)
- Add a convenience method to `AppNav` in `flutter/lib/app.dart` if it is called from multiple places (e.g., `AppNav.openChat(bot)`)

**New bottom-sheet composer:**
- Add `_<Entity>Composer` StatefulWidget + `show<Entity>Composer(context)` function inside the feature's `*_page.dart` file
- Call `Store.instance.add(...)` on submit

**Utilities (breakpoint helpers, formatters):**
- Breakpoint / layout: `flutter/lib/core/responsive.dart`
- Currency / formatting: `flutter/lib/theme/tokens.dart` (alongside `vnd()`)

## Special Directories

**`flutter/build/`:**
- Purpose: Compiled build artifacts
- Source: Generated by `flutter build`
- Committed: No (in `.gitignore`)

**`flutter/.dart_tool/`:**
- Purpose: Dart tooling cache
- Source: Auto-generated
- Committed: No

**`flutter/ios/Pods/`:**
- Purpose: CocoaPods dependency cache
- Source: Auto-generated by `pod install`
- Committed: No

**`design/screens/`:**
- Purpose: Authoritative screen reference images — 16 PNGs covering all mobile and tablet layouts
- Source: Exported from Figma/design tool
- Committed: Yes (source of truth for visual target)

**`.planning/codebase/`:**
- Purpose: Codebase analysis documents consumed by planning and execution commands
- Source: Written by `codebase-mapper` agent
- Committed: Yes (intended as persistent project knowledge)

---

*Structure analysis: 2026-05-31*
*Update when directory structure changes*
