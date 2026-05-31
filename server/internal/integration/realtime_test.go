// Package integration — realtime WebSocket endpoint tests.
// TestRealtimeRejectsUnauthenticated: verifies 401 without a Bearer token.
// TestRealtimeAcceptsValidToken: verifies the WS upgrade proceeds (non-401) with a valid token.
// SYNC-SEC-01/13/14 coverage.
package integration

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
	authpkg "github.com/rimi/server/internal/auth"
	wsmiddleware "github.com/rimi/server/internal/middleware"
	syncapi "github.com/rimi/server/internal/sync"
)

// buildRealtimeRouter constructs a minimal router with /realtime wired under Authenticate.
// Returns the router and a valid JWT token for the test workspace.
func buildRealtimeRouter(t *testing.T) (http.Handler, string) {
	t.Helper()
	privPEM, pubPEM := generateTestPEM(t)
	signer, err := authpkg.NewJWTSigner(privPEM, "rimi-auth", "rimi-api", "k1", 15*time.Minute)
	if err != nil {
		t.Fatalf("signer: %v", err)
	}
	verifier, err := wsmiddleware.NewJWTVerifier(pubPEM, "rimi-auth", "rimi-api")
	if err != nil {
		t.Fatalf("verifier: %v", err)
	}
	wsID := "ws-realtime-test"
	token, _, err := signer.Sign("user-realtime-test", &wsID)
	if err != nil {
		t.Fatalf("sign token: %v", err)
	}

	// NewRepository accepts a nil pool — pull is stubbed, batch is unused in these tests.
	syncHandler := syncapi.NewHandler(syncapi.NewService(syncapi.NewRepository(nil)))

	r := chi.NewRouter()
	r.Group(func(r chi.Router) {
		r.Use(wsmiddleware.Authenticate(verifier)) // SYNC-SEC-13: auth at router level
		r.Get("/realtime", syncHandler.Realtime)
	})
	return r, token
}

// TestRealtimeRejectsUnauthenticated verifies that /realtime returns 401 without a token.
// SYNC-SEC-01: Bearer JWT required.
func TestRealtimeRejectsUnauthenticated(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}
	router, _ := buildRealtimeRouter(t)
	srv := httptest.NewServer(router)
	defer srv.Close()

	req, _ := http.NewRequest(http.MethodGet, srv.URL+"/realtime", nil)
	req.Header.Set("Upgrade", "websocket")
	req.Header.Set("Connection", "upgrade")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("request: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", resp.StatusCode)
	}
}

// TestRealtimeAcceptsValidToken verifies the WS upgrade proceeds with a valid Bearer token.
// nhooyr.io/websocket Accept returns 101; the test verifies the response is not 401.
func TestRealtimeAcceptsValidToken(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}
	router, token := buildRealtimeRouter(t)
	srv := httptest.NewServer(router)
	defer srv.Close()

	wsURL := "ws" + strings.TrimPrefix(srv.URL, "http") + "/realtime"
	_ = wsURL // used for documentation; we test via raw HTTP to avoid a WS client dependency

	req, _ := http.NewRequest(http.MethodGet, srv.URL+"/realtime", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Upgrade", "websocket")
	req.Header.Set("Connection", "Upgrade")
	req.Header.Set("Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ==")
	req.Header.Set("Sec-WebSocket-Version", "13")

	// Use a transport that does not follow redirects and does not close the connection
	// before reading the response status.
	client := &http.Client{
		Transport: &http.Transport{},
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}
	resp, err := client.Do(req)
	if err != nil {
		// A successful WS upgrade may return an error from the HTTP client once the
		// connection is hijacked. Only fail if we have no response at all.
		if resp == nil {
			t.Fatalf("request error with no response: %v", err)
		}
	}
	if resp != nil {
		defer resp.Body.Close()
		if resp.StatusCode == http.StatusUnauthorized {
			t.Fatalf("valid token rejected with 401")
		}
	}
}
