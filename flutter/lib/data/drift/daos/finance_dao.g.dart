// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'finance_dao.dart';

// ignore_for_file: type=lint
mixin _$FinanceDaoMixin on DatabaseAccessor<AppDatabase> {
  $IncomeEntriesTable get incomeEntries => attachedDatabase.incomeEntries;
  $ExpenseEntriesTable get expenseEntries => attachedDatabase.expenseEntries;
  FinanceDaoManager get managers => FinanceDaoManager(this);
}

class FinanceDaoManager {
  final _$FinanceDaoMixin _db;
  FinanceDaoManager(this._db);
  $$IncomeEntriesTableTableManager get incomeEntries =>
      $$IncomeEntriesTableTableManager(_db.attachedDatabase, _db.incomeEntries);
  $$ExpenseEntriesTableTableManager get expenseEntries =>
      $$ExpenseEntriesTableTableManager(
        _db.attachedDatabase,
        _db.expenseEntries,
      );
}
