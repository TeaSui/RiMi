// Package workspace — HTTP handler unit tests.
// Tests validation, envelope shape, and error code mapping.
// Full DB-backed paths are covered by integration tests.
package workspace

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/go-chi/chi/v5"
	"github.com/rimi/server/internal/middleware"
)

// TestCreateWorkspaceValidation verifies INPUT-03: invalid name returns 400.
// We do NOT inject claims here so the missing-claims check is exercised first.
func TestCreateWorkspaceNoAuth(t *testing.T) {
	h := &Handler{repo: nil, authSvc: nil}

	req := httptest.NewRequest(http.MethodPost, "/v1/workspaces",
		bytes.NewBufferString(`{"name":"My Shop"}`))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	h.CreateWorkspace(w, req)

	// Without claims in context, handler returns 401.
	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d", w.Code)
	}
	assertErrorCode(t, w.Body.Bytes(), middleware.ErrUnauthorized)
}

// TestListWorkspacesNoAuth verifies 401 when no auth context.
func TestListWorkspacesNoAuth(t *testing.T) {
	h := &Handler{repo: nil, authSvc: nil}

	req := httptest.NewRequest(http.MethodGet, "/v1/workspaces", nil)
	w := httptest.NewRecorder()
	h.ListWorkspaces(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d", w.Code)
	}
}

// TestSwitchWorkspaceNoAuth verifies 401 when no auth context.
func TestSwitchWorkspaceNoAuth(t *testing.T) {
	h := &Handler{repo: nil, authSvc: nil}

	r := chi.NewRouter()
	r.Post("/v1/workspaces/{id}/switch", h.SwitchWorkspace)

	req := httptest.NewRequest(http.MethodPost, "/v1/workspaces/some-id/switch", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d", w.Code)
	}
}

// TestWorkspaceToMap verifies the serialization helper.
func TestWorkspaceToMap(t *testing.T) {
	ws := &Workspace{}
	ws.Name = "Test Workspace"
	m := workspaceToMap(ws, "owner")

	for _, key := range []string{"id", "name", "role", "created_at"} {
		if _, ok := m[key]; !ok {
			t.Errorf("missing key %q in workspace map", key)
		}
	}
	if m["role"] != "owner" {
		t.Errorf("expected role=owner, got %v", m["role"])
	}
	if m["name"] != "Test Workspace" {
		t.Errorf("expected name='Test Workspace', got %v", m["name"])
	}
}

// TestIsPGUniqueViolation verifies the error code detector.
func TestIsPGUniqueViolation(t *testing.T) {
	if !isPGUniqueViolation(makeErr("23505")) {
		t.Error("expected 23505 to be detected as unique violation")
	}
	if !isPGUniqueViolation(makeErr("unique constraint violation")) {
		t.Error("expected 'unique constraint' to be detected")
	}
	if isPGUniqueViolation(nil) {
		t.Error("nil should not be a unique violation")
	}
	if isPGUniqueViolation(makeErr("foreign key violation")) {
		t.Error("FK violation should not be detected as unique")
	}
}

// helpers

type mockErr struct{ msg string }

func (e *mockErr) Error() string { return e.msg }

func makeErr(msg string) error { return &mockErr{msg: msg} }

func assertErrorCode(t *testing.T, body []byte, code string) {
	t.Helper()
	var resp map[string]any
	if err := json.Unmarshal(body, &resp); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	errObj, ok := resp["error"].(map[string]any)
	if !ok {
		t.Fatalf("no error key in: %s", body)
	}
	if errObj["code"] != code {
		t.Errorf("error code: got %v want %v", errObj["code"], code)
	}
}
