// Workspace create and switch tests.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rimi/core/auth/auth_notifier.dart';
import 'package:rimi/core/auth/auth_state.dart';
import 'package:rimi/core/auth/token_storage.dart';
import 'package:rimi/core/network/dio_client.dart';
import 'package:rimi/core/workspace/workspace_notifier.dart';

import '../helpers/fake_token_storage.dart';

const _accessToken = 'eyJhbGciOiJSUzI1NiJ9.access';
const _refreshToken = 'refresh-opaque';
const _wsId = 'ws-uuid-abc';
const _wsId2 = 'ws-uuid-xyz';
const _userId = 'user-uuid-1';

Map<String, dynamic> _meEnvelope({String? wsId}) => {
      'data': {
        'profile': {
          'id': _userId,
          'email': 'user@example.com',
          'display_name': 'User',
          'phone': null,
          'email_verified': true,
          'created_at': '2026-01-01T00:00:00Z',
        },
        'active_workspace_id': wsId,
      },
      'meta': {'timestamp': '2026-05-31T00:00:00Z'},
    };

Map<String, dynamic> _wsCreatedEnvelope(String wsId, String name) => {
      'data': {
        'workspace': {
          'id': wsId,
          'name': name,
          'role': 'owner',
          'created_at': '2026-05-31T00:00:00Z',
        },
        'tokens': {
          'access_token': 'new-access-ws-$wsId',
          'refresh_token': _refreshToken,
          'token_type': 'Bearer',
          'expires_in': 900,
          'active_workspace_id': wsId,
        },
      },
      'meta': {'timestamp': '2026-05-31T00:00:00Z'},
    };

Map<String, dynamic> _wsSwitchedEnvelope(String wsId, String name) => {
      'data': {
        'workspace': {
          'id': wsId,
          'name': name,
          'role': 'member',
          'created_at': '2026-05-31T00:00:00Z',
        },
        'tokens': {
          'access_token': 'switched-access-$wsId',
          'refresh_token': _refreshToken,
          'token_type': 'Bearer',
          'expires_in': 900,
          'active_workspace_id': wsId,
        },
      },
      'meta': {'timestamp': '2026-05-31T00:00:00Z'},
    };

Map<String, dynamic> _wsListEnvelope(List<Map<String, dynamic>> wsList) => {
      'data': {'workspaces': wsList},
      'meta': {'timestamp': '2026-05-31T00:00:00Z'},
    };

Dio _scripted(Map<String, dynamic Function(RequestOptions)> routes) {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080/v1'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        // Match POST /workspaces/{id}/switch.
        for (final entry in routes.entries) {
          if (options.path == entry.key ||
              (entry.key.contains('{id}') &&
                  options.path
                      .contains(entry.key.replaceAll('{id}', '')))) {
            final result = entry.value(options);
            if (result is DioException) {
              handler.reject(result);
            } else {
              handler.resolve(Response<dynamic>(
                requestOptions: options,
                data: result,
                statusCode: 200,
              ));
            }
            return;
          }
        }
        handler.reject(DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: 'No handler for ${options.path}',
        ));
      },
    ),
  );
  return dio;
}

void main() {
  group('WorkspaceNotifier.createWorkspace (AUTH-05)', () {
    test('creates workspace, stores new access token, auth state → ready',
        () async {
      final storage = FakeTokenStorage()
        ..seed(
          accessToken: _accessToken,
          refreshToken: _refreshToken,
        );

      final dio = _scripted({
        '/workspaces': (_) => _wsCreatedEnvelope(_wsId, 'Phở Hà Nội'),
        '/auth/me': (_) => _meEnvelope(wsId: _wsId),
      });

      final container = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioClientProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      // Simulate post-login state.
      container.read(authNotifierProvider.notifier);

      await container
          .read(workspaceNotifierProvider.notifier)
          .createWorkspace('Phở Hà Nội');

      final authState = container.read(authNotifierProvider);
      expect(authState.status, AuthStatus.ready);
      expect(authState.activeWorkspaceId, _wsId);

      // New access token stored (CLIENT-01, CLIENT-04).
      expect(await storage.getAccessToken(), 'new-access-ws-$_wsId');
      // Refresh token unchanged (session-scoped, not workspace-scoped per ADR-001).
      expect(await storage.getRefreshToken(), _refreshToken);
    });
  });

  group('WorkspaceNotifier.switchWorkspace (AUTH-06)', () {
    test('switches workspace, stores new access token, auth state updated',
        () async {
      final storage = FakeTokenStorage()
        ..seed(
          accessToken: _accessToken,
          refreshToken: _refreshToken,
          activeWorkspaceId: _wsId,
        );

      // Seed initial auth state as ready.
      final wsList = [
        {
          'id': _wsId,
          'name': 'Phở Hà Nội',
          'role': 'owner',
          'created_at': '2026-05-31T00:00:00Z',
        },
        {
          'id': _wsId2,
          'name': 'Bún Bò',
          'role': 'member',
          'created_at': '2026-05-31T00:00:00Z',
        },
      ];

      final dio = _scripted({
        '/workspaces': (_) => _wsListEnvelope(wsList),
        '/workspaces/$_wsId2/switch': (_) =>
            _wsSwitchedEnvelope(_wsId2, 'Bún Bò'),
      });

      final container = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioClientProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(workspaceNotifierProvider.notifier)
          .switchWorkspace(_wsId2);

      final authState = container.read(authNotifierProvider);
      expect(authState.activeWorkspaceId, _wsId2);

      expect(await storage.getAccessToken(), 'switched-access-$_wsId2');
      expect(await storage.getRefreshToken(), _refreshToken); // unchanged
      expect(await storage.getActiveWorkspaceId(), _wsId2);
    });
  });

  group('WorkspaceNotifier.loadWorkspaces', () {
    test('populates workspace list from API', () async {
      final storage = FakeTokenStorage()
        ..seed(accessToken: _accessToken, refreshToken: _refreshToken);

      final wsList = [
        {
          'id': _wsId,
          'name': 'Shop A',
          'role': 'owner',
          'created_at': '2026-05-31T00:00:00Z',
        },
      ];

      final dio = _scripted({
        '/workspaces': (_) => _wsListEnvelope(wsList),
      });

      final container = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
          dioClientProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      await container.read(workspaceNotifierProvider.notifier).loadWorkspaces();

      final state = container.read(workspaceNotifierProvider);
      expect(state.workspaces, hasLength(1));
      expect(state.workspaces.first.name, 'Shop A');
      expect(state.isLoading, isFalse);
    });
  });
}
