// Package integration — Phase 5-8 integration tests.
// Tests customers, finance, AI usage, and e-invoice endpoints against a real Postgres container.
// All tests run through the full handler → TenantTx → repository → RLS stack.
package integration

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/httprate"
	chimiddleware "github.com/go-chi/chi/v5/middleware"
	"github.com/google/uuid"
	"github.com/rimi/server/internal/ai"
	authhandler "github.com/rimi/server/internal/auth"
	"github.com/rimi/server/internal/customers"
	"github.com/rimi/server/internal/db"
	"github.com/rimi/server/internal/einvoice"
	"github.com/rimi/server/internal/finance"
	wsmiddleware "github.com/rimi/server/internal/middleware"
	"github.com/rimi/server/internal/orders"
	"github.com/rimi/server/internal/workspace"
)

// setupPhase58Router builds a test router that includes Phase 5-8 endpoints.
// Returns the router, an auth token (workspace-scoped), and teardown.
func setupPhase58Router(t *testing.T) (http.Handler, string, func()) {
	t.Helper()

	migratorDSN, appDSN := setupPostgres(t)
	_ = migratorDSN
	ctx := context.Background()

	appPool, err := db.Open(ctx, appDSN)
	if err != nil {
		t.Fatalf("open app pool: %v", err)
	}

	privPEM, pubPEM := generateTestPEM(t)
	signer, _ := authhandler.NewJWTSigner(privPEM, "rimi-auth", "rimi-api", "k1", 15*time.Minute)
	verifier, _ := wsmiddleware.NewJWTVerifier(pubPEM, "rimi-auth", "rimi-api")
	sender := &capturingEmailSender{}

	authRepo := authhandler.NewRepository(appPool)
	authSvc := authhandler.NewService(authRepo, signer, sender, appPool, authhandler.ServiceConfig{
		LockoutThreshold: 5,
		LockoutDuration:  15 * time.Minute,
		RefreshTokenTTL:  30 * 24 * time.Hour,
		EmailVerifyTTL:   24 * time.Hour,
		PasswordResetTTL: 30 * time.Minute,
	})
	authH := authhandler.NewHandler(authSvc)
	wsRepo := workspace.NewRepository(appPool)
	wsH := workspace.NewHandler(wsRepo, authSvc)

	customersRepo := customers.NewRepository()
	customersH := customers.NewHandler(customersRepo)

	financeRepo := finance.NewRepository()
	financeH := finance.NewHandler(financeRepo)

	aiRepo := ai.NewRepository()
	aiH := ai.NewHandler(aiRepo)

	einvoiceRepo := einvoice.NewRepository()
	einvoiceH := einvoice.NewHandler(einvoiceRepo)

	ordersRepo := orders.NewRepository()
	ordersH := orders.NewHandler(ordersRepo)

	r := chi.NewRouter()
	r.Use(chimiddleware.Recoverer)
	r.Use(wsmiddleware.RequestLogger)
	r.Use(func(next http.Handler) http.Handler {
		return http.MaxBytesHandler(next, 1<<20)
	})

	r.Route("/v1", func(r chi.Router) {
		r.Route("/auth", func(r chi.Router) {
			r.Post("/register", authH.Register)
			r.Post("/verify-email", authH.VerifyEmail)
			r.Post("/login", authH.Login)
			r.Group(func(r chi.Router) {
				r.Use(wsmiddleware.Authenticate(verifier))
				r.Get("/me", authH.Me)
			})
		})
		r.Route("/workspaces", func(r chi.Router) {
			r.Use(wsmiddleware.Authenticate(verifier))
			r.Use(wsmiddleware.TenantTx(appPool))
			r.Post("/", wsH.CreateWorkspace)
			r.Get("/", wsH.ListWorkspaces)
			r.Post("/{id}/switch", wsH.SwitchWorkspace)
		})
		r.Route("/orders", func(r chi.Router) {
			r.Use(wsmiddleware.Authenticate(verifier))
			r.Use(httprate.LimitByIP(500, time.Minute))
			r.Use(wsmiddleware.TenantTx(appPool))
			r.Get("/", ordersH.ListOrders)
			r.Post("/", ordersH.CreateOrder)
		})
		r.Route("/customers", func(r chi.Router) {
			r.Use(wsmiddleware.Authenticate(verifier))
			r.Use(httprate.LimitByIP(500, time.Minute))
			r.Use(wsmiddleware.TenantTx(appPool))
			r.Get("/", customersH.ListCustomers)
			r.Post("/", customersH.CreateCustomer)
			r.Get("/{id}", customersH.GetCustomer)
			r.Patch("/{id}", customersH.UpdateCustomer)
			r.Post("/{id}/notes", customersH.AddNote)
		})
		r.Route("/finance", func(r chi.Router) {
			r.Use(wsmiddleware.Authenticate(verifier))
			r.Use(httprate.LimitByIP(500, time.Minute))
			r.Use(wsmiddleware.TenantTx(appPool))
			r.Get("/income", financeH.ListIncome)
			r.Post("/income", financeH.CreateIncome)
			r.Get("/expenses", financeH.ListExpenses)
			r.Post("/expenses", financeH.CreateExpense)
			r.Get("/pl", financeH.GetPL)
			r.Get("/receivables", financeH.ListReceivables)
			r.Post("/receivables", financeH.CreateReceivable)
			r.Put("/receivables/{id}/status", financeH.MarkReceivable)
			r.Get("/payments", financeH.ListPayments)
			r.Post("/payments", financeH.CreatePayment)
		})
		r.Route("/ai", func(r chi.Router) {
			r.Use(wsmiddleware.Authenticate(verifier))
			r.Use(httprate.LimitByIP(500, time.Minute))
			r.Use(wsmiddleware.TenantTx(appPool))
			r.Post("/usage", aiH.LogUsage)
			r.Get("/usage", aiH.GetUsageSummary)
		})
		r.Route("/einvoices", func(r chi.Router) {
			r.Use(wsmiddleware.Authenticate(verifier))
			r.Use(httprate.LimitByIP(500, time.Minute))
			r.Use(wsmiddleware.TenantTx(appPool))
			r.Get("/", einvoiceH.ListInvoices)
			r.Post("/", einvoiceH.CreateInvoice)
			r.Get("/{id}", einvoiceH.GetInvoice)
			r.Put("/{id}/status", einvoiceH.UpdateStatus)
		})
	})

	// Register, verify, login, create workspace, get workspace-scoped token.
	email := "phase58@integration.test"
	password := "integration-test-pw!"

	w := httpPost(t, r, "/v1/auth/register", map[string]any{
		"email": email, "password": password, "display_name": "Phase58 User",
	}, "")
	if w.Code != http.StatusAccepted {
		t.Fatalf("register: %d %s", w.Code, w.Body.String())
	}
	time.Sleep(50 * time.Millisecond)
	verifyTok := sender.lastVerifyToken
	httpPost(t, r, "/v1/auth/verify-email", map[string]any{"token": verifyTok}, "")

	loginW := httpPost(t, r, "/v1/auth/login", map[string]any{
		"email": email, "password": password,
	}, "")
	if loginW.Code != http.StatusOK {
		t.Fatalf("login: %d %s", loginW.Code, loginW.Body.String())
	}
	loginBody := parseBody(t, loginW)
	loginData, _ := loginBody["data"].(map[string]any)
	baseToken, _ := loginData["access_token"].(string)

	// Create workspace.
	wsID := uuid.New().String()
	wsW := httpPost(t, r, "/v1/workspaces", map[string]any{"id": wsID, "name": "Test Shop"}, baseToken)
	if wsW.Code != http.StatusCreated {
		t.Fatalf("create workspace: %d %s", wsW.Code, wsW.Body.String())
	}

	// Switch to workspace-scoped token.
	// Response shape: { "data": { "workspace": {...}, "tokens": { "access_token": "...", ... } } }
	switchW := httpPost(t, r, "/v1/workspaces/"+wsID+"/switch", nil, baseToken)
	if switchW.Code != http.StatusOK {
		t.Fatalf("switch workspace: %d %s", switchW.Code, switchW.Body.String())
	}
	switchBody := parseBody(t, switchW)
	switchData, _ := switchBody["data"].(map[string]any)
	tokens, _ := switchData["tokens"].(map[string]any)
	wsToken, _ := tokens["access_token"].(string)
	if wsToken == "" {
		t.Fatalf("no workspace-scoped access_token in switch response: %v", switchBody)
	}

	return r, wsToken, appPool.Close
}

// ── Phase 5: CRM ──────────────────────────────────────────────────────

func TestCustomersCRUD(t *testing.T) {
	if testing.Short() {
		t.Skip()
	}
	router, token, teardown := setupPhase58Router(t)
	defer teardown()

	// List empty.
	t.Run("list customers empty", func(t *testing.T) {
		w := httpGet(t, router, "/v1/customers", token)
		if w.Code != http.StatusOK {
			t.Fatalf("list: expected 200, got %d: %s", w.Code, w.Body.String())
		}
		body := parseBody(t, w)
		data, _ := body["data"].(map[string]any)
		list, _ := data["customers"].([]any)
		if len(list) != 0 {
			t.Errorf("expected empty list, got %d items", len(list))
		}
	})

	// Create customer.
	name := "Chị Lan"
	phone := "0909123456"
	cID := uuid.New().String()
	var customerID string
	t.Run("create customer", func(t *testing.T) {
		w := httpPost(t, router, "/v1/customers", map[string]any{
			"id": cID, "name": name, "phone": phone, "tier": "gold",
		}, token)
		if w.Code != http.StatusCreated {
			t.Fatalf("create: expected 201, got %d: %s", w.Code, w.Body.String())
		}
		body := parseBody(t, w)
		data, _ := body["data"].(map[string]any)
		if data["tier"] != "gold" {
			t.Errorf("tier: got %v want gold", data["tier"])
		}
		customerID, _ = data["id"].(string)
		if customerID != cID {
			t.Errorf("id: got %v want %v", customerID, cID)
		}
	})

	if customerID == "" {
		customerID = cID
	}

	// Get customer detail.
	t.Run("get customer with empty notes and order summary", func(t *testing.T) {
		w := httpGet(t, router, "/v1/customers/"+customerID, token)
		if w.Code != http.StatusOK {
			t.Fatalf("get: expected 200, got %d: %s", w.Code, w.Body.String())
		}
		body := parseBody(t, w)
		data, _ := body["data"].(map[string]any)
		notes, _ := data["notes"].([]any)
		if len(notes) != 0 {
			t.Errorf("expected 0 notes, got %d", len(notes))
		}
		if data["order_count"] != float64(0) {
			t.Errorf("expected order_count=0, got %v", data["order_count"])
		}
	})

	// Add note.
	t.Run("add note", func(t *testing.T) {
		w := httpPost(t, router, "/v1/customers/"+customerID+"/notes", map[string]any{
			"note": "Khách VIP, hay đặt mỗi thứ Hai",
		}, token)
		if w.Code != http.StatusCreated {
			t.Fatalf("add note: expected 201, got %d: %s", w.Code, w.Body.String())
		}
		body := parseBody(t, w)
		data, _ := body["data"].(map[string]any)
		if data["note"] != "Khách VIP, hay đặt mỗi thứ Hai" {
			t.Errorf("note text mismatch: %v", data["note"])
		}
	})

	// Get customer detail again — should now have 1 note.
	t.Run("get customer has 1 note", func(t *testing.T) {
		w := httpGet(t, router, "/v1/customers/"+customerID, token)
		if w.Code != http.StatusOK {
			t.Fatalf("get: expected 200, got %d: %s", w.Code, w.Body.String())
		}
		body := parseBody(t, w)
		data, _ := body["data"].(map[string]any)
		notes, _ := data["notes"].([]any)
		if len(notes) != 1 {
			t.Errorf("expected 1 note, got %d", len(notes))
		}
	})

	// Update customer tier.
	t.Run("update customer tier to vip", func(t *testing.T) {
		w := httpPatch(t, router, "/v1/customers/"+customerID, map[string]any{
			"tier": "vip",
		}, token)
		if w.Code != http.StatusOK {
			t.Fatalf("patch: expected 200, got %d: %s", w.Code, w.Body.String())
		}
		body := parseBody(t, w)
		data, _ := body["data"].(map[string]any)
		if data["tier"] != "vip" {
			t.Errorf("tier: got %v want vip", data["tier"])
		}
	})

	// Search customers.
	t.Run("search by phone", func(t *testing.T) {
		w := httpGet(t, router, "/v1/customers?q=0909123456", token)
		if w.Code != http.StatusOK {
			t.Fatalf("search: expected 200, got %d: %s", w.Code, w.Body.String())
		}
		body := parseBody(t, w)
		data, _ := body["data"].(map[string]any)
		list, _ := data["customers"].([]any)
		if len(list) == 0 {
			t.Error("expected ≥1 customer from phone search")
		}
	})

	// Not found.
	t.Run("get non-existent customer", func(t *testing.T) {
		fakeID := uuid.New().String()
		w := httpGet(t, router, "/v1/customers/"+fakeID, token)
		if w.Code != http.StatusNotFound {
			t.Fatalf("expected 404, got %d", w.Code)
		}
	})

	// Validation: create customer without name or phone.
	t.Run("create customer no name or phone", func(t *testing.T) {
		w := httpPost(t, router, "/v1/customers", map[string]any{
			"tier": "reg",
		}, token)
		if w.Code != http.StatusBadRequest {
			t.Fatalf("expected 400, got %d: %s", w.Code, w.Body.String())
		}
	})

	// Validation: invalid tier.
	t.Run("create customer invalid tier", func(t *testing.T) {
		w := httpPost(t, router, "/v1/customers", map[string]any{
			"name": "Test", "tier": "platinum",
		}, token)
		if w.Code != http.StatusBadRequest {
			t.Fatalf("expected 400, got %d: %s", w.Code, w.Body.String())
		}
	})
}

// ── Phase 6: Finance ──────────────────────────────────────────────────

func TestFinanceCRUD(t *testing.T) {
	if testing.Short() {
		t.Skip()
	}
	router, token, teardown := setupPhase58Router(t)
	defer teardown()

	// List empty income.
	t.Run("list income empty", func(t *testing.T) {
		w := httpGet(t, router, "/v1/finance/income", token)
		if w.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
		}
	})

	// List empty expenses.
	t.Run("list expenses empty", func(t *testing.T) {
		w := httpGet(t, router, "/v1/finance/expenses", token)
		if w.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
		}
	})

	// List empty receivables.
	t.Run("list receivables empty", func(t *testing.T) {
		w := httpGet(t, router, "/v1/finance/receivables", token)
		if w.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
		}
	})

	// Create income entry.
	incomeID := uuid.New().String()
	t.Run("create income entry", func(t *testing.T) {
		w := httpPost(t, router, "/v1/finance/income", map[string]any{
			"id": incomeID, "amount": "500000", "category": "food_sales", "description": "Bún bò order 001",
		}, token)
		if w.Code != http.StatusCreated {
			t.Fatalf("expected 201, got %d: %s", w.Code, w.Body.String())
		}
		body := parseBody(t, w)
		data, _ := body["data"].(map[string]any)
		if data["amount"] != "500000.00" {
			t.Errorf("amount: got %v want 500000.00", data["amount"])
		}
	})

	// Create expense entry.
	t.Run("create expense entry", func(t *testing.T) {
		w := httpPost(t, router, "/v1/finance/expenses", map[string]any{
			"amount": "80000", "category": "raw_materials", "description": "Thịt bò",
		}, token)
		if w.Code != http.StatusCreated {
			t.Fatalf("expected 201, got %d: %s", w.Code, w.Body.String())
		}
	})

	// P&L summary.
	t.Run("get P&L for current month", func(t *testing.T) {
		period := time.Now().Format("2006-01")
		w := httpGet(t, router, "/v1/finance/pl?period="+period, token)
		if w.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
		}
		body := parseBody(t, w)
		data, _ := body["data"].(map[string]any)
		if data["period"] != period {
			t.Errorf("period: got %v want %v", data["period"], period)
		}
		// Net should be 500000 - 80000 = 420000.
		netProfit, _ := data["net_profit"].(string)
		if netProfit == "" {
			t.Error("expected non-empty net_profit")
		}
	})

	// P&L invalid period.
	t.Run("get P&L invalid period", func(t *testing.T) {
		w := httpGet(t, router, "/v1/finance/pl?period=badperiod", token)
		if w.Code != http.StatusBadRequest {
			t.Fatalf("expected 400, got %d", w.Code)
		}
	})

	// Create receivable.
	recID := uuid.New().String()
	t.Run("create receivable", func(t *testing.T) {
		w := httpPost(t, router, "/v1/finance/receivables", map[string]any{
			"id": recID, "amount": "200000", "description": "Công nợ bàn 3",
		}, token)
		if w.Code != http.StatusCreated {
			t.Fatalf("expected 201, got %d: %s", w.Code, w.Body.String())
		}
		body := parseBody(t, w)
		data, _ := body["data"].(map[string]any)
		if data["status"] != "open" {
			t.Errorf("status: got %v want open", data["status"])
		}
	})

	// Mark receivable as paid.
	t.Run("mark receivable paid", func(t *testing.T) {
		w := httpPut(t, router, "/v1/finance/receivables/"+recID+"/status", map[string]any{
			"status": "paid",
		}, token)
		if w.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
		}
		body := parseBody(t, w)
		data, _ := body["data"].(map[string]any)
		if data["status"] != "paid" {
			t.Errorf("status: got %v want paid", data["status"])
		}
	})

	// Create payment record.
	t.Run("create payment record cash", func(t *testing.T) {
		w := httpPost(t, router, "/v1/finance/payments", map[string]any{
			"amount": "150000", "method": "cash",
		}, token)
		if w.Code != http.StatusCreated {
			t.Fatalf("expected 201, got %d: %s", w.Code, w.Body.String())
		}
	})

	// Payment invalid method.
	t.Run("create payment invalid method", func(t *testing.T) {
		w := httpPost(t, router, "/v1/finance/payments", map[string]any{
			"amount": "150000", "method": "paypal",
		}, token)
		if w.Code != http.StatusBadRequest {
			t.Fatalf("expected 400, got %d", w.Code)
		}
	})

	// List payments.
	t.Run("list payments", func(t *testing.T) {
		w := httpGet(t, router, "/v1/finance/payments", token)
		if w.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
		}
		body := parseBody(t, w)
		data, _ := body["data"].(map[string]any)
		list, _ := data["payments"].([]any)
		if len(list) == 0 {
			t.Error("expected ≥1 payment after create")
		}
	})
}

// ── Phase 7: AI Usage ─────────────────────────────────────────────────

func TestAIUsage(t *testing.T) {
	if testing.Short() {
		t.Skip()
	}
	router, token, teardown := setupPhase58Router(t)
	defer teardown()

	// Log a usage record.
	usageID := uuid.New().String()
	feature := "caption"
	t.Run("log AI usage", func(t *testing.T) {
		w := httpPost(t, router, "/v1/ai/usage", map[string]any{
			"id": usageID, "model": "claude-sonnet-4-5",
			"feature":    feature,
			"tokens_in":  150,
			"tokens_out": 80,
			"cost_usd":   0.000125,
		}, token)
		if w.Code != http.StatusCreated {
			t.Fatalf("expected 201, got %d: %s", w.Code, w.Body.String())
		}
		body := parseBody(t, w)
		data, _ := body["data"].(map[string]any)
		if data["tokens_in"] != float64(150) {
			t.Errorf("tokens_in: got %v want 150", data["tokens_in"])
		}
	})

	// Get usage summary.
	t.Run("get usage summary for current month", func(t *testing.T) {
		period := time.Now().Format("2006-01")
		w := httpGet(t, router, "/v1/ai/usage?period="+period, token)
		if w.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
		}
		body := parseBody(t, w)
		data, _ := body["data"].(map[string]any)
		if data["total_calls"] != float64(1) {
			t.Errorf("total_calls: got %v want 1", data["total_calls"])
		}
		if data["total_tokens"] != float64(230) {
			t.Errorf("total_tokens: got %v want 230", data["total_tokens"])
		}
	})

	// Invalid period.
	t.Run("get usage summary invalid period", func(t *testing.T) {
		w := httpGet(t, router, "/v1/ai/usage?period=badperiod", token)
		if w.Code != http.StatusBadRequest {
			t.Fatalf("expected 400, got %d", w.Code)
		}
	})

	// Log without model — validation error.
	t.Run("log usage without model", func(t *testing.T) {
		w := httpPost(t, router, "/v1/ai/usage", map[string]any{
			"tokens_in": 100, "tokens_out": 50,
		}, token)
		if w.Code != http.StatusBadRequest {
			t.Fatalf("expected 400, got %d: %s", w.Code, w.Body.String())
		}
	})
}

// ── Phase 8: E-Invoice ────────────────────────────────────────────────

func TestEInvoiceCRUD(t *testing.T) {
	if testing.Short() {
		t.Skip()
	}
	router, token, teardown := setupPhase58Router(t)
	defer teardown()

	// List empty.
	t.Run("list invoices empty", func(t *testing.T) {
		w := httpGet(t, router, "/v1/einvoices", token)
		if w.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
		}
		body := parseBody(t, w)
		data, _ := body["data"].(map[string]any)
		list, _ := data["invoices"].([]any)
		if len(list) != 0 {
			t.Errorf("expected empty list, got %d", len(list))
		}
	})

	// Create invoice.
	invID := uuid.New().String()
	t.Run("create e-invoice draft", func(t *testing.T) {
		w := httpPost(t, router, "/v1/einvoices", map[string]any{
			"id":           invID,
			"provider":     "viettel_s",
			"buyer_name":   "Công ty ABC",
			"total_amount": "550000",
			"tax_amount":   "50000",
			"items": []map[string]any{
				{"description": "Bún bò Huế", "quantity": 2, "unit_price": "150000", "vat_rate": 0.10},
				{"description": "Trà đá", "quantity": 5, "unit_price": "10000", "vat_rate": 0.10},
			},
		}, token)
		if w.Code != http.StatusCreated {
			t.Fatalf("expected 201, got %d: %s", w.Code, w.Body.String())
		}
		body := parseBody(t, w)
		data, _ := body["data"].(map[string]any)
		if data["status"] != "draft" {
			t.Errorf("status: got %v want draft", data["status"])
		}
		items, _ := data["items"].([]any)
		if len(items) != 2 {
			t.Errorf("expected 2 items, got %d", len(items))
		}
	})

	// Get invoice.
	t.Run("get invoice detail", func(t *testing.T) {
		w := httpGet(t, router, "/v1/einvoices/"+invID, token)
		if w.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
		}
		body := parseBody(t, w)
		data, _ := body["data"].(map[string]any)
		if data["id"] != invID {
			t.Errorf("id: got %v want %v", data["id"], invID)
		}
	})

	// Issue invoice.
	t.Run("issue invoice with ma_tra_cuu", func(t *testing.T) {
		w := httpPut(t, router, "/v1/einvoices/"+invID+"/status", map[string]any{
			"status":    "issued",
			"ma_tra_cuu": "AB12345678",
		}, token)
		if w.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
		}
		body := parseBody(t, w)
		data, _ := body["data"].(map[string]any)
		if data["status"] != "issued" {
			t.Errorf("status: got %v want issued", data["status"])
		}
		if data["ma_tra_cuu"] != "AB12345678" {
			t.Errorf("ma_tra_cuu: got %v want AB12345678", data["ma_tra_cuu"])
		}
		if data["issued_at"] == nil {
			t.Error("expected issued_at to be set")
		}
	})

	// Cancel invoice.
	t.Run("cancel invoice", func(t *testing.T) {
		w := httpPut(t, router, "/v1/einvoices/"+invID+"/status", map[string]any{
			"status": "cancelled",
		}, token)
		if w.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
		}
		body := parseBody(t, w)
		data, _ := body["data"].(map[string]any)
		if data["status"] != "cancelled" {
			t.Errorf("status: got %v want cancelled", data["status"])
		}
	})

	// Invalid status.
	t.Run("update invoice to invalid status", func(t *testing.T) {
		otherID := uuid.New().String()
		// Create another invoice first.
		httpPost(t, router, "/v1/einvoices", map[string]any{
			"id": otherID, "buyer_name": "ABC",
		}, token)
		w := httpPut(t, router, "/v1/einvoices/"+otherID+"/status", map[string]any{
			"status": "unknown_status",
		}, token)
		if w.Code != http.StatusBadRequest {
			t.Fatalf("expected 400, got %d", w.Code)
		}
	})

	// Not found.
	t.Run("get non-existent invoice", func(t *testing.T) {
		fakeID := uuid.New().String()
		w := httpGet(t, router, "/v1/einvoices/"+fakeID, token)
		if w.Code != http.StatusNotFound {
			t.Fatalf("expected 404, got %d", w.Code)
		}
	})
}

// httpPatch sends a PATCH request to the test router.
func httpPatch(t *testing.T, router http.Handler, path string, body interface{}, token string) *httptest.ResponseRecorder {
	t.Helper()
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPatch, path, bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	return w
}

// httpPut sends a PUT request to the test router.
func httpPut(t *testing.T, router http.Handler, path string, body interface{}, token string) *httptest.ResponseRecorder {
	t.Helper()
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPut, path, bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	return w
}
