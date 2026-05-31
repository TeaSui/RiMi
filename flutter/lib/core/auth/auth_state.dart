/// The auth state machine for the auth gate.
///
/// States map to router redirect decisions:
///   unknown         → /splash (bootstrapping in progress)
///   unauthenticated → /login (no valid session)
///   verifiedNoWs    → /workspace/create (email verified, no workspace yet)
///   ready           → /shell (fully authenticated, workspace active)
enum AuthStatus {
  /// Cold-start bootstrap in progress; router shows /splash.
  unknown,

  /// No valid session — access and refresh tokens absent or refresh failed.
  unauthenticated,

  /// Authenticated and email verified, but workspace_id claim is null.
  /// Router directs to /workspace/create.
  verifiedNoWorkspace,

  /// Fully authenticated with an active workspace. Router shows /shell.
  ready,
}

/// Immutable auth state snapshot used by the Riverpod notifier.
class AuthState {
  const AuthState({
    required this.status,
    this.userId,
    this.displayName,
    this.email,
    this.activeWorkspaceId,
  });

  const AuthState.unknown()
      : status = AuthStatus.unknown,
        userId = null,
        displayName = null,
        email = null,
        activeWorkspaceId = null;

  const AuthState.unauthenticated()
      : status = AuthStatus.unauthenticated,
        userId = null,
        displayName = null,
        email = null,
        activeWorkspaceId = null;

  final AuthStatus status;
  final String? userId;
  final String? displayName;
  final String? email;
  final String? activeWorkspaceId;

  AuthState copyWith({
    AuthStatus? status,
    String? userId,
    String? displayName,
    String? email,
    String? activeWorkspaceId,
    bool clearWorkspace = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      activeWorkspaceId:
          clearWorkspace ? null : (activeWorkspaceId ?? this.activeWorkspaceId),
    );
  }
}
