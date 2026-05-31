package auth

import (
	"testing"
)

func TestGenerateOpaqueToken(t *testing.T) {
	raw, hashed, err := GenerateOpaqueToken()
	if err != nil {
		t.Fatalf("GenerateOpaqueToken: %v", err)
	}
	if len(raw) < 32 {
		t.Fatalf("raw token too short: %d chars", len(raw))
	}
	if hashed == "" {
		t.Fatal("hashed token is empty")
	}
	// Hash is deterministic.
	if HashToken(raw) != hashed {
		t.Fatal("HashToken(raw) != hashed")
	}
	// Raw != hash (hash is hex of SHA-256).
	if raw == hashed {
		t.Fatal("raw token equals hash — should differ")
	}
}

func TestTokenUniqueness(t *testing.T) {
	raw1, _, _ := GenerateOpaqueToken()
	raw2, _, _ := GenerateOpaqueToken()
	if raw1 == raw2 {
		t.Fatal("expected unique tokens")
	}
}
