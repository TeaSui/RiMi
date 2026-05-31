import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_exception.dart';
import '../network/dio_client.dart';

/// Data container for the token pair returned by login/refresh/create-workspace.
class TokenPairData {
  const TokenPairData({
    required this.accessToken,
    required this.refreshToken,
    required this.activeWorkspaceId,
  });

  final String accessToken;
  final String refreshToken;
  final String? activeWorkspaceId;

  factory TokenPairData.fromJson(Map<String, dynamic> json) {
    return TokenPairData(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      activeWorkspaceId: json['active_workspace_id'] as String?,
    );
  }
}

/// Profile data returned by GET /auth/me.
class MeData {
  const MeData({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.emailVerified,
    required this.activeWorkspaceId,
  });

  final String userId;
  final String email;
  final String displayName;
  final bool emailVerified;
  final String? activeWorkspaceId;
}

/// REST repository for auth endpoints.
/// Maps Dio errors to typed [ApiException].
class AuthRepository {
  const AuthRepository(this._dio);

  final Dio _dio;

  /// POST /auth/register — returns registered: true (anti-enumeration).
  Future<void> register({
    required String email,
    required String password,
    required String displayName,
    String? phone,
  }) async {
    try {
      await _dio.post(
        '/auth/register',
        data: {
          'email': email,
          'password': password,
          'display_name': displayName,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
        },
      );
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// POST /auth/verify-email — token submitted in request body (EMAIL-06).
  Future<void> verifyEmail(String token) async {
    try {
      await _dio.post('/auth/verify-email', data: {'token': token});
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// POST /auth/login — returns [TokenPairData].
  Future<TokenPairData> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      final data = response.data!['data'] as Map<String, dynamic>;
      return TokenPairData.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// POST /auth/refresh — single-use rotation. Errors handled by interceptor
  /// normally; this direct call is used during bootstrap (skipAuth).
  Future<TokenPairData> refresh(String refreshToken) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
        options: Options(extra: {'skipAuth': true}),
      );
      final data = response.data!['data'] as Map<String, dynamic>;
      return TokenPairData.fromJson(data);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// POST /auth/logout — server-side revocation; idempotent.
  Future<void> logout(String refreshToken) async {
    try {
      await _dio.post(
        '/auth/logout',
        data: {'refresh_token': refreshToken},
        options: Options(extra: {'skipAuth': true}),
      );
    } on DioException catch (_) {
      // Best-effort: even if server call fails, client clears storage.
    }
  }

  /// POST /auth/password-reset/request — always returns sent: true.
  Future<void> requestPasswordReset(String email) async {
    try {
      await _dio.post(
        '/auth/password-reset/request',
        data: {'email': email},
      );
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// POST /auth/password-reset/confirm — token + new_password in body (EMAIL-06).
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) async {
    try {
      await _dio.post(
        '/auth/password-reset/confirm',
        data: {'token': token, 'new_password': newPassword},
      );
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// GET /auth/me — hydrates session for cold-start bootstrap (AUTH-04).
  Future<MeData> getMe() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/auth/me');
      final data = response.data!['data'] as Map<String, dynamic>;
      final profile = data['profile'] as Map<String, dynamic>;
      return MeData(
        userId: profile['id'] as String,
        email: profile['email'] as String,
        displayName: profile['display_name'] as String,
        emailVerified: profile['email_verified'] as bool,
        activeWorkspaceId: data['active_workspace_id'] as String?,
      );
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(dioClientProvider));
});
