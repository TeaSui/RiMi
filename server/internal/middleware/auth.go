// Package middleware — JWT authentication and per-request tenancy GUC setup.
// AUTH-10/11: verifies RS256 JWT, pins alg, validates exp/iss/aud.
// TENANCY-05/06: sets SET LOCAL GUCs inside a transaction for each request.
package middleware

import (
	"context"
	"fmt"
	"net/http"
	"strings"

	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// contextKey is a typed key for context values to avoid collisions.
type contextKey string

const (
	ctxClaims contextKey = "rimi_claims"
	ctxTx     contextKey = "rimi_tx"
)

// AccessTokenClaims mirrors the JWT claim shape from the contract.
type AccessTokenClaims struct {
	WorkspaceID *string `json:"workspace_id"`
	jwt.RegisteredClaims
}

// JWTVerifier holds the parsed RSA public key and validation parameters.
type JWTVerifier struct {
	publicKey interface{} // *rsa.PublicKey
	issuer    string
	audience  string
}

// NewJWTVerifier builds a verifier from the PEM-encoded public key.
func NewJWTVerifier(publicKeyPEM, issuer, audience string) (*JWTVerifier, error) {
	pk, err := jwt.ParseRSAPublicKeyFromPEM([]byte(publicKeyPEM))
	if err != nil {
		return nil, fmt.Errorf("jwt verifier: parse public key: %w", err)
	}
	return &JWTVerifier{publicKey: pk, issuer: issuer, audience: audience}, nil
}

// Verify parses and validates an RS256 JWT string.
// AUTH-11: pins alg=RS256, validates signature, exp, iss, aud.
func (v *JWTVerifier) Verify(tokenString string) (*AccessTokenClaims, error) {
	claims := &AccessTokenClaims{}
	token, err := jwt.ParseWithClaims(tokenString, claims,
		func(t *jwt.Token) (interface{}, error) {
			// AUTH-11: reject none/HS256 — alg must be RS256.
			if _, ok := t.Method.(*jwt.SigningMethodRSA); !ok {
				return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
			}
			return v.publicKey, nil
		},
		jwt.WithIssuer(v.issuer),
		jwt.WithAudience(v.audience),
		jwt.WithExpirationRequired(),
	)
	if err != nil || !token.Valid {
		return nil, fmt.Errorf("jwt: invalid: %w", err)
	}
	return claims, nil
}

// ClaimsFromContext retrieves the validated JWT claims from the request context.
func ClaimsFromContext(ctx context.Context) (*AccessTokenClaims, bool) {
	c, ok := ctx.Value(ctxClaims).(*AccessTokenClaims)
	return c, ok
}

// TxFromContext retrieves the per-request transaction set by TenantTx.
func TxFromContext(ctx context.Context) (pgx.Tx, bool) {
	tx, ok := ctx.Value(ctxTx).(pgx.Tx)
	return tx, ok
}

// Authenticate is the JWT auth middleware. It:
//  1. Extracts the Bearer token from Authorization.
//  2. Verifies the RS256 JWT (AUTH-11).
//  3. Sets claims on the request context.
func Authenticate(v *JWTVerifier) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			tokenStr := extractBearerToken(r)
			if tokenStr == "" {
				WriteError(w, http.StatusUnauthorized, ErrUnauthorized, "Authentication required.", nil)
				return
			}
			claims, err := v.Verify(tokenStr)
			if err != nil {
				WriteError(w, http.StatusUnauthorized, ErrUnauthorized, "Authentication required.", nil)
				return
			}
			ctx := context.WithValue(r.Context(), ctxClaims, claims)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// TenantTx opens a transaction, sets SET LOCAL rimi.user_id and rimi.workspace_id
// as the FIRST statements in that transaction, stores the tx on context, and
// commits (or rolls back) when the handler returns.
// TENANCY-06: SET LOCAL is transaction-scoped and auto-resets at commit/rollback —
// never bleeds across pooled connections.
func TenantTx(pool *pgxpool.Pool) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			claims, ok := ClaimsFromContext(r.Context())
			if !ok {
				WriteError(w, http.StatusUnauthorized, ErrUnauthorized, "Authentication required.", nil)
				return
			}

			tx, err := pool.Begin(r.Context())
			if err != nil {
				WriteError(w, http.StatusInternalServerError, ErrInternalError, "Something went wrong. Please try again.", nil)
				return
			}
			defer func() { _ = tx.Rollback(r.Context()) }()

			// TENANCY-06: SET LOCAL (transaction-scoped) as FIRST statements.
			userID := claims.Subject
			wsID := ""
			if claims.WorkspaceID != nil {
				wsID = *claims.WorkspaceID
			}

			// TENANCY-07: policies fail closed when GUC is empty/NULL.
			// Using set_config with is_local=true is equivalent to SET LOCAL.
			if _, err := tx.Exec(r.Context(),
				"SELECT set_config('rimi.user_id', $1, true), set_config('rimi.workspace_id', $2, true)",
				userID, wsID,
			); err != nil {
				WriteError(w, http.StatusInternalServerError, ErrInternalError, "Something went wrong. Please try again.", nil)
				return
			}

			ctx := context.WithValue(r.Context(), ctxTx, tx)
			rw := &captureWriter{ResponseWriter: w}
			next.ServeHTTP(rw, r.WithContext(ctx))

			if rw.status < 400 {
				_ = tx.Commit(r.Context())
			}
		})
	}
}

type captureWriter struct {
	http.ResponseWriter
	status int
}

func (cw *captureWriter) WriteHeader(status int) {
	cw.status = status
	cw.ResponseWriter.WriteHeader(status)
}

// Write intercepts the first write to capture implicit 200.
func (cw *captureWriter) Write(b []byte) (int, error) {
	if cw.status == 0 {
		cw.status = http.StatusOK
	}
	return cw.ResponseWriter.Write(b)
}

func extractBearerToken(r *http.Request) string {
	h := r.Header.Get("Authorization")
	if !strings.HasPrefix(h, "Bearer ") {
		return ""
	}
	return strings.TrimPrefix(h, "Bearer ")
}
