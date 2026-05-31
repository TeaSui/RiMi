import 'package:dio/dio.dart';

/// Minimal Dio factory for widget tests that don't hit the network.
/// Returns 404 for all requests (safe default — auth interceptor
/// will not 401-loop because these tests override the auth notifier).
class FakeDio {
  static Dio create() {
    final dio = Dio(
      BaseOptions(baseUrl: 'http://localhost:8080/v1'),
    );
    dio.interceptors.add(_AlwaysErrorInterceptor());
    return dio;
  }
}

class _AlwaysErrorInterceptor extends Interceptor {
  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    handler.reject(
      DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'FakeDio — no network in tests',
      ),
    );
  }
}

/// A Dio that returns pre-programmed responses for specific paths.
/// Use this in auth-flow tests.
class ScriptedDio {
  ScriptedDio(this._responses);

  /// Map of path → response factory.
  final Map<String, Response<dynamic> Function(RequestOptions)> _responses;

  Dio build() {
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080/v1'));
    dio.interceptors.add(_ScriptedInterceptor(_responses));
    return dio;
  }
}

class _ScriptedInterceptor extends Interceptor {
  _ScriptedInterceptor(this._responses);
  final Map<String, Response<dynamic> Function(RequestOptions)> _responses;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    final path = options.path;
    final factory = _responses[path];
    if (factory != null) {
      handler.resolve(factory(options));
    } else {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: 'ScriptedDio — no handler for $path',
        ),
      );
    }
  }
}
