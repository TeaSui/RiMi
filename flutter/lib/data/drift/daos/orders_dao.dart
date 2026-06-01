import 'package:drift/drift.dart';

import '../app_database.dart';
import '../orders_table.dart';

part 'orders_dao.g.dart';

/// DAO for the local orders cache.
///
/// All reads are workspace-scoped. Upserts handle both create and update
/// from server sync responses and optimistic local writes.
@DriftAccessor(tables: [Orders])
class OrdersDao extends DatabaseAccessor<AppDatabase> with _$OrdersDaoMixin {
  OrdersDao(super.db);

  /// Streams all orders for the given workspace, newest-first.
  ///
  /// Emits a new list whenever any order row changes.
  Stream<List<Order>> watchByWorkspace(String workspaceId) {
    return (select(orders)
          ..where((t) => t.workspaceId.equals(workspaceId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  /// Inserts or replaces a single order row.
  Future<void> upsert(OrdersCompanion o) {
    return into(orders).insertOnConflictUpdate(o);
  }

  /// Bulk-upserts a list of orders in a single batch statement.
  Future<void> upsertAll(List<OrdersCompanion> rows) async {
    await batch((b) => b.insertAllOnConflictUpdate(orders, rows));
  }

  /// Replaces ALL local orders for a workspace with the server-authoritative list.
  /// Deletes rows not present on the server (removes stale/mock data).
  Future<void> replaceAll(String workspaceId, List<OrdersCompanion> rows) async {
    await transaction(() async {
      await (delete(orders)..where((t) => t.workspaceId.equals(workspaceId))).go();
      if (rows.isNotEmpty) {
        await batch((b) => b.insertAllOnConflictUpdate(orders, rows));
      }
    });
  }

  /// Returns the count of active (non-done) orders for the given workspace.
  Future<int> countActive(String workspaceId) async {
    final count = orders.id.count();
    final q = selectOnly(orders)
      ..addColumns([count])
      ..where(
        orders.workspaceId.equals(workspaceId) &
            orders.status.isNotIn(['done']),
      );
    final result = await q.getSingle();
    return result.read(count) ?? 0;
  }
}
