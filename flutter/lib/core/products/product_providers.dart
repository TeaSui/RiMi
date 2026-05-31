import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/drift/app_database.dart';
import '../auth/auth_notifier.dart';
import '../network/dio_client.dart';
import '../sync/sync_providers.dart';

/// Stream of active products from local Drift DB for the given workspace.
///
/// Re-emits whenever a product row changes (insert/update/delete).
final productsProvider =
    StreamProvider.family<List<Product>, String>((ref, workspaceId) {
  final db = ref.watch(appDatabaseProvider);
  return db.productsDao.watchByWorkspace(workspaceId);
});

/// Notifier for product CRUD operations.
///
/// Writes are optimistic: the local Drift row is updated immediately, then the
/// HTTP call is made.  If the device is offline the local write still succeeds
/// and the server will be updated on the next sync flush.
class ProductsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(appDatabaseProvider);
  Dio get _dio => ref.read(dioClientProvider);

  String get _workspaceId {
    final auth = ref.read(authNotifierProvider);
    return auth.activeWorkspaceId ?? '';
  }

  /// Creates a product locally and pushes to the server best-effort.
  ///
  /// [price] is stored in VND (integer, from the first variant).
  Future<void> createProduct({
    required String name,
    String? description,
    required int price,
  }) async {
    final id = const Uuid().v4();
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    await _db.productsDao.upsert(
      ProductsCompanion.insert(
        id: id,
        workspaceId: _workspaceId,
        name: name,
        description: Value(description),
        price: Value(price),
        createdAt: nowMs,
        updatedAt: nowMs,
      ),
    );

    // Best-effort server call — offline is handled by the sync layer.
    try {
      await _dio.post<dynamic>('/v1/products', data: <String, dynamic>{
        'id': id,
        'name': name,
        'description': description,
      });
    } on DioException {
      // Offline or transient error — local write persisted; sync will push later.
    }
  }

  /// Soft-deletes a product locally and best-effort on the server.
  Future<void> deleteProduct(String id) async {
    await _db.productsDao.upsert(
      ProductsCompanion(
        id: Value(id),
        isActive: const Value(false),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );

    try {
      await _dio.delete<dynamic>('/v1/products/$id');
    } on DioException {
      // Offline — local delete persisted.
    }
  }

  /// Fetches the current product list from the server and merges into Drift.
  ///
  /// Call on screen mount when online; safe to call when offline (no-op on error).
  Future<void> refreshFromServer() async {
    final wsId = _workspaceId;
    if (wsId.isEmpty) return;
    try {
      final resp = await _dio.get<Map<String, dynamic>>('/v1/products');
      final data = resp.data?['data'] as Map<String, dynamic>?;
      final list = (data?['products'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      final rows = list.map((p) {
        final createdAtMs = _parseMs(p['created_at'] as String?);
        final updatedAtMs = _parseMs(p['updated_at'] as String?);
        return ProductsCompanion.insert(
          id: p['id'] as String,
          workspaceId: wsId,
          name: p['name'] as String,
          description: Value(p['description'] as String?),
          createdAt: createdAtMs,
          updatedAt: updatedAtMs,
        );
      }).toList();

      if (rows.isNotEmpty) {
        await _db.productsDao.upsertAll(rows);
      }
    } on DioException {
      // Offline — use cached data; stream consumers see no change.
    }
  }

  static int _parseMs(String? iso) {
    if (iso == null || iso.isEmpty) return 0;
    return DateTime.tryParse(iso)?.millisecondsSinceEpoch ?? 0;
  }
}

final productsNotifierProvider =
    AsyncNotifierProvider<ProductsNotifier, void>(ProductsNotifier.new);
