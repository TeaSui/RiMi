import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/drift/app_database.dart';
import '../auth/auth_notifier.dart';
import '../network/dio_client.dart';
import '../sync/sync_providers.dart';

/// Stream of orders for the given workspace from local Drift DB, newest-first.
///
/// Re-emits whenever any order row changes (insert/update/delete).
final ordersProvider =
    StreamProvider.family<List<Order>, String>((ref, workspaceId) {
  final db = ref.watch(appDatabaseProvider);
  return db.ordersDao.watchByWorkspace(workspaceId);
});

/// Notifier for order CRUD and status-advance operations.
///
/// Writes are optimistic: local Drift row is updated immediately, then the
/// HTTP call is made best-effort. If the device is offline the local write
/// persists and the server is updated on the next online reconnect.
class OrdersNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(appDatabaseProvider);
  Dio get _dio => ref.read(dioClientProvider);

  String get _workspaceId {
    final auth = ref.read(authNotifierProvider);
    return auth.activeWorkspaceId ?? '';
  }

  /// Advances the order to [newStatus] locally, then syncs to the server.
  Future<void> advanceStatus(String orderId, String newStatus) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _db.ordersDao.upsert(
      OrdersCompanion(
        id: Value(orderId),
        status: Value(newStatus),
        updatedAt: Value(nowMs),
      ),
    );
    try {
      await _dio.put<dynamic>(
        '/v1/orders/$orderId/status',
        data: <String, dynamic>{'status': newStatus},
      );
    } on DioException {
      // Offline or transient error — local write persisted; sync later.
    }
  }

  /// Creates an order locally and pushes to the server best-effort.
  Future<void> createOrder({
    required String channel,
    required String customerName,
    required String itemsSummary,
    required int totalAmount,
    String? note,
  }) async {
    final id = const Uuid().v4();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _db.ordersDao.upsert(
      OrdersCompanion.insert(
        id: id,
        workspaceId: _workspaceId,
        status: 'new',
        channel: channel,
        customerName: Value(customerName.isEmpty ? null : customerName),
        itemsSummary: Value(itemsSummary),
        totalAmount: Value(totalAmount),
        note: Value(note),
        createdAt: nowMs,
        updatedAt: nowMs,
      ),
    );
    try {
      await _dio.post<dynamic>('/v1/orders', data: <String, dynamic>{
        'id': id,
        'channel': channel,
        'customer_name': customerName.isEmpty ? null : customerName,
        'total_amount': totalAmount.toString(),
        'note': note,
      });
    } on DioException {
      // Offline — local write persisted.
    }
  }

  /// Fetches orders from the server and merges into local Drift DB.
  ///
  /// Safe to call when offline (no-op on error).
  Future<void> refreshFromServer() async {
    final wsId = _workspaceId;
    if (wsId.isEmpty) return;
    try {
      final resp = await _dio.get<Map<String, dynamic>>('/v1/orders');
      final data = resp.data?['data'] as Map<String, dynamic>?;
      final list =
          (data?['orders'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      final rows = list.map((o) {
        final createdAtMs = _parseMs(o['created_at'] as String?);
        final updatedAtMs = _parseMs(o['updated_at'] as String?);
        final rawTotal = o['total_amount'] as String? ?? '0';
        final totalInt = int.tryParse(rawTotal.split('.').first) ?? 0;
        return OrdersCompanion.insert(
          id: o['id'] as String,
          workspaceId: wsId,
          status: o['status'] as String,
          channel: o['channel'] as String,
          customerName: Value(o['customer_name'] as String?),
          totalAmount: Value(totalInt),
          note: Value(o['note'] as String?),
          createdAt: createdAtMs,
          updatedAt: updatedAtMs,
        );
      }).toList();

      // Replace all local rows for this workspace with the authoritative server list.
      // This removes any stale/mock rows that were never on the server.
      await _db.ordersDao.replaceAll(wsId, rows);
    } on DioException {
      // Offline — use cached data; stream consumers see no change.
    }
  }

  static int _parseMs(String? iso) {
    if (iso == null || iso.isEmpty) return 0;
    return DateTime.tryParse(iso)?.millisecondsSinceEpoch ?? 0;
  }
}

final ordersNotifierProvider =
    AsyncNotifierProvider<OrdersNotifier, void>(OrdersNotifier.new);
