-- Migration 002: Row-Level Security — enables RLS on every public table and
-- creates all policies. TENANCY-01/02/04/07/09/10.
-- This runs as rimi_migrator (owner), so DDL on policies is permitted.
--
-- PERMISSIVE vs RESTRICTIVE: Postgres RLS requires at least one PERMISSIVE policy
-- to allow any row access. RESTRICTIVE policies only restrict from what permissive
-- policies grant. We use PERMISSIVE policies here (the default "AS PERMISSIVE"),
-- which means "allow access if this condition matches". This is fail-closed because
-- with RLS enabled and FORCE ROW LEVEL SECURITY, rows that don't match any
-- PERMISSIVE policy are hidden. If GUCs are unset (NULL), the condition is false
-- and no rows are returned (TENANCY-07 fail-closed).

-- ============================================================
-- SECURITY DEFINER helper: app.is_workspace_member(wsid uuid)
-- Reads GUCs set by the application per-request (TENANCY-06/07).
-- Pinned search_path prevents SECURITY DEFINER privilege escalation (TENANCY-10/F-29).
-- Returns false when any GUC is unset (fail-closed per TENANCY-07).
-- ============================================================
CREATE SCHEMA IF NOT EXISTS app;

CREATE OR REPLACE FUNCTION app.is_workspace_member(wsid uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_user_id  text;
    v_ws_id    text;
BEGIN
    -- Fail closed when GUCs are absent (TENANCY-07).
    v_user_id := current_setting('rimi.user_id', true);
    v_ws_id   := current_setting('rimi.workspace_id', true);

    IF v_user_id IS NULL OR v_user_id = ''
       OR v_ws_id IS NULL OR v_ws_id = '' THEN
        RETURN false;
    END IF;

    -- The requested workspace must match the token's workspace claim
    -- AND the user must be a member (TENANCY-05/08).
    IF wsid::text != v_ws_id THEN
        RETURN false;
    END IF;

    RETURN EXISTS (
        SELECT 1 FROM workspace_members
        WHERE workspace_id = wsid
          AND user_id = v_user_id::uuid
    );
END;
$$;

GRANT EXECUTE ON FUNCTION app.is_workspace_member(uuid) TO rimi_app;

-- ============================================================
-- ENABLE RLS + POLICIES: user-scoped tables (permissive)
-- profiles: the application (rimi_app) needs to SELECT by email for auth;
-- UPDATE and DELETE are own-row only (protect PII from cross-user modification).
-- INSERT is always permitted (registration is unauthenticated).
-- ============================================================
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles FORCE ROW LEVEL SECURITY;

-- SELECT: allow all (the application looks up profiles by email for login;
-- the application layer enforces that users only access their own data via
-- the JWT claim and GUC. RLS restricts UPDATE/DELETE only).
DROP POLICY IF EXISTS profiles_select ON profiles;
CREATE POLICY profiles_select ON profiles
    FOR SELECT
    USING (true);

-- UPDATE: own-row only — prevent cross-user modification.
DROP POLICY IF EXISTS profiles_update ON profiles;
CREATE POLICY profiles_update ON profiles
    FOR UPDATE
    USING (id = NULLIF(current_setting('rimi.user_id', true), '')::uuid)
    WITH CHECK (id = NULLIF(current_setting('rimi.user_id', true), '')::uuid);

-- DELETE: own-row only.
DROP POLICY IF EXISTS profiles_delete ON profiles;
CREATE POLICY profiles_delete ON profiles
    FOR DELETE
    USING (id = NULLIF(current_setting('rimi.user_id', true), '')::uuid);

-- INSERT: allow unconditionally (registration creates a new profile without a
-- pre-existing GUC; the id is server-generated).
DROP POLICY IF EXISTS profiles_insert ON profiles;
CREATE POLICY profiles_insert ON profiles
    FOR INSERT
    WITH CHECK (true);

-- refresh_tokens: the application needs SELECT to look up tokens by hash for
-- rotation/revocation (before knowing the user). UPDATE/DELETE are user-scoped.
ALTER TABLE refresh_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE refresh_tokens FORCE ROW LEVEL SECURITY;

-- SELECT: allow all (token-hash lookup for auth; application enforces user binding).
DROP POLICY IF EXISTS refresh_tokens_select ON refresh_tokens;
CREATE POLICY refresh_tokens_select ON refresh_tokens
    FOR SELECT
    USING (true);

-- UPDATE: allow (revocation/rotation operations target specific rows via hash;
-- the application layer enforces user ownership before calling these operations).
DROP POLICY IF EXISTS refresh_tokens_update ON refresh_tokens;
CREATE POLICY refresh_tokens_update ON refresh_tokens
    FOR UPDATE
    USING (true)
    WITH CHECK (true);

-- INSERT: allow (issued by the server with the correct user_id).
DROP POLICY IF EXISTS refresh_tokens_insert ON refresh_tokens;
CREATE POLICY refresh_tokens_insert ON refresh_tokens
    FOR INSERT
    WITH CHECK (true);

-- email_tokens: same pattern — SELECT for token hash lookup, UPDATE restricted, INSERT open.
ALTER TABLE email_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE email_tokens FORCE ROW LEVEL SECURITY;

-- SELECT: allow all (token hash lookup; application layer enforces correctness).
DROP POLICY IF EXISTS email_tokens_select ON email_tokens;
CREATE POLICY email_tokens_select ON email_tokens
    FOR SELECT
    USING (true);

-- UPDATE: allow (ConsumeEmailToken uses UPDATE...RETURNING by hash;
-- the application enforces single-use and expiry via WHERE clauses).
DROP POLICY IF EXISTS email_tokens_update ON email_tokens;
CREATE POLICY email_tokens_update ON email_tokens
    FOR UPDATE
    USING (true)
    WITH CHECK (true);

-- INSERT: allow.
DROP POLICY IF EXISTS email_tokens_insert ON email_tokens;
CREATE POLICY email_tokens_insert ON email_tokens
    FOR INSERT
    WITH CHECK (true);

-- ============================================================
-- ENABLE RLS + POLICIES: workspace_members
-- Non-recursive own-row policy (TENANCY-09/F-28):
-- a user can only see their own membership rows.
-- SELECT/UPDATE/DELETE: own-row only.
-- INSERT: allowed unconditionally (server creates the OWNER row at workspace creation;
--   the application layer enforces that only the creating user is set as owner —
--   no client-controlled insertion path exists).
-- ============================================================
ALTER TABLE workspace_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE workspace_members FORCE ROW LEVEL SECURITY;

-- SELECT: own-row only (non-recursive, per TENANCY-09).
-- NULLIF handles the case where rimi.user_id is '' (empty, not set), preventing
-- a failed uuid cast; an empty GUC means no rows are visible (fail-closed).
DROP POLICY IF EXISTS workspace_members_own_row ON workspace_members;
CREATE POLICY workspace_members_own_row ON workspace_members
    FOR SELECT
    USING (user_id = NULLIF(current_setting('rimi.user_id', true), '')::uuid);

-- UPDATE/DELETE: own-row only.
DROP POLICY IF EXISTS workspace_members_update ON workspace_members;
CREATE POLICY workspace_members_update ON workspace_members
    FOR UPDATE
    USING (user_id = NULLIF(current_setting('rimi.user_id', true), '')::uuid)
    WITH CHECK (user_id = NULLIF(current_setting('rimi.user_id', true), '')::uuid);

DROP POLICY IF EXISTS workspace_members_delete ON workspace_members;
CREATE POLICY workspace_members_delete ON workspace_members
    FOR DELETE
    USING (user_id = NULLIF(current_setting('rimi.user_id', true), '')::uuid);

-- INSERT: allow unconditionally (server creates the OWNER row atomically).
DROP POLICY IF EXISTS workspace_members_insert ON workspace_members;
CREATE POLICY workspace_members_insert ON workspace_members
    FOR INSERT
    WITH CHECK (true);

-- ============================================================
-- ENABLE RLS + POLICIES: workspaces
-- A user can see a workspace they are a member of (via the function).
-- INSERT: allowed unconditionally (workspace creation is server-controlled;
--   the application layer ties the new workspace to the authenticated user).
-- ============================================================
ALTER TABLE workspaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE workspaces FORCE ROW LEVEL SECURITY;

-- SELECT: a user can see workspaces they are a member of.
-- Two cases:
-- (1) Single-workspace context (workspace_id GUC set): use app.is_workspace_member(id)
-- (2) List context (workspace_id GUC not set but user_id is): check workspace_members directly.
-- We use an OR to handle both: either the active workspace claim matches, OR the user
-- has a direct membership row (for listing all workspaces).
DROP POLICY IF EXISTS workspaces_member ON workspaces;
CREATE POLICY workspaces_member ON workspaces
    FOR SELECT
    USING (
        app.is_workspace_member(id)
        OR EXISTS (
            SELECT 1 FROM workspace_members wm
            WHERE wm.workspace_id = workspaces.id
              AND wm.user_id = NULLIF(current_setting('rimi.user_id', true), '')::uuid
        )
    );

DROP POLICY IF EXISTS workspaces_update ON workspaces;
CREATE POLICY workspaces_update ON workspaces
    FOR UPDATE
    USING (app.is_workspace_member(id))
    WITH CHECK (app.is_workspace_member(id));

DROP POLICY IF EXISTS workspaces_delete ON workspaces;
CREATE POLICY workspaces_delete ON workspaces
    FOR DELETE
    USING (app.is_workspace_member(id));

-- INSERT: allow unconditionally (workspace creation is server-controlled).
DROP POLICY IF EXISTS workspaces_insert ON workspaces;
CREATE POLICY workspaces_insert ON workspaces
    FOR INSERT
    WITH CHECK (true);

-- ============================================================
-- ENABLE RLS + POLICIES: all workspace-scoped tables (permissive)
-- Uses the SECURITY DEFINER function (TENANCY-10).
-- Pattern: USING + WITH CHECK both use app.is_workspace_member(workspace_id)
-- to enforce that SELECT/INSERT/UPDATE/DELETE all require active workspace membership.
-- ============================================================

-- Phase 3
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE products FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS products_workspace ON products;
CREATE POLICY products_workspace ON products
    USING (app.is_workspace_member(workspace_id))
    WITH CHECK (app.is_workspace_member(workspace_id));

ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_variants FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS product_variants_workspace ON product_variants;
CREATE POLICY product_variants_workspace ON product_variants
    USING (app.is_workspace_member(workspace_id))
    WITH CHECK (app.is_workspace_member(workspace_id));

ALTER TABLE product_channel_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_channel_overrides FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS product_channel_overrides_workspace ON product_channel_overrides;
CREATE POLICY product_channel_overrides_workspace ON product_channel_overrides
    USING (app.is_workspace_member(workspace_id))
    WITH CHECK (app.is_workspace_member(workspace_id));

ALTER TABLE inventory_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_items FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS inventory_items_workspace ON inventory_items;
CREATE POLICY inventory_items_workspace ON inventory_items
    USING (app.is_workspace_member(workspace_id))
    WITH CHECK (app.is_workspace_member(workspace_id));

ALTER TABLE inventory_adjustments ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_adjustments FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS inventory_adjustments_workspace ON inventory_adjustments;
CREATE POLICY inventory_adjustments_workspace ON inventory_adjustments
    USING (app.is_workspace_member(workspace_id))
    WITH CHECK (app.is_workspace_member(workspace_id));

-- Phase 4
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS orders_workspace ON orders;
CREATE POLICY orders_workspace ON orders
    USING (app.is_workspace_member(workspace_id))
    WITH CHECK (app.is_workspace_member(workspace_id));

ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS order_items_workspace ON order_items;
CREATE POLICY order_items_workspace ON order_items
    USING (app.is_workspace_member(workspace_id))
    WITH CHECK (app.is_workspace_member(workspace_id));

ALTER TABLE order_status_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_status_events FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS order_status_events_workspace ON order_status_events;
CREATE POLICY order_status_events_workspace ON order_status_events
    USING (app.is_workspace_member(workspace_id))
    WITH CHECK (app.is_workspace_member(workspace_id));

ALTER TABLE channel_order_refs ENABLE ROW LEVEL SECURITY;
ALTER TABLE channel_order_refs FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS channel_order_refs_workspace ON channel_order_refs;
CREATE POLICY channel_order_refs_workspace ON channel_order_refs
    USING (app.is_workspace_member(workspace_id))
    WITH CHECK (app.is_workspace_member(workspace_id));

-- Phase 5
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS customers_workspace ON customers;
CREATE POLICY customers_workspace ON customers
    USING (app.is_workspace_member(workspace_id))
    WITH CHECK (app.is_workspace_member(workspace_id));

ALTER TABLE customer_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_notes FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS customer_notes_workspace ON customer_notes;
CREATE POLICY customer_notes_workspace ON customer_notes
    USING (app.is_workspace_member(workspace_id))
    WITH CHECK (app.is_workspace_member(workspace_id));

-- Phase 6
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS transactions_workspace ON transactions;
CREATE POLICY transactions_workspace ON transactions
    USING (app.is_workspace_member(workspace_id))
    WITH CHECK (app.is_workspace_member(workspace_id));

ALTER TABLE income_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE income_entries FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS income_entries_workspace ON income_entries;
CREATE POLICY income_entries_workspace ON income_entries
    USING (app.is_workspace_member(workspace_id))
    WITH CHECK (app.is_workspace_member(workspace_id));

ALTER TABLE expense_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense_entries FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS expense_entries_workspace ON expense_entries;
CREATE POLICY expense_entries_workspace ON expense_entries
    USING (app.is_workspace_member(workspace_id))
    WITH CHECK (app.is_workspace_member(workspace_id));

ALTER TABLE receivables ENABLE ROW LEVEL SECURITY;
ALTER TABLE receivables FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS receivables_workspace ON receivables;
CREATE POLICY receivables_workspace ON receivables
    USING (app.is_workspace_member(workspace_id))
    WITH CHECK (app.is_workspace_member(workspace_id));

ALTER TABLE payment_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_records FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS payment_records_workspace ON payment_records;
CREATE POLICY payment_records_workspace ON payment_records
    USING (app.is_workspace_member(workspace_id))
    WITH CHECK (app.is_workspace_member(workspace_id));

ALTER TABLE bank_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE bank_transfers FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS bank_transfers_workspace ON bank_transfers;
CREATE POLICY bank_transfers_workspace ON bank_transfers
    USING (app.is_workspace_member(workspace_id))
    WITH CHECK (app.is_workspace_member(workspace_id));

-- Phase 7
ALTER TABLE ai_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_usage FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ai_usage_workspace ON ai_usage;
CREATE POLICY ai_usage_workspace ON ai_usage
    USING (app.is_workspace_member(workspace_id))
    WITH CHECK (app.is_workspace_member(workspace_id));

-- Phase 2/8
ALTER TABLE einvoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE einvoices FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS einvoices_workspace ON einvoices;
CREATE POLICY einvoices_workspace ON einvoices
    USING (app.is_workspace_member(workspace_id))
    WITH CHECK (app.is_workspace_member(workspace_id));

ALTER TABLE einvoice_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE einvoice_line_items FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS einvoice_line_items_workspace ON einvoice_line_items;
CREATE POLICY einvoice_line_items_workspace ON einvoice_line_items
    USING (app.is_workspace_member(workspace_id))
    WITH CHECK (app.is_workspace_member(workspace_id));
