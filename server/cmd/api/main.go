// Package main — RiMi API server entry point.
// Wires all dependencies and starts the HTTP server.
// Configuration loaded from environment variables only (SECRETS-01, patterns.md).
package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/go-chi/chi/v5"
	chimiddleware "github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/httprate"
	"github.com/joho/godotenv"

	"github.com/rimi/server/internal/auth"
	"github.com/rimi/server/internal/config"
	"github.com/rimi/server/internal/db"
	"github.com/rimi/server/internal/email"
	"github.com/rimi/server/internal/middleware"
	syncapi "github.com/rimi/server/internal/sync"
	"github.com/rimi/server/internal/workspace"
)

func main() {
	// Load .env for local development (ignored if file absent — prod uses env directly).
	_ = godotenv.Load()

	// Structured logger — no PII in log lines (PII-01).
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	})))

	cfg, err := config.Load()
	if err != nil {
		slog.Error("config load failed", slog.String("error", err.Error()))
		os.Exit(1)
	}

	// Run migrations as rimi_migrator (ADR-002).
	if err := db.Migrate(cfg.DBMigratorURL, cfg.MigrationsPath); err != nil {
		slog.Error("migration failed", slog.String("error", err.Error()))
		os.Exit(1)
	}

	// App pool — connects as rimi_app (NOBYPASSRLS, non-owner — ADR-002).
	ctx := context.Background()
	appPool, err := db.Open(ctx, cfg.DBAppURL)
	if err != nil {
		slog.Error("db connect failed", slog.String("error", err.Error()))
		os.Exit(1)
	}
	defer appPool.Close()

	// JWT signer (RS256 private key from env — SECRETS-01).
	signer, err := auth.NewJWTSigner(
		cfg.JWTPrivateKeyPEM, cfg.JWTIssuer, cfg.JWTAudience,
		cfg.JWTKeyID, cfg.JWTAccessTTL,
	)
	if err != nil {
		slog.Error("jwt signer init failed", slog.String("error", err.Error()))
		os.Exit(1)
	}

	// JWT verifier (RS256 public key from env — AUTH-10/11).
	verifier, err := middleware.NewJWTVerifier(
		cfg.JWTPublicKeyPEM, cfg.JWTIssuer, cfg.JWTAudience,
	)
	if err != nil {
		slog.Error("jwt verifier init failed", slog.String("error", err.Error()))
		os.Exit(1)
	}

	// Email sender (SMTP — credentials from env, never hardcoded — SECRETS-01).
	emailSender := email.NewSMTPSender(cfg.SMTPHost, cfg.SMTPPort, cfg.SMTPUser, cfg.SMTPPassword, cfg.SMTPFrom)

	// Repositories and services.
	authRepo := auth.NewRepository(appPool)
	authSvc := auth.NewService(authRepo, signer, emailSender, appPool, auth.ServiceConfig{
		LockoutThreshold: cfg.LockoutThreshold,
		LockoutDuration:  cfg.LockoutDuration,
		RefreshTokenTTL:  cfg.RefreshTokenTTL,
		EmailVerifyTTL:   cfg.EmailVerifyTTL,
		PasswordResetTTL: cfg.PasswordResetTTL,
	})
	authHandler := auth.NewHandler(authSvc)

	workspaceRepo := workspace.NewRepository(appPool)
	workspaceHandler := workspace.NewHandler(workspaceRepo, authSvc)

	// Router.
	r := chi.NewRouter()

	// Global middleware (NET-02: timeouts, INPUT-05: body limit, LOG-04: recover panics).
	r.Use(chimiddleware.RequestID)
	r.Use(chimiddleware.RealIP)
	r.Use(middleware.RequestLogger)
	r.Use(chimiddleware.Recoverer) // LOG-04: panics → 500, log full detail server-side
	r.Use(chimiddleware.CleanPath)
	r.Use(func(next http.Handler) http.Handler {
		return http.MaxBytesHandler(next, cfg.MaxBodyBytes) // INPUT-05
	})

	// v1 prefix.
	r.Route("/v1", func(r chi.Router) {
		// Health (unauthenticated).
		r.Get("/health", healthHandler(appPool))

		// Auth routes (unauthenticated).
		// RATE-01/02: rate limit auth endpoints.
		r.Route("/auth", func(r chi.Router) {
			r.Use(httprate.LimitByIP(20, time.Minute)) // RATE-01/02: 20 req/min per IP on auth
			r.Post("/register", authHandler.Register)
			r.Post("/verify-email", authHandler.VerifyEmail)
			r.Post("/login", authHandler.Login)
			r.Post("/refresh", authHandler.Refresh)
			r.Post("/logout", authHandler.Logout)
			r.Post("/password-reset/request", authHandler.PasswordResetRequest)
			r.Post("/password-reset/confirm", authHandler.PasswordResetConfirm)

			// Authenticated: GET /auth/me.
			r.Group(func(r chi.Router) {
				r.Use(middleware.Authenticate(verifier))
				r.Get("/me", authHandler.Me)
			})
		})

		// Workspace routes (authenticated).
		r.Route("/workspaces", func(r chi.Router) {
			r.Use(middleware.Authenticate(verifier))
			r.Post("/", workspaceHandler.CreateWorkspace)
			r.Get("/", workspaceHandler.ListWorkspaces)
			r.Post("/{id}/switch", workspaceHandler.SwitchWorkspace)
		})

		// Sync routes (authenticated + tenant transaction).
		// SYNC-SEC-01: Authenticate middleware required.
		// SYNC-SEC-02/03: workspace from JWT claim only (TenantTx enforces this).
		syncRepo := syncapi.NewRepository(appPool)
		syncHandler := syncapi.NewHandler(syncapi.NewService(syncRepo))

		r.Route("/sync", func(r chi.Router) {
			r.Use(middleware.Authenticate(verifier))
			r.Use(httprate.LimitByIP(60, time.Minute)) // SYNC: 60 req/min per IP
			r.Use(middleware.TenantTx(appPool))
			r.Post("/batch", syncHandler.Batch)
			r.Get("/pull", syncHandler.Pull)
		})

		// Realtime WebSocket endpoint (authenticated, no TenantTx — long-lived connection).
		// SYNC-SEC-13: Authenticate at router level, not inside handler.
		r.Group(func(r chi.Router) {
			r.Use(middleware.Authenticate(verifier))
			r.Get("/realtime", syncHandler.Realtime)
		})
	})

	srv := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      r,
		ReadTimeout:  cfg.ReadTimeout,  // NET-02
		WriteTimeout: cfg.WriteTimeout, // NET-02
		IdleTimeout:  cfg.IdleTimeout,  // NET-02
	}

	slog.Info("starting RiMi API server", slog.String("addr", srv.Addr))
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		slog.Error("server error", slog.String("error", err.Error()))
		os.Exit(1)
	}
}

// healthHandler returns a liveness/readiness probe response.
// 200 if DB is reachable, 503 otherwise.
func healthHandler(pool interface{ Ping(context.Context) error }) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if err := pool.Ping(r.Context()); err != nil {
			middleware.WriteError(w, http.StatusServiceUnavailable, middleware.ErrServiceUnavailable, "Database unreachable.", nil)
			return
		}
		middleware.WriteJSON(w, http.StatusOK, map[string]any{"status": "ok"})
	}
}
