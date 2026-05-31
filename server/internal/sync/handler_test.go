package sync

import (
	"bytes"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/rimi/server/internal/auth"
	"github.com/rimi/server/internal/middleware"
)

// generateHandlerTestPEM generates a fresh RSA-2048 key pair for use in handler tests.
func generateHandlerTestPEM(t *testing.T) (privPEM, pubPEM string) {
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

// signTestToken mints a signed JWT with the given workspaceID for handler tests.
func signTestToken(t *testing.T, privPEM, wsID string) string {
	t.Helper()
	signer, err := auth.NewJWTSigner(privPEM, "rimi-auth", "rimi-api", "k1", 15*time.Minute)
	if err != nil {
		t.Fatalf("new signer: %v", err)
	}
	token, _, err := signer.Sign("user-test", &wsID)
	if err != nil {
		t.Fatalf("sign token: %v", err)
	}
	return token
}

// buildAuthedRequest wraps req in middleware.Authenticate so claims are set on the context.
func buildAuthedRequest(t *testing.T, h http.Handler, req *http.Request, token string) *httptest.ResponseRecorder {
	t.Helper()
	privPEM, pubPEM := generateHandlerTestPEM(t)
	_ = privPEM // key pair generated externally; token passed in
	verifier, err := middleware.NewJWTVerifier(pubPEM, "rimi-auth", "rimi-api")
	if err != nil {
		t.Fatalf("verifier: %v", err)
	}
	w := httptest.NewRecorder()
	middleware.Authenticate(verifier)(h).ServeHTTP(w, req)
	return w
}

// makeAuthedHandler wraps a handler with Authenticate using a freshly generated key pair.
// Returns the wrapped handler and a function to mint tokens for that key pair.
func makeAuthedHandler(t *testing.T, h http.Handler) (http.Handler, func(wsID string) string) {
	t.Helper()
	privPEM, pubPEM := generateHandlerTestPEM(t)
	verifier, err := middleware.NewJWTVerifier(pubPEM, "rimi-auth", "rimi-api")
	if err != nil {
		t.Fatalf("verifier: %v", err)
	}
	mint := func(wsID string) string { return signTestToken(t, privPEM, wsID) }
	return middleware.Authenticate(verifier)(h), mint
}

// --- Tests ---

// TestBatchRejectsMissingClaims verifies 401 when no Authorization header is present.
func TestBatchRejectsMissingClaims(t *testing.T) {
	h := NewHandler(NewService(newFakeRepo(0)))
	authed, _ := makeAuthedHandler(t, http.HandlerFunc(h.Batch))

	req := httptest.NewRequest(http.MethodPost, "/v1/sync/batch", nil)
	w := httptest.NewRecorder()
	authed.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", w.Code)
	}
}

// TestPullRejectsUnknownEntity verifies 400 when entity param is not in the allowlist.
func TestPullRejectsUnknownEntity(t *testing.T) {
	h := NewHandler(NewService(newFakeRepo(0)))
	authed, mint := makeAuthedHandler(t, http.HandlerFunc(h.Pull))
	token := mint("ws-test")

	req := httptest.NewRequest(http.MethodGet, "/v1/sync/pull?entity=transactions", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	authed.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", w.Code)
	}
}

// TestPullRejectsOversizedLimit verifies 400 when limit > 500.
func TestPullRejectsOversizedLimit(t *testing.T) {
	h := NewHandler(NewService(newFakeRepo(0)))
	authed, mint := makeAuthedHandler(t, http.HandlerFunc(h.Pull))
	token := mint("ws-test")

	req := httptest.NewRequest(http.MethodGet, "/v1/sync/pull?entity=product&limit=999", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	authed.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", w.Code)
	}
}

// TestBatchRejectsOversizedBatch verifies 400 when more than 50 ops are submitted.
func TestBatchRejectsOversizedBatch(t *testing.T) {
	h := NewHandler(NewService(newFakeRepo(0)))
	authed, mint := makeAuthedHandler(t, http.HandlerFunc(h.Batch))
	token := mint("ws-test")

	ops := make([]Operation, handlerMaxBatchOps+1)
	for i := range ops {
		ops[i] = Operation{
			OpID:       "op",
			EntityType: "inventory_item",
			EntityID:   "e-1",
			OpType:     "inventory_delta",
			Delta:      intPtr(-1),
		}
	}
	body, _ := json.Marshal(BatchRequest{Ops: ops})

	req := httptest.NewRequest(http.MethodPost, "/v1/sync/batch", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	authed.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", w.Code)
	}
}
