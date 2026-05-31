import 'package:drift/drift.dart';

import '../app_database.dart';
import '../products_table.dart';

part 'products_dao.g.dart';

/// DAO for the local products cache.
///
/// All reads are workspace-scoped.  Upserts handle both create and update from
/// server sync responses.
@DriftAccessor(tables: [Products])
class ProductsDao extends DatabaseAccessor<AppDatabase>
    with _$ProductsDaoMixin {
  ProductsDao(super.db);

  /// Returns all active products for the given workspace, newest-first.
  Future<List<Product>> listByWorkspace(String workspaceId) {
    return (select(products)
          ..where(
            (t) =>
                t.workspaceId.equals(workspaceId) &
                t.isActive.equals(true),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// Inserts or replaces a single product row.
  Future<void> upsert(ProductsCompanion p) {
    return into(products).insertOnConflictUpdate(p);
  }

  /// Bulk-upserts a list of products in a single batch statement.
  Future<void> upsertAll(List<ProductsCompanion> rows) async {
    await batch((b) => b.insertAllOnConflictUpdate(products, rows));
  }

  /// Streams active products for the given workspace, ordered by newest-first.
  /// Emits a new list whenever any row changes.
  Stream<List<Product>> watchByWorkspace(String workspaceId) {
    return (select(products)
          ..where(
            (t) =>
                t.workspaceId.equals(workspaceId) &
                t.isActive.equals(true),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }
}
