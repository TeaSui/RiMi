import 'package:drift/drift.dart';

import '../app_database.dart';
import '../finance_table.dart';

part 'finance_dao.g.dart';

/// DAO for the local finance cache (income and expense entries).
///
/// All reads are workspace-scoped. Upserts merge server-pulled data with
/// any optimistic local writes.
@DriftAccessor(tables: [IncomeEntries, ExpenseEntries])
class FinanceDao extends DatabaseAccessor<AppDatabase>
    with _$FinanceDaoMixin {
  FinanceDao(super.db);

  // ── Income ───────────────────────────────────────────────────────────

  /// Streams income entries for the given workspace, newest-first.
  Stream<List<IncomeEntry>> watchIncomeByWorkspace(String workspaceId) {
    return (select(incomeEntries)
          ..where((t) => t.workspaceId.equals(workspaceId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  /// Returns all income entries for the workspace (one-shot).
  Future<List<IncomeEntry>> listIncomeByWorkspace(String workspaceId) {
    return (select(incomeEntries)
          ..where((t) => t.workspaceId.equals(workspaceId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// Inserts or replaces a single income entry.
  Future<void> upsertIncome(IncomeEntriesCompanion e) {
    return into(incomeEntries).insertOnConflictUpdate(e);
  }

  /// Bulk-upserts income entries.
  Future<void> upsertAllIncome(List<IncomeEntriesCompanion> rows) async {
    await batch((b) => b.insertAllOnConflictUpdate(incomeEntries, rows));
  }

  // ── Expenses ─────────────────────────────────────────────────────────

  /// Streams expense entries for the given workspace, newest-first.
  Stream<List<ExpenseEntry>> watchExpensesByWorkspace(String workspaceId) {
    return (select(expenseEntries)
          ..where((t) => t.workspaceId.equals(workspaceId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  /// Returns all expense entries for the workspace (one-shot).
  Future<List<ExpenseEntry>> listExpensesByWorkspace(String workspaceId) {
    return (select(expenseEntries)
          ..where((t) => t.workspaceId.equals(workspaceId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// Inserts or replaces a single expense entry.
  Future<void> upsertExpense(ExpenseEntriesCompanion e) {
    return into(expenseEntries).insertOnConflictUpdate(e);
  }

  /// Bulk-upserts expense entries.
  Future<void> upsertAllExpenses(List<ExpenseEntriesCompanion> rows) async {
    await batch((b) => b.insertAllOnConflictUpdate(expenseEntries, rows));
  }
}
