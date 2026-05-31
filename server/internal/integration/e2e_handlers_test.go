// Package integration — additional handler coverage tests.
// Tests handler error paths and success paths not covered by the main E2E flow.
package integration

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
	chimiddleware "github.com/go-chi/chi/v5/middleware"
	"github.com/google/uuid"
	authhandler "github.com/rimi/server/internal/auth"
	"github.com/rimi/server/internal/db"
	wsmiddleware "github.com/rimi/server/internal/middleware"
	"github.com/rimi/server/internal/workspace"
)

// setupMinimalRouter builds a router for handler-level tests.
func setupMinimalRouter(t *testing.T) (http.Handler, *capturingEmailSender) {
	t.Helper()
	migratorDSN, appDSN := setupPostgres(t)
	_ = migratorDSN
	ctx := context.Background()
	appPool, _ := db.Open(ctx, appDSN)
	t.Cleanup(appPool.Close)

	privPEM, pubPEM := generateTestPEM(t)
	signer, _ := authhandler.NewJWTSigner(privPEM, "rimi-auth", "rimi-api", "k1", 15*time.Minute)
	verifier, _ := wsmiddleware.NewJWTVerifier(pubPEM, "rimi-auth", "rimi-api")
	sender := &capturingEmailSender{}

	authRepo := authhandler.NewRepository(appPool)
	authSvc := authhandler.NewService(authRepo, signer, sender, appPool, authhandler.ServiceConfig{
		LockoutThreshold: 5,
		LockoutDuration:  15 * time.Minute,
		RefreshTokenTTL:  30 * 24 * time.Hour,
		EmailVerifyTTL:   24 * time.Hour,
		PasswordResetTTL: 30 * time.Minute,
	})
	authH := authhandler.NewHandler(authSvc)
	wsRepo := workspace.NewRepository(appPool)
	wsH := workspace.NewHandler(wsRepo, authSvc)

	r := chi.NewRouter()
	r.Use(chimiddleware.Recoverer)
	r.Use(wsmiddleware.RequestLogger)
	r.Use(func(next http.Handler) http.Handler {
		return http.MaxBytesHandler(next, 1<<20)
	})
	r.Route("/v1", func(r chi.Router) {
		r.Route("/auth", func(r chi.Router) {
			r.Post("/register", authH.Register)
			r.Post("/verify-email", authH.VerifyEmail)
			r.Post("/login", authH.Login)
			r.Post("/refresh", authH.Refresh)
			r.Post("/logout", authH.Logout)
			r.Post("/password-reset/request", authH.PasswordResetRequest)
			r.Post("/password-reset/confirm", authH.PasswordResetConfirm)
			r.Group(func(r chi.Router) {
				r.Use(wsmiddleware.Authenticate(verifier))
				r.Get("/me", authH.Me)
			})
		})
		r.Route("/workspaces", func(r chi.Router) {
			r.Use(wsmiddleware.Authenticate(verifier))
			r.Use(wsmiddleware.TenantTx(appPool))
			r.Post("/", wsH.CreateWorkspace)
			r.Get("/", wsH.ListWorkspaces)
			r.Post("/{id}/switch", wsH.SwitchWorkspace)
		})
	})
	return r, sender
}

// TestHandlerPasswordResetConfirmFlow exercises the full password reset confirm path.
func TestHandlerPasswordResetConfirmFlow(t *testing.T) {
	if testing.Short() {
		t.Skip()
	}

	router, sender := setupMinimalRouter(t)

	// Register + verify user.
	httpPost(t, router, "/v1/auth/register", map[string]any{
		"email": "prc@test.com", "password": "reset-flow-pw!", "display_name": "PRC User",
	}, "")
	time.Sleep(50 * time.Millisecond)
	verifyTok := sender.lastVerifyToken
	if verifyTok == "" {
		t.Fatal("no verify token")
	}
	w := httpPost(t, router, "/v1/auth/verify-email", map[string]any{"token": verifyTok}, "")
	if w.Code != http.StatusOK {
		t.Fatalf("verify: %d", w.Code)
	}

	// Request password reset.
	w = httpPost(t, router, "/v1/auth/password-reset/request", map[string]any{"email": "prc@test.com"}, "")
	if w.Code != http.StatusOK {
		t.Fatalf("reset request: %d", w.Code)
	}
	time.Sleep(50 * time.Millisecond)
	resetTok := sender.lastResetToken
	if resetTok == "" {
		t.Fatal("no reset token")
	}

	// Confirm password reset — success.
	t.Run("password reset confirm success", func(t *testing.T) {
		w := httpPost(t, router, "/v1/auth/password-reset/confirm", map[string]any{
			"token": resetTok, "new_password": "new-reset-pw!",
		}, "")
		if w.Code != http.StatusOK {
			t.Fatalf("confirm reset: expected 200, got %d: %s", w.Code, w.Body.String())
		}
		body := parseBody(t, w)
		data, _ := body["data"].(map[string]any)
		if data["reset"] != true {
			t.Errorf("expected reset=true, got: %v", data)
		}
	})

	// Confirm with same token again — 410 TOKEN_INVALID_OR_EXPIRED.
	t.Run("password reset confirm token reuse", func(t *testing.T) {
		w := httpPost(t, router, "/v1/auth/password-reset/confirm", map[string]any{
			"token": resetTok, "new_password": "another-pw!",
		}, "")
		if w.Code != http.StatusGone {
			t.Fatalf("expected 410, got %d", w.Code)
		}
	})

	// Confirm with weak password — 400 WEAK_PASSWORD.
	t.Run("password reset confirm weak password", func(t *testing.T) {
		// Request another reset first.
		httpPost(t, router, "/v1/auth/password-reset/request", map[string]any{"email": "prc@test.com"}, "")
		time.Sleep(50 * time.Millisecond)
		tok2 := sender.lastResetToken

		w := httpPost(t, router, "/v1/auth/password-reset/confirm", map[string]any{
			"token": tok2, "new_password": "short",
		}, "")
		if w.Code != http.StatusBadRequest {
			t.Fatalf("expected 400, got %d: %s", w.Code, w.Body.String())
		}
	})
}

// TestHandlerVerifyEmailPaths exercises verify-email handler paths.
func TestHandlerVerifyEmailPaths(t *testing.T) {
	if testing.Short() {
		t.Skip()
	}

	router, sender := setupMinimalRouter(t)

	// Register user.
	httpPost(t, router, "/v1/auth/register", map[string]any{
		"email": "verify@test.com", "password": "verify-pw!!", "display_name": "Verify User",
	}, "")
	time.Sleep(50 * time.Millisecond)
	tok := sender.lastVerifyToken
	if tok == "" {
		t.Fatal("no verify token")
	}

	// Success path.
	t.Run("verify email success", func(t *testing.T) {
		w := httpPost(t, router, "/v1/auth/verify-email", map[string]any{"token": tok}, "")
		if w.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
		}
	})

	// Expired/used token — 410.
	t.Run("verify email used token", func(t *testing.T) {
		w := httpPost(t, router, "/v1/auth/verify-email", map[string]any{"token": tok}, "")
		if w.Code != http.StatusGone {
			t.Fatalf("expected 410, got %d", w.Code)
		}
	})
}

// TestHandlerRegisterPaths exercises additional register paths.
func TestHandlerRegisterPaths(t *testing.T) {
	if testing.Short() {
		t.Skip()
	}

	router, _ := setupMinimalRouter(t)

	// Weak password — 400 VALIDATION_ERROR.
	t.Run("register weak password", func(t *testing.T) {
		w := httpPost(t, router, "/v1/auth/register", map[string]any{
			"email": "reg@test.com", "password": "short", "display_name": "Reg User",
		}, "")
		if w.Code != http.StatusBadRequest {
			t.Fatalf("expected 400, got %d: %s", w.Code, w.Body.String())
		}
	})

	// Valid registration with phone.
	t.Run("register with phone", func(t *testing.T) {
		phone := "+84912345678"
		w := httpPost(t, router, "/v1/auth/register", map[string]any{
			"email": "phone@test.com", "password": "valid-pass!", "display_name": "Phone User",
			"phone": phone,
		}, "")
		if w.Code != http.StatusAccepted {
			t.Fatalf("expected 202, got %d: %s", w.Code, w.Body.String())
		}
	})

	// Duplicate registration — still 202 (anti-enumeration).
	t.Run("duplicate email returns 202", func(t *testing.T) {
		httpPost(t, router, "/v1/auth/register", map[string]any{
			"email": "dup@test.com", "password": "valid-pass!", "display_name": "Dup User",
		}, "")
		w := httpPost(t, router, "/v1/auth/register", map[string]any{
			"email": "dup@test.com", "password": "valid-pass!", "display_name": "Dup2",
		}, "")
		if w.Code != http.StatusAccepted {
			t.Fatalf("expected 202 for duplicate email, got %d", w.Code)
		}
	})
}

// TestHandlerRefreshPaths exercises refresh handler paths.
func TestHandlerRefreshPaths(t *testing.T) {
	if testing.Short() {
		t.Skip()
	}

	router, sender := setupMinimalRouter(t)

	// Register + verify + login.
	httpPost(t, router, "/v1/auth/register", map[string]any{
		"email": "refresh@test.com", "password": "refresh-pw!!", "display_name": "Refresh User",
	}, "")
	time.Sleep(50 * time.Millisecond)
	tok := sender.lastVerifyToken
	httpPost(t, router, "/v1/auth/verify-email", map[string]any{"token": tok}, "")

	w := httpPost(t, router, "/v1/auth/login", map[string]any{
		"email": "refresh@test.com", "password": "refresh-pw!!",
	}, "")
	if w.Code != http.StatusOK {
		t.Fatalf("login: %d", w.Code)
	}
	body := parseBody(t, w)
	data, _ := body["data"].(map[string]any)
	refreshTok, _ := data["refresh_token"].(string)

	// Invalid refresh token — 401.
	t.Run("invalid refresh token", func(t *testing.T) {
		w := httpPost(t, router, "/v1/auth/refresh", map[string]any{
			"refresh_token": "invalid-but-long-enough-token",
		}, "")
		if w.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401, got %d", w.Code)
		}
	})

	// Valid refresh — 200.
	t.Run("valid refresh", func(t *testing.T) {
		w := httpPost(t, router, "/v1/auth/refresh", map[string]any{
			"refresh_token": refreshTok,
		}, "")
		if w.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
		}
	})
}

// TestHandlerWorkspacePaths exercises workspace handler paths more thoroughly.
func TestHandlerWorkspacePaths(t *testing.T) {
	if testing.Short() {
		t.Skip()
	}

	router, sender := setupMinimalRouter(t)

	// Register + verify + login.
	httpPost(t, router, "/v1/auth/register", map[string]any{
		"email": "ws@test.com", "password": "ws-pass-word!", "display_name": "WS User",
	}, "")
	time.Sleep(50 * time.Millisecond)
	tok := sender.lastVerifyToken
	httpPost(t, router, "/v1/auth/verify-email", map[string]any{"token": tok}, "")
	w := httpPost(t, router, "/v1/auth/login", map[string]any{
		"email": "ws@test.com", "password": "ws-pass-word!",
	}, "")
	body := parseBody(t, w)
	data, _ := body["data"].(map[string]any)
	accessToken, _ := data["access_token"].(string)

	// Create workspace with client-supplied id.
	t.Run("create workspace with client id", func(t *testing.T) {
		wsID := uuid.New().String()
		w := httpPost(t, router, "/v1/workspaces", map[string]any{
			"id": wsID, "name": "My Shop",
		}, accessToken)
		if w.Code != http.StatusCreated {
			t.Fatalf("expected 201, got %d: %s", w.Code, w.Body.String())
		}
		body := parseBody(t, w)
		data, _ := body["data"].(map[string]any)
		ws, _ := data["workspace"].(map[string]any)
		if ws["id"] != wsID {
			t.Errorf("workspace id: got %v want %v", ws["id"], wsID)
		}
	})

	// Create workspace with invalid id — 400.
	t.Run("create workspace invalid id", func(t *testing.T) {
		w := httpPost(t, router, "/v1/workspaces", map[string]any{
			"id": "not-a-uuid", "name": "Bad WS",
		}, accessToken)
		if w.Code != http.StatusBadRequest {
			t.Fatalf("expected 400, got %d", w.Code)
		}
	})

	// Create workspace with empty name — 400.
	t.Run("create workspace empty name", func(t *testing.T) {
		w := httpPost(t, router, "/v1/workspaces", map[string]any{"name": ""}, accessToken)
		if w.Code != http.StatusBadRequest {
			t.Fatalf("expected 400, got %d", w.Code)
		}
	})

	// Switch to non-existent workspace — 403.
	t.Run("switch to non-existent workspace", func(t *testing.T) {
		fakeID := uuid.New().String()
		w := httpPost(t, router, "/v1/workspaces/"+fakeID+"/switch", nil, accessToken)
		if w.Code != http.StatusForbidden {
			t.Fatalf("expected 403, got %d", w.Code)
		}
	})

	// Switch with invalid UUID — 400.
	t.Run("switch with invalid uuid", func(t *testing.T) {
		w := httpPost(t, router, "/v1/workspaces/not-a-uuid/switch", nil, accessToken)
		if w.Code != http.StatusBadRequest {
			t.Fatalf("expected 400, got %d", w.Code)
		}
	})
}
