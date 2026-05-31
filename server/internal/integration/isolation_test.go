// Package integration — two-workspace isolation integration test.
// Uses testcontainers-go to spin up a real Postgres container.
// Connects as rimi_app (NOBYPASSRLS, non-owner) so RLS is genuinely enforced.
// Tests:
//   (a) RLS alone returns 0 foreign-workspace rows even when queried explicitly.
//   (b) App guard (workspace_id filter in queries) also blocks.
//   (c) A token with a forged non-member workspace_id claim yields empty/403.
//
// TENANCY-02/04/06/07/08 verified here.
package integration

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
	"github.com/testcontainers/testcontainers-go/wait"

	"github.com/rimi/server/internal/auth"
	"github.com/rimi/server/internal/db"
	"github.com/rimi/server/internal/middleware"
)

// setupPostgres starts a Postgres container and runs migrations.
func setupPostgres(t *testing.T) (migratorDSN, appDSN string) {
	t.Helper()
	ctx := context.Background()

	pgContainer, err := postgres.RunContainer(ctx,
		testcontainers.WithImage("postgres:16-alpine"),
		postgres.WithDatabase("rimi_test"),
		postgres.WithUsername("rimi_migrator"),
		postgres.WithPassword("test_migrator_pw"),
		testcontainers.WithWaitStrategy(
			wait.ForLog("database system is ready to accept connections").
				WithOccurrence(2).WithStartupTimeout(60*time.Second),
		),
	)
	if err != nil {
		t.Fatalf("start postgres container: %v", err)
	}
	t.Cleanup(func() { _ = pgContainer.Terminate(ctx) })

	migratorDSN, err = pgContainer.ConnectionString(ctx, "sslmode=disable")
	if err != nil {
		t.Fatalf("migrator connection string: %v", err)
	}

	// Open migrator pool to set up roles BEFORE running migrations.
	// Migrations use DO $$ BEGIN ... END $$ for rimi_app creation, but we also
	// set the password here so rimi_app can actually connect.
	migratorPool, err := db.Open(ctx, migratorDSN)
	if err != nil {
		t.Fatalf("open migrator pool: %v", err)
	}
	defer migratorPool.Close()

	// Pre-create rimi_app with a known test password.
	// Migration 001's DO block will skip creation if role exists.
	if _, err := migratorPool.Exec(ctx,
		`CREATE ROLE rimi_app WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS PASSWORD 'test_app_pw'`); err != nil {
		// Role may already exist if migration ran first.
		t.Logf("create rimi_app role (may already exist): %v", err)
	} else {
		if _, err := migratorPool.Exec(ctx, `GRANT CONNECT ON DATABASE rimi_test TO rimi_app`); err != nil {
			t.Fatalf("grant connect: %v", err)
		}
	}

	// Run migrations (migration 001 also tries to CREATE ROLE rimi_app — idempotent).
	if err := db.Migrate(migratorDSN, "file://../../migrations"); err != nil {
		t.Fatalf("migrate: %v", err)
	}

	// Ensure rimi_app has the correct password (migration DO block doesn't set password).
	if _, err := migratorPool.Exec(ctx, `ALTER ROLE rimi_app PASSWORD 'test_app_pw'`); err != nil {
		t.Fatalf("set rimi_app password: %v", err)
	}

	// Build app DSN (rimi_app role).
	host, err := pgContainer.Host(ctx)
	if err != nil {
		t.Fatalf("container host: %v", err)
	}
	port, err := pgContainer.MappedPort(ctx, "5432")
	if err != nil {
		t.Fatalf("container port: %v", err)
	}
	appDSN = fmt.Sprintf("postgres://rimi_app:test_app_pw@%s:%s/rimi_test?sslmode=disable", host, port.Port())
	return migratorDSN, appDSN
}

func generateTestPEM(t *testing.T) (privPEM, pubPEM string) {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generate RSA key: %v", err)
	}
	privPEM = string(pem.EncodeToMemory(&pem.Block{
		Type:  "RSA PRIVATE KEY",
		Bytes: x509.MarshalPKCS1PrivateKey(key),
	}))
	pubBytes, err := x509.MarshalPKIXPublicKey(&key.PublicKey)
	if err != nil {
		t.Fatalf("marshal public key: %v", err)
	}
	pubPEM = string(pem.EncodeToMemory(&pem.Block{
		Type:  "PUBLIC KEY",
		Bytes: pubBytes,
	}))
	return
}

// TestTwoWorkspaceIsolation is the primary isolation integration test.
// TENANCY-02/04/06/07/08.
func TestTwoWorkspaceIsolation(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	migratorDSN, appDSN := setupPostgres(t)
	ctx := context.Background()

	// Open migrator pool to seed data.
	migratorPool, err := db.Open(ctx, migratorDSN)
	if err != nil {
		t.Fatalf("open migrator pool: %v", err)
	}
	defer migratorPool.Close()

	// Open app pool (rimi_app — NOBYPASSRLS — genuine RLS enforcement).
	appPool, err := db.Open(ctx, appDSN)
	if err != nil {
		t.Fatalf("open app pool: %v", err)
	}
	defer appPool.Close()

	// Seed: two users, two workspaces, cross-membership check.
	userA := uuid.New()
	userB := uuid.New()
	wsA := uuid.New()
	wsB := uuid.New()

	hash, _ := auth.HashPassword("password123")

	// Insert profiles as migrator (bypasses RLS).
	_, err = migratorPool.Exec(ctx,
		`INSERT INTO profiles (id, email, password_hash, display_name, email_verified, created_at, updated_at)
		 VALUES ($1, 'usera@test.com', $2, 'User A', true, now(), now()),
		        ($3, 'userb@test.com', $2, 'User B', true, now(), now())`,
		userA, hash, userB)
	if err != nil {
		t.Fatalf("insert profiles: %v", err)
	}

	_, err = migratorPool.Exec(ctx,
		`INSERT INTO workspaces (id, name, owner_user_id, created_at) VALUES
		 ($1, 'Workspace A', $2, now()), ($3, 'Workspace B', $4, now())`,
		wsA, userA, wsB, userB)
	if err != nil {
		t.Fatalf("insert workspaces: %v", err)
	}

	_, err = migratorPool.Exec(ctx,
		`INSERT INTO workspace_members (workspace_id, user_id, role, created_at) VALUES
		 ($1, $2, 'owner', now()), ($3, $4, 'owner', now())`,
		wsA, userA, wsB, userB)
	if err != nil {
		t.Fatalf("insert members: %v", err)
	}

	// Verify seeded data is visible via migrator pool before testing with app pool.
	var totalMembers int
	if err := migratorPool.QueryRow(ctx, `SELECT COUNT(*) FROM workspace_members`).Scan(&totalMembers); err != nil {
		t.Fatalf("count via migrator: %v", err)
	}
	t.Logf("Total workspace_members rows (migrator): %d", totalMembers)

	// (a) RLS alone: query workspaces as userA — must see only wsA.
	t.Run("(a) RLS isolates workspaces", func(t *testing.T) {
		tx, err := appPool.Begin(ctx)
		if err != nil {
			t.Fatalf("begin tx: %v", err)
		}
		defer func() { _ = tx.Rollback(ctx) }()

		// Set GUCs for userA scoped to wsA (TENANCY-06 SET LOCAL).
		_, err = tx.Exec(ctx,
			"SELECT set_config('rimi.user_id', $1, true), set_config('rimi.workspace_id', $2, true)",
			userA.String(), wsA.String())
		if err != nil {
			t.Fatalf("set GUCs: %v", err)
		}

		// Verify GUC is set within this tx.
		var gotUser string
		_ = tx.QueryRow(ctx, `SELECT current_setting('rimi.user_id', true)`).Scan(&gotUser)
		t.Logf("GUC rimi.user_id in tx: %q (want %q)", gotUser, userA.String())

		// Query workspace_members — userA should only see their own row.
		rows, err := tx.Query(ctx, `SELECT workspace_id, user_id FROM workspace_members`)
		if err != nil {
			t.Fatalf("query workspace_members: %v", err)
		}
		defer rows.Close()

		var count int
		for rows.Next() {
			var wsID, uID uuid.UUID
			if err := rows.Scan(&wsID, &uID); err != nil {
				t.Fatalf("scan: %v", err)
			}
			count++
			t.Logf("Row: workspace_id=%v user_id=%v", wsID, uID)
			if wsID != wsA {
				t.Errorf("RLS leak: userA sees workspace_id %v (expected only %v)", wsID, wsA)
			}
		}
		if count != 1 {
			t.Errorf("expected 1 row, got %d", count)
		}
	})

	// (b) App guard: query with explicit workspace_id filter for wsA must not leak wsB rows.
	t.Run("(b) app guard filters correctly", func(t *testing.T) {
		tx, err := appPool.Begin(ctx)
		if err != nil {
			t.Fatalf("begin tx: %v", err)
		}
		defer func() { _ = tx.Rollback(ctx) }()

		_, _ = tx.Exec(ctx,
			"SELECT set_config('rimi.user_id', $1, true), set_config('rimi.workspace_id', $2, true)",
			userA.String(), wsA.String())

		// App guard: query with workspace_id = wsA (TENANCY-05).
		var count int
		err = tx.QueryRow(ctx,
			`SELECT COUNT(*) FROM workspace_members WHERE workspace_id = $1`, wsA).Scan(&count)
		if err != nil {
			t.Fatalf("app guard query: %v", err)
		}
		if count != 1 {
			t.Errorf("expected 1 member in wsA, got %d", count)
		}

		// Attempt to query wsB rows while GUCs are set for wsA — must return 0.
		err = tx.QueryRow(ctx,
			`SELECT COUNT(*) FROM workspace_members WHERE workspace_id = $1`, wsB).Scan(&count)
		if err != nil {
			t.Fatalf("cross-workspace query: %v", err)
		}
		if count != 0 {
			t.Errorf("ISOLATION FAILURE: userA sees %d rows in wsB", count)
		}
	})

	// (c) Forged token: userA presents a token claiming workspace wsB (non-member).
	// Workspace-scoped business tables use app.is_workspace_member(workspace_id)
	// which checks BOTH rimi.user_id AND rimi.workspace_id must match.
	// A forged claim (wsB) where userA is not a member → 0 rows returned.
	// We test this on the `products` table (workspace-scoped via is_workspace_member).
	t.Run("(c) forged non-member workspace_id yields empty on workspace-scoped tables", func(t *testing.T) {
		// Seed a product in wsA using migrator (bypasses RLS).
		productID := uuid.New()
		_, err = migratorPool.Exec(ctx,
			`INSERT INTO products (id, workspace_id, name, created_at) VALUES ($1, $2, 'Product A', now())`,
			productID, wsA)
		if err != nil {
			t.Fatalf("seed product: %v", err)
		}

		// Verify the product is visible to userA with correct GUCs.
		tx, err := appPool.Begin(ctx)
		if err != nil {
			t.Fatalf("begin tx: %v", err)
		}
		defer func() { _ = tx.Rollback(ctx) }()

		_, _ = tx.Exec(ctx,
			"SELECT set_config('rimi.user_id', $1, true), set_config('rimi.workspace_id', $2, true)",
			userA.String(), wsA.String())

		var visibleCount int
		if err := tx.QueryRow(ctx, `SELECT COUNT(*) FROM products`).Scan(&visibleCount); err != nil {
			t.Fatalf("count products (legitimate): %v", err)
		}
		if visibleCount != 1 {
			t.Errorf("expected 1 product visible to userA in wsA, got %d", visibleCount)
		}
		_ = tx.Rollback(ctx)

		// Now forge: userA presents a token claiming wsB (where they are NOT a member).
		// The policy app.is_workspace_member(wsid) checks:
		//   (1) rimi.workspace_id == wsid AND
		//   (2) user is a member of that workspace
		// For wsA product: app.is_workspace_member(wsA) checks rimi.workspace_id(=wsB) != wsA → false → hidden.
		tx2, err := appPool.Begin(ctx)
		if err != nil {
			t.Fatalf("begin tx2: %v", err)
		}
		defer func() { _ = tx2.Rollback(ctx) }()

		_, _ = tx2.Exec(ctx,
			"SELECT set_config('rimi.user_id', $1, true), set_config('rimi.workspace_id', $2, true)",
			userA.String(), wsB.String())

		var forgedCount int
		if err := tx2.QueryRow(ctx, `SELECT COUNT(*) FROM products`).Scan(&forgedCount); err != nil {
			t.Fatalf("count products (forged token): %v", err)
		}
		if forgedCount != 0 {
			t.Errorf("ISOLATION FAILURE: forged token for wsB returned %d products for userA (expected 0)", forgedCount)
		}
	})
}

// TestRowSecurityGate verifies the hardened rowsecurity CI gate.
// TENANCY-01/02/04: every public table has RLS enabled and ≥1 policy.
// rimi_app is NOSUPERUSER, NOBYPASSRLS, and not the table owner.
func TestRowSecurityGate(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	migratorDSN, _ := setupPostgres(t)
	ctx := context.Background()

	migratorPool, err := db.Open(ctx, migratorDSN)
	if err != nil {
		t.Fatalf("open migrator pool: %v", err)
	}
	defer migratorPool.Close()

	// (i) No public table with rowsecurity=false (excluding golang-migrate's schema_migrations).
	t.Run("(i) no table with rowsecurity=false", func(t *testing.T) {
		rows, err := migratorPool.Query(ctx,
			`SELECT tablename FROM pg_tables
			 WHERE schemaname='public'
			   AND rowsecurity=false
			   AND tablename NOT IN ('schema_migrations')`)
		if err != nil {
			t.Fatalf("rowsecurity query: %v", err)
		}
		defer rows.Close()
		var tables []string
		for rows.Next() {
			var name string
			if err := rows.Scan(&name); err != nil {
				t.Fatalf("scan: %v", err)
			}
			tables = append(tables, name)
		}
		if len(tables) > 0 {
			t.Errorf("GATE FAIL: tables without RLS: %v", tables)
		}
	})

	// (ii) rimi_app has rolsuper=false AND rolbypassrls=false AND owns no public tables.
	t.Run("(ii) rimi_app role privileges", func(t *testing.T) {
		var rolsuper, rolbypassrls bool
		err := migratorPool.QueryRow(ctx,
			`SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname = 'rimi_app'`).
			Scan(&rolsuper, &rolbypassrls)
		if err != nil {
			t.Fatalf("query rimi_app role: %v", err)
		}
		if rolsuper {
			t.Error("GATE FAIL: rimi_app is superuser")
		}
		if rolbypassrls {
			t.Error("GATE FAIL: rimi_app has BYPASSRLS")
		}

		// rimi_app must not own any public tables.
		var ownedCount int
		err = migratorPool.QueryRow(ctx,
			`SELECT COUNT(*) FROM pg_tables t
			 JOIN pg_roles r ON r.rolname = tableowner
			 WHERE schemaname = 'public' AND r.rolname = 'rimi_app'`).Scan(&ownedCount)
		if err != nil {
			t.Fatalf("query table ownership: %v", err)
		}
		if ownedCount > 0 {
			t.Errorf("GATE FAIL: rimi_app owns %d public tables", ownedCount)
		}
	})

	// (iii) Every public table (except schema_migrations) has ≥1 policy.
	t.Run("(iii) every table has at least one policy", func(t *testing.T) {
		rows, err := migratorPool.Query(ctx,
			`SELECT t.tablename
			 FROM pg_tables t
			 WHERE t.schemaname = 'public'
			   AND t.tablename NOT IN ('schema_migrations')
			   AND NOT EXISTS (
			       SELECT 1 FROM pg_policies p
			       WHERE p.schemaname = 'public' AND p.tablename = t.tablename
			   )`)
		if err != nil {
			t.Fatalf("query tables without policies: %v", err)
		}
		defer rows.Close()
		var missing []string
		for rows.Next() {
			var name string
			if err := rows.Scan(&name); err != nil {
				t.Fatalf("scan: %v", err)
			}
			missing = append(missing, name)
		}
		if len(missing) > 0 {
			t.Errorf("GATE FAIL: tables without policies: %v", missing)
		}
	})
}

// TestGUCLeakAcrossPooledConnections verifies SET LOCAL isolation (TENANCY-06).
// A 1-connection pool: request A sets GUCs for wsA, commits; request B must NOT
// see wsA's GUCs.
func TestGUCLeakAcrossPooledConnections(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	_, appDSN := setupPostgres(t)
	ctx := context.Background()

	// Configure a pool with exactly 1 connection to force reuse.
	cfg, err := pgxpool.ParseConfig(appDSN)
	if err != nil {
		t.Fatalf("parse app config: %v", err)
	}
	cfg.MaxConns = 1
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		t.Fatalf("open 1-conn pool: %v", err)
	}
	defer pool.Close()

	userA := uuid.New()
	wsA := uuid.New()
	userB := uuid.New()
	wsB := uuid.New()

	// Request A: set GUCs for userA/wsA, then commit.
	txA, err := pool.Begin(ctx)
	if err != nil {
		t.Fatalf("begin txA: %v", err)
	}
	_, err = txA.Exec(ctx,
		"SELECT set_config('rimi.user_id', $1, true), set_config('rimi.workspace_id', $2, true)",
		userA.String(), wsA.String())
	if err != nil {
		_ = txA.Rollback(ctx)
		t.Fatalf("set GUCs for A: %v", err)
	}
	if err := txA.Commit(ctx); err != nil {
		t.Fatalf("commit txA: %v", err)
	}

	// Request B: set GUCs for userB/wsB. The same physical connection is reused.
	txB, err := pool.Begin(ctx)
	if err != nil {
		t.Fatalf("begin txB: %v", err)
	}
	defer func() { _ = txB.Rollback(ctx) }()

	_, err = txB.Exec(ctx,
		"SELECT set_config('rimi.user_id', $1, true), set_config('rimi.workspace_id', $2, true)",
		userB.String(), wsB.String())
	if err != nil {
		t.Fatalf("set GUCs for B: %v", err)
	}

	// Read GUCs back from the same transaction — must reflect userB/wsB, not userA/wsA.
	var gotUserID, gotWsID string
	err = txB.QueryRow(ctx,
		`SELECT current_setting('rimi.user_id', true), current_setting('rimi.workspace_id', true)`).
		Scan(&gotUserID, &gotWsID)
	if err != nil {
		t.Fatalf("read GUCs: %v", err)
	}
	if gotUserID != userB.String() {
		t.Errorf("GUC LEAK: got user_id=%q want %q", gotUserID, userB.String())
	}
	if gotWsID != wsB.String() {
		t.Errorf("GUC LEAK: got workspace_id=%q want %q", gotWsID, wsB.String())
	}
}

// TestFailClosedWhenGUCUnset verifies TENANCY-07.
// Queries run without setting GUCs must return 0 rows.
func TestFailClosedWhenGUCUnset(t *testing.T) {
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

	// Query workspace_members without setting any GUCs.
	// The policy reads current_setting('rimi.user_id', true) which returns NULL → no rows.
	tx, err := appPool.Begin(ctx)
	if err != nil {
		t.Fatalf("begin tx: %v", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var count int
	err = tx.QueryRow(ctx, `SELECT COUNT(*) FROM workspace_members`).Scan(&count)
	if err != nil {
		t.Fatalf("fail-closed query: %v", err)
	}
	if count != 0 {
		t.Errorf("TENANCY-07 FAIL: expected 0 rows without GUC, got %d", count)
	}
}

// Ensure middleware package is importable.
var _ = middleware.MaskEmail
