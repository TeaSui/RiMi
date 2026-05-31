package integration

import (
	"context"
	"testing"

	"github.com/google/uuid"
	"github.com/rimi/server/internal/db"
)

// TestGUCDebug checks if set_config/current_setting works as expected.
func TestGUCDebug(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	_, appDSN := setupPostgres(t)
	ctx := context.Background()

	appPool, err := db.Open(ctx, appDSN)
	if err != nil {
		t.Fatalf("open app pool: %v", err)
	}
	defer appPool.Close()

	userA := uuid.New()
	wsA := uuid.New()

	tx, err := appPool.Begin(ctx)
	if err != nil {
		t.Fatalf("begin tx: %v", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	// Set GUCs.
	if _, err := tx.Exec(ctx,
		"SELECT set_config('rimi.user_id', $1, true), set_config('rimi.workspace_id', $2, true)",
		userA.String(), wsA.String()); err != nil {
		t.Fatalf("set_config: %v", err)
	}

	// Read them back.
	var gotUser, gotWs string
	err = tx.QueryRow(ctx,
		`SELECT current_setting('rimi.user_id', true), current_setting('rimi.workspace_id', true)`).
		Scan(&gotUser, &gotWs)
	if err != nil {
		t.Fatalf("current_setting: %v", err)
	}
	t.Logf("GUC user_id: %q", gotUser)
	t.Logf("GUC workspace_id: %q", gotWs)

	if gotUser != userA.String() {
		t.Errorf("GUC user_id: got %q want %q", gotUser, userA.String())
	}
	if gotWs != wsA.String() {
		t.Errorf("GUC workspace_id: got %q want %q", gotWs, wsA.String())
	}

	// Try the UUID cast directly.
	var castOK bool
	err = tx.QueryRow(ctx,
		`SELECT current_setting('rimi.user_id', true)::uuid = $1`, userA).
		Scan(&castOK)
	if err != nil {
		t.Fatalf("uuid cast: %v", err)
	}
	t.Logf("UUID cast matches: %v", castOK)
}
