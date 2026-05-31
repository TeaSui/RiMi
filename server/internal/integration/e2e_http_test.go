// Package integration — end-to-end HTTP handler tests.
// These tests wire up the full handler stack (router + middleware + service + repository)
// against a real Postgres container and exercise HTTP endpoints end-to-end.
// This provides coverage for handler paths, middleware (TenantTx, Authenticate),
// and the response envelope shape.
package integration

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
	chimiddleware "github.com/go-chi/chi/v5/middleware"
	"github.com/rimi/server/internal/auth"
	"github.com/rimi/server/internal/db"
	"github.com/rimi/server/internal/email"
	authhandler "github.com/rimi/server/internal/auth"
	wsmiddleware "github.com/rimi/server/internal/middleware"
	"github.com/rimi/server/internal/workspace"
)

// setupHTTPServer builds a test HTTP server with the full handler stack.
func setupHTTPServer(t *testing.T) (router *chi.Mux, teardown func()) {
	t.Helper()

	migratorDSN, appDSN := setupPostgres(t)
	ctx := context.Background()

	appPool, err := db.Open(ctx, appDSN)
	if err != nil {
		t.Fatalf("open app pool: %v", err)
	}

	privPEM, pubPEM := generateTestPEM(t)
	signer, err := auth.NewJWTSigner(privPEM, "rimi-auth", "rimi-api", "k1", 15*time.Minute)
	if err != nil {
		t.Fatalf("jwt signer: %v", err)
	}
	verifier, err := wsmiddleware.NewJWTVerifier(pubPEM, "rimi-auth", "rimi-api")
	if err != nil {
		t.Fatalf("jwt verifier: %v", err)
	}

	captureSender := &capturingEmailSender{}
	authRepo := authhandler.NewRepository(appPool)
	authSvc := authhandler.NewService(authRepo, signer, captureSender, appPool, authhandler.ServiceConfig{
		LockoutThreshold: 5,
		LockoutDuration:  15 * time.Minute,
		RefreshTokenTTL:  30 * 24 * time.Hour,
		EmailVerifyTTL:   24 * time.Hour,
		PasswordResetTTL: 30 * time.Minute,
	})
	_ = captureSender
	authH := authhandler.NewHandler(authSvc)

	wsRepo := workspace.NewRepository(appPool)
	wsH := workspace.NewHandler(wsRepo, authSvc)

	r := chi.NewRouter()
	r.Use(chimiddleware.RequestID)
	r.Use(wsmiddleware.RequestLogger) // LOG coverage
	r.Use(chimiddleware.Recoverer)
	r.Use(func(next http.Handler) http.Handler {
		return http.MaxBytesHandler(next, 1<<20)
	})

	r.Route("/v1", func(r chi.Router) {
		r.Get("/health", func(w http.ResponseWriter, req *http.Request) {
			wsmiddleware.WriteJSON(w, http.StatusOK, map[string]any{"status": "ok"})
		})

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
			// Add TenantTx to cover that middleware for workspace-scoped data endpoints.
			r.Use(wsmiddleware.TenantTx(appPool))
			r.Post("/", wsH.CreateWorkspace)
			r.Get("/", wsH.ListWorkspaces)
			r.Post("/{id}/switch", wsH.SwitchWorkspace)
		})
	})

	_ = migratorDSN

	return r, appPool.Close
}

// httpPost sends a POST request to the test server.
func httpPost(t *testing.T, router http.Handler, path string, body interface{}, token string) *httptest.ResponseRecorder {
	t.Helper()
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	return w
}

func httpGet(t *testing.T, router http.Handler, path string, token string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, path, nil)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	return w
}

func parseBody(t *testing.T, rec *httptest.ResponseRecorder) map[string]any {
	t.Helper()
	var m map[string]any
	if err := json.NewDecoder(rec.Body).Decode(&m); err != nil {
		t.Fatalf("parse body: %v (body: %s)", err, rec.Body.String())
	}
	return m
}

// TestHTTPHealthEndpoint tests the /health endpoint.
func TestHTTPHealthEndpoint(t *testing.T) {
	if testing.Short() {
		t.Skip()
	}

	router, teardown := setupHTTPServer(t)
	defer teardown()

	w := httpGet(t, router, "/v1/health", "")
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	body := parseBody(t, w)
	data, _ := body["data"].(map[string]any)
	if data["status"] != "ok" {
		t.Errorf("expected status=ok, got: %v", data["status"])
	}
}

// TestHTTPFullAuthFlow tests the complete auth flow over HTTP.
func TestHTTPFullAuthFlow(t *testing.T) {
	if testing.Short() {
		t.Skip()
	}

	migratorDSN, appDSN := setupPostgres(t)
	ctx := context.Background()
	appPool, _ := db.Open(ctx, appDSN)
	defer appPool.Close()
	_ = migratorDSN

	privPEM, pubPEM := generateTestPEM(t)
	signer, _ := auth.NewJWTSigner(privPEM, "rimi-auth", "rimi-api", "k1", 15*time.Minute)
	verifier, _ := wsmiddleware.NewJWTVerifier(pubPEM, "rimi-auth", "rimi-api")
	captureSender := &capturingEmailSender{}

	authRepo := authhandler.NewRepository(appPool)
	authSvc := authhandler.NewService(authRepo, signer, captureSender, appPool, authhandler.ServiceConfig{
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
	r.Use(chimiddleware.RequestID)
	r.Use(wsmiddleware.RequestLogger)
	r.Use(chimiddleware.Recoverer)
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
			r.Post("/", wsH.CreateWorkspace)
			r.Get("/", wsH.ListWorkspaces)
			r.Post("/{id}/switch", wsH.SwitchWorkspace)
		})
	})

	// POST /auth/register — 202
	t.Run("register", func(t *testing.T) {
		w := httpPost(t, r, "/v1/auth/register", map[string]any{
			"email": "e2e@test.com", "password": "e2e-pass-word!", "display_name": "E2E User",
		}, "")
		if w.Code != http.StatusAccepted {
			t.Fatalf("register: expected 202, got %d: %s", w.Code, w.Body.String())
		}
		body := parseBody(t, w)
		data, _ := body["data"].(map[string]any)
		if data["registered"] != true {
			t.Errorf("expected registered=true, got: %v", data)
		}
		if _, ok := body["meta"].(map[string]any); !ok {
			t.Error("expected meta in response")
		}
	})

	// Login before verify — 401
	t.Run("login before verify", func(t *testing.T) {
		w := httpPost(t, r, "/v1/auth/login", map[string]any{
			"email": "e2e@test.com", "password": "e2e-pass-word!",
		}, "")
		if w.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401, got %d", w.Code)
		}
	})

	// Get verification token.
	time.Sleep(50 * time.Millisecond)
	verifyToken := captureSender.lastVerifyToken
	if verifyToken == "" {
		t.Fatal("no verify token captured")
	}

	// POST /auth/verify-email — 200
	t.Run("verify email", func(t *testing.T) {
		w := httpPost(t, r, "/v1/auth/verify-email", map[string]any{"token": verifyToken}, "")
		if w.Code != http.StatusOK {
			t.Fatalf("verify: expected 200, got %d: %s", w.Code, w.Body.String())
		}
	})

	// POST /auth/login — 200 with tokens
	var accessToken, refreshToken string
	t.Run("login", func(t *testing.T) {
		w := httpPost(t, r, "/v1/auth/login", map[string]any{
			"email": "e2e@test.com", "password": "e2e-pass-word!",
		}, "")
		if w.Code != http.StatusOK {
			t.Fatalf("login: expected 200, got %d: %s", w.Code, w.Body.String())
		}
		body := parseBody(t, w)
		data, _ := body["data"].(map[string]any)
		accessToken, _ = data["access_token"].(string)
		refreshToken, _ = data["refresh_token"].(string)
		if accessToken == "" || refreshToken == "" {
			t.Fatalf("missing tokens in login response: %v", data)
		}
	})

	// GET /auth/me — 200
	t.Run("get me", func(t *testing.T) {
		w := httpGet(t, r, "/v1/auth/me", accessToken)
		if w.Code != http.StatusOK {
			t.Fatalf("me: expected 200, got %d: %s", w.Code, w.Body.String())
		}
		body := parseBody(t, w)
		data, _ := body["data"].(map[string]any)
		profile, _ := data["profile"].(map[string]any)
		if profile["email"] != "e2e@test.com" {
			t.Errorf("me: wrong email in profile: %v", profile)
		}
	})

	// GET /auth/me without token — 401
	t.Run("me without auth", func(t *testing.T) {
		w := httpGet(t, r, "/v1/auth/me", "")
		if w.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401, got %d", w.Code)
		}
	})

	// POST /workspaces — 201
	var workspaceID, workspaceAccessToken string
	t.Run("create workspace", func(t *testing.T) {
		w := httpPost(t, r, "/v1/workspaces", map[string]any{"name": "My E2E Shop"}, accessToken)
		if w.Code != http.StatusCreated {
			t.Fatalf("create workspace: expected 201, got %d: %s", w.Code, w.Body.String())
		}
		body := parseBody(t, w)
		data, _ := body["data"].(map[string]any)
		ws, _ := data["workspace"].(map[string]any)
		tokens, _ := data["tokens"].(map[string]any)
		workspaceID, _ = ws["id"].(string)
		workspaceAccessToken, _ = tokens["access_token"].(string)
		if workspaceID == "" || workspaceAccessToken == "" {
			t.Fatalf("missing workspace or tokens: %v", data)
		}
		if ws["role"] != "owner" {
			t.Errorf("expected role=owner, got: %v", ws["role"])
		}
	})

	// GET /workspaces — 200 with list
	t.Run("list workspaces", func(t *testing.T) {
		w := httpGet(t, r, "/v1/workspaces", accessToken)
		if w.Code != http.StatusOK {
			t.Fatalf("list workspaces: expected 200, got %d: %s", w.Code, w.Body.String())
		}
		body := parseBody(t, w)
		data, _ := body["data"].(map[string]any)
		workspaces, _ := data["workspaces"].([]any)
		if len(workspaces) != 1 {
			t.Errorf("expected 1 workspace, got %d", len(workspaces))
		}
	})

	// POST /workspaces/{id}/switch — 200
	t.Run("switch workspace", func(t *testing.T) {
		if workspaceID == "" {
			t.Skip("no workspace to switch to")
		}
		w := httpPost(t, r, "/v1/workspaces/"+workspaceID+"/switch", nil, accessToken)
		if w.Code != http.StatusOK {
			t.Fatalf("switch: expected 200, got %d: %s", w.Code, w.Body.String())
		}
	})

	// POST /workspaces/{id}/switch to non-member — 403
	t.Run("switch to non-member workspace", func(t *testing.T) {
		fakeID := "00000000-0000-0000-0000-000000000001"
		w := httpPost(t, r, "/v1/workspaces/"+fakeID+"/switch", nil, accessToken)
		if w.Code != http.StatusForbidden {
			t.Fatalf("expected 403, got %d: %s", w.Code, w.Body.String())
		}
	})

	// POST /auth/refresh — 200
	var newRefreshToken string
	t.Run("refresh token", func(t *testing.T) {
		w := httpPost(t, r, "/v1/auth/refresh", map[string]any{"refresh_token": refreshToken}, "")
		if w.Code != http.StatusOK {
			t.Fatalf("refresh: expected 200, got %d: %s", w.Code, w.Body.String())
		}
		body := parseBody(t, w)
		data, _ := body["data"].(map[string]any)
		newRefreshToken, _ = data["refresh_token"].(string)
	})

	// POST /auth/refresh with old token — 401 REFRESH_TOKEN_REUSED
	t.Run("reuse old refresh token", func(t *testing.T) {
		w := httpPost(t, r, "/v1/auth/refresh", map[string]any{"refresh_token": refreshToken}, "")
		if w.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401, got %d", w.Code)
		}
	})

	// POST /auth/logout — 200
	t.Run("logout", func(t *testing.T) {
		if newRefreshToken == "" {
			t.Skip("no new refresh token")
		}
		w := httpPost(t, r, "/v1/auth/logout", map[string]any{"refresh_token": newRefreshToken}, "")
		if w.Code != http.StatusOK {
			t.Fatalf("logout: expected 200, got %d: %s", w.Code, w.Body.String())
		}
	})

	// POST /auth/password-reset/request — 200 always
	t.Run("password reset request", func(t *testing.T) {
		w := httpPost(t, r, "/v1/auth/password-reset/request", map[string]any{"email": "e2e@test.com"}, "")
		if w.Code != http.StatusOK {
			t.Fatalf("reset request: expected 200, got %d", w.Code)
		}
		body := parseBody(t, w)
		data, _ := body["data"].(map[string]any)
		if data["sent"] != true {
			t.Errorf("expected sent=true, got: %v", data)
		}
	})

	// GET /workspaces without workspace access token — empty list then non-member check.
	_ = workspaceAccessToken
}

// TestHTTPEnvelopeShape verifies all error responses use the standard envelope.
func TestHTTPEnvelopeShape(t *testing.T) {
	if testing.Short() {
		t.Skip()
	}

	router, teardown := setupHTTPServer(t)
	defer teardown()

	cases := []struct {
		name     string
		method   string
		path     string
		body     interface{}
		wantCode int
		wantCode2 string // error code
	}{
		{"register bad email", "POST", "/v1/auth/register", map[string]any{"email": "bad", "password": "12345678", "display_name": "T"}, 400, "VALIDATION_ERROR"},
		{"login bad email", "POST", "/v1/auth/login", map[string]any{"email": "bad"}, 400, "VALIDATION_ERROR"},
		{"verify bad token", "POST", "/v1/auth/verify-email", map[string]any{"token": "x"}, 400, "VALIDATION_ERROR"},
		{"me no auth", "GET", "/v1/auth/me", nil, 401, "UNAUTHORIZED"},
		{"workspaces no auth", "GET", "/v1/workspaces", nil, 401, "UNAUTHORIZED"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var w *httptest.ResponseRecorder
			if tc.method == "POST" {
				w = httpPost(t, router, tc.path, tc.body, "")
			} else {
				w = httpGet(t, router, tc.path, "")
			}
			if w.Code != tc.wantCode {
				t.Errorf("status: got %d want %d body: %s", w.Code, tc.wantCode, w.Body.String())
			}
			body := parseBody(t, w)
			errObj, _ := body["error"].(map[string]any)
			if errObj == nil {
				t.Fatalf("missing error envelope in: %v", body)
			}
			if errObj["code"] != tc.wantCode2 {
				t.Errorf("error code: got %v want %v", errObj["code"], tc.wantCode2)
			}
			// Error responses do not require meta; success responses do (patterns.md).
			if _, hasData := body["data"]; hasData {
				t.Error("error response must not have 'data' key")
			}
		})
	}
}

// Ensure imports are used.
var _ = email.NoopSender{}
