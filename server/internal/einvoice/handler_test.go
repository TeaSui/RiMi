// Package einvoice — handler unit tests.
// Tests auth-gate and input validation without a DB (httptest only).
package einvoice

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

func TestListInvoicesNoAuth(t *testing.T) {
	h := NewHandler(NewRepository())
	req := httptest.NewRequest(http.MethodGet, "/v1/einvoices", nil)
	w := httptest.NewRecorder()
	h.ListInvoices(w, req)
	assertStatus(t, w.Code, http.StatusUnauthorized)
	assertErrorCode(t, w.Body.Bytes(), middleware.ErrUnauthorized)
}

func TestGetInvoiceNoAuth(t *testing.T) {
	h := NewHandler(NewRepository())
	r := chi.NewRouter()
	r.Get("/v1/einvoices/{id}", h.GetInvoice)
	req := httptest.NewRequest(http.MethodGet, "/v1/einvoices/11111111-1111-1111-1111-111111111111", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	assertStatus(t, w.Code, http.StatusUnauthorized)
	assertErrorCode(t, w.Body.Bytes(), middleware.ErrUnauthorized)
}

func TestCreateInvoiceNoAuth(t *testing.T) {
	h := NewHandler(NewRepository())
	body, _ := json.Marshal(map[string]any{"buyer_name": "Công ty ABC"})
	req := httptest.NewRequest(http.MethodPost, "/v1/einvoices", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	h.CreateInvoice(w, req)
	assertStatus(t, w.Code, http.StatusUnauthorized)
	assertErrorCode(t, w.Body.Bytes(), middleware.ErrUnauthorized)
}

func TestUpdateStatusNoAuth(t *testing.T) {
	h := NewHandler(NewRepository())
	r := chi.NewRouter()
	r.Put("/v1/einvoices/{id}/status", h.UpdateStatus)
	body, _ := json.Marshal(map[string]any{"status": "issued"})
	req := httptest.NewRequest(http.MethodPut, "/v1/einvoices/11111111-1111-1111-1111-111111111111/status",
		bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	assertStatus(t, w.Code, http.StatusUnauthorized)
	assertErrorCode(t, w.Body.Bytes(), middleware.ErrUnauthorized)
}

// ── Validation logic tests ────────────────────────────────────────────

func TestValidIssueStatuses(t *testing.T) {
	valid := []string{"issued", "cancelled"}
	for _, s := range valid {
		if !validIssueStatuses[s] {
			t.Errorf("expected %q to be a valid issue status", s)
		}
	}
	invalid := []string{"", "draft", "replaced", "ISSUED"}
	for _, s := range invalid {
		if validIssueStatuses[s] {
			t.Errorf("expected %q to be an invalid issue status", s)
		}
	}
}

func TestValidProviders(t *testing.T) {
	valid := []string{"viettel_s", "misa"}
	for _, p := range valid {
		if !validProviders[p] {
			t.Errorf("expected %q to be a valid provider", p)
		}
	}
	invalid := []string{"", "vnpt", "bkav", "MISA"}
	for _, p := range invalid {
		if validProviders[p] {
			t.Errorf("expected %q to be an invalid provider", p)
		}
	}
}

func TestItoaHelper(t *testing.T) {
	cases := []struct {
		n    int
		want string
	}{
		{0, "0"},
		{1, "1"},
		{10, "10"},
		{-3, "-3"},
		{99, "99"},
	}
	for _, tc := range cases {
		got := itoa(tc.n)
		if got != tc.want {
			t.Errorf("itoa(%d) = %q, want %q", tc.n, got, tc.want)
		}
	}
}
