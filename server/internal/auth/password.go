// Package auth — password hashing with argon2id (AUTH-01).
// Parameters are tuned to ~250ms on a modern server. Never store plaintext passwords.
package auth

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"

	"golang.org/x/crypto/argon2"
)

// argon2Params holds the hashing parameters. These MUST be config-driven in
// a future phase; for Phase 1 they are constants meeting the AUTH-01 requirement.
// Tuned for ≈250ms on a 2-core VM (AUTH-01).
const (
	argonTime    = 3
	argonMemory  = 64 * 1024 // 64 MB
	argonThreads = 2
	argonKeyLen  = 32
	argonSaltLen = 16
)

// HashPassword hashes the password with argon2id and returns a PHC-formatted string.
// AUTH-01: memory-hard algorithm; no plaintext password ever stored.
func HashPassword(password string) (string, error) {
	salt := make([]byte, argonSaltLen)
	if _, err := rand.Read(salt); err != nil {
		return "", fmt.Errorf("hash password: generate salt: %w", err)
	}
	hash := argon2.IDKey([]byte(password), salt, argonTime, argonMemory, argonThreads, argonKeyLen)
	// Format: $argon2id$v=19$m=65536,t=3,p=2$<salt_b64>$<hash_b64>
	encoded := fmt.Sprintf("$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s",
		argon2.Version,
		argonMemory, argonTime, argonThreads,
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(hash),
	)
	return encoded, nil
}

// VerifyPassword checks a password against an argon2id hash in constant time.
// Returns nil if the password matches, an error otherwise.
// AUTH-01: timing-safe comparison.
func VerifyPassword(password, encoded string) error {
	parts := strings.Split(encoded, "$")
	// Expected format: ["", "argon2id", "v=19", "m=...,t=...,p=...", "<salt>", "<hash>"]
	if len(parts) != 6 {
		return errors.New("invalid hash format")
	}
	var version int
	if _, err := fmt.Sscanf(parts[2], "v=%d", &version); err != nil {
		return fmt.Errorf("parse version: %w", err)
	}
	var m, t uint32
	var p uint8
	if _, err := fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &m, &t, &p); err != nil {
		return fmt.Errorf("parse params: %w", err)
	}
	salt, err := base64.RawStdEncoding.DecodeString(parts[4])
	if err != nil {
		return fmt.Errorf("decode salt: %w", err)
	}
	storedHash, err := base64.RawStdEncoding.DecodeString(parts[5])
	if err != nil {
		return fmt.Errorf("decode hash: %w", err)
	}
	keyLen := uint32(len(storedHash))
	candidate := argon2.IDKey([]byte(password), salt, t, m, p, keyLen)
	if subtle.ConstantTimeCompare(storedHash, candidate) != 1 {
		return errors.New("password mismatch")
	}
	return nil
}

// ValidatePasswordPolicy enforces the minimum password policy server-side (AUTH-05).
// Rules: at least 8 characters.
func ValidatePasswordPolicy(password string) error {
	if len(password) < 8 {
		return errors.New("password too short")
	}
	if len(password) > 256 {
		return errors.New("password too long")
	}
	return nil
}
