// Package auth — handler unit tests.
// These tests use a mock service; they test HTTP contract compliance
// (status codes, envelope shape, validation).
package auth

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/google/uuid"
)

// We can't easily use the handler's real service in unit tests without a DB.
// Instead we test the handler's validation logic and envelope shaping directly.

// TestRegisterValidation tests that invalid input returns 400.
func TestRegisterValidation(t *testing.T) {
	cases := []struct {
		name   string
		body   string
		want   int
		code   string
	}{
		{"missing email", `{"password":"12345678","display_name":"Test"}`, 400, "VALIDATION_ERROR"},
		{"bad email", `{"email":"not-email","password":"12345678","display_name":"Test"}`, 400, "VALIDATION_ERROR"},
		{"short password", `{"email":"a@b.com","password":"short","display_name":"Test"}`, 400, "VALIDATION_ERROR"},
		{"missing display_name", `{"email":"a@b.com","password":"12345678"}`, 400, "VALIDATION_ERROR"},
	}

	// Build a handler with a noop service.
	svc := &Service{
		repo:   nil,
		signer: nil,
		sender: nil,
		pool:   nil,
		cfg:    ServiceConfig{},
	}
	h := NewHandler(svc)

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPost, "/v1/auth/register", bytes.NewBufferString(tc.body))
			req.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()
			h.Register(w, req)

			if w.Code != tc.want {
				t.Errorf("status: got %d want %d (body: %s)", w.Code, tc.want, w.Body.String())
			}
			var resp map[string]any
			if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
				t.Fatalf("decode response: %v", err)
			}
			errObj, _ := resp["error"].(map[string]any)
			if errObj == nil {
				t.Fatalf("expected error envelope, got: %v", resp)
			}
			if errObj["code"] != tc.code {
				t.Errorf("error code: got %v want %v", errObj["code"], tc.code)
			}
		})
	}
}

// TestRegisterEnvelope tests that a successful register returns the correct envelope.
func TestRegisterEnvelope(t *testing.T) {
	// We can't call the real service without a DB in unit tests.
	// This test verifies the envelope shape only by mocking at the HTTP level
	// using a handler that has nil internals but valid input will reach the service
	// call. Since we can't mock the service interface without it, we test only
	// validation path shape here.
	// Full e2e register flow is covered in integration tests.
	t.Skip("full register envelope tested in integration test")
}

// TestLoginValidation tests validation at the handler boundary.
func TestLoginValidation(t *testing.T) {
	svc := &Service{cfg: ServiceConfig{}}
	h := NewHandler(svc)

	cases := []struct {
		name string
		body string
		want int
	}{
		{"missing email", `{"password":"12345678"}`, 400},
		{"bad email", `{"email":"notanemail","password":"12345678"}`, 400},
		{"missing password", `{"email":"a@b.com"}`, 400},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPost, "/v1/auth/login", bytes.NewBufferString(tc.body))
			req.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()
			h.Login(w, req)
			if w.Code != tc.want {
				t.Errorf("status: got %d want %d", w.Code, tc.want)
			}
		})
	}
}

// TestVerifyEmailValidation tests token length enforcement.
func TestVerifyEmailValidation(t *testing.T) {
	svc := &Service{cfg: ServiceConfig{}}
	h := NewHandler(svc)

	cases := []struct {
		name string
		body string
		want int
	}{
		{"missing token", `{}`, 400},
		{"too short", `{"token":"abc"}`, 400},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPost, "/v1/auth/verify-email", bytes.NewBufferString(tc.body))
			w := httptest.NewRecorder()
			h.VerifyEmail(w, req)
			if w.Code != tc.want {
				t.Errorf("status: got %d want %d body: %s", w.Code, tc.want, w.Body.String())
			}
		})
	}
}

// TestPasswordResetRequestValidation ensures anti-enumeration: always returns 200.
// We can't call the real service without a DB; validate response shape with
// a malformed body.
func TestPasswordResetRequestBadInput(t *testing.T) {
	svc := &Service{cfg: ServiceConfig{}}
	h := NewHandler(svc)

	// Bad email format → 400 (validation before the anti-enum path).
	req := httptest.NewRequest(http.MethodPost, "/v1/auth/password-reset/request",
		bytes.NewBufferString(`{"email":"notanemail"}`))
	w := httptest.NewRecorder()
	h.PasswordResetRequest(w, req)
	if w.Code != 400 {
		t.Errorf("expected 400 for bad email, got %d", w.Code)
	}
}

// TestRefreshValidation tests input validation on the refresh endpoint.
func TestRefreshValidation(t *testing.T) {
	svc := &Service{cfg: ServiceConfig{}}
	h := NewHandler(svc)

	cases := []struct {
		name string
		body string
		want int
	}{
		{"missing field", `{}`, 400},
		{"too short", `{"refresh_token":"abc"}`, 400},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPost, "/v1/auth/refresh", bytes.NewBufferString(tc.body))
			w := httptest.NewRecorder()
			h.Refresh(w, req)
			if w.Code != tc.want {
				t.Errorf("status: got %d want %d body: %s", w.Code, tc.want, w.Body.String())
			}
		})
	}
}

// TestLogoutValidation tests input validation on logout.
func TestLogoutValidation(t *testing.T) {
	svc := &Service{cfg: ServiceConfig{}}
	h := NewHandler(svc)

	req := httptest.NewRequest(http.MethodPost, "/v1/auth/logout",
		bytes.NewBufferString(`{"refresh_token":"abc"}`))
	w := httptest.NewRecorder()
	h.Logout(w, req)
	if w.Code != 400 {
		t.Errorf("expected 400 for too-short token, got %d", w.Code)
	}
}

// TestPasswordResetConfirmValidation tests input validation.
func TestPasswordResetConfirmValidation(t *testing.T) {
	svc := &Service{cfg: ServiceConfig{}}
	h := NewHandler(svc)

	cases := []struct {
		name string
		body string
		want int
	}{
		{"missing token", `{"new_password":"12345678"}`, 400},
		{"short password", `{"token":"aaaaaaaaaaaaaaaa","new_password":"short"}`, 400},
		{"short token", `{"token":"abc","new_password":"12345678"}`, 400},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPost, "/v1/auth/password-reset/confirm",
				bytes.NewBufferString(tc.body))
			w := httptest.NewRecorder()
			h.PasswordResetConfirm(w, req)
			if w.Code != tc.want {
				t.Errorf("status: got %d want %d body: %s", w.Code, tc.want, w.Body.String())
			}
		})
	}
}

// TestMeNoAuth verifies /auth/me returns 401 when no claims in context.
func TestMeNoAuth(t *testing.T) {
	svc := &Service{cfg: ServiceConfig{}}
	h := NewHandler(svc)

	req := httptest.NewRequest(http.MethodGet, "/v1/auth/me", nil)
	w := httptest.NewRecorder()
	h.Me(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d body: %s", w.Code, w.Body.String())
	}
	var resp map[string]any
	_ = json.NewDecoder(w.Body).Decode(&resp)
	if errObj, _ := resp["error"].(map[string]any); errObj != nil {
		if errObj["code"] != "UNAUTHORIZED" {
			t.Errorf("expected UNAUTHORIZED, got %v", errObj["code"])
		}
	}
}

// TestProfileToMap verifies the profile serialization helper.
func TestProfileToMap(t *testing.T) {
	p := &Profile{
		ID:            uuid.New(),
		Email:         "test@example.com",
		DisplayName:   "Test User",
		Phone:         nil,
		EmailVerified: true,
		CreatedAt:     time.Now(),
	}
	m := profileToMap(p)
	for _, key := range []string{"id", "email", "display_name", "phone", "email_verified", "created_at"} {
		if _, ok := m[key]; !ok {
			t.Errorf("missing key %q in profileToMap result", key)
		}
	}
	if m["email"] != "test@example.com" {
		t.Errorf("email: got %v", m["email"])
	}
	if m["email_verified"] != true {
		t.Errorf("email_verified: got %v", m["email_verified"])
	}
}

// TestIsValidEmail tests the email validation helper.
func TestIsValidEmail(t *testing.T) {
	cases := []struct {
		email string
		valid bool
	}{
		{"user@example.com", true},
		{"u@b.co", true},
		{"notanemail", false},
		{"@no-local.com", false},
		{"no-domain@", false},
		{"", false},
	}
	for _, tc := range cases {
		got := isValidEmail(tc.email)
		if got != tc.valid {
			t.Errorf("isValidEmail(%q) = %v, want %v", tc.email, got, tc.valid)
		}
	}
}

// TestErrorEnvelopeShape verifies the error envelope has the right structure.
func TestErrorEnvelopeShape(t *testing.T) {
	svc := &Service{cfg: ServiceConfig{}}
	h := NewHandler(svc)

	req := httptest.NewRequest(http.MethodPost, "/v1/auth/login",
		bytes.NewBufferString(`{"email":"notanemail","password":"test"}`))
	w := httptest.NewRecorder()
	h.Login(w, req)

	var resp map[string]any
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode: %v", err)
	}

	// Must have "error" key with code/message/details.
	errObj, ok := resp["error"].(map[string]any)
	if !ok {
		t.Fatalf("missing error key in: %v", resp)
	}
	for _, field := range []string{"code", "message", "details"} {
		if _, exists := errObj[field]; !exists {
			t.Errorf("error envelope missing field: %s", field)
		}
	}
	// Must NOT have "data" key alongside "error".
	if _, exists := resp["data"]; exists {
		t.Error("error envelope must not have 'data' key")
	}
}
