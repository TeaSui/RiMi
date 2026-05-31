// Auth form validation widget tests.
// Tests: login form enable/disable, signup minimum password length.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:rimi/core/auth/token_storage.dart';
import 'package:rimi/core/network/dio_client.dart';
import 'package:rimi/features/auth/login_page.dart';
import 'package:rimi/features/auth/signup_page.dart';
import 'package:rimi/theme/app_theme.dart';

import '../helpers/fake_token_storage.dart';
import '../helpers/fake_dio.dart';

Widget _wrapPage(Widget page) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => page),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(path: '/signup', builder: (context, state) => const SignupPage()),
      GoRoute(
        path: '/verify-email',
        builder: (context, state) => const Scaffold(body: Text('Verify')),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => const Scaffold(body: Text('Reset')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
      dioClientProvider.overrideWithValue(FakeDio.create()),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: router,
    ),
  );
}

void main() {
  group('LoginPage form validation', () {
    testWidgets('submit button disabled when fields empty', (tester) async {
      await tester.pumpWidget(_wrapPage(const LoginPage()));
      await tester.pumpAndSettle();

      // The SheetSubmit button uses FilledButton internally.
      final button = find.byType(FilledButton);
      expect(button, findsOneWidget);
      // When disabled, onPressed is null.
      final fb = tester.widget<FilledButton>(button);
      expect(fb.onPressed, isNull);
    });

    testWidgets('submit button enabled when both fields filled', (tester) async {
      await tester.pumpWidget(_wrapPage(const LoginPage()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).first,
        'test@example.com',
      );
      await tester.pump();

      // There are 2 TextFields: email and password.
      await tester.enterText(
        find.byType(TextField).last,
        'password123',
      );
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('password visibility toggle works', (tester) async {
      await tester.pumpWidget(_wrapPage(const LoginPage()));
      await tester.pumpAndSettle();

      // Find the visibility icon button.
      expect(find.byIcon(Icons.visibility_off_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.visibility_off_rounded));
      await tester.pump();
      expect(find.byIcon(Icons.visibility_rounded), findsOneWidget);
    });
  });

  group('SignupPage form validation', () {
    testWidgets('submit disabled until password has 8+ chars', (tester) async {
      await tester.pumpWidget(_wrapPage(const SignupPage()));
      await tester.pumpAndSettle();

      // Fill name and email but short password.
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Nguyen Van A');
      await tester.pump();
      await tester.enterText(fields.at(1), 'test@example.com');
      await tester.pump();
      await tester.enterText(fields.at(2), 'short'); // < 8 chars
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('submit enabled with valid name + email + 8-char password',
        (tester) async {
      await tester.pumpWidget(_wrapPage(const SignupPage()));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Nguyen Van A');
      await tester.pump();
      await tester.enterText(fields.at(1), 'test@example.com');
      await tester.pump();
      await tester.enterText(fields.at(2), 'password123');
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
    });
  });
}
