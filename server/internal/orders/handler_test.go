// Package orders — handler unit tests.
// Tests auth-gate and input validation without a DB (httptest only).
package orders

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
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

// ── Tests: auth gate (no claims → 401) ──────────────────────────────

func TestListOrdersNoAuth(t *testing.T) {
	h := NewHandler(NewRepository())
	req := httptest.NewRequest(http.MethodGet, "/v1/orders", nil)
	w := httptest.NewRecorder()
	h.ListOrders(w, req)
	assertStatus(t, w.Code, http.StatusUnauthorized)
	assertErrorCode(t, w.Body.Bytes(), middleware.ErrUnauthorized)
}

func TestCreateOrderNoAuth(t *testing.T) {
	h := NewHandler(NewRepository())
	body, _ := json.Marshal(map[string]any{"channel": "walkin", "total_amount": "50000"})
	req := httptest.NewRequest(http.MethodPost, "/v1/orders", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	h.CreateOrder(w, req)
	assertStatus(t, w.Code, http.StatusUnauthorized)
	assertErrorCode(t, w.Body.Bytes(), middleware.ErrUnauthorized)
}

func TestGetOrderNoAuth(t *testing.T) {
	h := NewHandler(NewRepository())
	r := chi.NewRouter()
	r.Get("/v1/orders/{id}", h.GetOrder)
	req := httptest.NewRequest(http.MethodGet, "/v1/orders/11111111-1111-1111-1111-111111111111", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	assertStatus(t, w.Code, http.StatusUnauthorized)
	assertErrorCode(t, w.Body.Bytes(), middleware.ErrUnauthorized)
}

func TestAdvanceStatusNoAuth(t *testing.T) {
	h := NewHandler(NewRepository())
	r := chi.NewRouter()
	r.Put("/v1/orders/{id}/status", h.AdvanceStatus)
	body, _ := json.Marshal(map[string]any{"status": "cooking"})
	req := httptest.NewRequest(http.MethodPut, "/v1/orders/11111111-1111-1111-1111-111111111111/status",
		bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	assertStatus(t, w.Code, http.StatusUnauthorized)
	assertErrorCode(t, w.Body.Bytes(), middleware.ErrUnauthorized)
}

// ── Tests: input validation — AdvanceStatus rejects invalid status ────
// Auth gate fires first (401), so invalid-status validation is documented.
// These tests confirm the 401 path (auth gate fires before validation).

func TestAdvanceStatusInvalidStatusNoAuth(t *testing.T) {
	// Without claims, the handler returns 401 regardless of the status value.
	h := NewHandler(NewRepository())
	r := chi.NewRouter()
	r.Put("/v1/orders/{id}/status", h.AdvanceStatus)
	body, _ := json.Marshal(map[string]any{"status": "invalid_status_xyz"})
	req := httptest.NewRequest(http.MethodPut, "/v1/orders/11111111-1111-1111-1111-111111111111/status",
		bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	// Auth check fires first — even with bad status the result is 401.
	assertStatus(t, w.Code, http.StatusUnauthorized)
}

// TestAdvanceStatusInvalidStatusValue verifies that the validStatuses map
// correctly rejects bad values (unit test of logic, not HTTP).
func TestAdvanceStatusInvalidStatusValue(t *testing.T) {
	invalid := []string{"", "pending", "cancelled", "COOKING", "invalid_xyz"}
	for _, s := range invalid {
		if validStatuses[s] {
			t.Errorf("expected %q to be invalid but validStatuses[s] == true", s)
		}
	}
}

func TestAdvanceStatusValidValues(t *testing.T) {
	valid := []string{"new", "cooking", "ready", "delivering", "done"}
	for _, s := range valid {
		if !validStatuses[s] {
			t.Errorf("expected %q to be valid but validStatuses[s] == false", s)
		}
	}
}

// TestCreateOrderBadJSON verifies auth fires before JSON parse (returns 401).
func TestCreateOrderBadJSON(t *testing.T) {
	h := NewHandler(NewRepository())
	req := httptest.NewRequest(http.MethodPost, "/v1/orders",
		strings.NewReader(`{bad json`))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	h.CreateOrder(w, req)
	assertStatus(t, w.Code, http.StatusUnauthorized)
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

// TestValidChannels verifies channel validation logic.
func TestValidChannels(t *testing.T) {
	valid := []string{"online", "app", "phone", "walkin"}
	for _, c := range valid {
		if !validChannels[c] {
			t.Errorf("expected %q to be valid channel", c)
		}
	}
	invalid := []string{"", "web", "delivery", "WALKIN"}
	for _, c := range invalid {
		if validChannels[c] {
			t.Errorf("expected %q to be invalid channel", c)
		}
	}
}
