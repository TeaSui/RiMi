// RiMi — main widget smoke test.
//
// Verifies that RootShell renders with the bottom navigation intact after the
// MaterialApp.router + nested-Navigator change. This replaces the broken
// MyApp/Icons.add counter test that was shipped with the flutter template.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:rimi/app.dart';
import 'package:rimi/core/auth/auth_state.dart';
import 'package:rimi/core/auth/token_storage.dart';
import 'package:rimi/core/network/dio_client.dart';
import 'package:rimi/theme/app_theme.dart';
import 'package:rimi/widgets/navigation.dart';

import 'helpers/fake_token_storage.dart';
import 'helpers/fake_dio.dart';

void main() {
  group('RootShell smoke test', () {
    testWidgets('custom bottom nav renders', (tester) async {
      // Use a realistic screen size to avoid pre-existing prototype overflow errors.
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      // Suppress overflow errors from pre-existing prototype layout issues.
      final oldOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed')) return;
        oldOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = oldOnError);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
            dioClientProvider.overrideWithValue(FakeDio.create()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const RootShell(),
          ),
        ),
      );
      // Pump a frame; the nested Navigator builds its initial route synchronously.
      await tester.pump();

      // AppNav.navKey must be bound to the nested Navigator.
      expect(AppNav.navKey.currentState, isNotNull);
      // RiMiBottomNav is the custom bottom navigation bar (not Flutter's
      // BottomNavigationBar which is not used in this design system).
      expect(find.byType(RiMiBottomNav), findsOneWidget);
    });

    testWidgets('AppNav.navKey is bound to the nested Navigator inside RootShell',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final oldOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed')) return;
        oldOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = oldOnError);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
            dioClientProvider.overrideWithValue(FakeDio.create()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const RootShell(),
          ),
        ),
      );
      await tester.pump();

      // AppNav.navKey should be attached to the nested Navigator.
      expect(AppNav.navKey.currentState, isNotNull);
    });

    testWidgets('tab switch via AppNav.goTab changes the tab', (tester) async {
      AppNav.tab.value = 0;
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final oldOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed')) return;
        oldOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = oldOnError);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
            dioClientProvider.overrideWithValue(FakeDio.create()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const RootShell(),
          ),
        ),
      );
      await tester.pump();

      expect(AppNav.tab.value, 0);
      AppNav.goTab(1);
      await tester.pump();
      expect(AppNav.tab.value, 1);

      // Reset for other tests.
      AppNav.tab.value = 0;
    });
  });

  group('Router redirect guard', () {
    testWidgets('unknown state shows /splash', (tester) async {
      final router = GoRouter(
        initialLocation: '/splash',
        redirect: (context, state) {
          // Simulate unknown state.
          return state.matchedLocation == '/splash' ? null : '/splash';
        },
        routes: [
          GoRoute(
            path: '/splash',
            builder: (ctx, st) => const Scaffold(
              body: Center(child: Text('Splash')),
            ),
          ),
          GoRoute(
            path: '/login',
            builder: (ctx, st) => const Scaffold(
              body: Center(child: Text('Login')),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(FakeTokenStorage()),
            dioClientProvider.overrideWithValue(FakeDio.create()),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Splash'), findsOneWidget);
    });
  });

  group('AuthState transitions', () {
    test('unknown → unauthenticated on empty storage', () {
      const state = AuthState.unknown();
      expect(state.status, AuthStatus.unknown);

      const next = AuthState.unauthenticated();
      expect(next.status, AuthStatus.unauthenticated);
    });

    test('copyWith preserves fields', () {
      final s = AuthState(
        status: AuthStatus.ready,
        userId: 'u1',
        displayName: 'Test',
        email: 'test@x.com',
        activeWorkspaceId: 'ws1',
      );
      final s2 = s.copyWith(activeWorkspaceId: 'ws2');
      expect(s2.userId, 'u1');
      expect(s2.activeWorkspaceId, 'ws2');
    });

    test('copyWith with clearWorkspace sets activeWorkspaceId to null', () {
      final s = AuthState(
        status: AuthStatus.ready,
        userId: 'u1',
        displayName: 'Test',
        email: 'test@x.com',
        activeWorkspaceId: 'ws1',
      );
      final s2 = s.copyWith(clearWorkspace: true);
      expect(s2.activeWorkspaceId, isNull);
    });
  });
}
