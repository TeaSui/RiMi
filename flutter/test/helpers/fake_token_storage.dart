import 'package:rimi/core/auth/token_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// In-memory token storage for tests. Does not touch FlutterSecureStorage.
/// Fulfills CLIENT-01 contract (tokens in secure storage) by providing
/// a testable substitute that doesn't require platform channels.
class FakeTokenStorage extends TokenStorage {
  FakeTokenStorage([Map<String, String>? initial])
      : _store = initial ?? {},
        super(const FlutterSecureStorage());

  final Map<String, String> _store;

  static const _access = 'rimi.access_token';
  static const _refresh = 'rimi.refresh_token';
  static const _wsId = 'rimi.active_workspace_id';

  @override
  Future<void> storeTokens({
    required String accessToken,
    required String refreshToken,
    String? activeWorkspaceId,
  }) async {
    _store[_access] = accessToken;
    _store[_refresh] = refreshToken;
    if (activeWorkspaceId != null) {
      _store[_wsId] = activeWorkspaceId;
    }
  }

  @override
  Future<void> storeActiveWorkspaceId(String? workspaceId) async {
    if (workspaceId == null) {
      _store.remove(_wsId);
    } else {
      _store[_wsId] = workspaceId;
    }
  }

  @override
  Future<String?> getAccessToken() async => _store[_access];

  @override
  Future<String?> getRefreshToken() async => _store[_refresh];

  @override
  Future<String?> getActiveWorkspaceId() async => _store[_wsId];

  @override
  Future<void> clearAll() async {
    _store.remove(_access);
    _store.remove(_refresh);
    _store.remove(_wsId);
  }

  /// Seed initial tokens for session-restore tests.
  void seed({
    required String accessToken,
    required String refreshToken,
    String? activeWorkspaceId,
  }) {
    _store[_access] = accessToken;
    _store[_refresh] = refreshToken;
    if (activeWorkspaceId != null) _store[_wsId] = activeWorkspaceId;
  }

  bool get isEmpty => _store.isEmpty;
}
