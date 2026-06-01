import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'customers_table.dart';
import 'daos/customers_dao.dart';
import 'daos/einvoice_dao.dart';
import 'daos/finance_dao.dart';
import 'daos/orders_dao.dart';
import 'daos/products_dao.dart';
import 'daos/sync_meta_dao.dart';
import 'daos/sync_queue_dao.dart';
import 'einvoice_table.dart';
import 'finance_table.dart';
import 'orders_table.dart';
import 'products_table.dart';
import 'sync_meta_table.dart';
import 'sync_operations_table.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    SyncOperations,
    SyncMeta,
    Products,
    Orders,
    Customers,
    IncomeEntries,
    ExpenseEntries,
    Invoices,
  ],
  daos: [
    SyncQueueDao,
    SyncMetaDao,
    ProductsDao,
    OrdersDao,
    CustomersDao,
    FinanceDao,
    EinvoiceDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 5;

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
          if (from < 3) {
            await m.createTable(orders);
          }
          if (from < 4) {
            await m.createTable(customers);
            await m.createTable(incomeEntries);
            await m.createTable(expenseEntries);
            await m.createTable(invoices);
          }
          if (from < 5) {
            // Clear all local mock/stale data — real data reloads from backend.
            // Use raw SQL to drop tables (Migrator.deleteTable requires table objects,
            // but these may already exist from prior schema versions).
            await customStatement('DROP TABLE IF EXISTS orders');
            await customStatement('DROP TABLE IF EXISTS products');
            await customStatement('DROP TABLE IF EXISTS customers');
            await customStatement('DROP TABLE IF EXISTS income_entries');
            await customStatement('DROP TABLE IF EXISTS expense_entries');
            await customStatement('DROP TABLE IF EXISTS invoices');
            await m.createTable(orders);
            await m.createTable(products);
            await m.createTable(customers);
            await m.createTable(incomeEntries);
            await m.createTable(expenseEntries);
            await m.createTable(invoices);
          }
        },
        beforeOpen: (details) async {
          try {
            await _createIndexes();
          } catch (_) {
            // Index creation is best-effort — don't crash if it fails on first open.
          }
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
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_orders_workspace
      ON orders(workspace_id, created_at)
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_customers_workspace
      ON customers(workspace_id, created_at)
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_income_workspace
      ON income_entries(workspace_id, created_at)
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_expense_workspace
      ON expense_entries(workspace_id, created_at)
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_invoices_workspace
      ON invoices(workspace_id, created_at)
    ''');
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'rimi.sqlite'));
    try {
      return NativeDatabase(file);
    } catch (_) {
      // If DB is corrupt or missing after cache clear, delete and recreate.
      if (await file.exists()) await file.delete();
      return NativeDatabase(file);
    }
  });
}
