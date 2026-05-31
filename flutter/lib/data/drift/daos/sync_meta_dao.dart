import 'package:drift/drift.dart';

import '../app_database.dart';
import '../sync_meta_table.dart';

part 'sync_meta_dao.g.dart';

@DriftAccessor(tables: [SyncMeta])
class SyncMetaDao extends DatabaseAccessor<AppDatabase>
    with _$SyncMetaDaoMixin {
  SyncMetaDao(super.db);

  Future<SyncMetaData?> getCursor(String workspaceId, String entityType) {
    return (select(syncMeta)
          ..where((tbl) =>
              tbl.workspaceId.equals(workspaceId) &
              tbl.entityType.equals(entityType)))
        .getSingleOrNull();
  }

  Future<void> upsertCursor({
    required String workspaceId,
    required String entityType,
    required int lastSyncedAt,
    required String lastSyncedId,
  }) {
    return into(syncMeta).insertOnConflictUpdate(SyncMetaCompanion.insert(
      workspaceId: workspaceId,
      entityType: entityType,
      lastSyncedAt: lastSyncedAt,
      lastSyncedId: lastSyncedId,
    ));
  }
}
