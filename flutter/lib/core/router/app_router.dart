import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_notifier.dart';
import '../auth/auth_state.dart';
import '../../features/auth/splash_page.dart';
import '../../features/auth/login_page.dart';
import '../../features/auth/signup_page.dart';
import '../../features/auth/email_verification_pending_page.dart';
import '../../features/auth/password_reset_request_page.dart';
import '../../features/auth/password_reset_confirm_page.dart';
import '../../features/workspace/create_workspace_page.dart';
import '../../app.dart';

/// Route path constants.
abstract final class AppRoutes {
  static const splash = '/splash';
  static const login = '/login';
  static const signup = '/signup';
  static const verifyEmail = '/verify-email';
  static const resetPassword = '/reset-password';
  static const resetPasswordConfirm = '/reset-password/confirm';
  static const workspaceCreate = '/workspace/create';
  static const shell = '/shell';
}

/// Creates the GoRouter with auth redirect guard.
///
/// The redirect guard maps [AuthStatus] to routes:
///   unknown           → /splash
///   unauthenticated   → auth routes only
///   verifiedNoWs      → /workspace/create
///   ready             → /shell
///
/// [refreshListenable] bridges the Riverpod provider to the router,
/// so the router re-evaluates the redirect whenever auth state changes.
GoRouter createRouter(WidgetRef ref) {
  final listenable = _AuthStateListenable(ref.container);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: listenable,
    redirect: (context, state) {
      final authState = ref.read(authNotifierProvider);
      final location = state.matchedLocation;

      final isAuthRoute = location == AppRoutes.login ||
          location == AppRoutes.signup ||
          location == AppRoutes.verifyEmail ||
          location == AppRoutes.resetPassword ||
          location == AppRoutes.resetPasswordConfirm;

      switch (authState.status) {
        case AuthStatus.unknown:
          // Always show splash during bootstrap.
          return location == AppRoutes.splash ? null : AppRoutes.splash;

        case AuthStatus.unauthenticated:
          // Allow auth routes; redirect everything else to login.
          if (location == AppRoutes.splash || isAuthRoute) return null;
          return AppRoutes.login;

        case AuthStatus.verifiedNoWorkspace:
          // Must create a workspace before accessing shell.
          if (location == AppRoutes.workspaceCreate) return null;
          return AppRoutes.workspaceCreate;

        case AuthStatus.ready:
          // Fully authenticated — redirect splash/auth routes to shell.
          if (location == AppRoutes.splash ||
              isAuthRoute ||
              location == AppRoutes.workspaceCreate) {
            return AppRoutes.shell;
          }
          return null;
      }
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: AppRoutes.signup,
        builder: (context, state) => const SignupPage(),
      ),
      GoRoute(
        path: AppRoutes.verifyEmail,
        builder: (context, state) {
          final email = state.uri.queryParameters['email'] ?? '';
          return EmailVerificationPendingPage(email: email);
        },
      ),
      GoRoute(
        path: AppRoutes.resetPassword,
        builder: (context, state) => const PasswordResetRequestPage(),
      ),
      GoRoute(
        path: AppRoutes.resetPasswordConfirm,
        builder: (context, state) => const PasswordResetConfirmPage(),
      ),
      GoRoute(
        path: AppRoutes.workspaceCreate,
        builder: (context, state) => const CreateWorkspacePage(),
      ),
      GoRoute(
        path: AppRoutes.shell,
        builder: (context, state) => const RootShell(),
      ),
    ],
  );
}

/// Bridges Riverpod's [authNotifierProvider] to GoRouter's refreshListenable.
///
/// GoRouter requires a [Listenable]; Riverpod providers are not directly
/// Listenable. This class listens to the provider via a [ProviderContainer]
/// and notifies GoRouter whenever auth state changes.
class _AuthStateListenable extends ChangeNotifier {
  _AuthStateListenable(ProviderContainer container) {
    // ProviderContainer.listen returns a ProviderSubscription.
    _subscription = container.listen<AuthState>(
      authNotifierProvider,
      (previous, next) => notifyListeners(),
    );
  }

  late final ProviderSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}

/// Provider for the GoRouter instance.
final routerProvider = Provider<GoRouter>((ref) {
  throw UnimplementedError(
    'routerProvider must be overridden with createRouter(ref)',
  );
});
