import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'daos/products_dao.dart';
import 'daos/sync_meta_dao.dart';
import 'daos/sync_queue_dao.dart';
import 'products_table.dart';
import 'sync_meta_table.dart';
import 'sync_operations_table.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [SyncOperations, SyncMeta, Products],
  daos: [SyncQueueDao, SyncMetaDao, ProductsDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createIndexes();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(products);
          }
        },
        beforeOpen: (details) async {
          await _createIndexes();
        },
      );

  Future<void> _createIndexes() async {
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_sync_ops_flush
      ON sync_operations(workspace_id, created_at)
      WHERE status = 'pending'
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_products_workspace
      ON products(workspace_id, created_at)
      WHERE is_active = 1
    ''');
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'rimi.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
