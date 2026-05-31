import 'dart:async';
import 'package:dio/dio.dart';
import '../auth/token_storage.dart';

/// Injects the bearer access token on every request that needs auth.
/// On 401, performs a SINGLE-FLIGHT token refresh:
///  - All concurrent 401s queue until the refresh completes.
///  - On success: replay all queued requests with the new token.
///  - On failure: force logout (clear storage) and reject all queued requests.
///
/// This satisfies CLIENT-03 (single-flight refresh, no spam / race condition).
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required TokenStorage tokenStorage,
    required Dio dio,
    void Function()? onForceLogout,
  })  : _tokenStorage = tokenStorage,
        _dio = dio,
        _onForceLogout = onForceLogout;

  final TokenStorage _tokenStorage;
  final Dio _dio;
  final void Function()? _onForceLogout;

  bool _isRefreshing = false;
  final List<_PendingRequest> _queue = [];

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Skip token injection for the refresh endpoint itself to avoid loops.
    if (options.extra['skipAuth'] == true) {
      return handler.next(options);
    }

    final token = await _tokenStorage.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final statusCode = err.response?.statusCode;

    // Only handle 401 on non-refresh endpoints.
    if (statusCode != 401 || err.requestOptions.extra['skipAuth'] == true) {
      return handler.next(err);
    }

    final refreshToken = await _tokenStorage.getRefreshToken();
    if (refreshToken == null) {
      await _forceLogout();
      return handler.reject(err);
    }

    if (_isRefreshing) {
      // Queue this request for replay after the in-flight refresh completes.
      final completer = Completer<Response<dynamic>>();
      _queue.add(_PendingRequest(err.requestOptions, completer));
      try {
        final response = await completer.future;
        return handler.resolve(response);
      } catch (e) {
        return handler.reject(err);
      }
    }

    _isRefreshing = true;

    try {
      // Perform single refresh call (skipAuth prevents recursion).
      final refreshResponse = await _dio.post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
        options: Options(extra: {'skipAuth': true}),
      );

      final tokenPair = _extractTokenPair(refreshResponse.data);
      if (tokenPair == null) throw Exception('Invalid refresh response');

      await _tokenStorage.storeTokens(
        accessToken: tokenPair['access_token'] as String,
        refreshToken: tokenPair['refresh_token'] as String,
        activeWorkspaceId: tokenPair['active_workspace_id'] as String?,
      );

      // Replay the original failing request with the new token.
      final newToken = tokenPair['access_token'] as String;
      final originalRequest = err.requestOptions;
      originalRequest.headers['Authorization'] = 'Bearer $newToken';

      // Replay all queued requests.
      for (final pending in _queue) {
        pending.options.headers['Authorization'] = 'Bearer $newToken';
        try {
          final response = await _dio.fetch<dynamic>(pending.options);
          pending.completer.complete(response);
        } catch (e) {
          pending.completer.completeError(e);
        }
      }
      _queue.clear();

      final response = await _dio.fetch<dynamic>(originalRequest);
      return handler.resolve(response);
    } on DioException catch (e) {
      // Refresh failed — force logout and reject everything queued.
      for (final pending in _queue) {
        pending.completer.completeError(e);
      }
      _queue.clear();
      await _forceLogout();
      return handler.reject(err);
    } catch (e) {
      for (final pending in _queue) {
        pending.completer.completeError(e);
      }
      _queue.clear();
      await _forceLogout();
      return handler.reject(err);
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> _forceLogout() async {
    await _tokenStorage.clearAll();
    _onForceLogout?.call();
  }

  /// Extracts the TokenPair map from the API success envelope.
  Map<String, dynamic>? _extractTokenPair(dynamic data) {
    if (data is Map<String, dynamic>) {
      final d = data['data'];
      if (d is Map<String, dynamic>) {
        // Direct token pair (login/refresh response).
        if (d.containsKey('access_token')) return d;
        // Workspace create/switch: tokens nested under 'tokens'.
        if (d.containsKey('tokens') && d['tokens'] is Map<String, dynamic>) {
          return d['tokens'] as Map<String, dynamic>;
        }
      }
    }
    return null;
  }
}

class _PendingRequest {
  _PendingRequest(this.options, this.completer);
  final RequestOptions options;
  final Completer<Response<dynamic>> completer;
}
