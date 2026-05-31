import 'package:drift/drift.dart';

/// Drift table for the local product catalog cache.
///
/// Columns map to the server `products` table with additional denormalized
/// fields (price, quantity, status, soldToday) that are populated from
/// product_variants and inventory_items during a full sync pull.
class Products extends Table {
  /// UUID primary key — matches server products.id.
  TextColumn get id => text()();

  /// Workspace this product belongs to.
  TextColumn get workspaceId => text()();

  /// Display name of the product.
  TextColumn get name => text()();

  /// Optional description.
  TextColumn get description => text().nullable()();

  /// Price in VND — sourced from the first variant.
  IntColumn get price => integer().withDefault(const Constant(0))();

  /// Denormalized current stock quantity.
  IntColumn get quantity => integer().withDefault(const Constant(0))();

  /// Stock status: 'ok' | 'low' | 'out'.
  TextColumn get status => text().withDefault(const Constant('ok'))();

  /// Product category (e.g. 'Mains', 'Drinks', 'Sides').
  TextColumn get cat => text().withDefault(const Constant('Mains'))();

  /// Visual seed for the food slot illustration (0–5).
  IntColumn get seed => integer().withDefault(const Constant(0))();

  /// Whether the product is visible on the menu.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// How many units sold today (reset at midnight via server sync).
  IntColumn get soldToday => integer().withDefault(const Constant(0))();

  /// Creation time as Unix milliseconds.
  IntColumn get createdAt => integer()();

  /// Last update time as Unix milliseconds.
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
