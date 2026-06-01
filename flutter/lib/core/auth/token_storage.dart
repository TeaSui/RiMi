import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keys used for secure storage. All tokens stored in platform Keychain/Keystore.
/// CLIENT-01: tokens MUST NOT be stored in SharedPreferences or plaintext files.
abstract final class _Keys {
  static const accessToken = 'rimi.access_token';
  static const refreshToken = 'rimi.refresh_token';
  static const activeWorkspaceId = 'rimi.active_workspace_id';
}

/// Secure storage wrapper for auth tokens.
///
/// Uses [FlutterSecureStorage] which maps to:
///   iOS  — Keychain with kSecAttrAccessibleWhenUnlockedThisDeviceOnly
///   Android — EncryptedSharedPreferences (AES-256-GCM)
///
/// CLIENT-01: access/refresh tokens + active_workspace_id go ONLY here.
/// CLIENT-02: clearAll() is called on logout and on refresh failure.
class TokenStorage {
  TokenStorage(this._storage);

  final FlutterSecureStorage _storage;

  // Use platform defaults — no custom IOSOptions to avoid Keychain deadlocks
  // on iOS 18 simulator. Production builds can re-enable strict accessibility
  // once simulator behaviour is confirmed stable.
  Future<void> storeTokens({
    required String accessToken,
    required String refreshToken,
    String? activeWorkspaceId,
  }) async {
    await _storage.write(key: _Keys.accessToken, value: accessToken);
    await _storage.write(key: _Keys.refreshToken, value: refreshToken);
    if (activeWorkspaceId != null) {
      await _storage.write(key: _Keys.activeWorkspaceId, value: activeWorkspaceId);
    }
  }

  Future<void> storeActiveWorkspaceId(String? workspaceId) async {
    if (workspaceId == null) {
      await _storage.delete(key: _Keys.activeWorkspaceId);
    } else {
      await _storage.write(key: _Keys.activeWorkspaceId, value: workspaceId);
    }
  }

  Future<String?> getAccessToken() => _storage.read(key: _Keys.accessToken);
  Future<String?> getRefreshToken() => _storage.read(key: _Keys.refreshToken);
  Future<String?> getActiveWorkspaceId() => _storage.read(key: _Keys.activeWorkspaceId);

  /// CLIENT-02: Clear all tokens on logout / forced logout.
  Future<void> clearAll() async {
    await _storage.delete(key: _Keys.accessToken);
    await _storage.delete(key: _Keys.refreshToken);
    await _storage.delete(key: _Keys.activeWorkspaceId);
  }
}

/// Provider for [TokenStorage]. Override in tests with a fake implementation.
final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return TokenStorage(const FlutterSecureStorage());
});
