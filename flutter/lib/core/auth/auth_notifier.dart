import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_exception.dart';
import 'auth_repository.dart';
import 'auth_state.dart';
import 'token_storage.dart';

/// Riverpod Notifier that owns the auth state machine.
///
/// Cold-start bootstrap (AUTH-04):
///   1. SplashPage calls bootstrap().
///   2. Read stored tokens.
///   3. If access token present: GET /auth/me.
///   4. On 401: try one refresh → GET /auth/me.
///   5. On failure: clear storage → unauthenticated.
///
/// The notifier is also the onForceLogout callback for the AuthInterceptor.
class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState.unknown();

  TokenStorage get _storage => ref.read(tokenStorageProvider);
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  /// Cold-start: try to restore session from secure storage.
  Future<void> bootstrap() async {
    state = const AuthState.unknown();

    try {
      // Hard 10-second timeout guards against Keychain deadlock on simulator.
      final accessToken = await _storage.getAccessToken()
          .timeout(const Duration(seconds: 10), onTimeout: () => null);
      if (accessToken == null) {
        state = const AuthState.unauthenticated();
        return;
      }

      MeData me;
      try {
        me = await _repo.getMe();
      } on ApiException catch (e) {
        if (e.isUnauthorized) {
          // One refresh attempt.
          final refreshToken = await _storage.getRefreshToken();
          if (refreshToken == null) {
            await _storage.clearAll();
            state = const AuthState.unauthenticated();
            return;
          }
          try {
            final tokens = await _repo.refresh(refreshToken);
            await _storage.storeTokens(
              accessToken: tokens.accessToken,
              refreshToken: tokens.refreshToken,
              activeWorkspaceId: tokens.activeWorkspaceId,
            );
            me = await _repo.getMe();
          } catch (_) {
            await _storage.clearAll();
            state = const AuthState.unauthenticated();
            return;
          }
        } else {
          rethrow;
        }
      }

      _applyMeState(me);
    } catch (_) {
      await _storage.clearAll();
      state = const AuthState.unauthenticated();
    }
  }

  /// Registers a new user; on success the user must verify their email.
  Future<void> register({
    required String email,
    required String password,
    required String displayName,
    String? phone,
  }) async {
    await _repo.register(
      email: email,
      password: password,
      displayName: displayName,
      phone: phone,
    );
    // Registration succeeded (202 accepted). User must verify email.
    // Do not store tokens — they aren't issued yet.
  }

  /// Logs in; stores tokens; updates state.
  Future<void> login({required String email, required String password}) async {
    final tokens = await _repo.login(email: email, password: password);
    await _storage.storeTokens(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      activeWorkspaceId: tokens.activeWorkspaceId,
    );
    final me = await _repo.getMe();
    _applyMeState(me);
  }

  /// Logs out: server-side revocation + client token clear (CLIENT-02).
  Future<void> logout() async {
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken != null) {
      await _repo.logout(refreshToken);
    }
    await _storage.clearAll();
    state = const AuthState.unauthenticated();
  }

  /// Called by AuthInterceptor when refresh fails — forces logout.
  void forceLogout() {
    state = const AuthState.unauthenticated();
  }

  /// Updates the active workspace id in state and storage.
  Future<void> setActiveWorkspace(String workspaceId, String newAccessToken) async {
    await _storage.storeActiveWorkspaceId(workspaceId);
    // Update stored access token with the new workspace-scoped one.
    final refresh = await _storage.getRefreshToken();
    if (refresh != null) {
      await _storage.storeTokens(
        accessToken: newAccessToken,
        refreshToken: refresh,
        activeWorkspaceId: workspaceId,
      );
    }
    state = state.copyWith(
      status: AuthStatus.ready,
      activeWorkspaceId: workspaceId,
    );
  }

  void _applyMeState(MeData me) {
    final wsId = me.activeWorkspaceId;
    state = AuthState(
      status: wsId != null ? AuthStatus.ready : AuthStatus.verifiedNoWorkspace,
      userId: me.userId,
      displayName: me.displayName,
      email: me.email,
      activeWorkspaceId: wsId,
    );
  }
}

final authNotifierProvider =
    NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
