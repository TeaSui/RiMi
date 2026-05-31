import 'package:drift/drift.dart';

/// Drift table for the local CRM customer cache.
///
/// Maps to the server `customers` table. All columns are nullable except
/// [id] and [workspaceId] to match the server schema.
class Customers extends Table {
  /// UUID primary key — matches server customers.id.
  TextColumn get id => text()();

  /// Workspace this customer belongs to.
  TextColumn get workspaceId => text()();

  /// Customer display name.
  TextColumn get name => text().nullable()();

  /// Phone number.
  TextColumn get phone => text().nullable()();

  /// Customer tier: reg | gold | vip | risk.
  TextColumn get tier => text().withDefault(const Constant('reg'))();

  /// Area / source (e.g. 'Q.3' or 'GrabFood').
  TextColumn get area => text().nullable()();

  /// Denormalized order count from the server detail response.
  IntColumn get orderCount => integer().withDefault(const Constant(0))();

  /// Denormalized lifetime spend as a string (e.g. '3.2M₫').
  TextColumn get totalSpent =>
      text().withDefault(const Constant('0'))();

  /// Creation time as Unix milliseconds.
  IntColumn get createdAt => integer()();

  /// Last update time as Unix milliseconds.
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
