-- Migration 004: Phase 4-8 column additions.
-- Adds columns to the sparse Phase 4-8 stubs from migration 001.
-- All new columns are NULLABLE or have server-side DEFAULTs (zero-downtime safe).

-- ============================================================
-- PHASE 4 — ORDERS: add missing columns and rename total → total_amount
-- ============================================================

-- Rename the stub `total` column to `total_amount` to match the Phase 4 handler.
ALTER TABLE orders RENAME COLUMN total TO total_amount;

ALTER TABLE orders ADD COLUMN IF NOT EXISTS channel       text    NOT NULL DEFAULT 'walkin';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_name text;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS note          text;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS updated_at    timestamptz NOT NULL DEFAULT now();

-- Remove the default on channel so new inserts must supply it.
-- (NOT NULL constraint remains — handler always provides the value.)
ALTER TABLE orders ALTER COLUMN channel DROP DEFAULT;

DROP TRIGGER IF EXISTS orders_set_updated_at ON orders;
CREATE TRIGGER orders_set_updated_at BEFORE UPDATE ON orders
  FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

-- order_status_events needs from_status / to_status columns (handler inserts them).
ALTER TABLE order_status_events ADD COLUMN IF NOT EXISTS from_status text;
ALTER TABLE order_status_events ADD COLUMN IF NOT EXISTS to_status   text;

-- ============================================================
-- PHASE 5 — CUSTOMERS: add detail columns
-- ============================================================

ALTER TABLE customers ADD COLUMN IF NOT EXISTS tier       text        NOT NULL DEFAULT 'reg';
ALTER TABLE customers ADD COLUMN IF NOT EXISTS area       text;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

DROP TRIGGER IF EXISTS customers_set_updated_at ON customers;
CREATE TRIGGER customers_set_updated_at BEFORE UPDATE ON customers
  FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

ALTER TABLE customer_notes ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

DROP TRIGGER IF EXISTS customer_notes_set_updated_at ON customer_notes;
CREATE TRIGGER customer_notes_set_updated_at BEFORE UPDATE ON customer_notes
  FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

-- Link orders to customers (optional FK — offline-first; customer may not exist yet).
ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_id uuid REFERENCES customers(id);

CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_customers_workspace_phone ON customers(workspace_id, phone);

-- ============================================================
-- PHASE 6 — FINANCE: enrich transaction tables
-- ============================================================

-- income_entries: add category, description, order_id.
ALTER TABLE income_entries ADD COLUMN IF NOT EXISTS category    text;
ALTER TABLE income_entries ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE income_entries ADD COLUMN IF NOT EXISTS order_id    uuid REFERENCES orders(id);
ALTER TABLE income_entries ADD COLUMN IF NOT EXISTS updated_at  timestamptz NOT NULL DEFAULT now();

DROP TRIGGER IF EXISTS income_entries_set_updated_at ON income_entries;
CREATE TRIGGER income_entries_set_updated_at BEFORE UPDATE ON income_entries
  FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

-- expense_entries: add category, description.
ALTER TABLE expense_entries ADD COLUMN IF NOT EXISTS category    text;
ALTER TABLE expense_entries ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE expense_entries ADD COLUMN IF NOT EXISTS updated_at  timestamptz NOT NULL DEFAULT now();

DROP TRIGGER IF EXISTS expense_entries_set_updated_at ON expense_entries;
CREATE TRIGGER expense_entries_set_updated_at BEFORE UPDATE ON expense_entries
  FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

-- receivables: add customer_id, status, due_date.
ALTER TABLE receivables ADD COLUMN IF NOT EXISTS customer_id uuid REFERENCES customers(id);
ALTER TABLE receivables ADD COLUMN IF NOT EXISTS status      text NOT NULL DEFAULT 'open';
ALTER TABLE receivables ADD COLUMN IF NOT EXISTS due_date    date;
ALTER TABLE receivables ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE receivables ADD COLUMN IF NOT EXISTS updated_at  timestamptz NOT NULL DEFAULT now();

DROP TRIGGER IF EXISTS receivables_set_updated_at ON receivables;
CREATE TRIGGER receivables_set_updated_at BEFORE UPDATE ON receivables
  FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

-- payment_records: add method, order_id, status, note.
ALTER TABLE payment_records ADD COLUMN IF NOT EXISTS method     text NOT NULL DEFAULT 'cash';
ALTER TABLE payment_records ADD COLUMN IF NOT EXISTS order_id   uuid REFERENCES orders(id);
ALTER TABLE payment_records ADD COLUMN IF NOT EXISTS status     text NOT NULL DEFAULT 'completed';
ALTER TABLE payment_records ADD COLUMN IF NOT EXISTS note       text;
ALTER TABLE payment_records ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

DROP TRIGGER IF EXISTS payment_records_set_updated_at ON payment_records;
CREATE TRIGGER payment_records_set_updated_at BEFORE UPDATE ON payment_records
  FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

-- bank_transfers: add reference, status, matched_order_id, description.
ALTER TABLE bank_transfers ADD COLUMN IF NOT EXISTS reference         text;
ALTER TABLE bank_transfers ADD COLUMN IF NOT EXISTS status            text NOT NULL DEFAULT 'pending';
ALTER TABLE bank_transfers ADD COLUMN IF NOT EXISTS matched_order_id  uuid REFERENCES orders(id);
ALTER TABLE bank_transfers ADD COLUMN IF NOT EXISTS description       text;
ALTER TABLE bank_transfers ADD COLUMN IF NOT EXISTS updated_at        timestamptz NOT NULL DEFAULT now();

DROP TRIGGER IF EXISTS bank_transfers_set_updated_at ON bank_transfers;
CREATE TRIGGER bank_transfers_set_updated_at BEFORE UPDATE ON bank_transfers
  FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_bank_transfers_workspace_status ON bank_transfers(workspace_id, status);
CREATE INDEX IF NOT EXISTS idx_bank_transfers_reference ON bank_transfers(reference) WHERE reference IS NOT NULL;

-- ============================================================
-- PHASE 7 — AI USAGE: add feature and prompt fields
-- ============================================================

ALTER TABLE ai_usage ADD COLUMN IF NOT EXISTS feature    text;
ALTER TABLE ai_usage ADD COLUMN IF NOT EXISTS prompt_key text;

-- ============================================================
-- PHASE 8 — E-INVOICE: add required NĐ 123/2020 fields
-- ============================================================

-- einvoices: add provider, serial, buyer fields, ma_tra_cuu.
ALTER TABLE einvoices ADD COLUMN IF NOT EXISTS provider         text;
ALTER TABLE einvoices ADD COLUMN IF NOT EXISTS invoice_number   text;
ALTER TABLE einvoices ADD COLUMN IF NOT EXISTS buyer_name       text;
ALTER TABLE einvoices ADD COLUMN IF NOT EXISTS buyer_tax_code   text;
ALTER TABLE einvoices ADD COLUMN IF NOT EXISTS buyer_address    text;
ALTER TABLE einvoices ADD COLUMN IF NOT EXISTS buyer_email      text;
ALTER TABLE einvoices ADD COLUMN IF NOT EXISTS total_amount     NUMERIC(15,2);
ALTER TABLE einvoices ADD COLUMN IF NOT EXISTS tax_amount       NUMERIC(15,2);
ALTER TABLE einvoices ADD COLUMN IF NOT EXISTS ma_tra_cuu       text;
ALTER TABLE einvoices ADD COLUMN IF NOT EXISTS provider_raw     jsonb;
ALTER TABLE einvoices ADD COLUMN IF NOT EXISTS issued_at        timestamptz;
ALTER TABLE einvoices ADD COLUMN IF NOT EXISTS updated_at       timestamptz NOT NULL DEFAULT now();

DROP TRIGGER IF EXISTS einvoices_set_updated_at ON einvoices;
CREATE TRIGGER einvoices_set_updated_at BEFORE UPDATE ON einvoices
  FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

-- einvoice_line_items: add vat_rate.
ALTER TABLE einvoice_line_items ADD COLUMN IF NOT EXISTS vat_rate NUMERIC(5,2) NOT NULL DEFAULT 0.10;
