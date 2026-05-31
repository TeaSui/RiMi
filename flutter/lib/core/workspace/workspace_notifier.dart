import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_notifier.dart';
import '../auth/token_storage.dart';
import 'workspace_repository.dart';

/// State for the workspace list provider.
class WorkspaceListState {
  const WorkspaceListState({
    this.workspaces = const [],
    this.isLoading = false,
    this.error,
  });

  final List<WorkspaceModel> workspaces;
  final bool isLoading;
  final String? error;

  WorkspaceListState copyWith({
    List<WorkspaceModel>? workspaces,
    bool? isLoading,
    String? error,
  }) =>
      WorkspaceListState(
        workspaces: workspaces ?? this.workspaces,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

/// Notifier that manages workspace list and switch operations.
class WorkspaceNotifier extends Notifier<WorkspaceListState> {
  @override
  WorkspaceListState build() => const WorkspaceListState();

  WorkspaceRepository get _repo => ref.read(workspaceRepositoryProvider);
  TokenStorage get _storage => ref.read(tokenStorageProvider);
  AuthNotifier get _authNotifier => ref.read(authNotifierProvider.notifier);

  /// Loads the workspace list from the API.
  Future<void> loadWorkspaces() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final workspaces = await _repo.listWorkspaces();
      state = WorkspaceListState(workspaces: workspaces);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Không thể tải danh sách cửa hàng.',
      );
    }
  }

  /// Creates a new workspace and stores the re-issued scoped access token.
  /// On success, updates auth state to ready.
  Future<void> createWorkspace(String name) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _repo.createWorkspace(name: name);
      // Store the new workspace-scoped token (only access token changes — CLIENT-04).
      final refresh = await _storage.getRefreshToken();
      if (refresh != null) {
        await _storage.storeTokens(
          accessToken: result.accessToken,
          refreshToken: refresh,
          activeWorkspaceId: result.workspace.id,
        );
      }
      await _authNotifier.setActiveWorkspace(result.workspace.id, result.accessToken);
      state = WorkspaceListState(workspaces: [result.workspace]);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Không thể tạo cửa hàng. Vui lòng thử lại.',
      );
    }
  }

  /// Switches to the target workspace, stores the new scoped access token.
  Future<void> switchWorkspace(String workspaceId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _repo.switchWorkspace(workspaceId);
      final refresh = await _storage.getRefreshToken();
      if (refresh != null) {
        await _storage.storeTokens(
          accessToken: result.accessToken,
          refreshToken: refresh,
          activeWorkspaceId: result.workspace.id,
        );
      }
      await _authNotifier.setActiveWorkspace(result.workspace.id, result.accessToken);
      // Refresh the workspace list to reflect changes.
      await loadWorkspaces();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Không thể chuyển cửa hàng. Vui lòng thử lại.',
      );
    }
  }
}

final workspaceNotifierProvider =
    NotifierProvider<WorkspaceNotifier, WorkspaceListState>(WorkspaceNotifier.new);
