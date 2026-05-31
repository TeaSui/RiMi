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
	migratorDSN, _ := setupPostgres(t)
	ctx := context.Background()

	pool, err := openPool(ctx, migratorDSN)
	if err != nil {
		t.Fatalf("open pool: %v", err)
	}
	defer pool.Close()

	// Check updated_at and deleted_at on all three tables
	for _, tbl := range []string{"products", "product_variants", "inventory_items"} {
		var hasUpdated, hasDeleted bool
		if err := pool.QueryRow(ctx, `
			SELECT
			  EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name=$1 AND column_name='updated_at'),
			  EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name=$1 AND column_name='deleted_at')
		`, tbl).Scan(&hasUpdated, &hasDeleted); err != nil {
			t.Fatalf("%s column check: %v", tbl, err)
		}
		if !hasUpdated {
			t.Errorf("%s.updated_at missing", tbl)
		}
		if !hasDeleted {
			t.Errorf("%s.deleted_at missing", tbl)
		}
	}

	// Check triggers exist on all three tables
	for _, tbl := range []string{"products", "product_variants", "inventory_items"} {
		var triggerExists bool
		if err := pool.QueryRow(ctx, `
			SELECT EXISTS(
				SELECT 1 FROM pg_trigger t
				JOIN pg_class c ON c.oid = t.tgrelid
				WHERE c.relname = $1 AND t.tgname = $1 || '_set_updated_at'
			)
		`, tbl).Scan(&triggerExists); err != nil {
			t.Fatalf("%s trigger check: %v", tbl, err)
		}
		if !triggerExists {
			t.Errorf("%s_set_updated_at trigger missing", tbl)
		}
	}

	// Check sync_applied_ops indexes exist
	for _, idx := range []string{"idx_sync_applied_ops_ttl", "idx_sync_applied_ops_workspace"} {
		var idxExists bool
		if err := pool.QueryRow(ctx, `
			SELECT EXISTS(SELECT 1 FROM pg_indexes WHERE indexname = $1)
		`, idx).Scan(&idxExists); err != nil {
			t.Fatalf("%s index check: %v", idx, err)
		}
		if !idxExists {
			t.Errorf("index %s missing", idx)
		}
	}

	// Check sync_applied_ops has FORCE RLS
	var rlsEnabled, forceRLS bool
	if err := pool.QueryRow(ctx, `
		SELECT relrowsecurity, relforcerowsecurity
		FROM pg_class WHERE relname = 'sync_applied_ops'
	`).Scan(&rlsEnabled, &forceRLS); err != nil {
		t.Fatalf("rls check: %v", err)
	}
	if !rlsEnabled || !forceRLS {
		t.Fatalf("sync_applied_ops RLS: enabled=%v force=%v", rlsEnabled, forceRLS)
	}

	// Check cleanup function is SECURITY DEFINER (SYNC-SEC-16)
	var isSecDef bool
	if err := pool.QueryRow(ctx, `
		SELECT p.prosecdef
		FROM pg_proc p
		JOIN pg_namespace n ON n.oid = p.pronamespace
		WHERE n.nspname = 'app' AND p.proname = 'cleanup_sync_applied_ops'
	`).Scan(&isSecDef); err != nil {
		t.Fatalf("cleanup function check: %v", err)
	}
	if !isSecDef {
		t.Fatal("app.cleanup_sync_applied_ops is not SECURITY DEFINER (SYNC-SEC-16 violation)")
	}
}
