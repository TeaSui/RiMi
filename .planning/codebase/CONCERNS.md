# Codebase Concerns

**Analysis Date:** 2026-05-31

## Tech Debt

**All data is hardcoded in-process mock state — no backend layer exists:**
- Issue: Every store (`OrderStore`, `ProductStore`, `CustomerStore`) is a `ChangeNotifier` singleton populated with hardcoded Vietnamese fixture data. All mutations are in-memory only; a hot-restart resets all state.
- Files: `flutter/lib/data/mock_data.dart` (entire file — 383 lines of models + stores + fixture records)
- Why: Prototype / design-fidelity build explicitly mirrors a JS prototype ("Stores — ChangeNotifier singletons (mirror the JS module stores)").
- Impact: Cannot persist any user action. New orders, new dishes, new customers all vanish on restart. Cannot be connected to a real backend without replacing the store layer entirely.
- Fix approach: Introduce a repository layer (e.g. `lib/data/repositories/`) behind the same store interface; replace fixture lists with async data sources. Stores become thin adapters over repositories.

**Models, style maps, stores, and fixture data all live in one 383-line file:**
- Issue: `flutter/lib/data/mock_data.dart` co-locates four distinct concerns: domain models (`Order`, `Product`, `Customer`, `Bot`), style-mapping constants (`channelColor`, `statusStyle`, `tiers`), ChangeNotifier stores, and hardcoded fixture records.
- Why: Originated as a direct port of a single JS module.
- Impact: Any change to a model requires navigating through unrelated store code; style maps are duplicated with logic that also lives in feature pages.
- Fix approach: Split into `lib/models/`, `lib/data/stores/`, and `lib/data/fixtures/` (or remove fixtures entirely when backend exists).

**Business name and KPI figures hardcoded in widget trees:**
- Issue: The restaurant name "Bếp Nhà Hằng" and today's stats (`2.84M₫`, `38`, `12%`, `96%`) appear as string literals directly in widget builds.
- Files: `flutter/lib/features/home/home_page.dart` (lines 74–75, 265), `flutter/lib/features/content/content_page.dart` (line 227), `flutter/lib/features/ai/ai_page.dart` (lines 28–41), `flutter/lib/data/mock_data.dart` (line 351–353)
- Why: Prototype fidelity — values mirror a specific demo scenario.
- Impact: Multi-tenant or multi-restaurant use is impossible without a global find-and-replace; real revenue figures will never surface.
- Fix approach: Move shop identity into a `ShopConfig` model fetched at startup; compute KPIs from live order data.

**Order `time` field is a static display string, not a timestamp:**
- Issue: `Order.time` is typed `String` and holds values like `'8 min'`, `'just now'`, `'30 min'`. It is never updated as real time passes.
- File: `flutter/lib/data/mock_data.dart` (Order model and all fixture records)
- Why: Prototype convenience — static snapshot of "current" state.
- Impact: The `late` badge is also static (set at construction). A real kitchen display must auto-update elapsed times and recompute lateness dynamically.
- Fix approach: Replace `time` with `createdAt: DateTime` and `late` with a computed getter; drive countdown with a `Timer` or stream.

**Widget test references a non-existent `MyApp` class:**
- Issue: `flutter/test/widget_test.dart` imports `package:rimi/main.dart` and calls `tester.pumpWidget(const MyApp())`, but the app's root widget is `RiMiApp`, not `MyApp`. The test is the scaffolded Flutter template and has never been updated.
- File: `flutter/test/widget_test.dart`
- Why: Auto-generated template was never replaced.
- Impact: `flutter test` fails at compile time. CI will report a broken test suite even before any feature code is exercised.
- Fix approach: Replace with `tester.pumpWidget(const RiMiApp())` and a meaningful smoke assertion, or delete and write real tests.

**Singleton stores accessed directly by name across all widgets:**
- Issue: `OrderStore.instance`, `ProductStore.instance`, and `CustomerStore.instance` are referenced by direct static access in every feature file without any injection mechanism.
- Files: `flutter/lib/features/orders/orders_page.dart`, `flutter/lib/features/home/home_page.dart`, `flutter/lib/features/products/products_page.dart`, `flutter/lib/features/customers/customers_page.dart`, `flutter/lib/app.dart`
- Why: Prototype simplicity — mirrors direct JS module imports.
- Impact: Untestable without a mocking strategy; cannot swap implementations; makes adding `provider` or `riverpod` a grep-and-replace across all files.
- Fix approach: Expose stores via `InheritedWidget` or a DI package at the `RootShell` level so widgets access them through context.

---

## Known Bugs

**`OrderStore.advance()` and `ProductStore.toggle()` call `firstWhere` without `orElse` — will throw on stale IDs:**
- Symptoms: Unhandled exception (`StateError: No element`) if an order or product ID referenced by a button no longer exists in the store.
- Trigger: Could occur if an order is removed from the list while a detail view is still open, then the advance button is tapped.
- Files: `flutter/lib/data/mock_data.dart` lines 220 (`OrderStore.advance`) and 261 (`ProductStore.toggle`)
- Workaround: Currently impossible to delete items, so the bug is dormant in prototype use.
- Root cause: Missing `orElse` guard — compare the safe pattern used in `OrderDetailPage` (`orElse: () => OrderStore.instance.all.first`).
- Fix: Add `orElse: () => throw ArgumentError('id $id not found')` or return early if not found.

**`DraggableAiOrb` position is not persisted across tab switches — orb resets to bottom-right:**
- Symptoms: User drags the AI orb to a preferred position; switching to another tab and back resets it to `Offset(w - 56 - 16, h - 56 - 24)`.
- Trigger: `_pos` is an instance field on `_DraggableAiOrbState`. The `RootShell` uses `IndexedStack`, so the widget is kept alive, but the condition `_pos ??= ...` only fires when `_pos` is null — which it is on first build before the size is known.
- File: `flutter/lib/widgets/navigation.dart` (`_DraggableAiOrbState`)
- Workaround: Drag again after each tab switch.
- Root cause: Position initialisation is deferred to `LayoutBuilder` inside `build()`, overwriting any drag if the widget is rebuilt after a resize event.

**`_NewOrderComposer._create()` uses `composerMenu.first` as seed fallback when no item is selected:**
- Symptoms: Creating an order with zero items (no quantity bumped) silently submits an empty order with `items: ''` and `total: 0`.
- Trigger: Tap "Create" without adding any items to the order.
- File: `flutter/lib/features/orders/orders_page.dart` lines 540–549
- Workaround: The "Create" button is enabled based on `_count > 0` check at the call site — verify this guard is enforced.
- Root cause: The guard appears to require `_count > 0` or `_name` non-empty but does not enforce both simultaneously.

---

## Security Considerations

**Phone numbers in mock data are plausible real Vietnamese numbers:**
- Risk: Mock data contains phone numbers in the format `0908 123 456` etc. If this data is ever seeded into a real database or demo environment, it could represent real individuals.
- Files: `flutter/lib/data/mock_data.dart` (lines 277–284, `CustomerStore` fixture)
- Current mitigation: Data is in-memory only; no network transmission.
- Recommendations: Replace with clearly fictional numbers (e.g. `0900 000 001`) before any database seeding or demo deployment.

**No input validation on customer phone field:**
- Risk: `RmTextField` for phone accepts any string; no length or format validation is performed before `CustomerStore.instance.add()` is called.
- File: `flutter/lib/features/customers/customers_page.dart` (`_AddCustomerComposerState._create`)
- Current mitigation: In-memory store only — no SQL injection vector exists today.
- Recommendations: Add phone format validation (Vietnamese 10-digit pattern) before any backend integration; treat phone as PII requiring masking in logs.

**No authentication layer exists anywhere in the codebase:**
- Risk: The app has no login screen, session management, or role-based access control.
- Current mitigation: Prototype only — no sensitive data is transmitted.
- Recommendations: Before any backend integration, design an auth flow (trust-boundary trigger per `workflow-routing.md`); all backend calls must carry authenticated credentials.

---

## Performance Bottlenecks

**`ListenableBuilder` on `OrderStore.instance` rebuilds entire order list on every `notifyListeners`:**
- Problem: Any mutation (advance, add) triggers `notifyListeners()`, which rebuilds the full `OrdersMobile`/`OrdersTablet` widget subtrees including all filter computations.
- Files: `flutter/lib/features/orders/orders_page.dart` (lines 765, 899), `flutter/lib/features/home/home_page.dart` (line 230)
- Cause: No granular change notification; stores notify all listeners on any mutation regardless of which record changed.
- Improvement path: Use `select`-style filtering (riverpod's `select`, or a `ValueNotifier<List<Order>>` per status bucket) to scope rebuilds. For the prototype scale (< 20 orders) this is not perceptible, but will degrade as list grows.

**Search filtering runs synchronously on every keystroke against the full order/customer list:**
- Problem: `onChanged` callbacks call `setState`, triggering a synchronous linear scan of all orders/customers on every character typed.
- Files: `flutter/lib/features/orders/orders_page.dart`, `flutter/lib/features/customers/customers_page.dart`
- Cause: No debounce on the search field; filter computed inline inside `build()`.
- Improvement path: Add `debounce` (300ms) and extract filter logic to a computed field updated only when input settles. Non-issue at current data scale.

**`google_fonts` package fetches fonts at runtime from the network on first launch:**
- Problem: `Be Vietnam Pro` and `Bricolage Grotesque` are loaded via `GoogleFonts.*` — on first cold start on a real device with no cache, the app may render with fallback fonts until the download completes.
- Files: `flutter/lib/theme/tokens.dart`, `flutter/lib/theme/app_theme.dart`
- Cause: `google_fonts` default behaviour is network-first.
- Improvement path: Bundle fonts as local assets in `pubspec.yaml` `fonts:` section; remove dependency on `google_fonts` or configure it to use bundled assets only. This is critical for offline restaurant scenarios.

---

## Fragile Areas

**`AppNav` uses a `GlobalKey<NavigatorState>` that breaks if the `MaterialApp` is rebuilt:**
- File: `flutter/lib/app.dart` (`AppNav.navKey`)
- Why fragile: `GlobalKey` references are invalidated if the widget holding them is unmounted and remounted. Hot-reload or deep-link handling that recreates `RiMiApp` will silently drop navigation calls.
- Common failures: `AppNav.push()` / `AppNav.goTab()` called from `home_page.dart` quick-action buttons return null from `navKey.currentState`.
- Safe modification: Always check `navKey.currentState != null` before calling; consider replacing with a `NavigatorObserver`-based approach or go_router.
- Test coverage: Zero — no navigation integration tests exist.

**`isTablet` breakpoint (700 logical pixels) is the sole responsive trigger:**
- File: `flutter/lib/core/responsive.dart`
- Why fragile: A single width threshold determines mobile vs. tablet layout for the entire app. Foldable phones, landscape phones, and unusual screen densities may render wrong layout variants.
- Common failures: A phone in landscape (e.g. 844×390 on iPhone 14) stays on mobile layout; a large-screen Android phone at 720px triggers tablet layout on a device the design never targeted.
- Safe modification: Consider adding an intermediate "phablet" tier or using `AdaptiveLayout` from `flutter_adaptive_scaffold`.
- Test coverage: Zero — no golden tests or layout tests exist.

**`DraggableAiOrb` is rendered inside `Positioned.fill` over the entire body but is conditionally hidden for tab 3 only:**
- File: `flutter/lib/app.dart` (line 85)
- Why fragile: The orb is absent on the Content tab but present on all others. If the tab order changes (e.g. a new tab is inserted), the `tab != 3` guard silently misses.
- Common failures: Moving "Content" to tab 4 would show the orb on the content screen.
- Safe modification: Compare against the actual `ContentMobile` type or a named constant, not a magic index.
- Test coverage: None.

**Tablet `OrdersTablet` hardcodes list pane width to `470` logical pixels:**
- File: `flutter/lib/features/orders/orders_page.dart` (line ~968)
- Why fragile: On very wide tablets (> 1200px), the detail pane becomes excessively wide; on minimum-tablet widths (700–800px), the list pane occupies 67% of the screen leaving little room for the detail view.
- Common failures: Detail pane overflows on small landscape iPads.
- Safe modification: Replace with a `Flexible`/`Expanded` ratio split (e.g. 40/60).
- Test coverage: None.

---

## Scaling Limits

**In-memory stores have no capacity limit:**
- Current capacity: Unlimited additions accepted by all three stores.
- Limit: On a real device, adding thousands of orders would degrade list rendering (no pagination, no lazy loading beyond `ListView.builder`).
- Symptoms at limit: Frame drops on list scroll; memory growth unbounded.
- Scaling path: Add backend-backed pagination; use `ListView.builder` with a paged data source (already used in some lists but data source is never paged).

**Single-breakpoint responsive system cannot handle >2 screen classes:**
- Current capacity: Mobile (< 700px) and tablet (≥ 700px).
- Limit: Desktop web or TV targets; landscape phones.
- Symptoms at limit: Tablet layout on phone landscape; no desktop-specific spacing.
- Scaling path: Add a second breakpoint (e.g. 1200px for desktop) and corresponding `Desktop*` widget variants per feature.

---

## Dependencies at Risk

**`google_fonts: ^6.2.1` — runtime font download required for correct rendering:**
- Risk: Requires network on first launch; fonts may be unavailable offline (critical for a kitchen app that may operate on poor Wi-Fi).
- Impact: App renders with system fallback fonts on first offline launch, breaking the premium design.
- Migration plan: Download and bundle `Be Vietnam Pro` and `Bricolage Grotesque` as local assets; either remove `google_fonts` or use `GoogleFonts.asMap()` with a local asset configuration.

**`cupertino_icons: ^1.0.8` — imported but unused:**
- Risk: Low — but adds unnecessary bundle weight.
- Impact: Minimal. No Cupertino icons are referenced in the codebase (all icons go through `AppIcons.of()` which uses Material icons).
- Migration plan: Remove from `pubspec.yaml` at next dependency audit.

---

## Missing Critical Features

**No persistence layer — all data lost on restart:**
- Problem: There is no local storage (SQLite, Hive, shared_preferences) and no remote API client. Every store is purely in-memory.
- Current workaround: Prototype only — users do not expect data to persist.
- Blocks: Cannot ship any production-usable version without this.
- Implementation complexity: High — requires choosing a backend, designing API contracts, and refactoring all three stores.

**No authentication or multi-user support:**
- Problem: No login screen, no session, no concept of which restaurant is using the app.
- Current workaround: Single hardcoded restaurant "Bếp Nhà Hằng".
- Blocks: Any real deployment; any multi-tenant scenario.
- Implementation complexity: High — full-workflow trust-boundary change.

**No real-time order timer or lateness detection:**
- Problem: `Order.time` is a static string; `Order.late` is set at construction and never recomputed. A real kitchen display must show elapsed time and flag orders dynamically.
- Current workaround: Fixture data pre-sets `late: true` on specific orders.
- Blocks: Kitchen display reliability.
- Implementation complexity: Medium — replace `time: String` with `createdAt: DateTime`; add a `Timer.periodic` or stream-based updater in `OrderStore`.

**AI chat is fully scripted — no real LLM integration:**
- Problem: All AI responses in `flutter/lib/features/ai/ai_page.dart` are pre-written `ChatScript` objects keyed by bot ID. The send button fires `rmToast(context, 'Message sent')`.
- Current workaround: Prototype demo only.
- Blocks: Any real AI functionality.
- Implementation complexity: High — requires API key management (trust-boundary), streaming response handling, and error states.

**Content posting is a no-op:**
- Problem: "Post" buttons on the Content page call `rmToast(context, 'Posted to ${_picked.join(', ')} 🎉')` — no social media API integration exists.
- Files: `flutter/lib/features/content/content_page.dart` (lines 128, 307)
- Current workaround: Demo only.
- Blocks: The core content-marketing value proposition.
- Implementation complexity: High — each platform (Facebook, Zalo, TikTok, Instagram) has distinct OAuth and posting APIs.

**Finance data is entirely static:**
- Problem: All revenue, expense, and profit figures in `flutter/lib/features/finance/finance_page.dart` and `flutter/lib/data/mock_data.dart` (line 351–353) are hardcoded constants. The bar chart is rendered from a fixed dataset.
- Current workaround: Demo only.
- Blocks: Any real financial reporting.
- Implementation complexity: High — requires aggregating order data and integrating with an accounting/expense data source.

---

## Test Coverage Gaps

**Zero meaningful test coverage across the entire application:**
- What's not tested: Every feature page, every store mutation, all navigation logic, all responsive layout variants, all form validation paths, the `DraggableAiOrb` position logic.
- Risk: Any refactoring (store layer replacement, navigation overhaul, backend integration) is entirely unguarded. Regressions are undetectable before manual testing.
- Priority: High — especially before the backend integration phase begins.
- Difficulty to test: Moderate — most widgets are `StatelessWidget` or simple `StatefulWidget`; stores are pure Dart. The main friction is the singleton store pattern (requires `instance` replacement or a test seam).

**The only test file will not compile (`MyApp` does not exist):**
- What's not tested: Everything.
- Risk: CI would show a red test suite from day one.
- Priority: Critical — fix immediately.
- File: `flutter/test/widget_test.dart`
- Difficulty to test: Trivial — replace `MyApp` with `RiMiApp`.

**No golden/screenshot tests for responsive layouts:**
- What's not tested: Mobile vs. tablet layout rendering at the 700px breakpoint.
- Risk: Layout regressions when adding new features that touch shared widgets (`navigation.dart`, `primitives.dart`).
- Priority: Medium.
- Difficulty to test: Moderate — requires setting up `flutter_test` with `WidgetTester.setSurfaceSize`.

---

*Concerns audit: 2026-05-31*
*Update as issues are fixed or new ones discovered*
