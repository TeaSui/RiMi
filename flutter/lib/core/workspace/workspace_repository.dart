import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_exception.dart';
import '../network/dio_client.dart';

/// Workspace model matching the API Workspace schema.
class WorkspaceModel {
  const WorkspaceModel({
    required this.id,
    required this.name,
    required this.role,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String role; // 'owner' | 'member'
  final String createdAt;

  factory WorkspaceModel.fromJson(Map<String, dynamic> json) => WorkspaceModel(
        id: json['id'] as String,
        name: json['name'] as String,
        role: json['role'] as String,
        createdAt: json['created_at'] as String,
      );
}

/// TokenPair returned by workspace create/switch.
class WorkspaceTokens {
  const WorkspaceTokens({
    required this.workspace,
    required this.accessToken,
    required this.refreshToken,
    required this.activeWorkspaceId,
  });

  final WorkspaceModel workspace;
  final String accessToken;
  final String refreshToken;
  final String? activeWorkspaceId;
}

/// REST repository for /workspaces endpoints.
class WorkspaceRepository {
  const WorkspaceRepository(this._dio);

  final Dio _dio;

  /// POST /workspaces — creates a workspace, returns scoped token.
  Future<WorkspaceTokens> createWorkspace({
    required String name,
    String? id,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/workspaces',
        data: {
          'name': name,
          'id': ?id,
        },
      );
      return _parseWorkspaceTokens(response.data!['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// GET /workspaces — lists all workspace memberships.
  Future<List<WorkspaceModel>> listWorkspaces() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/workspaces');
      final data = response.data!['data'] as Map<String, dynamic>;
      final list = data['workspaces'] as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(WorkspaceModel.fromJson)
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// POST /workspaces/{id}/switch — switches active workspace, returns scoped token.
  Future<WorkspaceTokens> switchWorkspace(String workspaceId) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/workspaces/$workspaceId/switch',
      );
      return _parseWorkspaceTokens(response.data!['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  WorkspaceTokens _parseWorkspaceTokens(Map<String, dynamic> data) {
    final workspace = WorkspaceModel.fromJson(
      data['workspace'] as Map<String, dynamic>,
    );
    final tokens = data['tokens'] as Map<String, dynamic>;
    return WorkspaceTokens(
      workspace: workspace,
      accessToken: tokens['access_token'] as String,
      refreshToken: tokens['refresh_token'] as String,
      activeWorkspaceId: tokens['active_workspace_id'] as String?,
    );
  }
}

final workspaceRepositoryProvider = Provider<WorkspaceRepository>((ref) {
  return WorkspaceRepository(ref.watch(dioClientProvider));
});
