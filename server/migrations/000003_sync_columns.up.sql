-- app.set_updated_at() trigger function (idempotent CREATE OR REPLACE)
CREATE OR REPLACE FUNCTION app.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Add updated_at and deleted_at to Phase 2 sync tables
ALTER TABLE products ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE products ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
DROP TRIGGER IF EXISTS products_set_updated_at ON products;
CREATE TRIGGER products_set_updated_at BEFORE UPDATE ON products
  FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

ALTER TABLE product_variants ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE product_variants ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
DROP TRIGGER IF EXISTS product_variants_set_updated_at ON product_variants;
CREATE TRIGGER product_variants_set_updated_at BEFORE UPDATE ON product_variants
  FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

ALTER TABLE inventory_items ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE inventory_items ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
DROP TRIGGER IF EXISTS inventory_items_set_updated_at ON inventory_items;
CREATE TRIGGER inventory_items_set_updated_at BEFORE UPDATE ON inventory_items
  FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

-- Idempotency ledger for sync batch operations
CREATE TABLE IF NOT EXISTS sync_applied_ops (
    workspace_id  uuid        NOT NULL,
    op_id         text        NOT NULL,
    result        jsonb       NOT NULL,
    applied_at    timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (workspace_id, op_id)
);

CREATE INDEX IF NOT EXISTS idx_sync_applied_ops_ttl       ON sync_applied_ops(applied_at);
CREATE INDEX IF NOT EXISTS idx_sync_applied_ops_workspace  ON sync_applied_ops(workspace_id);

ALTER TABLE sync_applied_ops ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_applied_ops FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS sync_applied_ops_workspace ON sync_applied_ops;
CREATE POLICY sync_applied_ops_workspace ON sync_applied_ops
    USING (app.is_workspace_member(workspace_id))
    WITH CHECK (app.is_workspace_member(workspace_id));

GRANT SELECT, INSERT, UPDATE, DELETE ON sync_applied_ops TO rimi_app;

-- TTL cleanup function — SECURITY DEFINER owned by rimi_migrator (SYNC-SEC-16)
-- Must NOT be called as rimi_app; invoke from a scheduled job running as rimi_migrator.
CREATE OR REPLACE FUNCTION app.cleanup_sync_applied_ops()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_deleted integer;
BEGIN
  DELETE FROM sync_applied_ops
  WHERE applied_at < now() - interval '90 days';
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;
