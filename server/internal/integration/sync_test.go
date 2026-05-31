// Package integration — sync batch idempotency integration test.
// Verifies SYNC-SEC-11: ledger check + apply + insert in one transaction.
// Uses testcontainers-go (setupPostgres from isolation_test.go).
package integration

import (
	"context"
	"testing"

	"github.com/google/uuid"
	"github.com/rimi/server/internal/db"
	"github.com/rimi/server/internal/sync"
)

// TestSyncBatchIdempotentInventoryDelta verifies:
//  1. An inventory_delta op applied for the first time reduces quantity by delta.
//  2. Replaying the exact same op_id returns the cached result; DB quantity is unchanged.
//
// SYNC-SEC-11: idempotency check inside same transaction as apply.
func TestSyncBatchIdempotentInventoryDelta(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	migratorDSN, appDSN := setupPostgres(t)
	ctx := context.Background()

	// Seed via migratorPool — bypasses RLS.
	migratorPool, err := db.Open(ctx, migratorDSN)
	if err != nil {
		t.Fatalf("open migrator pool: %v", err)
	}
	defer migratorPool.Close()

	// App pool — rimi_app, NOBYPASSRLS, genuine RLS enforcement.
	appPool, err := openPool(ctx, appDSN)
	if err != nil {
		t.Fatalf("open app pool: %v", err)
	}
	defer appPool.Close()

	// --- Seed ---
	userID := uuid.New()
	wsID := uuid.New()
	productID := uuid.New()
	variantID := uuid.New()
	itemID := uuid.New()

	// Profile
	_, err = migratorPool.Exec(ctx,
		`INSERT INTO profiles (id, email, password_hash, display_name, email_verified, created_at, updated_at)
		 VALUES ($1, 'syncuser@test.com', 'hash', 'Sync User', true, now(), now())`,
		userID)
	if err != nil {
		t.Fatalf("seed profile: %v", err)
	}

	// Workspace
	_, err = migratorPool.Exec(ctx,
		`INSERT INTO workspaces (id, name, owner_user_id, created_at) VALUES ($1, 'Sync WS', $2, now())`,
		wsID, userID)
	if err != nil {
		t.Fatalf("seed workspace: %v", err)
	}

	// Workspace member
	_, err = migratorPool.Exec(ctx,
		`INSERT INTO workspace_members (workspace_id, user_id, role, created_at)
		 VALUES ($1, $2, 'owner', now())`,
		wsID, userID)
	if err != nil {
		t.Fatalf("seed workspace member: %v", err)
	}

	// Product
	_, err = migratorPool.Exec(ctx,
		`INSERT INTO products (id, workspace_id, name, created_at) VALUES ($1, $2, 'Test Product', now())`,
		productID, wsID)
	if err != nil {
		t.Fatalf("seed product: %v", err)
	}

	// Product variant
	_, err = migratorPool.Exec(ctx,
		`INSERT INTO product_variants (id, workspace_id, product_id, created_at) VALUES ($1, $2, $3, now())`,
		variantID, wsID, productID)
	if err != nil {
		t.Fatalf("seed product variant: %v", err)
	}

	// Inventory item — quantity = 10
	_, err = migratorPool.Exec(ctx,
		`INSERT INTO inventory_items (id, workspace_id, variant_id, quantity, created_at)
		 VALUES ($1, $2, $3, 10, now())`,
		itemID, wsID, variantID)
	if err != nil {
		t.Fatalf("seed inventory_item: %v", err)
	}

	// --- Service ---
	repo := sync.NewRepository(appPool)
	svc := sync.NewService(repo)

	delta := -2
	op := sync.Operation{
		OpID:       "op-replay",
		EntityType: "inventory_item",
		EntityID:   itemID.String(),
		OpType:     "inventory_delta",
		Delta:      &delta,
	}

	// --- First apply ---
	results1, err := svc.ApplyBatch(ctx, userID.String(), wsID.String(), []sync.Operation{op})
	if err != nil {
		t.Fatalf("first ApplyBatch: %v", err)
	}
	if len(results1) != 1 {
		t.Fatalf("first apply: expected 1 result, got %d", len(results1))
	}
	r1 := results1[0]
	if r1.Status != "applied" {
		t.Errorf("first apply: expected status=applied, got %s", r1.Status)
	}
	if r1.ResolvedValue == nil || *r1.ResolvedValue != 8 {
		t.Errorf("first apply: expected resolved_value=8, got %v", r1.ResolvedValue)
	}

	// --- Replay same batch ---
	results2, err := svc.ApplyBatch(ctx, userID.String(), wsID.String(), []sync.Operation{op})
	if err != nil {
		t.Fatalf("second ApplyBatch (replay): %v", err)
	}
	if len(results2) != 1 {
		t.Fatalf("replay: expected 1 result, got %d", len(results2))
	}
	r2 := results2[0]
	if r2.Status != "applied" {
		t.Errorf("replay: expected status=applied, got %s", r2.Status)
	}
	// Cached result must return the same resolved value (8), NOT 6.
	if r2.ResolvedValue == nil || *r2.ResolvedValue != 8 {
		t.Errorf("replay: expected cached resolved_value=8 (idempotent), got %v", r2.ResolvedValue)
	}

	// --- Verify DB quantity = 8 (delta applied exactly once) ---
	var qty int
	err = migratorPool.QueryRow(ctx,
		`SELECT quantity FROM inventory_items WHERE id = $1`, itemID).Scan(&qty)
	if err != nil {
		t.Fatalf("query inventory quantity: %v", err)
	}
	if qty != 8 {
		t.Errorf("DB quantity: expected 8 (delta applied once), got %d", qty)
	}
}
