# Testing Patterns

**Analysis Date:** 2026-05-31

## Test Framework

**Runner:**
- `flutter_test` SDK package (bundled with Flutter SDK `^3.8.0`)
- No separate test runner configuration file; uses Flutter's built-in test runner

**Assertion Library:**
- `flutter_test` built-in `expect` with Flutter matchers (`findsOneWidget`, `findsNothing`, etc.)
- Standard Dart `expect` matchers also available (`equals`, `isA`, etc.)

**Run Commands:**
```bash
flutter test                                # Run all tests (from flutter/ directory)
flutter test test/widget_test.dart          # Run single file
flutter test --coverage                     # Generate coverage report
```

## Test File Organization

**Location:**
- `flutter/test/` directory (separate from source, not co-located with source)
- Currently only one test file exists: `flutter/test/widget_test.dart`

**Naming:**
- `widget_test.dart` — Flutter's default scaffold test name
- No naming convention established beyond the default (only one test file present)

**Current Structure:**
```
flutter/
  lib/
    main.dart
    app.dart
    core/
    data/
    features/
    theme/
    widgets/
  test/
    widget_test.dart    ← only test file (default scaffold, not updated for app)
```

**State of Testing:**
- The sole test file (`flutter/test/widget_test.dart`) is the **unmodified Flutter scaffold** — it tests a counter widget that does not exist in the actual app (`MyApp` is imported but the counter assertions (`find.text('0')`, `find.byIcon(Icons.add)`) will fail against the real `RiMiApp`)
- No feature tests, no unit tests for stores, no widget tests for any `RiMi`-specific widget have been written
- This codebase is a **UI prototype** — testing infrastructure is present (dependencies declared) but not exercised

## Test Structure

**Scaffold Pattern (from `widget_test.dart`):**
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rimi/main.dart';

void main() {
  testWidgets('description', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('expected'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('result'), findsOneWidget);
  });
}
```

**Recommended Pattern (when adding tests):**
```dart
void main() {
  group('WidgetName', () {
    testWidgets('renders correctly', (WidgetTester tester) async {
      // arrange
      await tester.pumpWidget(const MaterialApp(home: WidgetUnderTest()));
      // assert
      expect(find.text('expected text'), findsOneWidget);
    });
  });

  group('StoreName', () {
    test('mutation method updates state', () {
      // arrange
      final store = OrderStore.instance;
      // act
      store.advance('1042');
      // assert
      expect(store.all.firstWhere((o) => o.id == '1042').status, 'cooking');
    });
  });
}
```

## Mocking

**Framework:**
- `flutter_test` provides `MockNavigatorObserver`, `WidgetTester`, etc.
- No additional mocking library installed (no `mocktail`, `mockito`)

**Current Mocking Approach:**
- No mocks in use — the app uses in-memory `ChangeNotifier` singleton stores (`OrderStore.instance`, `ProductStore.instance`, `CustomerStore.instance`) defined in `lib/data/mock_data.dart`
- All data is static mock data initialized at startup; no network calls or external dependencies to mock

**Recommended When Adding Tests:**
- For store-level unit tests: use the singleton stores directly (already mock data)
- For widget tests needing isolated store state: reset store data or create a test instance
- Wrap widgets under test in `MaterialApp` + `AppTheme.light` to provide required theming context (`RM.*` tokens)

## Fixtures and Factories

**Current State:**
- No fixture files or factory functions for tests exist
- All test data lives in `lib/data/mock_data.dart` as the application's mock data layer — the same data used at runtime

**Available Test Data (from `lib/data/mock_data.dart`):**
- `OrderStore.instance.all` — 11 pre-seeded `Order` objects spanning all statuses
- `ProductStore.instance.all` — pre-seeded `Product` list
- `CustomerStore.instance.all` — pre-seeded `Customer` list

**Recommended Factory Pattern (when adding tests):**
```dart
// In test file or a shared test helper
Order testOrder({String status = 'new', bool late = false}) => Order(
  id: 'T001',
  cust: 'Test Customer',
  ch: 'online',
  items: 'Test item ×1',
  total: 50000,
  status: status,
  time: '1 min',
  late: late,
  seed: 0,
);
```

**Location (recommended):**
- Shared helpers: `flutter/test/helpers/` directory (not yet created)
- File-local factories: define in the test file near usage

## Coverage

**Requirements:**
- No enforced coverage target; `flutter_lints` does not enforce coverage thresholds
- No CI configuration found — coverage is not currently measured

**Configuration:**
- Coverage uses Flutter's built-in LCOV output: `flutter test --coverage`
- Output: `flutter/coverage/lcov.info`

**View Coverage:**
```bash
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

## Test Types

**Widget Tests (flutter_test):**
- Scope: single widget in isolation pumped into a test Flutter environment
- Use `tester.pumpWidget(MaterialApp(home: widget))` — always wrap with `MaterialApp` to satisfy `Theme.of(context)` and `MediaQuery` dependencies that `RM.*` tokens do not require but navigation/scaffold widgets do
- Use `tester.pump()` after interactions; `tester.pumpAndSettle()` for animations

**Unit Tests (dart test):**
- Scope: `ChangeNotifier` store methods (`OrderStore`, `ProductStore`, `CustomerStore`)
- No widget tree needed; import and call directly
- Use `test(...)` not `testWidgets(...)` for pure Dart logic

**Integration / E2E:**
- Not configured; no `integration_test` package in `pubspec.yaml`
- Not applicable for current prototype scope

## Common Patterns

**Widget Test with Theme:**
```dart
testWidgets('SoftCard renders child', (WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
        body: SoftCard(child: Text('Hello')),
      ),
    ),
  );
  expect(find.text('Hello'), findsOneWidget);
});
```

**Store Unit Test:**
```dart
test('OrderStore.advance moves status forward', () {
  final store = OrderStore.instance;
  final order = store.all.firstWhere((o) => o.status == 'new');
  store.advance(order.id);
  expect(order.status, 'cooking');
});
```

**Async Widget Test:**
```dart
testWidgets('tap triggers callback', (WidgetTester tester) async {
  bool tapped = false;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SoftCard(onTap: () => tapped = true, child: const Text('tap'))),
  ));
  await tester.tap(find.text('tap'));
  await tester.pump();
  expect(tapped, isTrue);
});
```

**Snapshot Testing:**
- Not used; no `golden_toolkit` or Flutter golden file tests configured

---

*Testing analysis: 2026-05-31*
*Update when test patterns change*
