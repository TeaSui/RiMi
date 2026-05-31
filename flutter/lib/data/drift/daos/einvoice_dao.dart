import 'package:drift/drift.dart';

import '../app_database.dart';
import '../einvoice_table.dart';

part 'einvoice_dao.g.dart';

/// DAO for the local e-invoice cache.
///
/// All reads are workspace-scoped. Upserts merge server-pulled data with
/// any optimistic local writes.
@DriftAccessor(tables: [Invoices])
class EinvoiceDao extends DatabaseAccessor<AppDatabase>
    with _$EinvoiceDaoMixin {
  EinvoiceDao(super.db);

  /// Streams all invoices for the given workspace, newest-first.
  Stream<List<Invoice>> watchByWorkspace(String workspaceId) {
    return (select(invoices)
          ..where((t) => t.workspaceId.equals(workspaceId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  /// Returns all invoices for the workspace (one-shot).
  Future<List<Invoice>> listByWorkspace(String workspaceId) {
    return (select(invoices)
          ..where((t) => t.workspaceId.equals(workspaceId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// Inserts or replaces a single invoice row.
  Future<void> upsert(InvoicesCompanion inv) {
    return into(invoices).insertOnConflictUpdate(inv);
  }

  /// Bulk-upserts invoices.
  Future<void> upsertAll(List<InvoicesCompanion> rows) async {
    await batch((b) => b.insertAllOnConflictUpdate(invoices, rows));
  }
}
