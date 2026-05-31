// Package auth — JWT signing (RS256) and token pair generation.
// AUTH-10/11/12, SECRETS-01/02.
package auth

import (
	"crypto/rsa"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// JWTSigner signs access JWTs with an RSA private key (AUTH-10).
type JWTSigner struct {
	privateKey *rsa.PrivateKey
	issuer     string
	audience   string
	ttl        time.Duration
	kid        string // key id for rotation SECRETS-02
}

// NewJWTSigner creates a signer from the PEM-encoded private key.
// The private key must come from env/secret store — never committed (SECRETS-01).
func NewJWTSigner(privateKeyPEM, issuer, audience, kid string, ttl time.Duration) (*JWTSigner, error) {
	pk, err := jwt.ParseRSAPrivateKeyFromPEM([]byte(privateKeyPEM))
	if err != nil {
		return nil, fmt.Errorf("jwt signer: parse private key: %w", err)
	}
	return &JWTSigner{
		privateKey: pk,
		issuer:     issuer,
		audience:   audience,
		ttl:        ttl,
		kid:        kid,
	}, nil
}

// AccessTokenClaims is the custom claim set for RiMi access tokens.
// workspace_id matches the AccessTokenClaims schema in the contract.
type AccessTokenClaims struct {
	WorkspaceID *string `json:"workspace_id"`
	jwt.RegisteredClaims
}

// Sign issues a new RS256 access JWT.
// AUTH-12: exp - iat ≈ 15 min.
func (s *JWTSigner) Sign(userID string, workspaceID *string) (string, time.Time, error) {
	now := time.Now().UTC()
	exp := now.Add(s.ttl)

	claims := AccessTokenClaims{
		WorkspaceID: workspaceID,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    s.issuer,
			Audience:  jwt.ClaimStrings{s.audience},
			Subject:   userID,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(exp),
		},
	}

	t := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	t.Header["kid"] = s.kid // SECRETS-02 rotation support

	tokenString, err := t.SignedString(s.privateKey)
	if err != nil {
		return "", time.Time{}, fmt.Errorf("jwt sign: %w", err)
	}
	return tokenString, exp, nil
}
