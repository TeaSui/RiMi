// Package integration — workspace integration tests.
// Tests workspace creation, membership, and switch flow end-to-end.
// AUTH-05/06/07, TENANCY-05/08 verified here.
package integration

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/rimi/server/internal/auth"
	"github.com/rimi/server/internal/db"
	"github.com/rimi/server/internal/email"
	"github.com/rimi/server/internal/workspace"
)

// TestWorkspaceCreateAndSwitch covers AUTH-05/06/07 end-to-end.
func TestWorkspaceCreateAndSwitch(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	migratorDSN, appDSN := setupPostgres(t)
	ctx := context.Background()

	migratorPool, err := db.Open(ctx, migratorDSN)
	if err != nil {
		t.Fatalf("open migratorPool: %v", err)
	}
	defer migratorPool.Close()
	appPool, err := db.Open(ctx, appDSN)
	if err != nil {
		t.Fatalf("open appPool: %v", err)
	}
	defer appPool.Close()

	privPEM, _ := generateTestPEM(t)
	signer, _ := auth.NewJWTSigner(privPEM, "rimi-auth", "rimi-api", "k1", 15*time.Minute)
	authRepo := auth.NewRepository(appPool)
	authSvc := auth.NewService(authRepo, signer, &email.NoopSender{}, appPool, auth.ServiceConfig{
		LockoutThreshold: 5,
		LockoutDuration:  15 * time.Minute,
		RefreshTokenTTL:  30 * 24 * time.Hour,
		EmailVerifyTTL:   24 * time.Hour,
		PasswordResetTTL: 30 * time.Minute,
	})
	wsRepo := workspace.NewRepository(appPool)

	// Seed a verified user.
	userID := uuid.New()
	hash, _ := auth.HashPassword("wstest-pass")
	_, seedErr := migratorPool.Exec(ctx,
		`INSERT INTO profiles (id, email, password_hash, display_name, email_verified, created_at, updated_at)
		 VALUES ($1, 'wstest@test.com', $2, 'WS Test User', true, now(), now())`,
		userID, hash)
	if seedErr != nil {
		t.Fatalf("seed user: %v", seedErr)
	}

	// Create workspace.
	t.Run("create workspace", func(t *testing.T) {
		wsID := uuid.New()
		ws, err := wsRepo.CreateWorkspace(ctx, wsID, "My Test Shop", userID)
		if err != nil {
			t.Fatalf("CreateWorkspace: %v", err)
		}
		if ws.ID != wsID {
			t.Errorf("workspace ID mismatch: got %v want %v", ws.ID, wsID)
		}
		if ws.Name != "My Test Shop" {
			t.Errorf("workspace name: got %q want %q", ws.Name, "My Test Shop")
		}

		// Verify the owner is a member.
		role, err := wsRepo.IsMember(ctx, userID, wsID)
		if err != nil {
			t.Fatalf("IsMember: %v", err)
		}
		if role != "owner" {
			t.Errorf("expected role=owner, got: %q", role)
		}

		// List workspaces.
		memberships, err := wsRepo.ListWorkspaces(ctx, userID)
		if err != nil {
			t.Fatalf("ListWorkspaces: %v", err)
		}
		if len(memberships) != 1 {
			t.Errorf("expected 1 workspace, got %d", len(memberships))
		}
		if memberships[0].WorkspaceID != wsID {
			t.Errorf("membership workspace ID mismatch")
		}

		// GetWorkspaceForUser.
		fetched, err := wsRepo.GetWorkspaceForUser(ctx, wsID, userID)
		if err != nil {
			t.Fatalf("GetWorkspaceForUser: %v", err)
		}
		if fetched.ID != wsID {
			t.Errorf("GetWorkspaceForUser ID mismatch")
		}
	})

	// Create workspace — duplicate id returns ErrConflict.
	t.Run("duplicate workspace id returns conflict", func(t *testing.T) {
		dupID := uuid.New()
		if _, err := wsRepo.CreateWorkspace(ctx, dupID, "First", userID); err != nil {
			t.Fatalf("first CreateWorkspace: %v", err)
		}
		_, err := wsRepo.CreateWorkspace(ctx, dupID, "Duplicate", userID)
		if err != workspace.ErrConflict {
			t.Errorf("expected ErrConflict, got: %v", err)
		}
	})

	// IsMember returns ErrForbidden for non-member.
	t.Run("non-member workspace returns forbidden", func(t *testing.T) {
		nonMemberID := uuid.New()
		_, err := wsRepo.IsMember(ctx, nonMemberID, uuid.New())
		if err != workspace.ErrForbidden {
			t.Errorf("expected ErrForbidden, got: %v", err)
		}
	})

	// GetWorkspace returns ErrNotFound for missing workspace.
	t.Run("get unknown workspace returns not found", func(t *testing.T) {
		_, err := wsRepo.GetWorkspace(ctx, uuid.New())
		if err != workspace.ErrNotFound {
			t.Errorf("expected ErrNotFound, got: %v", err)
		}
	})

	// IssueWorkspaceScopedTokenPair.
	t.Run("issue workspace scoped token pair", func(t *testing.T) {
		wsID := uuid.New()
		if _, err := wsRepo.CreateWorkspace(ctx, wsID, "Scoped WS", userID); err != nil {
			t.Fatalf("create workspace: %v", err)
		}
		wsIDStr := wsID.String()
		pair, err := authSvc.IssueWorkspaceScopedTokenPair(ctx, userID, &wsIDStr)
		if err != nil {
			t.Fatalf("IssueWorkspaceScopedTokenPair: %v", err)
		}
		if pair.AccessToken == "" {
			t.Fatal("expected non-empty access token")
		}
		if pair.ActiveWorkspaceID == nil || *pair.ActiveWorkspaceID != wsIDStr {
			t.Errorf("workspace_id in pair: got %v want %s", pair.ActiveWorkspaceID, wsIDStr)
		}
	})

	// TENANCY-08: non-member user cannot list workspaces they don't belong to.
	t.Run("non-member sees empty workspace list", func(t *testing.T) {
		otherUser := uuid.New()
		memberships, err := wsRepo.ListWorkspaces(ctx, otherUser)
		if err != nil {
			t.Fatalf("ListWorkspaces: %v", err)
		}
		if len(memberships) != 0 {
			t.Errorf("TENANCY-08 FAIL: non-member user sees %d workspaces", len(memberships))
		}
	})
}
