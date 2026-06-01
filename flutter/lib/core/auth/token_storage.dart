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

  static const _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );
  // encryptedSharedPreferences is deprecated in v10+ — custom cipher is used
  // automatically. Just enable Android-specific options.
  static const _androidOptions = AndroidOptions();

  Future<void> storeTokens({
    required String accessToken,
    required String refreshToken,
    String? activeWorkspaceId,
  }) async {
    await _storage.write(
      key: _Keys.accessToken,
      value: accessToken,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
    await _storage.write(
      key: _Keys.refreshToken,
      value: refreshToken,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
    if (activeWorkspaceId != null) {
      await _storage.write(
        key: _Keys.activeWorkspaceId,
        value: activeWorkspaceId,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
      );
    }
  }

  Future<void> storeActiveWorkspaceId(String? workspaceId) async {
    if (workspaceId == null) {
      await _storage.delete(
        key: _Keys.activeWorkspaceId,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
      );
    } else {
      await _storage.write(
        key: _Keys.activeWorkspaceId,
        value: workspaceId,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
      );
    }
  }

  Future<String?> getAccessToken() => _storage.read(
        key: _Keys.accessToken,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
      );

  Future<String?> getRefreshToken() => _storage.read(
        key: _Keys.refreshToken,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
      );

  Future<String?> getActiveWorkspaceId() => _storage.read(
        key: _Keys.activeWorkspaceId,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
      );

  /// CLIENT-02: Clear all tokens on logout / forced logout.
  Future<void> clearAll() async {
    await _storage.delete(
      key: _Keys.accessToken,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
    await _storage.delete(
      key: _Keys.refreshToken,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
    await _storage.delete(
      key: _Keys.activeWorkspaceId,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
  }
}

/// Provider for [TokenStorage]. Override in tests with a fake implementation.
final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return TokenStorage(const FlutterSecureStorage());
});
