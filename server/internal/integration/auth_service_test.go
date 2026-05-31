// Package integration — auth service integration tests.
// These tests run against a real Postgres container and exercise the full
// service/repository layer that can't be covered by unit tests.
// AUTH-01..04, SESSION-01..06, EMAIL-01..06, TENANCY-06/07 verified here.
package integration

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/rimi/server/internal/auth"
	"github.com/rimi/server/internal/db"
	"github.com/rimi/server/internal/email"
)

// TestAuthRegisterAndVerify covers Register + VerifyEmail (AUTH-01/02/03, EMAIL-01/02/03).
func TestAuthRegisterAndVerify(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	migratorDSN, appDSN := setupPostgres(t)
	ctx := context.Background()

	migratorPool, err := db.Open(ctx, migratorDSN)
	if err != nil {
		t.Fatalf("migrator pool: %v", err)
	}
	defer migratorPool.Close()

	appPool, err := db.Open(ctx, appDSN)
	if err != nil {
		t.Fatalf("app pool: %v", err)
	}
	defer appPool.Close()

	privPEM, _ := generateTestPEM(t)
	signer, _ := auth.NewJWTSigner(privPEM, "rimi-auth", "rimi-api", "k1", 15*time.Minute)

	// Use a capturing sender to get the token.
	captureSender := &capturingEmailSender{}
	repo := auth.NewRepository(appPool)
	svc := auth.NewService(repo, signer, captureSender, appPool, auth.ServiceConfig{
		LockoutThreshold: 5,
		LockoutDuration:  15 * time.Minute,
		RefreshTokenTTL:  30 * 24 * time.Hour,
		EmailVerifyTTL:   24 * time.Hour,
		PasswordResetTTL: 30 * time.Minute,
	})

	testEmail := "testuser@integration.test"
	testPassword := "integration-test-password"

	// Register (AUTH-01).
	t.Run("register creates account", func(t *testing.T) {
		err := svc.Register(ctx, testEmail, testPassword, "Integration Test", nil)
		if err != nil {
			t.Fatalf("Register: %v", err)
		}
	})

	// AUTH-03: second register with same email returns nil (anti-enumeration).
	t.Run("register with existing email — anti-enumeration", func(t *testing.T) {
		err := svc.Register(ctx, testEmail, testPassword, "Duplicate", nil)
		if err != nil {
			t.Fatalf("Register with existing email should return nil, got: %v", err)
		}
	})

	// AUTH-02: login before verification must fail.
	t.Run("login before email verification fails", func(t *testing.T) {
		_, err := svc.Login(ctx, testEmail, testPassword)
		if err == nil {
			t.Fatal("expected error for unverified account")
		}
		// Must be generic INVALID_CREDENTIALS, not a revealing message (AUTH-02).
		if err != auth.ErrInvalidCredentials {
			t.Errorf("expected ErrInvalidCredentials, got: %v", err)
		}
	})

	// Get the verification token from the capturing sender.
	// Wait briefly for the goroutine to complete.
	time.Sleep(50 * time.Millisecond)
	rawToken := captureSender.lastVerifyToken
	if rawToken == "" {
		t.Fatal("expected verification token to be captured by email sender")
	}

	// VerifyEmail (AUTH-02, EMAIL-02/03).
	t.Run("verify email succeeds", func(t *testing.T) {
		err := svc.VerifyEmail(ctx, rawToken)
		if err != nil {
			t.Fatalf("VerifyEmail: %v", err)
		}
	})

	// EMAIL-02: single-use — second verification must fail.
	t.Run("verify email again — single-use rejection", func(t *testing.T) {
		err := svc.VerifyEmail(ctx, rawToken)
		if err != auth.ErrTokenInvalidOrExpired {
			t.Fatalf("expected ErrTokenInvalidOrExpired on reuse, got: %v", err)
		}
	})

	// Login after verification must succeed (AUTH-01/04).
	t.Run("login after verification succeeds", func(t *testing.T) {
		pair, err := svc.Login(ctx, testEmail, testPassword)
		if err != nil {
			t.Fatalf("Login: %v", err)
		}
		if pair.AccessToken == "" || pair.RefreshToken == "" {
			t.Fatal("expected non-empty token pair")
		}
		if pair.TokenType != "Bearer" {
			t.Errorf("expected Bearer token_type, got: %s", pair.TokenType)
		}
	})

	// AUTH-03: wrong password returns INVALID_CREDENTIALS.
	t.Run("login with wrong password", func(t *testing.T) {
		_, err := svc.Login(ctx, testEmail, "wrong-password")
		if err != auth.ErrInvalidCredentials {
			t.Fatalf("expected ErrInvalidCredentials, got: %v", err)
		}
	})

	// AUTH-03: unknown email returns INVALID_CREDENTIALS.
	t.Run("login with unknown email", func(t *testing.T) {
		_, err := svc.Login(ctx, "unknown@nowhere.test", "somepassword")
		if err != auth.ErrInvalidCredentials {
			t.Fatalf("expected ErrInvalidCredentials, got: %v", err)
		}
	})
}

// TestAuthRefreshRotation covers SESSION-03/04 (rotation + reuse detection).
func TestAuthRefreshRotation(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	migratorDSN, appDSN := setupPostgres(t)
	ctx := context.Background()

	migratorPool, err := db.Open(ctx, migratorDSN)
	if err != nil {
		t.Fatalf("migrator pool: %v", err)
	}
	defer migratorPool.Close()

	appPool, err := db.Open(ctx, appDSN)
	if err != nil {
		t.Fatalf("app pool: %v", err)
	}
	defer appPool.Close()

	privPEM, _ := generateTestPEM(t)
	signer, _ := auth.NewJWTSigner(privPEM, "rimi-auth", "rimi-api", "k1", 15*time.Minute)
	captureSender := &capturingEmailSender{}
	repo := auth.NewRepository(appPool)
	svc := auth.NewService(repo, signer, captureSender, appPool, auth.ServiceConfig{
		LockoutThreshold: 5,
		LockoutDuration:  15 * time.Minute,
		RefreshTokenTTL:  30 * 24 * time.Hour,
		EmailVerifyTTL:   24 * time.Hour,
		PasswordResetTTL: 30 * time.Minute,
	})

	// Seed a verified user via migrator.
	userID := uuid.New()
	hash, _ := auth.HashPassword("mypassword")
	_, err = migratorPool.Exec(ctx,
		`INSERT INTO profiles (id, email, password_hash, display_name, email_verified, created_at, updated_at)
		 VALUES ($1, 'rotation@test.com', $2, 'Rotation User', true, now(), now())`,
		userID, hash)
	if err != nil {
		t.Fatalf("seed user: %v", err)
	}

	// Login to get initial token pair.
	pair1, err := svc.Login(ctx, "rotation@test.com", "mypassword")
	if err != nil {
		t.Fatalf("Login: %v", err)
	}

	// Refresh: SESSION-03 — rotate. Old token revoked; new token issued.
	pair2, err := svc.Refresh(ctx, pair1.RefreshToken)
	if err != nil {
		t.Fatalf("Refresh: %v", err)
	}
	if pair2.RefreshToken == "" {
		t.Fatal("expected new refresh token after rotation")
	}
	if pair2.RefreshToken == pair1.RefreshToken {
		t.Error("SESSION-03 FAIL: new refresh token should differ from old")
	}

	// SESSION-03: old refresh token must now be rejected.
	t.Run("old refresh token rejected after rotation", func(t *testing.T) {
		_, err := svc.Refresh(ctx, pair1.RefreshToken)
		if err == nil {
			t.Fatal("expected error for already-rotated token")
		}
		// SESSION-04: reusing a rotated token = theft → REFRESH_TOKEN_REUSED and family revoked.
		if err != auth.ErrRefreshTokenReused {
			t.Errorf("expected ErrRefreshTokenReused, got: %v", err)
		}
	})

	// After reuse detection, the new token (pair2) should also be invalidated (family revoked).
	t.Run("new refresh token also rejected after family revocation", func(t *testing.T) {
		_, err := svc.Refresh(ctx, pair2.RefreshToken)
		if err == nil {
			t.Fatal("expected error — family should be revoked")
		}
	})
}

// TestAuthLogout covers SESSION-06: server-side family revocation.
func TestAuthLogout(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	migratorDSN, appDSN := setupPostgres(t)
	ctx := context.Background()

	migratorPool, _ := db.Open(ctx, migratorDSN)
	defer migratorPool.Close()
	appPool, _ := db.Open(ctx, appDSN)
	defer appPool.Close()

	privPEM, _ := generateTestPEM(t)
	signer, _ := auth.NewJWTSigner(privPEM, "rimi-auth", "rimi-api", "k1", 15*time.Minute)
	repo := auth.NewRepository(appPool)
	svc := auth.NewService(repo, signer, &email.NoopSender{}, appPool, auth.ServiceConfig{
		LockoutThreshold: 5,
		LockoutDuration:  15 * time.Minute,
		RefreshTokenTTL:  30 * 24 * time.Hour,
		EmailVerifyTTL:   24 * time.Hour,
		PasswordResetTTL: 30 * time.Minute,
	})

	userID := uuid.New()
	hash, _ := auth.HashPassword("logoutpass")
	_, err := migratorPool.Exec(ctx,
		`INSERT INTO profiles (id, email, password_hash, display_name, email_verified, created_at, updated_at)
		 VALUES ($1, 'logout@test.com', $2, 'Logout User', true, now(), now())`,
		userID, hash)
	if err != nil {
		t.Fatalf("seed user: %v", err)
	}

	pair, err := svc.Login(ctx, "logout@test.com", "logoutpass")
	if err != nil {
		t.Fatalf("Login: %v", err)
	}

	// Logout.
	if err := svc.Logout(ctx, pair.RefreshToken); err != nil {
		t.Fatalf("Logout: %v", err)
	}

	// SESSION-06: after logout, refresh token must be rejected.
	_, err = svc.Refresh(ctx, pair.RefreshToken)
	if err == nil {
		t.Fatal("SESSION-06 FAIL: expected error after logout, got nil")
	}

	// Logout is idempotent (per contract).
	if err := svc.Logout(ctx, pair.RefreshToken); err != nil {
		t.Errorf("Logout idempotency: expected nil, got: %v", err)
	}
}

// TestAuthPasswordReset covers AUTH-03/09, EMAIL-01..06.
func TestAuthPasswordReset(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	migratorDSN, appDSN := setupPostgres(t)
	ctx := context.Background()

	migratorPool, _ := db.Open(ctx, migratorDSN)
	defer migratorPool.Close()
	appPool, _ := db.Open(ctx, appDSN)
	defer appPool.Close()

	privPEM, _ := generateTestPEM(t)
	signer, _ := auth.NewJWTSigner(privPEM, "rimi-auth", "rimi-api", "k1", 15*time.Minute)
	captureSender := &capturingEmailSender{}
	repo := auth.NewRepository(appPool)
	svc := auth.NewService(repo, signer, captureSender, appPool, auth.ServiceConfig{
		LockoutThreshold: 5,
		LockoutDuration:  15 * time.Minute,
		RefreshTokenTTL:  30 * 24 * time.Hour,
		EmailVerifyTTL:   24 * time.Hour,
		PasswordResetTTL: 30 * time.Minute,
	})

	userID := uuid.New()
	hash, _ := auth.HashPassword("old-pass-word")
	_, err := migratorPool.Exec(ctx,
		`INSERT INTO profiles (id, email, password_hash, display_name, email_verified, created_at, updated_at)
		 VALUES ($1, 'reset@test.com', $2, 'Reset User', true, now(), now())`,
		userID, hash)
	if err != nil {
		t.Fatalf("seed user: %v", err)
	}

	// Login to get a refresh token.
	pair, err := svc.Login(ctx, "reset@test.com", "old-pass-word")
	if err != nil {
		t.Fatalf("Login: %v", err)
	}

	// EMAIL-04: request for unknown email returns nil (anti-enumeration).
	t.Run("reset request for unknown email", func(t *testing.T) {
		if err := svc.RequestPasswordReset(ctx, "unknown@nowhere.test"); err != nil {
			t.Fatalf("expected nil, got: %v", err)
		}
	})

	// Request reset for known email.
	if err := svc.RequestPasswordReset(ctx, "reset@test.com"); err != nil {
		t.Fatalf("RequestPasswordReset: %v", err)
	}
	time.Sleep(50 * time.Millisecond)
	resetToken := captureSender.lastResetToken
	if resetToken == "" {
		t.Fatal("expected reset token from email sender")
	}

	// ConfirmPasswordReset: invalid token rejected.
	t.Run("confirm with bad token", func(t *testing.T) {
		err := svc.ConfirmPasswordReset(ctx, "invalid-token-that-is-long-enough", "new-password-123")
		if err != auth.ErrTokenInvalidOrExpired {
			t.Fatalf("expected ErrTokenInvalidOrExpired, got: %v", err)
		}
	})

	// AUTH-09: confirm reset revokes all sessions.
	if err := svc.ConfirmPasswordReset(ctx, resetToken, "new-password-123"); err != nil {
		t.Fatalf("ConfirmPasswordReset: %v", err)
	}

	// Old refresh token should now be revoked (AUTH-09).
	_, err = svc.Refresh(ctx, pair.RefreshToken)
	if err == nil {
		t.Fatal("AUTH-09 FAIL: expected refresh token to be revoked after password reset")
	}

	// New password works.
	newPair, err := svc.Login(ctx, "reset@test.com", "new-password-123")
	if err != nil {
		t.Fatalf("Login with new password: %v", err)
	}
	if newPair.AccessToken == "" {
		t.Fatal("expected non-empty access token")
	}
}

// TestAuthLockout covers AUTH-04: per-account lockout.
func TestAuthLockout(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	migratorDSN, appDSN := setupPostgres(t)
	ctx := context.Background()

	migratorPool, _ := db.Open(ctx, migratorDSN)
	defer migratorPool.Close()
	appPool, _ := db.Open(ctx, appDSN)
	defer appPool.Close()

	privPEM, _ := generateTestPEM(t)
	signer, _ := auth.NewJWTSigner(privPEM, "rimi-auth", "rimi-api", "k1", 15*time.Minute)
	repo := auth.NewRepository(appPool)
	svc := auth.NewService(repo, signer, &email.NoopSender{}, appPool, auth.ServiceConfig{
		LockoutThreshold: 3, // Lower threshold for faster test.
		LockoutDuration:  5 * time.Minute,
		RefreshTokenTTL:  30 * 24 * time.Hour,
		EmailVerifyTTL:   24 * time.Hour,
		PasswordResetTTL: 30 * time.Minute,
	})

	userID := uuid.New()
	hash, _ := auth.HashPassword("correct-pass")
	_, err := migratorPool.Exec(ctx,
		`INSERT INTO profiles (id, email, password_hash, display_name, email_verified, created_at, updated_at)
		 VALUES ($1, 'lockout@test.com', $2, 'Lockout User', true, now(), now())`,
		userID, hash)
	if err != nil {
		t.Fatalf("seed user: %v", err)
	}

	// AUTH-04: 3 consecutive failures trigger lockout.
	for i := 0; i < 3; i++ {
		_, err := svc.Login(ctx, "lockout@test.com", "wrong-password")
		if err != auth.ErrInvalidCredentials {
			t.Fatalf("attempt %d: expected ErrInvalidCredentials, got: %v", i+1, err)
		}
	}

	// After threshold, account is locked.
	_, err = svc.Login(ctx, "lockout@test.com", "correct-pass")
	if err != auth.ErrAccountLocked {
		t.Fatalf("AUTH-04 FAIL: expected ErrAccountLocked after lockout, got: %v", err)
	}
}

// TestAuthGetMe covers GetMe path.
func TestAuthGetMe(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	migratorDSN, appDSN := setupPostgres(t)
	ctx := context.Background()

	migratorPool, _ := db.Open(ctx, migratorDSN)
	defer migratorPool.Close()
	appPool, _ := db.Open(ctx, appDSN)
	defer appPool.Close()

	privPEM, _ := generateTestPEM(t)
	signer, _ := auth.NewJWTSigner(privPEM, "rimi-auth", "rimi-api", "k1", 15*time.Minute)
	repo := auth.NewRepository(appPool)
	svc := auth.NewService(repo, signer, &email.NoopSender{}, appPool, auth.ServiceConfig{
		LockoutThreshold: 5,
		LockoutDuration:  15 * time.Minute,
		RefreshTokenTTL:  30 * 24 * time.Hour,
		EmailVerifyTTL:   24 * time.Hour,
		PasswordResetTTL: 30 * time.Minute,
	})

	userID := uuid.New()
	hash, _ := auth.HashPassword("me-pass")
	_, err := migratorPool.Exec(ctx,
		`INSERT INTO profiles (id, email, password_hash, display_name, email_verified, created_at, updated_at)
		 VALUES ($1, 'me@test.com', $2, 'Me User', true, now(), now())`,
		userID, hash)
	if err != nil {
		t.Fatalf("seed user: %v", err)
	}

	profile, err := svc.GetMe(ctx, userID)
	if err != nil {
		t.Fatalf("GetMe: %v", err)
	}
	if profile.Email != "me@test.com" {
		t.Errorf("email: got %q want %q", profile.Email, "me@test.com")
	}
}

// capturingEmailSender captures tokens for test verification.
type capturingEmailSender struct {
	lastVerifyToken string
	lastResetToken  string
}

func (c *capturingEmailSender) SendVerificationToken(_, token string) error {
	c.lastVerifyToken = token
	return nil
}

func (c *capturingEmailSender) SendPasswordResetToken(_, token string) error {
	c.lastResetToken = token
	return nil
}
