// Package customers — handler unit tests.
// Tests auth-gate and input validation without a DB (httptest only).
package customers

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

func TestListCustomersNoAuth(t *testing.T) {
	h := NewHandler(NewRepository())
	req := httptest.NewRequest(http.MethodGet, "/v1/customers", nil)
	w := httptest.NewRecorder()
	h.ListCustomers(w, req)
	assertStatus(t, w.Code, http.StatusUnauthorized)
	assertErrorCode(t, w.Body.Bytes(), middleware.ErrUnauthorized)
}

func TestGetCustomerNoAuth(t *testing.T) {
	h := NewHandler(NewRepository())
	r := chi.NewRouter()
	r.Get("/v1/customers/{id}", h.GetCustomer)
	req := httptest.NewRequest(http.MethodGet, "/v1/customers/11111111-1111-1111-1111-111111111111", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	assertStatus(t, w.Code, http.StatusUnauthorized)
	assertErrorCode(t, w.Body.Bytes(), middleware.ErrUnauthorized)
}

func TestCreateCustomerNoAuth(t *testing.T) {
	h := NewHandler(NewRepository())
	body, _ := json.Marshal(map[string]any{"name": "Chị Lan"})
	req := httptest.NewRequest(http.MethodPost, "/v1/customers", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	h.CreateCustomer(w, req)
	assertStatus(t, w.Code, http.StatusUnauthorized)
	assertErrorCode(t, w.Body.Bytes(), middleware.ErrUnauthorized)
}

func TestUpdateCustomerNoAuth(t *testing.T) {
	h := NewHandler(NewRepository())
	r := chi.NewRouter()
	r.Patch("/v1/customers/{id}", h.UpdateCustomer)
	body, _ := json.Marshal(map[string]any{"tier": "gold"})
	req := httptest.NewRequest(http.MethodPatch, "/v1/customers/11111111-1111-1111-1111-111111111111",
		bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	assertStatus(t, w.Code, http.StatusUnauthorized)
	assertErrorCode(t, w.Body.Bytes(), middleware.ErrUnauthorized)
}

func TestAddNoteNoAuth(t *testing.T) {
	h := NewHandler(NewRepository())
	r := chi.NewRouter()
	r.Post("/v1/customers/{id}/notes", h.AddNote)
	body, _ := json.Marshal(map[string]any{"note": "Khách VIP"})
	req := httptest.NewRequest(http.MethodPost, "/v1/customers/11111111-1111-1111-1111-111111111111/notes",
		bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	assertStatus(t, w.Code, http.StatusUnauthorized)
	assertErrorCode(t, w.Body.Bytes(), middleware.ErrUnauthorized)
}

// ── Validation tests (require valid auth context) ────────────────────

// TestValidTiers verifies the tier allowlist.
func TestValidTiers(t *testing.T) {
	valid := []string{"reg", "gold", "vip", "risk"}
	for _, tier := range valid {
		if !validTiers[tier] {
			t.Errorf("expected %q to be a valid tier", tier)
		}
	}
	invalid := []string{"", "premium", "VIP", "GOLD", "unknown"}
	for _, tier := range invalid {
		if validTiers[tier] {
			t.Errorf("expected %q to be an invalid tier", tier)
		}
	}
}

// TestNewUUID verifies the UUID helper produces a valid UUID.
func TestNewUUID(t *testing.T) {
	id := newUUID()
	if len(id) != 36 {
		t.Errorf("expected UUID length 36, got %d: %q", len(id), id)
	}
	if id[8] != '-' || id[13] != '-' || id[18] != '-' || id[23] != '-' {
		t.Errorf("UUID format invalid: %q", id)
	}
}
