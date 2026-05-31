-- Migration 001: All-tables-upfront schema creation.
-- Creates every core table for phases 1-8 with workspace_id, PKs, timestamps, and money types.
-- RLS is NOT enabled here — that is migration 002.
-- Owner: rimi_migrator role.

-- Enable citext for case-insensitive email lookups (TENANCY-11 index + case-insensitivity).
CREATE EXTENSION IF NOT EXISTS "citext";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- DB ROLES (created idempotently so re-runs are safe)
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rimi_app') THEN
    CREATE ROLE rimi_app WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
  END IF;
END
$$;

-- ============================================================
-- PHASE 1 — AUTH TABLES
-- ============================================================

-- profiles: one row per user; PII classification Level 2 (PII-01/02).
CREATE TABLE IF NOT EXISTS profiles (
    id              uuid PRIMARY KEY,
    email           citext NOT NULL,
    password_hash   text   NOT NULL,  -- argon2id hash (AUTH-01)
    display_name    text   NOT NULL,
    phone           text,
    email_verified  boolean NOT NULL DEFAULT false,  -- AUTH-13
    failed_attempts integer NOT NULL DEFAULT 0,      -- AUTH-04 lockout counter
    locked_until    timestamptz,                      -- AUTH-04 lockout expiry
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT profiles_email_key UNIQUE (email)
);

-- workspaces: one per tenant.
CREATE TABLE IF NOT EXISTS workspaces (
    id            uuid PRIMARY KEY,  -- client-supplied offline-first
    name          text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 120),
    owner_user_id uuid NOT NULL REFERENCES profiles(id),
    created_at    timestamptz NOT NULL DEFAULT now()
);

-- workspace_members: flat M:N membership (TENANCY-09 non-recursive RLS anchor).
CREATE TABLE IF NOT EXISTS workspace_members (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    user_id      uuid NOT NULL REFERENCES profiles(id)   ON DELETE CASCADE,
    role         text NOT NULL CHECK (role IN ('owner', 'member')),  -- AUTH-13 server-set
    created_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workspace_members_workspace_user_key UNIQUE (workspace_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_workspace_members_workspace_id ON workspace_members(workspace_id);
CREATE INDEX IF NOT EXISTS idx_workspace_members_user_id      ON workspace_members(user_id);

-- refresh_tokens: durable revocable sessions with family tracking (SESSION-01..06).
CREATE TABLE IF NOT EXISTS refresh_tokens (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    family_id      uuid NOT NULL,   -- rotation chain SESSION-04
    token_hash     text NOT NULL,   -- SHA-256 of opaque token SESSION-02
    issued_at      timestamptz NOT NULL DEFAULT now(),
    expires_at     timestamptz NOT NULL,  -- absolute expiry SESSION-05
    revoked_at     timestamptz,
    revoked_reason text CHECK (revoked_reason IN ('rotated','logout','reuse_detected','password_reset'))
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_refresh_tokens_token_hash ON refresh_tokens(token_hash);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_family ON refresh_tokens(user_id, family_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_id    ON refresh_tokens(user_id);

-- email_tokens: verification and password-reset tokens (EMAIL-01/02/03).
CREATE TABLE IF NOT EXISTS email_tokens (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    purpose      text NOT NULL CHECK (purpose IN ('email_verification','password_reset')),
    token_hash   text NOT NULL,   -- SHA-256 of raw token EMAIL-01
    expires_at   timestamptz NOT NULL,  -- EMAIL-03
    consumed_at  timestamptz,           -- single-use EMAIL-02
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_email_tokens_token_hash ON email_tokens(token_hash);
CREATE INDEX IF NOT EXISTS idx_email_tokens_user_id    ON email_tokens(user_id);

-- ============================================================
-- PHASE 3 — PRODUCTS & INVENTORY
-- ============================================================

CREATE TABLE IF NOT EXISTS products (
    id           uuid PRIMARY KEY,
    workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    name         text NOT NULL,
    description  text,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_products_workspace_id ON products(workspace_id);

CREATE TABLE IF NOT EXISTS product_variants (
    id           uuid PRIMARY KEY,
    workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    product_id   uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    sku          text,
    price        NUMERIC(15,2),
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_product_variants_workspace_id ON product_variants(workspace_id);

CREATE TABLE IF NOT EXISTS product_channel_overrides (
    id           uuid PRIMARY KEY,
    workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    variant_id   uuid NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    channel      text NOT NULL,
    price        NUMERIC(15,2),
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_product_channel_overrides_workspace_id ON product_channel_overrides(workspace_id);

CREATE TABLE IF NOT EXISTS inventory_items (
    id           uuid PRIMARY KEY,
    workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    variant_id   uuid NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
    quantity     integer NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_inventory_items_workspace_id ON inventory_items(workspace_id);

CREATE TABLE IF NOT EXISTS inventory_adjustments (
    id           uuid PRIMARY KEY,
    workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    item_id      uuid NOT NULL REFERENCES inventory_items(id) ON DELETE CASCADE,
    delta        integer NOT NULL,
    reason       text,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_inventory_adjustments_workspace_id ON inventory_adjustments(workspace_id);

-- ============================================================
-- PHASE 4 — ORDERS
-- ============================================================

CREATE TABLE IF NOT EXISTS orders (
    id           uuid PRIMARY KEY,
    workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    status       text NOT NULL DEFAULT 'pending',
    total        NUMERIC(15,2),
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_orders_workspace_id ON orders(workspace_id);

CREATE TABLE IF NOT EXISTS order_items (
    id           uuid PRIMARY KEY,
    workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    order_id     uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    variant_id   uuid REFERENCES product_variants(id),
    quantity     integer NOT NULL CHECK (quantity >= 0),
    unit_price   NUMERIC(15,2),
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_order_items_workspace_id ON order_items(workspace_id);

CREATE TABLE IF NOT EXISTS order_status_events (
    id           uuid PRIMARY KEY,
    workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    order_id     uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    status       text NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_order_status_events_workspace_id ON order_status_events(workspace_id);

CREATE TABLE IF NOT EXISTS channel_order_refs (
    id            uuid PRIMARY KEY,
    workspace_id  uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    order_id      uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    channel       text NOT NULL,
    external_id   text NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (workspace_id, channel, external_id)
);
CREATE INDEX IF NOT EXISTS idx_channel_order_refs_workspace_id ON channel_order_refs(workspace_id);

-- ============================================================
-- PHASE 5 — CRM
-- ============================================================

CREATE TABLE IF NOT EXISTS customers (
    id           uuid PRIMARY KEY,
    workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    name         text,
    phone        text,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_customers_workspace_id ON customers(workspace_id);

CREATE TABLE IF NOT EXISTS customer_notes (
    id           uuid PRIMARY KEY,
    workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    customer_id  uuid NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    note         text,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_customer_notes_workspace_id ON customer_notes(workspace_id);

-- ============================================================
-- PHASE 6 — FINANCE
-- ============================================================

CREATE TABLE IF NOT EXISTS transactions (
    id           uuid PRIMARY KEY,
    workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    amount       NUMERIC(15,2) NOT NULL,
    type         text NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_transactions_workspace_id ON transactions(workspace_id);

CREATE TABLE IF NOT EXISTS income_entries (
    id           uuid PRIMARY KEY,
    workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    amount       NUMERIC(15,2) NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_income_entries_workspace_id ON income_entries(workspace_id);

CREATE TABLE IF NOT EXISTS expense_entries (
    id           uuid PRIMARY KEY,
    workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    amount       NUMERIC(15,2) NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_expense_entries_workspace_id ON expense_entries(workspace_id);

CREATE TABLE IF NOT EXISTS receivables (
    id           uuid PRIMARY KEY,
    workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    amount       NUMERIC(15,2) NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_receivables_workspace_id ON receivables(workspace_id);

CREATE TABLE IF NOT EXISTS payment_records (
    id           uuid PRIMARY KEY,
    workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    amount       NUMERIC(15,2) NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_payment_records_workspace_id ON payment_records(workspace_id);

CREATE TABLE IF NOT EXISTS bank_transfers (
    id           uuid PRIMARY KEY,
    workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    amount       NUMERIC(15,2) NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_bank_transfers_workspace_id ON bank_transfers(workspace_id);

-- ============================================================
-- PHASE 7 — AI USAGE
-- ============================================================

CREATE TABLE IF NOT EXISTS ai_usage (
    id           uuid PRIMARY KEY,
    workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    model        text NOT NULL,
    tokens_in    integer NOT NULL DEFAULT 0,
    tokens_out   integer NOT NULL DEFAULT 0,
    cost_usd     NUMERIC(15,6),
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ai_usage_workspace_id ON ai_usage(workspace_id);

-- ============================================================
-- PHASE 2/8 — E-INVOICE (optional)
-- ============================================================

CREATE TABLE IF NOT EXISTS einvoices (
    id           uuid PRIMARY KEY,
    workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    order_id     uuid REFERENCES orders(id),
    status       text NOT NULL DEFAULT 'draft',
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_einvoices_workspace_id ON einvoices(workspace_id);

CREATE TABLE IF NOT EXISTS einvoice_line_items (
    id           uuid PRIMARY KEY,
    workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    einvoice_id  uuid NOT NULL REFERENCES einvoices(id) ON DELETE CASCADE,
    description  text,
    quantity     integer NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    unit_price   NUMERIC(15,2),
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_einvoice_line_items_workspace_id ON einvoice_line_items(workspace_id);

-- ============================================================
-- GRANTS for rimi_app (non-owner, NOBYPASSRLS per ADR-002)
-- ============================================================
GRANT USAGE ON SCHEMA public TO rimi_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO rimi_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO rimi_app;
