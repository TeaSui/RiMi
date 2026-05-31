# Architecture

**Analysis Date:** 2026-05-31

## Pattern Overview

**Overall:** Flutter Mobile/Tablet UI Prototype — Feature-sliced, single-tier, in-memory state

**Key Characteristics:**
- Single-process Flutter app (no backend; all data is mock/in-memory)
- Feature-sliced directory structure: each screen domain owns its own `*_page.dart`
- Responsive dual-layout: every feature exports a `*Mobile` and a `*Tablet` widget; the root shell picks the right one based on a 700pt breakpoint
- Navigation is centralised through a static `AppNav` class (`flutter/lib/app.dart`) — tabs driven by `ValueNotifier<int>`, stack-pushed routes via a `GlobalKey<NavigatorState>`
- State managed by `ChangeNotifier` singletons (one store per domain: `OrderStore`, `ProductStore`, `CustomerStore`) living in `flutter/lib/data/mock_data.dart`

## Layers

**Presentation Layer (feature pages):**
- Purpose: Render UI, handle user interactions, compose domain widgets
- Contains: `*Mobile` and `*Tablet` StatelessWidget / StatefulWidget pairs, in-page sub-widgets (private `_Foo` classes), composer bottom-sheets
- Location: `flutter/lib/features/<domain>/<domain>_page.dart`
- Depends on: Data layer (stores + models), theme tokens, shared widgets, `AppNav`
- Used by: `RootShell` (via `IndexedStack`) and `AppNav.push()`

**Shared Widget Layer:**
- Purpose: Reusable, brand-consistent building blocks shared across features
- Contains: `SoftCard`, `Avatar`, `FoodSlot`, `SectionHead`, `BotIconView`, `StatusDot` (`primitives.dart`); `PillChip`, `RmToggle`, `RmTextField`, `SheetHeader`, `SheetSubmit` (`forms.dart`); `RiMiBottomNav`, `TabletRail`, `DraggableAiOrb` (`navigation.dart`)
- Location: `flutter/lib/widgets/`
- Depends on: Theme tokens (`RM`, `RMType`), `AppIcons`
- Used by: Feature pages

**Theme / Token Layer:**
- Purpose: Single source of truth for design tokens, typography, and global theme
- Contains: `RM` (color constants), `RMType` (text style factory), `vnd()` (currency formatter) in `tokens.dart`; `AppTheme.light` MaterialTheme build + `rmToast()` helper in `app_theme.dart`
- Location: `flutter/lib/theme/`
- Depends on: `google_fonts` package only
- Used by: Every widget layer

**Core Utilities Layer:**
- Purpose: Cross-cutting helpers with no UI
- Contains: `isTablet(context)` / `screenW(context)` breakpoint helpers (`responsive.dart`); `AppIcons.of(name)` icon name-to-IconData map + `RmIcon` convenience widget (`app_icons.dart`)
- Location: `flutter/lib/core/`
- Depends on: Flutter framework only
- Used by: Feature pages, shared widgets

**Data Layer (mock stores + models):**
- Purpose: In-memory application state and data models
- Contains: `Order`, `Product`, `Customer`, `Bot` model classes; `OrderStore`, `ProductStore`, `CustomerStore` ChangeNotifier singletons; style maps (`statusStyle`, `channelColor`, `tiers`, etc.); static bot roster (`bots` list); static finance data (`finance` map)
- Location: `flutter/lib/data/mock_data.dart`
- Depends on: Flutter Material (for `ChangeNotifier`, `Color`)
- Used by: Feature pages, `RootShell` (for badge count)

**App Shell Layer:**
- Purpose: Bootstrap, navigation controller, root scaffold
- Contains: `RiMiApp` (MaterialApp), `RootShell` (responsive shell with `IndexedStack`), `AppNav` (static navigation API)
- Location: `flutter/lib/app.dart`, `flutter/lib/main.dart`
- Depends on: All feature pages (import at top of `app.dart`), theme, core
- Used by: `main.dart` entry point

## Data Flow

**Tab Switch:**
1. User taps bottom nav or rail item
2. `AppNav.tab.value = i` updates the `ValueNotifier<int>`
3. `ValueListenableBuilder` in `RootShell` rebuilds
4. `IndexedStack` reveals the pre-built child at index `i` — no rebuild of other children

**Action that mutates state (e.g., advance order status):**
1. User taps action button on `OrderDetailPage`
2. Widget calls `OrderStore.instance.advance(id)`
3. Store mutates in-memory list, calls `notifyListeners()`
4. All `ListenableBuilder` / `AnimatedBuilder` widgets that depend on `OrderStore.instance` rebuild
5. UI reflects new state (status badge, active-count badge in bottom nav)

**Push navigation (e.g., open order detail):**
1. Widget calls `AppNav.push(OrderDetailPage(id: o.id))` or `Navigator.of(context).push(...)`
2. `AppNav.navKey` routes push onto the navigator stack inside `RiMiApp`
3. Back button or `Navigator.pop()` returns to previous screen

**AI chat open:**
1. User taps floating AI orb or `_SearchAiBar`
2. `AppNav.openAiTeam()` → `AppNav.push(AiTeamPage())`
3. From team page, `AppNav.openChat(bot)` → `AppNav.push(AiChatPage(bot: bot))`
4. Chat uses pre-scripted `chatScripts[bot.id]` — no real network calls

**Bottom sheet composer (e.g., add order):**
1. Feature calls `showAddOrderComposer(context)` / `showAddDishComposer(context)` / `showAddCustomerComposer(context)`
2. `showModalBottomSheet` presents a stateful composer widget
3. On confirm, composer calls `Store.instance.add(...)` → `notifyListeners()` → parent rebuilds
4. Sheet pops and `rmToast` confirms success

**State Management:**
- All state is in-memory singleton `ChangeNotifier` stores — no persistence, no backend
- `ValueNotifier<int>` drives tab selection (not a store)
- Widget-local state (search text, selected filters, period toggles) is managed with `StatefulWidget` + `setState`

## Key Abstractions

**`AppNav` (static navigation controller):**
- Purpose: Decouple navigation calls from widget tree — any widget can navigate without needing a `BuildContext` ancestor
- Location: `flutter/lib/app.dart`
- Pattern: Static facade over `GlobalKey<NavigatorState>` + `ValueNotifier<int>`

**`ChangeNotifier` Store Singletons:**
- Purpose: Shared mutable state per domain (orders, products, customers)
- Examples: `OrderStore.instance`, `ProductStore.instance`, `CustomerStore.instance`
- Location: `flutter/lib/data/mock_data.dart`
- Pattern: Singleton + Observer (`ChangeNotifier` / `ListenableBuilder`)

**Dual-Layout Widget Pairs:**
- Purpose: Serve responsive layouts without runtime branching inside a page
- Examples: `HomeMobile` / `HomeTablet`, `OrdersMobile` / `OrdersTablet`, etc.
- Pattern: `RootShell` selects the correct pair via `isTablet(context)` and places both in a static const list

**`RM` Token Class:**
- Purpose: Named design token access — all colors referenced by semantic name
- Location: `flutter/lib/theme/tokens.dart`
- Pattern: `abstract final class` with `static const` fields (no instantiation)

**`RMType` Typography Factory:**
- Purpose: Consistent text styles without style duplication
- Location: `flutter/lib/theme/tokens.dart`
- Pattern: Static factory methods `RMType.body(...)` and `RMType.display(...)` accepting named parameters

**`SoftCard`:**
- Purpose: Default surface in the app — white card with hairline border, optional tap + shadow
- Location: `flutter/lib/widgets/primitives.dart`
- Pattern: Composable wrapper widget accepting a `child`

**Bottom-Sheet Composers:**
- Purpose: Modal forms for creating new entities (orders, products, customers)
- Examples: `showAddOrderComposer`, `showAddDishComposer`, `showAddCustomerComposer`
- Pattern: `showModalBottomSheet` + stateful inner widget + `Store.instance.add(...)` on submit

## Entry Points

**App Entry:**
- Location: `flutter/lib/main.dart`
- Triggers: Flutter engine startup (`flutter run`)
- Responsibilities: Single line — `runApp(const RiMiApp())`

**App Root:**
- Location: `flutter/lib/app.dart` — `RiMiApp` class
- Triggers: Called by `main()`
- Responsibilities: Create `MaterialApp` with `AppTheme.light`, register `AppNav.navKey`, mount `RootShell`

**`RootShell`:**
- Location: `flutter/lib/app.dart`
- Triggers: Built by `RiMiApp`
- Responsibilities: Detect tablet breakpoint, render `IndexedStack` of feature pages, render `RiMiBottomNav` or `TabletRail`, overlay `DraggableAiOrb` on mobile

## Error Handling

**Strategy:** No formal error-handling strategy — this is a UI prototype with no network calls or file I/O. Toast feedback (`rmToast`) is used to signal user actions that are not yet wired.

**Patterns:**
- User actions that have no real implementation call `rmToast(context, '...')` as a placeholder
- Widget-local state guards (e.g., `enabled: _valid` on `SheetSubmit`) prevent invalid submissions
- No try/catch, no error boundaries — not applicable to a mock-data prototype

## Cross-Cutting Concerns

**Theming:**
- `AppTheme.light` defined in `flutter/lib/theme/app_theme.dart` applies brand tokens globally via `ThemeData`
- All widgets reference `RM.*` constants directly rather than `Theme.of(context)` — intentional for speed in a prototype

**Typography:**
- `RMType.display(...)` → Bricolage Grotesque (display headings)
- `RMType.body(...)` → Be Vietnam Pro (body, labels, captions)
- Both loaded via `google_fonts` package

**Responsive Layout:**
- Single breakpoint: `isTablet(context)` returns `true` when width ≥ 700pt
- Navigation: `RiMiBottomNav` (mobile) vs `TabletRail` (tablet)
- Page layouts: `*Mobile` vs `*Tablet` widget pairs per feature

**Icons:**
- Semantic icon names (strings) mapped to Material icons via `AppIcons.of(name)`
- Location: `flutter/lib/core/app_icons.dart`

**Currency Formatting:**
- `vnd(n)` helper in `flutter/lib/theme/tokens.dart` formats integers as Vietnamese dong (e.g., `148000` → `"148.000 ₫"`)

---

*Architecture analysis: 2026-05-31*
*Update when major patterns change*
