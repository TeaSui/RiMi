# Coding Conventions

**Analysis Date:** 2026-05-31

## Naming Patterns

**Files:**
- `snake_case` for all Dart files (e.g., `home_page.dart`, `app_theme.dart`, `mock_data.dart`)
- Feature pages named `<feature>_page.dart` (e.g., `orders_page.dart`, `finance_page.dart`)
- Widget collection files named by category (`primitives.dart`, `navigation.dart`, `forms.dart`)
- Tokens/theme: `tokens.dart` and `app_theme.dart`

**Classes:**
- `PascalCase` for all public classes (e.g., `OrderStore`, `SoftCard`, `RiMiApp`)
- `_PascalCase` (underscore prefix) for private/file-local classes (e.g., `_Tab`, `_Bubble`, `_Bar`, `_ProductsMobileState`)
- Widget pairs: public `StatefulWidget` + private `_State` (e.g., `ProductsMobile` / `_ProductsMobileState`)
- Utility namespaces: `abstract final class` with only static members (e.g., `RM`, `RMType`, `AppNav`, `AppIcons`, `AppTheme`)
- Stores: `XxxStore` suffix for `ChangeNotifier` singletons (e.g., `OrderStore`, `ProductStore`, `CustomerStore`)
- Style data classes: descriptive short names (e.g., `StatusStyle`, `TierStyle`, `StockStyle`)

**Functions:**
- `camelCase` for all functions and methods
- Private helper methods prefixed with `_` (e.g., `_create`, `_valid`, `_quickGo`)
- No special prefix for async functions
- Positional parameter names in callbacks: single-letter `_` when unused (`builder: (_) => ...`)
- Navigation helpers: `goTab`, `push`, `openAiTeam`, `openChat`

**Variables:**
- `camelCase` for instance variables and local variables
- Private fields prefixed with `_` in `State` classes (e.g., `_period`, `_searchOpen`, `_search`, `_tier`)
- `UPPER_SNAKE_CASE` is not used; constants use `camelCase` (e.g., `navTabs`, `channels`, `statusTabs`)
- Controller fields named after their purpose without suffix: `_name`, `_phone`, `_price` (not `_nameController`)

**Types / Constants:**
- `const` used aggressively: widget constructors, `EdgeInsets`, `SizedBox`, `Icon`, inline decorations
- Design token class `RM` (short namespace prefix): all color tokens accessed as `RM.brand`, `RM.ink`, etc.
- `RMType` for typography factory methods (`RMType.display(...)`, `RMType.body(...)`)

## Code Style

**Formatting:**
- Standard `dart format` (enforced by SDK `^3.8.0`)
- No explicit line-length config; long lines are accepted for inline decoration chains
- Single quotes for strings throughout
- Trailing commas on multi-line argument lists (standard Dart formatter practice)

**Linting:**
- `flutter_lints ^6.0.0` via `analysis_options.yaml`
- Extra rules added: `prefer_const_constructors: true`, `avoid_print: true`
- Run: `flutter analyze` from `flutter/` directory

**Dart Features Used:**
- Record types for inline data tuples: `(String, Color, String)` records used in `const` lists (e.g., `navTabs`, `_quick`, `statusTabs`)
- `final` on all immutable fields in `StatelessWidget` subclasses
- Pattern matching via destructuring not yet adopted; record field access via positional `.$1`, `.$2`, `.$3`
- `withValues(alpha: ...)` used instead of deprecated `withOpacity`

## Import Organization

**Order (observed consistently):**
1. `package:flutter/material.dart` (or `widgets.dart`) — always first
2. Other `package:` imports (e.g., `package:google_fonts/google_fonts.dart`)
3. Internal relative imports — ordered: `../../app.dart` → core → data → theme → widgets → sibling features
4. No `import as` aliases; no barrel `index.dart` files

**Path Style:**
- All internal imports use relative paths (`../../theme/tokens.dart`, `../widgets/primitives.dart`)
- No `package:rimi/...` absolute imports for internal code
- No path aliases configured

**Grouping:**
- Single blank line separates the Flutter package import from others when there are additional packages
- Internal imports listed consecutively without blank lines between them

## Error Handling

**Patterns:**
- No `try/catch` or `throw` in this codebase — it is a UI-only prototype with mock data
- Validation uses guard expressions inline (e.g., `bool get _valid => _name.text.trim().isNotEmpty && (int.tryParse(_price.text) ?? 0) > 0`)
- Null fallback with `?? defaultValue` pattern for optional fields
- `firstWhere` used without `orElse` on known-good data (stores only mutate via controlled IDs)

**Error States:**
- No error state widgets; current scope is prototype/design-fidelity only
- `rmToast` used as the single feedback mechanism for actions that would normally be async (e.g., "Exporting report…", "Bill sent to printer")

## Logging

**Framework:**
- No logging library; `avoid_print: true` lint rule is active
- `rmToast` in `lib/theme/app_theme.dart` is the sole runtime feedback channel
- No debug output in committed code

**Patterns:**
- User feedback via `ScaffoldMessenger` / `SnackBar` through `rmToast(context, message)`
- No structured logging; prototype scope does not require it

## Comments

**When to Comment:**
- `///` doc comments on every public class and top-level function (e.g., all widgets in `primitives.dart`, `forms.dart`, `navigation.dart`, token classes)
- `//` single-line comments used for design-source cross-references (e.g., `// Mirrors RM in the design source (tokens.jsx) 1:1`)
- Section separator blocks using `// ── Section name ────────` pattern to divide large files into logical groups
- No inline `TODO`, `FIXME`, or `HACK` comments found in codebase

**Section Separators (required in large feature files):**
```dart
// ─────────────────────────────────────────────────────────────────────
// Section Name
// ─────────────────────────────────────────────────────────────────────
```
Or compact form:
```dart
// ── Section name ─────────────────────────────────────────────────────
```

**Design Source References:**
- Comments explicitly note when code mirrors a JS/design source (e.g., `/// Mirrors NAV_TABS in tokens.jsx`)
- This is intentional traceability back to the approved Figma/prototype

## Function Design

**Size:**
- Utility/token classes: small, pure static methods
- Widget `build` methods range from 10–60 lines; larger ones use extracted private widgets
- `_State` classes extract sub-builders into private `Widget` methods (e.g., `_inline` in `FinanceMobile`)

**Parameters:**
- Widget constructors use named parameters with `required` for mandatory values
- Optional parameters use default values rather than nullable types where possible
- `super.key` shorthand used consistently across all widgets

**Return Values:**
- `build` returns a single widget; complex layouts decomposed into private `StatelessWidget` subclasses rather than helper methods when reuse across contexts is expected
- Helper methods that return `Widget` are private and used inline within the same `State`

## Module Design

**Exports:**
- No barrel `index.dart` files; all imports are direct file references
- Public classes exported from their defining file only
- Private helpers (prefixed `_`) never referenced outside their file

**Singletons:**
- `ChangeNotifier` stores use private constructor + `static final instance` pattern:
  ```dart
  class OrderStore extends ChangeNotifier {
    OrderStore._();
    static final OrderStore instance = OrderStore._();
    // ...
  }
  ```
- Accessed directly via `OrderStore.instance` — no dependency injection

**Utility Namespaces:**
- `abstract final class` used as a non-instantiable namespace for static constants and methods:
  ```dart
  abstract final class RM {
    static const brand = Color(0xFFE0552B);
    // ...
  }
  ```
- Pattern used for: `RM`, `RMType`, `AppIcons`, `AppNav`, `AppTheme`

**Responsive Layout Convention:**
- Every feature that has both mobile and tablet variants defines two public classes: `XxxMobile` and `XxxTablet`
- `isTablet(context)` from `lib/core/responsive.dart` is the single breakpoint check (≥ 700pt)
- `RootShell` in `lib/app.dart` owns the mobile/tablet switch; feature files define both variants inline

---

*Convention analysis: 2026-05-31*
*Update when patterns change*
