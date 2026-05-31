// Package config loads all application settings from environment variables.
// No default secrets or sensitive values are hardcoded here.
package config

import (
	"fmt"
	"os"
	"strconv"
	"time"
)

// Config holds all runtime configuration loaded from environment variables.
type Config struct {
	// Server
	Port            string
	ReadTimeout     time.Duration
	WriteTimeout    time.Duration
	IdleTimeout     time.Duration
	MaxBodyBytes    int64

	// Database — two roles per ADR-002
	DBMigratorURL string // rimi_migrator for migrations
	DBAppURL      string // rimi_app for the running server

	// JWT
	JWTPrivateKeyPEM string // RS256 private key PEM (never committed)
	JWTPublicKeyPEM  string // RS256 public key PEM
	JWTIssuer        string
	JWTAudience      string
	JWTAccessTTL     time.Duration // ~15 min per AUTH-12
	JWTKeyID         string        // kid header for rotation per SECRETS-02

	// Refresh tokens
	RefreshTokenTTL time.Duration // absolute expiry SESSION-05

	// Email
	SMTPHost     string
	SMTPPort     int
	SMTPUser     string
	SMTPPassword string
	SMTPFrom     string

	// Auth
	LockoutThreshold int           // consecutive failures before lockout AUTH-04
	LockoutDuration  time.Duration // lockout window AUTH-04

	// Email tokens
	EmailVerifyTTL    time.Duration // EMAIL-03
	PasswordResetTTL  time.Duration // EMAIL-03

	// Migration path
	MigrationsPath string
}

// Load reads configuration from environment variables and returns an error if
// any required variable is missing.
func Load() (*Config, error) {
	c := &Config{}
	var errs []string

	c.Port = getEnv("PORT", "8080")

	c.ReadTimeout = getDurationEnv("READ_TIMEOUT", 15*time.Second)
	c.WriteTimeout = getDurationEnv("WRITE_TIMEOUT", 15*time.Second)
	c.IdleTimeout = getDurationEnv("IDLE_TIMEOUT", 60*time.Second)
	c.MaxBodyBytes = getInt64Env("MAX_BODY_BYTES", 1<<20) // 1 MB default INPUT-05

	// Required: DB credentials
	c.DBMigratorURL = os.Getenv("DB_MIGRATOR_URL")
	if c.DBMigratorURL == "" {
		errs = append(errs, "DB_MIGRATOR_URL is required")
	}
	c.DBAppURL = os.Getenv("DB_APP_URL")
	if c.DBAppURL == "" {
		errs = append(errs, "DB_APP_URL is required")
	}

	// Required: JWT keys (from env/secrets vault — never committed per SECRETS-01)
	c.JWTPrivateKeyPEM = os.Getenv("JWT_PRIVATE_KEY_PEM")
	if c.JWTPrivateKeyPEM == "" {
		errs = append(errs, "JWT_PRIVATE_KEY_PEM is required")
	}
	c.JWTPublicKeyPEM = os.Getenv("JWT_PUBLIC_KEY_PEM")
	if c.JWTPublicKeyPEM == "" {
		errs = append(errs, "JWT_PUBLIC_KEY_PEM is required")
	}

	c.JWTIssuer = getEnv("JWT_ISSUER", "rimi-auth")
	c.JWTAudience = getEnv("JWT_AUDIENCE", "rimi-api")
	c.JWTKeyID = getEnv("JWT_KEY_ID", "k1") // SECRETS-02 rotation support
	c.JWTAccessTTL = getDurationEnv("JWT_ACCESS_TTL", 15*time.Minute)
	c.RefreshTokenTTL = getDurationEnv("REFRESH_TOKEN_TTL", 30*24*time.Hour)

	// Email
	c.SMTPHost = getEnv("SMTP_HOST", "localhost")
	c.SMTPPort = getIntEnv("SMTP_PORT", 1025)
	c.SMTPUser = os.Getenv("SMTP_USER")
	c.SMTPPassword = os.Getenv("SMTP_PASSWORD")
	c.SMTPFrom = getEnv("SMTP_FROM", "noreply@rimi.app")

	// Auth lockout
	c.LockoutThreshold = getIntEnv("LOCKOUT_THRESHOLD", 5)
	c.LockoutDuration = getDurationEnv("LOCKOUT_DURATION", 15*time.Minute)

	// Token TTLs
	c.EmailVerifyTTL = getDurationEnv("EMAIL_VERIFY_TTL", 24*time.Hour)
	c.PasswordResetTTL = getDurationEnv("PASSWORD_RESET_TTL", 30*time.Minute)

	c.MigrationsPath = getEnv("MIGRATIONS_PATH", "file://migrations")

	if len(errs) > 0 {
		return nil, fmt.Errorf("config: missing required env vars: %v", errs)
	}
	return c, nil
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func getDurationEnv(key string, fallback time.Duration) time.Duration {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	d, err := time.ParseDuration(v)
	if err != nil {
		return fallback
	}
	return d
}

func getIntEnv(key string, fallback int) int {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	i, err := strconv.Atoi(v)
	if err != nil {
		return fallback
	}
	return i
}

func getInt64Env(key string, fallback int64) int64 {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	i, err := strconv.ParseInt(v, 10, 64)
	if err != nil {
		return fallback
	}
	return i
}
