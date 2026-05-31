// Package finance — handler unit tests.
// Tests auth-gate and input validation without a DB (httptest only).
package finance

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/go-chi/chi/v5"
	"github.com/rimi/server/internal/middleware"
)

// helpers

func assertStatus(t *testing.T, got, want int) {
	t.Helper()
	if got != want {
		t.Errorf("status: got %d want %d", got, want)
	}
}

func assertErrorCode(t *testing.T, body []byte, code string) {
	t.Helper()
	var resp map[string]any
	if err := json.Unmarshal(body, &resp); err != nil {
		t.Fatalf("unmarshal body: %v\nbody was: %s", err, body)
	}
	errObj, ok := resp["error"].(map[string]any)
	if !ok {
		t.Fatalf("no error key in: %s", body)
	}
	if errObj["code"] != code {
		t.Errorf("error code: got %v want %v", errObj["code"], code)
	}
}

// ── Auth gate tests ──────────────────────────────────────────────────

func TestListIncomeNoAuth(t *testing.T) {
	h := NewHandler(NewRepository())
	req := httptest.NewRequest(http.MethodGet, "/v1/finance/income", nil)
	w := httptest.NewRecorder()
	h.ListIncome(w, req)
	assertStatus(t, w.Code, http.StatusUnauthorized)
	assertErrorCode(t, w.Body.Bytes(), middleware.ErrUnauthorized)
}

func TestCreateIncomeNoAuth(t *testing.T) {
	h := NewHandler(NewRepository())
	body, _ := json.Marshal(map[string]any{"amount": "500000"})
	req := httptest.NewRequest(http.MethodPost, "/v1/finance/income", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	h.CreateIncome(w, req)
	assertStatus(t, w.Code, http.StatusUnauthorized)
	assertErrorCode(t, w.Body.Bytes(), middleware.ErrUnauthorized)
}

func TestListExpensesNoAuth(t *testing.T) {
	h := NewHandler(NewRepository())
	req := httptest.NewRequest(http.MethodGet, "/v1/finance/expenses", nil)
	w := httptest.NewRecorder()
	h.ListExpenses(w, req)
	assertStatus(t, w.Code, http.StatusUnauthorized)
	assertErrorCode(t, w.Body.Bytes(), middleware.ErrUnauthorized)
}

func TestGetPLNoAuth(t *testing.T) {
	h := NewHandler(NewRepository())
	req := httptest.NewRequest(http.MethodGet, "/v1/finance/pl?period=2026-05", nil)
	w := httptest.NewRecorder()
	h.GetPL(w, req)
	assertStatus(t, w.Code, http.StatusUnauthorized)
	assertErrorCode(t, w.Body.Bytes(), middleware.ErrUnauthorized)
}

func TestListReceivablesNoAuth(t *testing.T) {
	h := NewHandler(NewRepository())
	req := httptest.NewRequest(http.MethodGet, "/v1/finance/receivables", nil)
	w := httptest.NewRecorder()
	h.ListReceivables(w, req)
	assertStatus(t, w.Code, http.StatusUnauthorized)
	assertErrorCode(t, w.Body.Bytes(), middleware.ErrUnauthorized)
}

func TestMarkReceivableNoAuth(t *testing.T) {
	h := NewHandler(NewRepository())
	r := chi.NewRouter()
	r.Put("/v1/finance/receivables/{id}/status", h.MarkReceivable)
	body, _ := json.Marshal(map[string]any{"status": "paid"})
	req := httptest.NewRequest(http.MethodPut, "/v1/finance/receivables/11111111-1111-1111-1111-111111111111/status",
		bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	assertStatus(t, w.Code, http.StatusUnauthorized)
	assertErrorCode(t, w.Body.Bytes(), middleware.ErrUnauthorized)
}

func TestListPaymentsNoAuth(t *testing.T) {
	h := NewHandler(NewRepository())
	req := httptest.NewRequest(http.MethodGet, "/v1/finance/payments", nil)
	w := httptest.NewRecorder()
	h.ListPayments(w, req)
	assertStatus(t, w.Code, http.StatusUnauthorized)
	assertErrorCode(t, w.Body.Bytes(), middleware.ErrUnauthorized)
}

func TestCreatePaymentNoAuth(t *testing.T) {
	h := NewHandler(NewRepository())
	body, _ := json.Marshal(map[string]any{"amount": "150000", "method": "cash"})
	req := httptest.NewRequest(http.MethodPost, "/v1/finance/payments", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	h.CreatePayment(w, req)
	assertStatus(t, w.Code, http.StatusUnauthorized)
	assertErrorCode(t, w.Body.Bytes(), middleware.ErrUnauthorized)
}

// ── Validation logic tests ────────────────────────────────────────────

func TestValidPaymentMethods(t *testing.T) {
	valid := []string{"cash", "momo", "zalopay", "vnpay", "bank"}
	for _, m := range valid {
		if !validMethods[m] {
			t.Errorf("expected %q to be a valid payment method", m)
		}
	}
	invalid := []string{"", "card", "paypal", "CASH", "Bank"}
	for _, m := range invalid {
		if validMethods[m] {
			t.Errorf("expected %q to be an invalid payment method", m)
		}
	}
}

func TestValidReceivableStatuses(t *testing.T) {
	valid := []string{"paid", "written_off"}
	for _, s := range valid {
		if !validReceivableStatuses[s] {
			t.Errorf("expected %q to be a valid receivable status", s)
		}
	}
	invalid := []string{"", "open", "closed", "PAID"}
	for _, s := range invalid {
		if validReceivableStatuses[s] {
			t.Errorf("expected %q to be an invalid receivable status", s)
		}
	}
}

func TestPeriodRegex(t *testing.T) {
	valid := []string{"2026-05", "2026-12", "2026", "2025"}
	for _, p := range valid {
		if !periodRE.MatchString(p) {
			t.Errorf("expected %q to be a valid period", p)
		}
	}
	invalid := []string{"", "26-05", "2026-5", "abcd", "2026/05"}
	for _, p := range invalid {
		if periodRE.MatchString(p) {
			t.Errorf("expected %q to be an invalid period", p)
		}
	}
}
