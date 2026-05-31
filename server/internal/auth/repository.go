// Package auth — database repository for auth tables.
// All queries use parameterized statements (INPUT-02).
// Repository pattern per patterns.md.
package auth

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// DB is the database executor interface, satisfied by pgxpool.Pool and pgx.Tx.
// Uses the actual pgconn.CommandTag return type from pgx.
type DB interface {
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

// ErrNotFound is returned when a queried row does not exist.
var ErrNotFound = errors.New("not found")

// ErrConflict is returned on unique constraint violations.
var ErrConflict = errors.New("conflict")

// Profile is the database representation of a user profile.
type Profile struct {
	ID             uuid.UUID
	Email          string
	PasswordHash   string
	DisplayName    string
	Phone          *string
	EmailVerified  bool
	FailedAttempts int
	LockedUntil    *time.Time
	CreatedAt      time.Time
	UpdatedAt      time.Time
}

// RefreshToken is a row in the refresh_tokens table.
type RefreshToken struct {
	ID            uuid.UUID
	UserID        uuid.UUID
	FamilyID      uuid.UUID
	TokenHash     string
	IssuedAt      time.Time
	ExpiresAt     time.Time
	RevokedAt     *time.Time
	RevokedReason *string
}

// EmailToken is a row in the email_tokens table.
type EmailToken struct {
	ID         uuid.UUID
	UserID     uuid.UUID
	Purpose    string
	TokenHash  string
	ExpiresAt  time.Time
	ConsumedAt *time.Time
	CreatedAt  time.Time
}

// Repository handles all auth-related DB operations.
type Repository struct {
	pool *pgxpool.Pool
}

// NewRepository creates a repository backed by the app pool.
func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

// --- Profile queries ---

// CreateProfile inserts a new user profile.
// INPUT-02: parameterized. AUTH-13: email_verified defaults to false server-side.
func (r *Repository) CreateProfile(ctx context.Context, db DB, id uuid.UUID, email, passwordHash, displayName string, phone *string) (*Profile, error) {
	const q = `
		INSERT INTO profiles (id, email, password_hash, display_name, phone, email_verified, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, false, now(), now())
		RETURNING id, email, password_hash, display_name, phone, email_verified, failed_attempts, locked_until, created_at, updated_at`
	row := db.QueryRow(ctx, q, id, email, passwordHash, displayName, phone)
	return scanProfile(row)
}

// GetProfileByEmail retrieves a profile by email (case-insensitive via citext).
func (r *Repository) GetProfileByEmail(ctx context.Context, db DB, email string) (*Profile, error) {
	const q = `SELECT id, email, password_hash, display_name, phone, email_verified, failed_attempts, locked_until, created_at, updated_at
			   FROM profiles WHERE email = $1`
	row := db.QueryRow(ctx, q, email)
	p, err := scanProfile(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	return p, err
}

// GetProfileByID retrieves a profile by UUID.
func (r *Repository) GetProfileByID(ctx context.Context, db DB, id uuid.UUID) (*Profile, error) {
	const q = `SELECT id, email, password_hash, display_name, phone, email_verified, failed_attempts, locked_until, created_at, updated_at
			   FROM profiles WHERE id = $1`
	row := db.QueryRow(ctx, q, id)
	p, err := scanProfile(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	return p, err
}

// IncrementFailedAttempts updates the lockout counter and optionally sets locked_until.
func (r *Repository) IncrementFailedAttempts(ctx context.Context, db DB, id uuid.UUID, lockedUntil *time.Time) error {
	const q = `UPDATE profiles SET failed_attempts = failed_attempts + 1, locked_until = $2, updated_at = now() WHERE id = $1`
	_, err := db.Exec(ctx, q, id, lockedUntil)
	return err
}

// ResetFailedAttempts clears the lockout state after a successful login.
func (r *Repository) ResetFailedAttempts(ctx context.Context, db DB, id uuid.UUID) error {
	const q = `UPDATE profiles SET failed_attempts = 0, locked_until = NULL, updated_at = now() WHERE id = $1`
	_, err := db.Exec(ctx, q, id)
	return err
}

// UpdatePassword sets a new password hash for a profile.
func (r *Repository) UpdatePassword(ctx context.Context, db DB, id uuid.UUID, passwordHash string) error {
	const q = `UPDATE profiles SET password_hash = $2, updated_at = now() WHERE id = $1`
	_, err := db.Exec(ctx, q, id, passwordHash)
	return err
}

// SetEmailVerified marks a profile's email as verified.
func (r *Repository) SetEmailVerified(ctx context.Context, db DB, id uuid.UUID) error {
	const q = `UPDATE profiles SET email_verified = true, updated_at = now() WHERE id = $1`
	_, err := db.Exec(ctx, q, id)
	return err
}

// ProfileExists returns true if a profile with the given email exists.
func (r *Repository) ProfileExists(ctx context.Context, email string) (bool, error) {
	const q = `SELECT EXISTS(SELECT 1 FROM profiles WHERE email = $1)`
	var exists bool
	// Use pool directly (no tenant context needed for existence check).
	err := r.pool.QueryRow(ctx, q, email).Scan(&exists)
	return exists, err
}

// --- Email token queries ---

// CreateEmailToken inserts a new email token row.
// EMAIL-01: token_hash only, raw token never stored.
func (r *Repository) CreateEmailToken(ctx context.Context, db DB, userID uuid.UUID, purpose, tokenHash string, expiresAt time.Time) error {
	const q = `INSERT INTO email_tokens (id, user_id, purpose, token_hash, expires_at, created_at)
			   VALUES ($1, $2, $3, $4, $5, now())`
	_, err := db.Exec(ctx, q, uuid.New(), userID, purpose, tokenHash, expiresAt)
	return err
}

// CreateEmailTokenDirect inserts a new email token using the pool (no tenant tx needed).
func (r *Repository) CreateEmailTokenDirect(ctx context.Context, userID uuid.UUID, purpose, tokenHash string, expiresAt time.Time) error {
	const q = `INSERT INTO email_tokens (id, user_id, purpose, token_hash, expires_at, created_at)
			   VALUES ($1, $2, $3, $4, $5, now())`
	_, err := r.pool.Exec(ctx, q, uuid.New(), userID, purpose, tokenHash, expiresAt)
	return err
}

// ConsumeEmailToken atomically finds and marks an email token consumed.
// EMAIL-02: single-use; EMAIL-03: must not be expired.
// Returns ErrNotFound if no matching valid unconsumed token exists.
func (r *Repository) ConsumeEmailToken(ctx context.Context, purpose, tokenHash string) (*EmailToken, error) {
	const q = `
		UPDATE email_tokens
		SET consumed_at = now()
		WHERE token_hash = $1
		  AND purpose = $2
		  AND consumed_at IS NULL
		  AND expires_at > now()
		RETURNING id, user_id, purpose, token_hash, expires_at, consumed_at, created_at`
	row := r.pool.QueryRow(ctx, q, tokenHash, purpose)
	var et EmailToken
	err := row.Scan(&et.ID, &et.UserID, &et.Purpose, &et.TokenHash, &et.ExpiresAt, &et.ConsumedAt, &et.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("consume email token: %w", err)
	}
	return &et, nil
}

// --- Refresh token queries ---

// CreateRefreshToken stores a new refresh token row (hash only — SESSION-02).
func (r *Repository) CreateRefreshToken(ctx context.Context, userID, familyID uuid.UUID, tokenHash string, expiresAt time.Time) error {
	const q = `INSERT INTO refresh_tokens (id, user_id, family_id, token_hash, issued_at, expires_at)
			   VALUES ($1, $2, $3, $4, now(), $5)`
	_, err := r.pool.Exec(ctx, q, uuid.New(), userID, familyID, tokenHash, expiresAt)
	return err
}

// GetRefreshToken fetches a refresh token row by its hash.
func (r *Repository) GetRefreshToken(ctx context.Context, tokenHash string) (*RefreshToken, error) {
	const q = `SELECT id, user_id, family_id, token_hash, issued_at, expires_at, revoked_at, revoked_reason
			   FROM refresh_tokens WHERE token_hash = $1`
	row := r.pool.QueryRow(ctx, q, tokenHash)
	return scanRefreshToken(row)
}

// RevokeRefreshToken marks a single refresh token as revoked.
func (r *Repository) RevokeRefreshToken(ctx context.Context, tokenHash, reason string) error {
	const q = `UPDATE refresh_tokens SET revoked_at = now(), revoked_reason = $2 WHERE token_hash = $1`
	_, err := r.pool.Exec(ctx, q, tokenHash, reason)
	return err
}

// RevokeFamilyByID revokes all tokens in the given family (SESSION-04 reuse-detection).
func (r *Repository) RevokeFamilyByID(ctx context.Context, familyID uuid.UUID, reason string) error {
	const q = `UPDATE refresh_tokens SET revoked_at = now(), revoked_reason = $2
			   WHERE family_id = $1 AND revoked_at IS NULL`
	_, err := r.pool.Exec(ctx, q, familyID, reason)
	return err
}

// RevokeAllUserFamilies revokes every refresh token for a user (AUTH-09 password reset).
func (r *Repository) RevokeAllUserFamilies(ctx context.Context, userID uuid.UUID, reason string) error {
	const q = `UPDATE refresh_tokens SET revoked_at = now(), revoked_reason = $2
			   WHERE user_id = $1 AND revoked_at IS NULL`
	_, err := r.pool.Exec(ctx, q, userID, reason)
	return err
}

// RevokeFamilyByTokenHash revokes all tokens in the same family as the given token hash.
func (r *Repository) RevokeFamilyByTokenHash(ctx context.Context, tokenHash, reason string) error {
	const q = `UPDATE refresh_tokens rt
			   SET revoked_at = now(), revoked_reason = $2
			   FROM (SELECT family_id FROM refresh_tokens WHERE token_hash = $1) fam
			   WHERE rt.family_id = fam.family_id AND rt.revoked_at IS NULL`
	_, err := r.pool.Exec(ctx, q, tokenHash, reason)
	return err
}

// --- Helpers ---

func scanProfile(row pgx.Row) (*Profile, error) {
	p := &Profile{}
	err := row.Scan(
		&p.ID, &p.Email, &p.PasswordHash, &p.DisplayName, &p.Phone,
		&p.EmailVerified, &p.FailedAttempts, &p.LockedUntil,
		&p.CreatedAt, &p.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return p, nil
}

func scanRefreshToken(row pgx.Row) (*RefreshToken, error) {
	rt := &RefreshToken{}
	err := row.Scan(
		&rt.ID, &rt.UserID, &rt.FamilyID, &rt.TokenHash,
		&rt.IssuedAt, &rt.ExpiresAt, &rt.RevokedAt, &rt.RevokedReason,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("scan refresh token: %w", err)
	}
	return rt, nil
}
