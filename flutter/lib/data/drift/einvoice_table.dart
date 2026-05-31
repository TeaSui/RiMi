import 'package:drift/drift.dart';

/// Drift table for cached e-invoice records.
///
/// Maps to server `invoices`. Only stores display-essential fields — line
/// items are not cached locally (fetched on demand).
class Invoices extends Table {
  /// UUID primary key.
  TextColumn get id => text()();

  /// Workspace this invoice belongs to.
  TextColumn get workspaceId => text()();

  /// Optional linked order ID.
  TextColumn get orderId => text().nullable()();

  /// Invoice status: draft | issued | cancelled | replaced.
  TextColumn get status => text().withDefault(const Constant('draft'))();

  /// Provider: viettel_s | misa.
  TextColumn get provider => text().nullable()();

  /// Issued invoice number (assigned by provider).
  TextColumn get invoiceNumber => text().nullable()();

  /// Buyer display name.
  TextColumn get buyerName => text().nullable()();

  /// Buyer tax code.
  TextColumn get buyerTaxCode => text().nullable()();

  /// Total amount as a numeric string.
  TextColumn get totalAmount => text().nullable()();

  /// Tax amount as a numeric string.
  TextColumn get taxAmount => text().nullable()();

  /// Provider lookup code (mã tra cứu).
  TextColumn get maTraCuu => text().nullable()();

  /// Issued timestamp as Unix milliseconds (nullable until issued).
  IntColumn get issuedAt => integer().nullable()();

  /// Creation time as Unix milliseconds.
  IntColumn get createdAt => integer()();

  /// Last update time as Unix milliseconds.
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
