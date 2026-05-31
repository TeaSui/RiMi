// Package ai — handler unit tests.
// Tests auth-gate and input validation without a DB (httptest only).
package ai

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

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

func TestLogUsageNoAuth(t *testing.T) {
	h := NewHandler(NewRepository())
	body, _ := json.Marshal(map[string]any{"model": "claude-sonnet-4-5", "tokens_in": 100, "tokens_out": 50})
	req := httptest.NewRequest(http.MethodPost, "/v1/ai/usage", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	h.LogUsage(w, req)
	assertStatus(t, w.Code, http.StatusUnauthorized)
	assertErrorCode(t, w.Body.Bytes(), middleware.ErrUnauthorized)
}

func TestGetUsageSummaryNoAuth(t *testing.T) {
	h := NewHandler(NewRepository())
	req := httptest.NewRequest(http.MethodGet, "/v1/ai/usage?period=2026-05", nil)
	w := httptest.NewRecorder()
	h.GetUsageSummary(w, req)
	assertStatus(t, w.Code, http.StatusUnauthorized)
	assertErrorCode(t, w.Body.Bytes(), middleware.ErrUnauthorized)
}

// ── Validation logic tests ────────────────────────────────────────────

func TestValidFeatures(t *testing.T) {
	valid := []string{"caption", "menu_copy"}
	for _, f := range valid {
		if !validFeatures[f] {
			t.Errorf("expected %q to be a valid feature", f)
		}
	}
	invalid := []string{"", "chat", "translate", "CAPTION"}
	for _, f := range invalid {
		if validFeatures[f] {
			t.Errorf("expected %q to be an invalid feature", f)
		}
	}
}

func TestNewUUID(t *testing.T) {
	id := newUUID()
	if len(id) != 36 {
		t.Errorf("expected UUID length 36, got %d: %q", len(id), id)
	}
	if id[8] != '-' || id[13] != '-' || id[18] != '-' || id[23] != '-' {
		t.Errorf("UUID format invalid: %q", id)
	}
}
