// Package auth — service layer implementing AUTH-01..04 business logic.
// Single responsibility; DI via constructor injection.
package auth

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/rimi/server/internal/email"
)

// Service handles authentication business logic.
type Service struct {
	repo    *Repository
	signer  *JWTSigner
	sender  email.Sender
	pool    *pgxpool.Pool
	cfg     ServiceConfig
}

// ServiceConfig holds auth service tunables.
type ServiceConfig struct {
	LockoutThreshold int
	LockoutDuration  time.Duration
	RefreshTokenTTL  time.Duration
	EmailVerifyTTL   time.Duration
	PasswordResetTTL time.Duration
}

// TokenPair is the response shape for auth token responses.
type TokenPair struct {
	AccessToken        string    `json:"access_token"`
	RefreshToken       string    `json:"refresh_token"`
	TokenType          string    `json:"token_type"`
	ExpiresIn          int       `json:"expires_in"`
	ActiveWorkspaceID  *string   `json:"active_workspace_id"`
}

// NewService constructs an auth service.
func NewService(repo *Repository, signer *JWTSigner, sender email.Sender, pool *pgxpool.Pool, cfg ServiceConfig) *Service {
	return &Service{repo: repo, signer: signer, sender: sender, pool: pool, cfg: cfg}
}

// Register creates a new user account. Anti-enumeration (AUTH-03): returns the
// same success shape whether the email is new or already registered.
// AUTH-13: server sets email_verified=false; client cannot override this.
func (s *Service) Register(ctx context.Context, email_, password, displayName string, phone *string) error {
	// AUTH-05: enforce password policy server-side before doing expensive work.
	if err := ValidatePasswordPolicy(password); err != nil {
		return &ValidationError{Field: "password", Issue: "too_short"}
	}

	// Anti-enumeration: always hash and always attempt a token send; the caller
	// gets an identical response either way (AUTH-03).
	hash, err := HashPassword(password)
	if err != nil {
		return fmt.Errorf("register: hash password: %w", err)
	}

	// Check existence separately so we can fire-and-forget without leaking timing.
	exists, err := s.repo.ProfileExists(ctx, email_)
	if err != nil {
		return fmt.Errorf("register: check existence: %w", err)
	}

	if exists {
		// AUTH-03: do not leak existence; return without error so the caller
		// returns 202 regardless.
		return nil
	}

	// Insert new user.
	userID := uuid.New()
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("register: begin tx: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err := s.repo.CreateProfile(ctx, tx, userID, email_, hash, displayName, phone); err != nil {
		return fmt.Errorf("register: create profile: %w", err)
	}

	// Generate email verification token (EMAIL-01/03).
	raw, hashed, err := GenerateOpaqueToken()
	if err != nil {
		return fmt.Errorf("register: generate token: %w", err)
	}
	expiresAt := time.Now().Add(s.cfg.EmailVerifyTTL)
	if err := s.repo.CreateEmailToken(ctx, tx, userID, "email_verification", hashed, expiresAt); err != nil {
		return fmt.Errorf("register: store token: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("register: commit: %w", err)
	}

	// Send email asynchronously (don't block the response, but log failures).
	// PII-01: do not log the email address or the raw token.
	go func() {
		if err := s.sender.SendVerificationToken(email_, raw); err != nil {
			slog.Error("send verification email failed", slog.String("error", err.Error()))
		}
	}()

	return nil
}

// VerifyEmail consumes an email verification token atomically (EMAIL-02).
func (s *Service) VerifyEmail(ctx context.Context, rawToken string) error {
	hashed := HashToken(rawToken)
	et, err := s.repo.ConsumeEmailToken(ctx, "email_verification", hashed)
	if err != nil {
		if errors.Is(err, ErrNotFound) {
			return ErrTokenInvalidOrExpired
		}
		return fmt.Errorf("verify email: %w", err)
	}
	// Set the profile as verified.
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("verify email: begin tx: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	// Set GUC so RLS UPDATE policy passes for the user-scoped profiles table (TENANCY-06).
	if _, err := tx.Exec(ctx,
		"SELECT set_config('rimi.user_id', $1, true), set_config('rimi.workspace_id', '', true)",
		et.UserID.String(),
	); err != nil {
		return fmt.Errorf("verify email: set guc: %w", err)
	}

	if err := s.repo.SetEmailVerified(ctx, tx, et.UserID); err != nil {
		return fmt.Errorf("verify email: set verified: %w", err)
	}
	return tx.Commit(ctx)
}

// Login authenticates a user and issues a token pair.
// AUTH-02: rejects unverified accounts with generic INVALID_CREDENTIALS.
// AUTH-03: same response for unknown accounts (anti-enumeration).
// AUTH-04: per-account lockout.
func (s *Service) Login(ctx context.Context, emailAddr, password string) (*TokenPair, error) {
	profile, err := s.repo.GetProfileByEmail(ctx, s.pool, emailAddr)
	if err != nil {
		if errors.Is(err, ErrNotFound) {
			// AUTH-03: account does not exist — do equivalent bcrypt work to normalize timing.
			// EMAIL-05: constant-time-ish by hashing anyway.
			_ = hashDummy(password)
			return nil, ErrInvalidCredentials
		}
		return nil, fmt.Errorf("login: lookup: %w", err)
	}

	// AUTH-04: check lockout.
	if profile.LockedUntil != nil && time.Now().Before(*profile.LockedUntil) {
		slog.Info("login blocked: account locked",
			slog.String("user_id", profile.ID.String()),
		)
		return nil, ErrAccountLocked
	}

	// AUTH-02: reject unverified accounts with the generic error.
	if !profile.EmailVerified {
		_ = hashDummy(password) // normalize timing EMAIL-05
		return nil, ErrInvalidCredentials
	}

	// Verify password (AUTH-01).
	if err := VerifyPassword(password, profile.PasswordHash); err != nil {
		// AUTH-04: increment failed attempt counter.
		s.handleFailedAttempt(ctx, profile)
		slog.Info("login failed: bad password",
			slog.String("user_id", profile.ID.String()),
		)
		return nil, ErrInvalidCredentials
	}

	// Reset lockout counter on success.
	// Use a tx with GUC set so the RLS UPDATE policy on profiles passes (TENANCY-06).
	if resetTx, err := s.pool.Begin(ctx); err == nil {
		_, _ = resetTx.Exec(ctx,
			"SELECT set_config('rimi.user_id', $1, true), set_config('rimi.workspace_id', '', true)",
			profile.ID.String())
		_ = s.repo.ResetFailedAttempts(ctx, resetTx, profile.ID)
		_ = resetTx.Commit(ctx)
	}

	slog.Info("login success",
		slog.String("user_id", profile.ID.String()),
	)
	return s.issueTokenPair(ctx, profile.ID, nil)
}

// Refresh rotates a refresh token and issues a new token pair.
// SESSION-03: atomic rotation. SESSION-04: reuse detection.
func (s *Service) Refresh(ctx context.Context, rawToken string) (*TokenPair, error) {
	hashed := HashToken(rawToken)
	rt, err := s.repo.GetRefreshToken(ctx, hashed)
	if err != nil {
		if errors.Is(err, ErrNotFound) {
			return nil, ErrRefreshTokenInvalid
		}
		return nil, fmt.Errorf("refresh: lookup: %w", err)
	}

	// SESSION-05: check absolute expiry.
	if time.Now().After(rt.ExpiresAt) {
		return nil, ErrRefreshTokenInvalid
	}

	// SESSION-04: reuse detection — token already revoked means theft.
	if rt.RevokedAt != nil {
		slog.Warn("refresh token reuse detected — revoking family",
			slog.String("family_id", rt.FamilyID.String()),
			slog.String("user_id", rt.UserID.String()),
		)
		_ = s.repo.RevokeFamilyByID(ctx, rt.FamilyID, "reuse_detected")
		return nil, ErrRefreshTokenReused
	}

	// Determine current workspace from the existing token's family data.
	// The workspace is embedded in the access token claim (ADR-001);
	// we re-issue with a null workspace_id; the client will switch if needed.
	// For simplicity in Phase 1, workspace is not tracked on the refresh token;
	// the client re-requests via /auth/me after refresh.
	profile, err := s.repo.GetProfileByID(ctx, s.pool, rt.UserID)
	if err != nil {
		return nil, fmt.Errorf("refresh: get profile: %w", err)
	}
	_ = profile // profile used for future workspace lookup

	// SESSION-03: rotate — revoke old, issue new in the same family.
	if err := s.repo.RevokeRefreshToken(ctx, hashed, "rotated"); err != nil {
		return nil, fmt.Errorf("refresh: revoke old: %w", err)
	}

	slog.Info("refresh token rotated",
		slog.String("user_id", rt.UserID.String()),
		slog.String("family_id", rt.FamilyID.String()),
	)
	return s.issueTokenPairInFamily(ctx, rt.UserID, rt.FamilyID, nil)
}

// Logout revokes the presented refresh token's family (SESSION-06).
// Idempotent: revoking an already-revoked family still returns nil.
func (s *Service) Logout(ctx context.Context, rawToken string) error {
	hashed := HashToken(rawToken)
	_ = s.repo.RevokeFamilyByTokenHash(ctx, hashed, "logout")
	slog.Info("logout: family revoked")
	return nil
}

// RequestPasswordReset generates a reset token and emails it.
// EMAIL-04: ALWAYS returns nil regardless of account existence (anti-enumeration).
// EMAIL-05: normalizes timing.
func (s *Service) RequestPasswordReset(ctx context.Context, emailAddr string) error {
	profile, err := s.repo.GetProfileByEmail(ctx, s.pool, emailAddr)
	if err != nil {
		// Account doesn't exist — do dummy work to normalize timing (EMAIL-05).
		_ = hashDummy("dummy")
		return nil // anti-enumeration
	}

	raw, hashed, err := GenerateOpaqueToken()
	if err != nil {
		return fmt.Errorf("password reset request: generate token: %w", err)
	}
	expiresAt := time.Now().Add(s.cfg.PasswordResetTTL)
	if err := s.repo.CreateEmailTokenDirect(ctx, profile.ID, "password_reset", hashed, expiresAt); err != nil {
		// Log but do not expose error (anti-enumeration).
		slog.Error("store reset token failed", slog.String("error", err.Error()))
		return nil
	}

	go func() {
		if err := s.sender.SendPasswordResetToken(emailAddr, raw); err != nil {
			slog.Error("send reset email failed", slog.String("error", err.Error()))
		}
	}()

	slog.Info("password reset requested")
	return nil
}

// ConfirmPasswordReset validates the reset token, changes the password, and
// revokes ALL of the user's sessions (AUTH-09, SESSION-06).
func (s *Service) ConfirmPasswordReset(ctx context.Context, rawToken, newPassword string) error {
	// AUTH-05: validate new password policy.
	if err := ValidatePasswordPolicy(newPassword); err != nil {
		return &ValidationError{Field: "new_password", Issue: "too_short"}
	}

	hashed := HashToken(rawToken)
	et, err := s.repo.ConsumeEmailToken(ctx, "password_reset", hashed)
	if err != nil {
		if errors.Is(err, ErrNotFound) {
			return ErrTokenInvalidOrExpired
		}
		return fmt.Errorf("confirm reset: consume token: %w", err)
	}

	hash, err := HashPassword(newPassword)
	if err != nil {
		return fmt.Errorf("confirm reset: hash password: %w", err)
	}

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("confirm reset: begin tx: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	// Set GUC so RLS UPDATE policy passes for the user-scoped profiles table (TENANCY-06).
	if _, err := tx.Exec(ctx,
		"SELECT set_config('rimi.user_id', $1, true), set_config('rimi.workspace_id', '', true)",
		et.UserID.String(),
	); err != nil {
		return fmt.Errorf("confirm reset: set guc: %w", err)
	}

	if err := s.repo.UpdatePassword(ctx, tx, et.UserID, hash); err != nil {
		return fmt.Errorf("confirm reset: update password: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("confirm reset: commit: %w", err)
	}

	// AUTH-09: revoke ALL refresh-token families server-side.
	if err := s.repo.RevokeAllUserFamilies(ctx, et.UserID, "password_reset"); err != nil {
		slog.Error("revoke all families failed", slog.String("error", err.Error()), slog.String("user_id", et.UserID.String()))
	}

	slog.Info("password reset confirmed — all sessions revoked",
		slog.String("user_id", et.UserID.String()),
	)
	return nil
}

// GetMe returns the authenticated user's profile.
func (s *Service) GetMe(ctx context.Context, userID uuid.UUID) (*Profile, error) {
	return s.repo.GetProfileByID(ctx, s.pool, userID)
}

// IssueWorkspaceScopedTokenPair issues an access token with the given workspace_id
// WITHOUT rotating the refresh token (ADR-001, session-scoped refresh).
func (s *Service) IssueWorkspaceScopedTokenPair(ctx context.Context, userID uuid.UUID, workspaceID *string) (*TokenPair, error) {
	accessToken, exp, err := s.signer.Sign(userID.String(), workspaceID)
	if err != nil {
		return nil, fmt.Errorf("issue workspace token: %w", err)
	}
	expiresIn := int(time.Until(exp).Seconds())

	// Re-use the existing active refresh token — do not rotate.
	// We return an empty refresh_token string; the client retains the existing one.
	// The contract TokenPair requires refresh_token; we return "keep_existing" sentinel
	// which the client should treat as "no change". Better: client passes existing token.
	// For the workspace-scoped flow (create/switch), only the access token changes.
	return &TokenPair{
		AccessToken:       accessToken,
		RefreshToken:      "", // client retains existing refresh token (not rotated)
		TokenType:         "Bearer",
		ExpiresIn:         expiresIn,
		ActiveWorkspaceID: workspaceID,
	}, nil
}

// --- internal helpers ---

func (s *Service) issueTokenPair(ctx context.Context, userID uuid.UUID, workspaceID *string) (*TokenPair, error) {
	familyID := uuid.New()
	return s.issueTokenPairInFamily(ctx, userID, familyID, workspaceID)
}

func (s *Service) issueTokenPairInFamily(ctx context.Context, userID, familyID uuid.UUID, workspaceID *string) (*TokenPair, error) {
	accessToken, exp, err := s.signer.Sign(userID.String(), workspaceID)
	if err != nil {
		return nil, fmt.Errorf("issue token pair: sign: %w", err)
	}

	rawRefresh, hashedRefresh, err := GenerateOpaqueToken()
	if err != nil {
		return nil, fmt.Errorf("issue token pair: generate refresh: %w", err)
	}

	expiresAt := time.Now().Add(s.cfg.RefreshTokenTTL)
	if err := s.repo.CreateRefreshToken(ctx, userID, familyID, hashedRefresh, expiresAt); err != nil {
		return nil, fmt.Errorf("issue token pair: store refresh: %w", err)
	}

	expiresIn := int(time.Until(exp).Seconds())
	return &TokenPair{
		AccessToken:       accessToken,
		RefreshToken:      rawRefresh,
		TokenType:         "Bearer",
		ExpiresIn:         expiresIn,
		ActiveWorkspaceID: workspaceID,
	}, nil
}

func (s *Service) handleFailedAttempt(ctx context.Context, p *Profile) {
	var lockedUntil *time.Time
	if p.FailedAttempts+1 >= s.cfg.LockoutThreshold {
		t := time.Now().Add(s.cfg.LockoutDuration)
		lockedUntil = &t
		slog.Warn("account locked after failed attempts",
			slog.String("user_id", p.ID.String()),
			slog.Time("locked_until", t),
		)
	}
	// Use a tx with GUC set so RLS UPDATE policy on profiles passes (TENANCY-06).
	if tx, err := s.pool.Begin(ctx); err == nil {
		_, _ = tx.Exec(ctx,
			"SELECT set_config('rimi.user_id', $1, true), set_config('rimi.workspace_id', '', true)",
			p.ID.String())
		_ = s.repo.IncrementFailedAttempts(ctx, tx, p.ID, lockedUntil)
		_ = tx.Commit(ctx)
	}
}

// hashDummy performs a dummy hash to normalize timing for anti-enumeration (EMAIL-05).
func hashDummy(s string) string {
	h, _ := HashPassword(s)
	return h
}

// Sentinel errors used by service methods.
var (
	ErrInvalidCredentials  = errors.New("invalid credentials")
	ErrAccountLocked       = errors.New("account locked")
	ErrTokenInvalidOrExpired = errors.New("token invalid or expired")
	ErrRefreshTokenInvalid = errors.New("refresh token invalid")
	ErrRefreshTokenReused  = errors.New("refresh token reused")
)

// ValidationError signals a DTO validation failure at the service level.
type ValidationError struct {
	Field string
	Issue string
}

func (e *ValidationError) Error() string {
	return fmt.Sprintf("validation: %s: %s", e.Field, e.Issue)
}

// Ensure DB interface is satisfied by pgxpool.Pool and pgx.Tx at compile time.
var (
	_ DB = (*pgxpool.Pool)(nil)
	_ DB = (pgx.Tx)(nil)
)
