-- Migration 004 rollback: drop all added columns.
-- Order matters: drop referencing columns before referenced ones.

-- Phase 8 rollback
DROP TRIGGER IF EXISTS einvoices_set_updated_at ON einvoices;
ALTER TABLE einvoice_line_items DROP COLUMN IF EXISTS vat_rate;
ALTER TABLE einvoices DROP COLUMN IF EXISTS provider;
ALTER TABLE einvoices DROP COLUMN IF EXISTS invoice_number;
ALTER TABLE einvoices DROP COLUMN IF EXISTS buyer_name;
ALTER TABLE einvoices DROP COLUMN IF EXISTS buyer_tax_code;
ALTER TABLE einvoices DROP COLUMN IF EXISTS buyer_address;
ALTER TABLE einvoices DROP COLUMN IF EXISTS buyer_email;
ALTER TABLE einvoices DROP COLUMN IF EXISTS total_amount;
ALTER TABLE einvoices DROP COLUMN IF EXISTS tax_amount;
ALTER TABLE einvoices DROP COLUMN IF EXISTS ma_tra_cuu;
ALTER TABLE einvoices DROP COLUMN IF EXISTS provider_raw;
ALTER TABLE einvoices DROP COLUMN IF EXISTS issued_at;
ALTER TABLE einvoices DROP COLUMN IF EXISTS updated_at;

-- Phase 7 rollback
ALTER TABLE ai_usage DROP COLUMN IF EXISTS feature;
ALTER TABLE ai_usage DROP COLUMN IF EXISTS prompt_key;

-- Phase 6 rollback
DROP TRIGGER IF EXISTS bank_transfers_set_updated_at ON bank_transfers;
DROP INDEX IF EXISTS idx_bank_transfers_workspace_status;
DROP INDEX IF EXISTS idx_bank_transfers_reference;
ALTER TABLE bank_transfers DROP COLUMN IF EXISTS reference;
ALTER TABLE bank_transfers DROP COLUMN IF EXISTS status;
ALTER TABLE bank_transfers DROP COLUMN IF EXISTS matched_order_id;
ALTER TABLE bank_transfers DROP COLUMN IF EXISTS description;
ALTER TABLE bank_transfers DROP COLUMN IF EXISTS updated_at;

DROP TRIGGER IF EXISTS payment_records_set_updated_at ON payment_records;
ALTER TABLE payment_records DROP COLUMN IF EXISTS method;
ALTER TABLE payment_records DROP COLUMN IF EXISTS order_id;
ALTER TABLE payment_records DROP COLUMN IF EXISTS status;
ALTER TABLE payment_records DROP COLUMN IF EXISTS note;
ALTER TABLE payment_records DROP COLUMN IF EXISTS updated_at;

DROP TRIGGER IF EXISTS receivables_set_updated_at ON receivables;
ALTER TABLE receivables DROP COLUMN IF EXISTS customer_id;
ALTER TABLE receivables DROP COLUMN IF EXISTS status;
ALTER TABLE receivables DROP COLUMN IF EXISTS due_date;
ALTER TABLE receivables DROP COLUMN IF EXISTS description;
ALTER TABLE receivables DROP COLUMN IF EXISTS updated_at;

DROP TRIGGER IF EXISTS expense_entries_set_updated_at ON expense_entries;
ALTER TABLE expense_entries DROP COLUMN IF EXISTS category;
ALTER TABLE expense_entries DROP COLUMN IF EXISTS description;
ALTER TABLE expense_entries DROP COLUMN IF EXISTS updated_at;

DROP TRIGGER IF EXISTS income_entries_set_updated_at ON income_entries;
ALTER TABLE income_entries DROP COLUMN IF EXISTS category;
ALTER TABLE income_entries DROP COLUMN IF EXISTS description;
ALTER TABLE income_entries DROP COLUMN IF EXISTS order_id;
ALTER TABLE income_entries DROP COLUMN IF EXISTS updated_at;

-- Phase 5 rollback
DROP INDEX IF EXISTS idx_orders_customer_id;
DROP INDEX IF EXISTS idx_customers_workspace_phone;
ALTER TABLE orders DROP COLUMN IF EXISTS customer_id;

DROP TRIGGER IF EXISTS customer_notes_set_updated_at ON customer_notes;
ALTER TABLE customer_notes DROP COLUMN IF EXISTS updated_at;

DROP TRIGGER IF EXISTS customers_set_updated_at ON customers;
ALTER TABLE customers DROP COLUMN IF EXISTS tier;
ALTER TABLE customers DROP COLUMN IF EXISTS area;
ALTER TABLE customers DROP COLUMN IF EXISTS updated_at;

-- Phase 4 rollback
DROP TRIGGER IF EXISTS orders_set_updated_at ON orders;
ALTER TABLE order_status_events DROP COLUMN IF EXISTS from_status;
ALTER TABLE order_status_events DROP COLUMN IF EXISTS to_status;
ALTER TABLE orders DROP COLUMN IF EXISTS channel;
ALTER TABLE orders DROP COLUMN IF EXISTS customer_name;
ALTER TABLE orders DROP COLUMN IF EXISTS note;
ALTER TABLE orders DROP COLUMN IF EXISTS updated_at;
-- Rename back
ALTER TABLE orders RENAME COLUMN total_amount TO total;
