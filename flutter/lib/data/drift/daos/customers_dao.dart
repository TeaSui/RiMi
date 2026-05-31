import 'package:drift/drift.dart';

import '../app_database.dart';
import '../customers_table.dart';

part 'customers_dao.g.dart';

/// DAO for the local CRM customer cache.
///
/// All reads are workspace-scoped. Upserts handle both server-pulled data
/// and optimistic local writes from the customer create/update flows.
@DriftAccessor(tables: [Customers])
class CustomersDao extends DatabaseAccessor<AppDatabase>
    with _$CustomersDaoMixin {
  CustomersDao(super.db);

  /// Streams all customers for the given workspace, newest-first.
  ///
  /// Emits a new list whenever any customer row changes.
  Stream<List<Customer>> watchByWorkspace(String workspaceId) {
    return (select(customers)
          ..where((t) => t.workspaceId.equals(workspaceId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  /// Returns all customers for the given workspace (one-shot).
  Future<List<Customer>> listByWorkspace(String workspaceId) {
    return (select(customers)
          ..where((t) => t.workspaceId.equals(workspaceId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// Inserts or replaces a single customer row.
  Future<void> upsert(CustomersCompanion c) {
    return into(customers).insertOnConflictUpdate(c);
  }

  /// Bulk-upserts a list of customers in a single batch statement.
  Future<void> upsertAll(List<CustomersCompanion> rows) async {
    await batch((b) => b.insertAllOnConflictUpdate(customers, rows));
  }
}
