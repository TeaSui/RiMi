// Package auth — opaque refresh token and email token generation.
// SESSION-02/05, EMAIL-01/03.
package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
)

// GenerateOpaqueToken creates a ≥256-bit CSPRNG base64url token (SESSION-05).
// The raw token is returned to the caller for delivery; only the hash is stored.
func GenerateOpaqueToken() (raw, hashed string, err error) {
	b := make([]byte, 32) // 256 bits
	if _, err := rand.Read(b); err != nil {
		return "", "", fmt.Errorf("generate token: %w", err)
	}
	raw = base64.URLEncoding.EncodeToString(b)
	hashed = HashToken(raw)
	return raw, hashed, nil
}

// HashToken returns the SHA-256 hex of the raw token (SESSION-02/EMAIL-01).
// This is what gets stored in the database — the raw token is never persisted.
func HashToken(raw string) string {
	h := sha256.Sum256([]byte(raw))
	return fmt.Sprintf("%x", h)
}
