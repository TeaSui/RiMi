import 'package:drift/drift.dart';

class SyncOperations extends Table {
  TextColumn get opId => text()();
  TextColumn get workspaceId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get opType => text()();
  TextColumn get payload => text().nullable()();
  IntColumn get delta => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get inflightSince => integer().nullable()();
  IntColumn get nextRetryAt => integer().nullable()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {opId};
}
