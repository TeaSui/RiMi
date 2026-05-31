// Package middleware — auth middleware tests.
// AUTH-10/11: JWT verification, algorithm pinning.
package middleware

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/pem"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// generateTestRSAPEM generates a temporary RSA key pair for tests.
func generateTestRSAPEM(t *testing.T) (privPEM, pubPEM string) {
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

// signTestToken creates a signed RS256 JWT for tests.
func signTestToken(t *testing.T, privPEM, issuer, audience, subject string, wsID *string, ttl time.Duration) string {
	t.Helper()
	pk, err := jwt.ParseRSAPrivateKeyFromPEM([]byte(privPEM))
	if err != nil {
		t.Fatalf("parse private key: %v", err)
	}
	now := time.Now().UTC()
	claims := &AccessTokenClaims{
		WorkspaceID: wsID,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    issuer,
			Audience:  jwt.ClaimStrings{audience},
			Subject:   subject,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(ttl)),
		},
	}
	tok := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	tok.Header["kid"] = "k1"
	s, err := tok.SignedString(pk)
	if err != nil {
		t.Fatalf("sign token: %v", err)
	}
	return s
}

// --- JWTVerifier tests ---

func TestJWTVerifierValidToken(t *testing.T) {
	priv, pub := generateTestRSAPEM(t)
	v, err := NewJWTVerifier(pub, "rimi-auth", "rimi-api")
	if err != nil {
		t.Fatalf("NewJWTVerifier: %v", err)
	}

	wsID := "ws-abc"
	tok := signTestToken(t, priv, "rimi-auth", "rimi-api", "user-123", &wsID, 15*time.Minute)

	claims, err := v.Verify(tok)
	if err != nil {
		t.Fatalf("Verify: %v", err)
	}
	if claims.Subject != "user-123" {
		t.Errorf("sub: got %q", claims.Subject)
	}
	if claims.WorkspaceID == nil || *claims.WorkspaceID != "ws-abc" {
		t.Errorf("workspace_id: got %v", claims.WorkspaceID)
	}
}

func TestJWTVerifierNullWorkspace(t *testing.T) {
	priv, pub := generateTestRSAPEM(t)
	v, _ := NewJWTVerifier(pub, "rimi-auth", "rimi-api")
	tok := signTestToken(t, priv, "rimi-auth", "rimi-api", "user-1", nil, 15*time.Minute)
	claims, err := v.Verify(tok)
	if err != nil {
		t.Fatalf("Verify: %v", err)
	}
	if claims.WorkspaceID != nil {
		t.Errorf("expected nil workspace_id")
	}
}

func TestJWTVerifierRejectsExpired(t *testing.T) {
	priv, pub := generateTestRSAPEM(t)
	v, _ := NewJWTVerifier(pub, "rimi-auth", "rimi-api")
	tok := signTestToken(t, priv, "rimi-auth", "rimi-api", "user-1", nil, -1*time.Minute)
	if _, err := v.Verify(tok); err == nil {
		t.Fatal("expected error for expired token")
	}
}

func TestJWTVerifierRejectsWrongIssuer(t *testing.T) {
	priv, pub := generateTestRSAPEM(t)
	v, _ := NewJWTVerifier(pub, "rimi-auth", "rimi-api")
	tok := signTestToken(t, priv, "bad-issuer", "rimi-api", "user-1", nil, 15*time.Minute)
	if _, err := v.Verify(tok); err == nil {
		t.Fatal("expected error for wrong issuer")
	}
}

func TestJWTVerifierRejectsWrongAudience(t *testing.T) {
	priv, pub := generateTestRSAPEM(t)
	v, _ := NewJWTVerifier(pub, "rimi-auth", "rimi-api")
	tok := signTestToken(t, priv, "rimi-auth", "bad-audience", "user-1", nil, 15*time.Minute)
	if _, err := v.Verify(tok); err == nil {
		t.Fatal("expected error for wrong audience")
	}
}

func TestJWTVerifierRejectsAlgNone(t *testing.T) {
	_, pub := generateTestRSAPEM(t)
	v, _ := NewJWTVerifier(pub, "rimi-auth", "rimi-api")
	// Crafted token with alg:none.
	noneToken := "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiJ1c2VyLTEifQ."
	if _, err := v.Verify(noneToken); err == nil {
		t.Fatal("expected error for alg:none token")
	}
}

func TestJWTVerifierRejectsEmpty(t *testing.T) {
	_, pub := generateTestRSAPEM(t)
	v, _ := NewJWTVerifier(pub, "rimi-auth", "rimi-api")
	if _, err := v.Verify(""); err == nil {
		t.Fatal("expected error for empty token")
	}
}

// --- Authenticate middleware tests ---

func TestAuthenticateMiddleware(t *testing.T) {
	priv, pub := generateTestRSAPEM(t)
	v, _ := NewJWTVerifier(pub, "rimi-auth", "rimi-api")

	tok := signTestToken(t, priv, "rimi-auth", "rimi-api", "user-999", nil, 15*time.Minute)

	called := false
	next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
		claims, ok := ClaimsFromContext(r.Context())
		if !ok || claims.Subject != "user-999" {
			t.Error("claims not in context or wrong subject")
		}
		w.WriteHeader(http.StatusOK)
	})

	handler := Authenticate(v)(next)

	req := httptest.NewRequest(http.MethodGet, "/v1/auth/me", nil)
	req.Header.Set("Authorization", "Bearer "+tok)
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	if !called {
		t.Error("expected next handler to be called")
	}
	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", w.Code)
	}
}

func TestAuthenticateMiddlewareNoToken(t *testing.T) {
	_, pub := generateTestRSAPEM(t)
	v, _ := NewJWTVerifier(pub, "rimi-auth", "rimi-api")

	next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Error("next handler must not be called for missing token")
	})

	handler := Authenticate(v)(next)
	req := httptest.NewRequest(http.MethodGet, "/v1/auth/me", nil)
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d", w.Code)
	}
}

func TestAuthenticateMiddlewareInvalidToken(t *testing.T) {
	_, pub := generateTestRSAPEM(t)
	v, _ := NewJWTVerifier(pub, "rimi-auth", "rimi-api")

	next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Error("next handler must not be called for invalid token")
	})

	handler := Authenticate(v)(next)
	req := httptest.NewRequest(http.MethodGet, "/v1/auth/me", nil)
	req.Header.Set("Authorization", "Bearer totally-invalid-token")
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d", w.Code)
	}
}

// TestClaimsFromContextMissing verifies that missing claims return ok=false.
func TestClaimsFromContextMissing(t *testing.T) {
	_, ok := ClaimsFromContext(context.Background())
	if ok {
		t.Error("expected ok=false for empty context")
	}
}

// TestExtractBearerToken verifies Bearer token extraction.
func TestExtractBearerToken(t *testing.T) {
	cases := []struct {
		header string
		want   string
	}{
		{"Bearer abc123", "abc123"},
		{"bearer abc123", ""},  // must have correct case
		{"", ""},
		{"Basic abc", ""},
		{"Bearer ", ""},
	}
	for _, tc := range cases {
		req := httptest.NewRequest(http.MethodGet, "/", nil)
		if tc.header != "" {
			req.Header.Set("Authorization", tc.header)
		}
		got := extractBearerToken(req)
		if got != tc.want {
			t.Errorf("extractBearerToken(%q) = %q, want %q", tc.header, got, tc.want)
		}
	}
}
