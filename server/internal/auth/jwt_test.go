package auth

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/pem"
	"testing"
	"time"

	"github.com/rimi/server/internal/middleware"
)

// generateTestRSAPEM creates a test RSA PEM key pair.
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
	return privPEM, pubPEM
}

func TestJWTSignAndVerify(t *testing.T) {
	privPEM, pubPEM := generateTestRSAPEM(t)

	signer, err := NewJWTSigner(privPEM, "rimi-auth", "rimi-api", "k1", 15*time.Minute)
	if err != nil {
		t.Fatalf("NewJWTSigner: %v", err)
	}

	verifier, err := middleware.NewJWTVerifier(pubPEM, "rimi-auth", "rimi-api")
	if err != nil {
		t.Fatalf("NewJWTVerifier: %v", err)
	}

	wsID := "ws-123"
	tokenStr, exp, err := signer.Sign("user-456", &wsID)
	if err != nil {
		t.Fatalf("Sign: %v", err)
	}

	// AUTH-12: exp - iat ≈ 15 min.
	if time.Until(exp) > 16*time.Minute {
		t.Fatalf("expiry too far: %v", exp)
	}

	claims, err := verifier.Verify(tokenStr)
	if err != nil {
		t.Fatalf("Verify: %v", err)
	}
	if claims.Subject != "user-456" {
		t.Errorf("sub: got %q want user-456", claims.Subject)
	}
	if claims.WorkspaceID == nil || *claims.WorkspaceID != "ws-123" {
		t.Errorf("workspace_id: got %v", claims.WorkspaceID)
	}
}

func TestJWTNullWorkspace(t *testing.T) {
	privPEM, pubPEM := generateTestRSAPEM(t)
	signer, _ := NewJWTSigner(privPEM, "rimi-auth", "rimi-api", "k1", 15*time.Minute)
	verifier, _ := middleware.NewJWTVerifier(pubPEM, "rimi-auth", "rimi-api")

	tokenStr, _, err := signer.Sign("user-1", nil)
	if err != nil {
		t.Fatalf("Sign: %v", err)
	}
	claims, err := verifier.Verify(tokenStr)
	if err != nil {
		t.Fatalf("Verify: %v", err)
	}
	if claims.WorkspaceID != nil {
		t.Errorf("expected nil workspace_id, got %v", claims.WorkspaceID)
	}
}

// AUTH-11: expired, wrong iss/aud, alg:none must all be rejected.
func TestJWTVerifierRejectsInvalidTokens(t *testing.T) {
	privPEM, pubPEM := generateTestRSAPEM(t)
	verifier, _ := middleware.NewJWTVerifier(pubPEM, "rimi-auth", "rimi-api")

	t.Run("expired token", func(t *testing.T) {
		expiredSigner, _ := NewJWTSigner(privPEM, "rimi-auth", "rimi-api", "k1", -1*time.Minute)
		tokenStr, _, _ := expiredSigner.Sign("user-1", nil)
		if _, err := verifier.Verify(tokenStr); err == nil {
			t.Fatal("expected error for expired token")
		}
	})

	t.Run("wrong issuer", func(t *testing.T) {
		wrongSigner, _ := NewJWTSigner(privPEM, "wrong-issuer", "rimi-api", "k1", 15*time.Minute)
		tokenStr, _, _ := wrongSigner.Sign("user-1", nil)
		if _, err := verifier.Verify(tokenStr); err == nil {
			t.Fatal("expected error for wrong issuer")
		}
	})

	t.Run("wrong audience", func(t *testing.T) {
		wrongSigner, _ := NewJWTSigner(privPEM, "rimi-auth", "wrong-audience", "k1", 15*time.Minute)
		tokenStr, _, _ := wrongSigner.Sign("user-1", nil)
		if _, err := verifier.Verify(tokenStr); err == nil {
			t.Fatal("expected error for wrong audience")
		}
	})

	t.Run("alg none rejected", func(t *testing.T) {
		// Crafted token with alg:none header (base64url of {"alg":"none","typ":"JWT"}).
		noneToken := "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiJ1c2VyLTEifQ."
		if _, err := verifier.Verify(noneToken); err == nil {
			t.Fatal("expected error for alg:none token")
		}
	})

	t.Run("empty token", func(t *testing.T) {
		if _, err := verifier.Verify(""); err == nil {
			t.Fatal("expected error for empty token")
		}
	})
}
