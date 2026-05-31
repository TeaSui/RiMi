import 'package:drift/drift.dart';

/// Drift table for the local orders cache.
///
/// Columns map to the server `orders` table with additional denormalized
/// fields (itemsSummary, isLate) for display purposes.
class Orders extends Table {
  /// UUID primary key — matches server orders.id.
  TextColumn get id => text()();

  /// Workspace this order belongs to.
  TextColumn get workspaceId => text()();

  /// Order status: new | cooking | ready | delivering | done.
  TextColumn get status => text()();

  /// Order channel: online | app | phone | walkin.
  TextColumn get channel => text()();

  /// Optional customer name.
  TextColumn get customerName => text().nullable()();

  /// Display string for line items (e.g. "Bún bò ×2, Chả giò ×1").
  TextColumn get itemsSummary =>
      text().withDefault(const Constant(''))();

  /// Total order amount in VND (integer).
  IntColumn get totalAmount =>
      integer().withDefault(const Constant(0))();

  /// Optional note for the kitchen.
  TextColumn get note => text().nullable()();

  /// Whether the order is running late.
  BoolColumn get isLate =>
      boolean().withDefault(const Constant(false))();

  /// Creation time as Unix milliseconds.
  IntColumn get createdAt => integer()();

  /// Last update time as Unix milliseconds.
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
