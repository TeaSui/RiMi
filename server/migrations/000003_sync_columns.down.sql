DROP FUNCTION IF EXISTS app.cleanup_sync_applied_ops();
DROP TABLE IF EXISTS sync_applied_ops;

DROP TRIGGER IF EXISTS inventory_items_set_updated_at ON inventory_items;
ALTER TABLE inventory_items DROP COLUMN IF EXISTS deleted_at;
ALTER TABLE inventory_items DROP COLUMN IF EXISTS updated_at;

DROP TRIGGER IF EXISTS product_variants_set_updated_at ON product_variants;
ALTER TABLE product_variants DROP COLUMN IF EXISTS deleted_at;
ALTER TABLE product_variants DROP COLUMN IF EXISTS updated_at;

DROP TRIGGER IF EXISTS products_set_updated_at ON products;
ALTER TABLE products DROP COLUMN IF EXISTS deleted_at;
ALTER TABLE products DROP COLUMN IF EXISTS updated_at;

DROP FUNCTION IF EXISTS app.set_updated_at();
