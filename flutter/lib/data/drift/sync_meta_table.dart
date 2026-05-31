import 'package:drift/drift.dart';

class SyncMeta extends Table {
  TextColumn get workspaceId => text()();
  TextColumn get entityType => text()();
  IntColumn get lastSyncedAt => integer()();
  TextColumn get lastSyncedId => text()();

  @override
  Set<Column> get primaryKey => {workspaceId, entityType};
}
