import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'daos/sync_meta_dao.dart';
import 'daos/sync_queue_dao.dart';
import 'sync_meta_table.dart';
import 'sync_operations_table.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [SyncOperations, SyncMeta],
  daos: [SyncQueueDao, SyncMetaDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement('''
            CREATE INDEX IF NOT EXISTS idx_sync_ops_flush
            ON sync_operations(workspace_id, created_at)
            WHERE status = 'pending'
          ''');
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'rimi.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
