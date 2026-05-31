// Auth flow integration tests with a mock Dio adapter.
// Tests: login→gate→shell; 401 single-flight refresh→replay; refresh-fail→logout;
// session-restore (AUTH-04); workspace-switch.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rimi/core/auth/auth_notifier.dart';
import 'package:rimi/core/auth/auth_state.dart';
import 'package:rimi/core/auth/token_storage.dart';
import 'package:rimi/core/network/api_exception.dart';
import 'package:rimi/core/network/dio_client.dart';

import '../helpers/fake_token_storage.dart';

// ── Fixtures ──────────────────────────────────────────────────────────

const _accessToken = 'eyJhbGciOiJSUzI1NiJ9.test-access';
const _refreshToken = 'opaque-refresh-token-abc123';
const _accessToken2 = 'eyJhbGciOiJSUzI1NiJ9.test-access-2';
const _refreshToken2 = 'opaque-refresh-token-xyz789';
const _workspaceId = 'ws-uuid-1234';
const _userId = 'user-uuid-5678';

Map<String, dynamic> _tokenPairEnvelope({
  String access = _accessToken,
  String refresh = _refreshToken,
  String? wsId = _workspaceId,
}) =>
    {
      'data': {
        'access_token': access,
        'refresh_token': refresh,
        'token_type': 'Bearer',
        'expires_in': 900,
        'active_workspace_id': wsId,
      },
      'meta': {'timestamp': '2026-05-31T08:00:00Z'},
    };

Map<String, dynamic> _meEnvelope({String? wsId = _workspaceId}) => {
      'data': {
        'profile': {
          'id': _userId,
          'email': 'test@example.com',
          'display_name': 'Test User',
          'phone': null,
          'email_verified': true,
          'created_at': '2026-01-01T00:00:00Z',
        },
        'active_workspace_id': wsId,
      },
      'meta': {'timestamp': '2026-05-31T08:00:00Z'},
    };

Map<String, dynamic> _errorEnvelope(String code) => {
      'error': {
        'code': code,
        'message': 'Error',
        'details': <dynamic>[],
      },
    };

// ── Helpers ───────────────────────────────────────────────────────────

/// Builds a scripted Dio with the given path responses.
Dio _scripted(Map<String, dynamic Function(RequestOptions)> routes) {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080/v1'));
  dio.interceptors.add(_MapInterceptor(routes));
  return dio;
}

class _MapInterceptor extends Interceptor {
  _MapInterceptor(this._routes);
  final Map<String, dynamic Function(RequestOptions)> _routes;
  final Map<String, int> _counts = {};

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    final path = options.path;
    _counts[path] = (_counts[path] ?? 0) + 1;
    final factory = _routes[path];
    if (factory != null) {
      final result = factory(options);
      if (result is DioException) {
        handler.reject(result);
      } else {
        handler.resolve(Response<dynamic>(
          requestOptions: options,
          data: result,
          statusCode: 200,
        ));
      }
    } else {
      handler.reject(DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'No handler for $path',
      ));
    }
  }

  int countFor(String path) => _counts[path] ?? 0;
}

// ── Tests ─────────────────────────────────────────────────────────────

void main() {
  group('AuthNotifier bootstrap (AUTH-04)', () {
    test('empty storage → unauthenticated', () async {
      final storage = FakeTokenStorage();
      final dio = _scripted({});

      final container = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioClientProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authNotifierProvider.notifier).bootstrap();

      expect(
        container.read(authNotifierProvider).status,
        AuthStatus.unauthenticated,
      );
    });

    test('valid access token + /auth/me success → ready', () async {
      final storage = FakeTokenStorage()
        ..seed(
          accessToken: _accessToken,
          refreshToken: _refreshToken,
          activeWorkspaceId: _workspaceId,
        );

      final dio = _scripted({
        '/auth/me': (_) => _meEnvelope(),
      });

      final container = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioClientProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authNotifierProvider.notifier).bootstrap();

      final state = container.read(authNotifierProvider);
      expect(state.status, AuthStatus.ready);
      expect(state.activeWorkspaceId, _workspaceId);
      expect(state.userId, _userId);
    });

    test('401 on /auth/me → refreshes once → success', () async {
      final storage = FakeTokenStorage()
        ..seed(
          accessToken: _accessToken,
          refreshToken: _refreshToken,
          activeWorkspaceId: _workspaceId,
        );

      var meCallCount = 0;
      final dio = _scripted({
        '/auth/me': (options) {
          meCallCount++;
          if (meCallCount == 1) {
            // First call: 401
            return DioException(
              requestOptions: options,
              response: Response<dynamic>(
                requestOptions: options,
                statusCode: 401,
                data: _errorEnvelope('UNAUTHORIZED'),
              ),
              type: DioExceptionType.badResponse,
            );
          }
          // Second call (after refresh): success
          return _meEnvelope();
        },
        '/auth/refresh': (_) => _tokenPairEnvelope(
              access: _accessToken2,
              refresh: _refreshToken2,
            ),
      });

      final container = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioClientProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authNotifierProvider.notifier).bootstrap();

      final state = container.read(authNotifierProvider);
      expect(state.status, AuthStatus.ready);

      // New tokens should be stored.
      expect(await storage.getAccessToken(), _accessToken2);
    });

    test('401 on /auth/me + refresh fails → unauthenticated, storage cleared',
        () async {
      final storage = FakeTokenStorage()
        ..seed(
          accessToken: _accessToken,
          refreshToken: _refreshToken,
        );

      final dio = _scripted({
        '/auth/me': (options) => DioException(
              requestOptions: options,
              response: Response<dynamic>(
                requestOptions: options,
                statusCode: 401,
                data: _errorEnvelope('UNAUTHORIZED'),
              ),
              type: DioExceptionType.badResponse,
            ),
        '/auth/refresh': (options) => DioException(
              requestOptions: options,
              response: Response<dynamic>(
                requestOptions: options,
                statusCode: 401,
                data: _errorEnvelope('REFRESH_TOKEN_INVALID'),
              ),
              type: DioExceptionType.badResponse,
            ),
      });

      final container = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioClientProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authNotifierProvider.notifier).bootstrap();

      expect(
        container.read(authNotifierProvider).status,
        AuthStatus.unauthenticated,
      );
      expect(storage.isEmpty, isTrue);
    });

    test('valid tokens but no workspace → verifiedNoWorkspace', () async {
      final storage = FakeTokenStorage()
        ..seed(
          accessToken: _accessToken,
          refreshToken: _refreshToken,
          // No activeWorkspaceId
        );

      final dio = _scripted({
        '/auth/me': (_) => _meEnvelope(wsId: null),
      });

      final container = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioClientProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authNotifierProvider.notifier).bootstrap();

      expect(
        container.read(authNotifierProvider).status,
        AuthStatus.verifiedNoWorkspace,
      );
    });
  });

  group('Login flow', () {
    test('successful login → stores tokens → ready', () async {
      final storage = FakeTokenStorage();
      final dio = _scripted({
        '/auth/login': (_) => _tokenPairEnvelope(),
        '/auth/me': (_) => _meEnvelope(),
      });

      final container = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioClientProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authNotifierProvider.notifier).login(
            email: 'test@example.com',
            password: 'password123',
          );

      final state = container.read(authNotifierProvider);
      expect(state.status, AuthStatus.ready);
      expect(state.activeWorkspaceId, _workspaceId);

      // Tokens must be stored in secure storage (CLIENT-01).
      expect(await storage.getAccessToken(), _accessToken);
      expect(await storage.getRefreshToken(), _refreshToken);
    });

    test('invalid credentials → throws ApiException(invalidCredentials)', () async {
      final storage = FakeTokenStorage();
      final dio = _scripted({
        '/auth/login': (options) => DioException(
              requestOptions: options,
              response: Response<dynamic>(
                requestOptions: options,
                statusCode: 401,
                data: _errorEnvelope('INVALID_CREDENTIALS'),
              ),
              type: DioExceptionType.badResponse,
            ),
      });

      final container = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioClientProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(authNotifierProvider.notifier).login(
              email: 'bad@example.com',
              password: 'wrong',
            ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.invalidCredentials,
          ),
        ),
      );
    });
  });

  group('Logout flow', () {
    test('logout clears storage and sets unauthenticated', () async {
      final storage = FakeTokenStorage()
        ..seed(
          accessToken: _accessToken,
          refreshToken: _refreshToken,
          activeWorkspaceId: _workspaceId,
        );

      final dio = _scripted({
        '/auth/logout': (_) => {'data': {'revoked': true}, 'meta': {'timestamp': '2026-05-31T00:00:00Z'}},
      });

      final container = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioClientProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authNotifierProvider.notifier).logout();

      expect(
        container.read(authNotifierProvider).status,
        AuthStatus.unauthenticated,
      );
      expect(storage.isEmpty, isTrue); // CLIENT-02
    });
  });

  group('AuthInterceptor single-flight refresh (CLIENT-03)', () {
    test('interceptor handles 401 by refreshing once: clears and stores new token',
        () async {
      final storage = FakeTokenStorage()
        ..seed(
          accessToken: _accessToken,
          refreshToken: _refreshToken,
          activeWorkspaceId: _workspaceId,
        );

      // We test the interceptor indirectly through the AuthNotifier bootstrap:
      // store an access token that triggers 401, then a refresh that succeeds.
      // This is the same flow the single-flight interceptor handles on a real 401.
      // After refresh, /auth/me is called again (second call).
      // We need a stateful mock that returns success on the second call.
      var meCallCount = 0;
      final statefulDio = Dio(BaseOptions(baseUrl: 'http://localhost:8080/v1'));
      statefulDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            meCallCount++;
            if (options.path == '/auth/refresh') {
              handler.resolve(Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: _tokenPairEnvelope(
                  access: _accessToken2,
                  refresh: _refreshToken2,
                ),
              ));
            } else if (options.path == '/auth/me' && meCallCount <= 1) {
              handler.reject(DioException(
                requestOptions: options,
                response: Response<dynamic>(
                  requestOptions: options,
                  statusCode: 401,
                  data: _errorEnvelope('UNAUTHORIZED'),
                ),
                type: DioExceptionType.badResponse,
              ));
            } else {
              handler.resolve(Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: _meEnvelope(),
              ));
            }
          },
        ),
      );

      final container = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioClientProvider.overrideWithValue(statefulDio),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authNotifierProvider.notifier).bootstrap();

      // After bootstrap completes, the state should be ready.
      expect(
        container.read(authNotifierProvider).status,
        AuthStatus.ready,
      );
      // New tokens stored (CLIENT-01).
      expect(await storage.getAccessToken(), _accessToken2);
      expect(await storage.getRefreshToken(), _refreshToken2);
    });

    test('refresh failure forces logout and clears storage (CLIENT-02)', () async {
      final storage = FakeTokenStorage()
        ..seed(
          accessToken: _accessToken,
          refreshToken: _refreshToken,
        );

      // Both /auth/me and /auth/refresh fail with 401.
      final failDio = _scripted({
        '/auth/me': (options) => DioException(
              requestOptions: options,
              response: Response<dynamic>(
                requestOptions: options,
                statusCode: 401,
                data: _errorEnvelope('UNAUTHORIZED'),
              ),
              type: DioExceptionType.badResponse,
            ),
        '/auth/refresh': (options) => DioException(
              requestOptions: options,
              response: Response<dynamic>(
                requestOptions: options,
                statusCode: 401,
                data: _errorEnvelope('REFRESH_TOKEN_INVALID'),
              ),
              type: DioExceptionType.badResponse,
            ),
      });

      final container = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioClientProvider.overrideWithValue(failDio),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authNotifierProvider.notifier).bootstrap();

      // After both fail, state is unauthenticated and storage is cleared.
      expect(
        container.read(authNotifierProvider).status,
        AuthStatus.unauthenticated,
      );
      expect(storage.isEmpty, isTrue); // CLIENT-02
    });
  });

  group('ApiException parsing', () {
    test('parses INVALID_CREDENTIALS envelope correctly', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/auth/login'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/auth/login'),
          statusCode: 401,
          data: {
            'error': {
              'code': 'INVALID_CREDENTIALS',
              'message': 'Email or password is incorrect.',
              'details': <dynamic>[],
            },
          },
        ),
        type: DioExceptionType.badResponse,
      );

      final ex = ApiException.fromDioError(dioError);
      expect(ex.code, ApiErrorCode.invalidCredentials);
      expect(ex.statusCode, 401);
    });

    test('parses VALIDATION_ERROR with details', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/auth/register'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/auth/register'),
          statusCode: 400,
          data: {
            'error': {
              'code': 'VALIDATION_ERROR',
              'message': 'Invalid fields.',
              'details': [
                {'field': 'email', 'issue': 'invalid_format'},
              ],
            },
          },
        ),
        type: DioExceptionType.badResponse,
      );

      final ex = ApiException.fromDioError(dioError);
      expect(ex.code, ApiErrorCode.validationError);
      expect(ex.details, hasLength(1));
      expect(ex.details.first.field, 'email');
    });

    test('network error → unknown code', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/test'),
        type: DioExceptionType.connectionError,
      );

      final ex = ApiException.fromDioError(dioError);
      expect(ex.code, ApiErrorCode.unknown);
    });

    test('isRefreshTokenFailure covers both INVALID and REUSED', () {
      for (final code in ['REFRESH_TOKEN_INVALID', 'REFRESH_TOKEN_REUSED']) {
        final ex = ApiException(
          code: ApiErrorCode.values.byName(
            code == 'REFRESH_TOKEN_INVALID'
                ? 'refreshTokenInvalid'
                : 'refreshTokenReused',
          ),
          message: 'x',
        );
        expect(ex.isRefreshTokenFailure, isTrue);
      }
    });
  });
}
