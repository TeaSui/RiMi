import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_config.dart';
import '../auth/token_storage.dart';
import 'auth_interceptor.dart';

/// Creates and configures the app-wide Dio instance.
///
/// One Dio instance per app lifecycle (provided via Riverpod).
/// The auth interceptor is wired in to handle bearer injection and
/// single-flight 401 refresh (CLIENT-03).
Dio createDio({
  required TokenStorage tokenStorage,
  void Function()? onForceLogout,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBase,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  dio.interceptors.add(
    AuthInterceptor(
      tokenStorage: tokenStorage,
      dio: dio,
      onForceLogout: onForceLogout,
    ),
  );

  return dio;
}

/// Provider for the singleton Dio instance.
///
/// Wire [onForceLogout] after the auth notifier is available, or use the
/// [dioClientProvider] override in tests.
final dioClientProvider = Provider<Dio>((ref) {
  final tokenStorage = ref.watch(tokenStorageProvider);
  return createDio(tokenStorage: tokenStorage);
});
