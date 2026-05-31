package integration

import (
	"context"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

func openPool(ctx context.Context, dsn string) (*pgxpool.Pool, error) {
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		return nil, err
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, err
	}
	return pool, nil
}

func TestMigration000003(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}
	migratorDSN, appDSN := setupPostgres(t)
	_ = appDSN
	ctx := context.Background()

	migratorPool, err := openPool(ctx, migratorDSN)
	if err != nil {
		t.Fatalf("open migrator pool: %v", err)
	}
	defer migratorPool.Close()

	// Check products.updated_at exists
	var hasUpdated, hasDeleted bool
	if err := migratorPool.QueryRow(ctx, `
		SELECT
		  EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='updated_at'),
		  EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='deleted_at')
	`).Scan(&hasUpdated, &hasDeleted); err != nil {
		t.Fatalf("query columns: %v", err)
	}
	if !hasUpdated {
		t.Fatal("products.updated_at missing")
	}
	if !hasDeleted {
		t.Fatal("products.deleted_at missing")
	}

	// Check sync_applied_ops exists with FORCE RLS
	var rlsEnabled, forceRLS bool
	if err := migratorPool.QueryRow(ctx, `
		SELECT relrowsecurity, relforcerowsecurity
		FROM pg_class WHERE relname = 'sync_applied_ops'
	`).Scan(&rlsEnabled, &forceRLS); err != nil {
		t.Fatalf("query rls: %v", err)
	}
	if !rlsEnabled || !forceRLS {
		t.Fatalf("sync_applied_ops RLS: enabled=%v force=%v", rlsEnabled, forceRLS)
	}

	// Check cleanup function exists
	var fnExists bool
	if err := migratorPool.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM pg_proc p
			JOIN pg_namespace n ON n.oid = p.pronamespace
			WHERE n.nspname = 'app' AND p.proname = 'cleanup_sync_applied_ops'
		)
	`).Scan(&fnExists); err != nil {
		t.Fatalf("query function: %v", err)
	}
	if !fnExists {
		t.Fatal("app.cleanup_sync_applied_ops function missing")
	}
}
