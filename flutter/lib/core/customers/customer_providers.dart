import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/drift/app_database.dart';
import '../auth/auth_notifier.dart';
import '../network/dio_client.dart';
import '../sync/sync_providers.dart';

/// Stream of customers from local Drift DB for the given workspace,
/// newest-first.
///
/// Re-emits whenever any customer row changes (insert/update/delete).
final customersProvider =
    StreamProvider.family<List<Customer>, String>((ref, workspaceId) {
  final db = ref.watch(appDatabaseProvider);
  return db.customersDao.watchByWorkspace(workspaceId);
});

/// Notifier for customer CRUD operations.
///
/// Writes are optimistic: the local Drift row is updated immediately, then
/// the HTTP call is made best-effort. If the device is offline the local
/// write still persists and the server is updated on the next sync flush.
class CustomersNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(appDatabaseProvider);
  Dio get _dio => ref.read(dioClientProvider);

  String get _workspaceId {
    final auth = ref.read(authNotifierProvider);
    return auth.activeWorkspaceId ?? '';
  }

  /// Creates a customer locally and pushes to the server best-effort.
  Future<void> createCustomer({
    required String name,
    String? phone,
    String? area,
    String tier = 'reg',
  }) async {
    final id = const Uuid().v4();
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    await _db.customersDao.upsert(
      CustomersCompanion.insert(
        id: id,
        workspaceId: _workspaceId,
        name: Value(name.isNotEmpty ? name : null),
        phone: Value(phone?.isNotEmpty == true ? phone : null),
        area: Value(area?.isNotEmpty == true ? area : null),
        tier: Value(tier),
        createdAt: nowMs,
        updatedAt: nowMs,
      ),
    );

    try {
      await _dio.post<dynamic>('/customers', data: <String, dynamic>{
        'id': id,
        'name': name.isNotEmpty ? name : null,
        'phone': phone?.isNotEmpty == true ? phone : null,
        'area': area?.isNotEmpty == true ? area : null,
        'tier': tier,
      });
    } on DioException {
      // Offline or transient error — local write persisted; sync later.
    }
  }

  /// Updates a customer's tier locally and pushes to the server best-effort.
  Future<void> updateTier(String customerId, String tier) async {
    await _db.customersDao.upsert(
      CustomersCompanion(
        id: Value(customerId),
        tier: Value(tier),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );

    try {
      await _dio.patch<dynamic>(
        '/customers/$customerId',
        data: <String, dynamic>{'tier': tier},
      );
    } on DioException {
      // Offline — local update persisted.
    }
  }

  /// Fetches the current customer list from the server and merges into Drift.
  ///
  /// Call on screen mount when online; safe to call when offline (no-op on error).
  Future<void> refreshFromServer() async {
    final wsId = _workspaceId;
    if (wsId.isEmpty) return;
    try {
      final resp =
          await _dio.get<Map<String, dynamic>>('/customers');
      final data = resp.data?['data'] as Map<String, dynamic>?;
      final list =
          (data?['customers'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      final rows = list.map((c) {
        final createdAtMs = _parseMs(c['created_at'] as String?);
        final updatedAtMs = _parseMs(c['updated_at'] as String?);
        return CustomersCompanion.insert(
          id: c['id'] as String,
          workspaceId: wsId,
          name: Value(c['name'] as String?),
          phone: Value(c['phone'] as String?),
          tier: Value((c['tier'] as String?) ?? 'reg'),
          area: Value(c['area'] as String?),
          orderCount:
              Value(c['order_count'] as int? ?? 0),
          totalSpent:
              Value((c['total_spent'] as String?) ?? '0'),
          createdAt: createdAtMs,
          updatedAt: updatedAtMs,
        );
      }).toList();

      if (rows.isNotEmpty) {
        await _db.customersDao.upsertAll(rows);
      }
    } on DioException {
      // Offline — use cached data.
    }
  }

  static int _parseMs(String? iso) {
    if (iso == null || iso.isEmpty) return 0;
    return DateTime.tryParse(iso)?.millisecondsSinceEpoch ?? 0;
  }
}

final customersNotifierProvider =
    AsyncNotifierProvider<CustomersNotifier, void>(CustomersNotifier.new);
