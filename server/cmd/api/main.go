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

	"github.com/rimi/server/internal/ai"
	"github.com/rimi/server/internal/auth"
	"github.com/rimi/server/internal/config"
	"github.com/rimi/server/internal/customers"
	"github.com/rimi/server/internal/db"
	"github.com/rimi/server/internal/einvoice"
	"github.com/rimi/server/internal/email"
	"github.com/rimi/server/internal/finance"
	"github.com/rimi/server/internal/middleware"
	"github.com/rimi/server/internal/orders"
	"github.com/rimi/server/internal/products"
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

		// Product catalog routes (authenticated + tenant transaction).
		productsRepo := products.NewRepository()
		productsHandler := products.NewHandler(productsRepo)

		r.Route("/products", func(r chi.Router) {
			r.Use(middleware.Authenticate(verifier))
			r.Use(httprate.LimitByIP(120, time.Minute))
			r.Use(middleware.TenantTx(appPool))
			r.Get("/", productsHandler.ListProducts)
			r.Post("/", productsHandler.CreateProduct)
			r.Put("/{id}", productsHandler.UpdateProduct)
			r.Delete("/{id}", productsHandler.DeleteProduct)
		})

		// Inventory routes (authenticated + tenant transaction).
		r.Route("/inventory", func(r chi.Router) {
			r.Use(middleware.Authenticate(verifier))
			r.Use(httprate.LimitByIP(120, time.Minute))
			r.Use(middleware.TenantTx(appPool))
			r.Post("/{id}/adjust", productsHandler.AdjustInventory)
		})

		// Order management routes (authenticated + tenant transaction).
		ordersRepo := orders.NewRepository()
		ordersHandler := orders.NewHandler(ordersRepo)

		r.Route("/orders", func(r chi.Router) {
			r.Use(middleware.Authenticate(verifier))
			r.Use(httprate.LimitByIP(120, time.Minute))
			r.Use(middleware.TenantTx(appPool))
			r.Get("/", ordersHandler.ListOrders)
			r.Post("/", ordersHandler.CreateOrder)
			r.Get("/{id}", ordersHandler.GetOrder)
			r.Put("/{id}/status", ordersHandler.AdvanceStatus)
		})

		// Phase 5: CRM — customer profiles + notes.
		customersRepo := customers.NewRepository()
		customersHandler := customers.NewHandler(customersRepo)

		r.Route("/customers", func(r chi.Router) {
			r.Use(middleware.Authenticate(verifier))
			r.Use(httprate.LimitByIP(120, time.Minute))
			r.Use(middleware.TenantTx(appPool))
			r.Get("/", customersHandler.ListCustomers)
			r.Post("/", customersHandler.CreateCustomer)
			r.Get("/{id}", customersHandler.GetCustomer)
			r.Patch("/{id}", customersHandler.UpdateCustomer)
			r.Post("/{id}/notes", customersHandler.AddNote)
		})

		// Phase 6: Finance — income, expenses, P&L, receivables, payments.
		financeRepo := finance.NewRepository()
		financeHandler := finance.NewHandler(financeRepo)

		r.Route("/finance", func(r chi.Router) {
			r.Use(middleware.Authenticate(verifier))
			r.Use(httprate.LimitByIP(120, time.Minute))
			r.Use(middleware.TenantTx(appPool))
			r.Get("/income", financeHandler.ListIncome)
			r.Post("/income", financeHandler.CreateIncome)
			r.Get("/expenses", financeHandler.ListExpenses)
			r.Post("/expenses", financeHandler.CreateExpense)
			r.Get("/pl", financeHandler.GetPL)
			r.Get("/receivables", financeHandler.ListReceivables)
			r.Post("/receivables", financeHandler.CreateReceivable)
			r.Put("/receivables/{id}/status", financeHandler.MarkReceivable)
			r.Get("/payments", financeHandler.ListPayments)
			r.Post("/payments", financeHandler.CreatePayment)
		})

		// Phase 7: AI usage logging.
		aiRepo := ai.NewRepository()
		aiHandler := ai.NewHandler(aiRepo)

		r.Route("/ai", func(r chi.Router) {
			r.Use(middleware.Authenticate(verifier))
			r.Use(httprate.LimitByIP(60, time.Minute)) // tighter: AI calls are expensive
			r.Use(middleware.TenantTx(appPool))
			r.Post("/usage", aiHandler.LogUsage)
			r.Get("/usage", aiHandler.GetUsageSummary)
		})

		// Phase 8: E-invoice (hóa đơn điện tử).
		einvoiceRepo := einvoice.NewRepository()
		einvoiceHandler := einvoice.NewHandler(einvoiceRepo)

		r.Route("/einvoices", func(r chi.Router) {
			r.Use(middleware.Authenticate(verifier))
			r.Use(httprate.LimitByIP(60, time.Minute))
			r.Use(middleware.TenantTx(appPool))
			r.Get("/", einvoiceHandler.ListInvoices)
			r.Post("/", einvoiceHandler.CreateInvoice)
			r.Get("/{id}", einvoiceHandler.GetInvoice)
			r.Put("/{id}/status", einvoiceHandler.UpdateStatus)
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
