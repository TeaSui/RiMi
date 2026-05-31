import 'package:drift/drift.dart';

/// Drift table for cached income entries.
///
/// Maps to server `income_entries`. Amount is stored as a string (NUMERIC).
class IncomeEntries extends Table {
  /// UUID primary key.
  TextColumn get id => text()();

  /// Workspace this entry belongs to.
  TextColumn get workspaceId => text()();

  /// Amount in VND as a numeric string (e.g. '150000').
  TextColumn get amount => text()();

  /// Optional category (e.g. 'food_sales', 'delivery').
  TextColumn get category => text().nullable()();

  /// Optional human-readable description.
  TextColumn get description => text().nullable()();

  /// Optional linked order ID.
  TextColumn get orderId => text().nullable()();

  /// Creation time as Unix milliseconds.
  IntColumn get createdAt => integer()();

  /// Last update time as Unix milliseconds.
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Drift table for cached expense entries.
///
/// Maps to server `expense_entries`. Amount is stored as a string (NUMERIC).
class ExpenseEntries extends Table {
  /// UUID primary key.
  TextColumn get id => text()();

  /// Workspace this entry belongs to.
  TextColumn get workspaceId => text()();

  /// Amount in VND as a numeric string (e.g. '50000').
  TextColumn get amount => text()();

  /// Optional category (e.g. 'ingredients', 'staff').
  TextColumn get category => text().nullable()();

  /// Optional human-readable description.
  TextColumn get description => text().nullable()();

  /// Creation time as Unix milliseconds.
  IntColumn get createdAt => integer()();

  /// Last update time as Unix milliseconds.
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
