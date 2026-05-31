package middleware

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// TestWriteJSON verifies the success envelope shape per patterns.md.
func TestWriteJSON(t *testing.T) {
	w := httptest.NewRecorder()
	WriteJSON(w, http.StatusOK, map[string]any{"status": "ok"})

	if w.Code != http.StatusOK {
		t.Errorf("status: got %d want 200", w.Code)
	}

	var resp map[string]any
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode: %v", err)
	}

	// Must have "data" and "meta" with "timestamp".
	if _, ok := resp["data"]; !ok {
		t.Error("missing 'data' key")
	}
	meta, ok := resp["meta"].(map[string]any)
	if !ok {
		t.Fatal("missing or wrong type 'meta' key")
	}
	if _, ok := meta["timestamp"]; !ok {
		t.Error("missing 'timestamp' in meta")
	}
	// Must NOT have "error" in a success response.
	if _, ok := resp["error"]; ok {
		t.Error("success response must not have 'error' key")
	}
}

// TestWriteError verifies the error envelope shape per patterns.md.
func TestWriteError(t *testing.T) {
	w := httptest.NewRecorder()
	details := []ErrorDetail{{Field: "email", Issue: "invalid_format"}}
	WriteError(w, http.StatusBadRequest, ErrValidation, "One or more fields are invalid.", details)

	if w.Code != http.StatusBadRequest {
		t.Errorf("status: got %d want 400", w.Code)
	}

	var resp map[string]any
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode: %v", err)
	}

	// Must have "error" key; must NOT have "data".
	errObj, ok := resp["error"].(map[string]any)
	if !ok {
		t.Fatal("missing or wrong type 'error' key")
	}
	if errObj["code"] != ErrValidation {
		t.Errorf("code: got %v want %v", errObj["code"], ErrValidation)
	}
	if _, ok := resp["data"]; ok {
		t.Error("error response must not have 'data' key")
	}
	// Details array must be present and non-nil.
	dets, ok := errObj["details"].([]any)
	if !ok || len(dets) == 0 {
		t.Errorf("details: expected non-empty array, got %v", errObj["details"])
	}
}

// TestWriteErrorNilDetails ensures details is always an array (never null in JSON).
func TestWriteErrorNilDetails(t *testing.T) {
	w := httptest.NewRecorder()
	WriteError(w, http.StatusInternalServerError, ErrInternalError, "Something went wrong.", nil)

	var resp map[string]any
	_ = json.NewDecoder(w.Body).Decode(&resp)
	errObj := resp["error"].(map[string]any)
	dets := errObj["details"]
	if dets == nil {
		t.Error("details must be [] not null")
	}
}
