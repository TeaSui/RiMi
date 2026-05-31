// Package auth — service unit tests covering validation, error paths, and
// sentinel error behaviour. These tests use nil DB/pool to cover paths that
// return before hitting the database (validation, dummy-work, policy checks).
// Full DB-backed paths are covered by the integration tests.
package auth

import (
	"context"
	"errors"
	"testing"
)

// TestValidatePasswordPolicyEdges supplements the existing password_test.go cases.
func TestValidatePasswordPolicyEdges(t *testing.T) {
	cases := []struct {
		name    string
		pw      string
		wantErr bool
	}{
		{"exactly 8 chars", "12345678", false},
		{"exactly 256 chars", genStr('a', 256), false},
		{"7 chars — too short", "1234567", true},
		{"257 chars — too long", genStr('b', 257), true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := ValidatePasswordPolicy(tc.pw)
			if tc.wantErr && err == nil {
				t.Fatal("expected error, got nil")
			}
			if !tc.wantErr && err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
		})
	}
}

// TestSentinelErrors verifies the sentinel error set is distinct.
func TestSentinelErrors(t *testing.T) {
	sentinels := []error{
		ErrInvalidCredentials,
		ErrAccountLocked,
		ErrTokenInvalidOrExpired,
		ErrRefreshTokenInvalid,
		ErrRefreshTokenReused,
		ErrNotFound,
		ErrConflict,
	}
	for i, a := range sentinels {
		for j, b := range sentinels {
			if i != j && errors.Is(a, b) {
				t.Errorf("sentinel %d and %d are the same: %v == %v", i, j, a, b)
			}
		}
	}
}

// TestValidationErrorString verifies the Error() method.
func TestValidationErrorString(t *testing.T) {
	ve := &ValidationError{Field: "email", Issue: "invalid_format"}
	got := ve.Error()
	if got == "" {
		t.Fatal("Error() returned empty string")
	}
	// Must contain field and issue.
	if !contains(got, "email") || !contains(got, "invalid_format") {
		t.Errorf("Error() = %q, expected to contain field and issue", got)
	}
}

// TestHashTokenDeterminism verifies SHA-256 hash of the same input is stable.
func TestHashTokenDeterminism(t *testing.T) {
	raw := "test-raw-token-value"
	h1 := HashToken(raw)
	h2 := HashToken(raw)
	if h1 != h2 {
		t.Errorf("HashToken is not deterministic: %q != %q", h1, h2)
	}
	if h1 == raw {
		t.Error("HashToken must not return the raw input")
	}
}

// TestGenerateOpaqueTokenEntropy verifies that generated tokens are long enough.
func TestGenerateOpaqueTokenEntropy(t *testing.T) {
	raw, hashed, err := GenerateOpaqueToken()
	if err != nil {
		t.Fatalf("GenerateOpaqueToken: %v", err)
	}
	// 32 bytes base64url = 44 chars (with padding). At minimum 40+ chars.
	if len(raw) < 40 {
		t.Errorf("token too short for ≥256-bit entropy: %d chars", len(raw))
	}
	if hashed == raw {
		t.Error("hashed must not equal raw")
	}
}

// TestServiceRegisterWeakPassword verifies AUTH-05 is enforced before DB call.
// A nil pool/repo means the service will panic on DB access — the weak-password
// check must return before reaching the DB.
func TestServiceRegisterWeakPasswordBeforeDB(t *testing.T) {
	svc := &Service{
		repo:   nil, // intentionally nil — must not be reached
		signer: nil,
		sender: nil,
		pool:   nil,
		cfg:    ServiceConfig{},
	}
	err := svc.Register(context.Background(), "test@test.com", "short", "Test", nil)
	var ve *ValidationError
	if !errors.As(err, &ve) {
		t.Fatalf("expected ValidationError for short password, got: %v", err)
	}
	if ve.Field != "password" {
		t.Errorf("expected field=password, got: %q", ve.Field)
	}
}

// TestServiceConfirmPasswordResetWeakPassword verifies AUTH-05 at confirm reset.
func TestServiceConfirmPasswordResetWeakPassword(t *testing.T) {
	svc := &Service{
		repo:   nil,
		signer: nil,
		sender: nil,
		pool:   nil,
		cfg:    ServiceConfig{},
	}
	err := svc.ConfirmPasswordReset(context.Background(), "sometoken", "short")
	var ve *ValidationError
	if !errors.As(err, &ve) {
		t.Fatalf("expected ValidationError for short password, got: %v", err)
	}
	if ve.Field != "new_password" {
		t.Errorf("expected field=new_password, got: %q", ve.Field)
	}
}

// helpers

func genStr(c byte, n int) string {
	b := make([]byte, n)
	for i := range b {
		b[i] = c
	}
	return string(b)
}

// contains is the same as in repository.go — redeclared here to avoid import cycle.
func contains(s, sub string) bool {
	return len(s) >= len(sub) && (s == sub ||
		func() bool {
			for i := 0; i <= len(s)-len(sub); i++ {
				if s[i:i+len(sub)] == sub {
					return true
				}
			}
			return false
		}())
}
