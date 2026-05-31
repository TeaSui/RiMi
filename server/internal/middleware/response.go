// Package middleware provides HTTP middleware for RiMi.
// This file enforces the mandatory response envelope from patterns.md.
package middleware

import (
	"encoding/json"
	"net/http"
	"time"
)

// SuccessEnvelope wraps a successful payload per patterns.md.
type SuccessEnvelope struct {
	Data any    `json:"data"`
	Meta Meta   `json:"meta"`
}

// Meta is the mandatory metadata included in every response.
type Meta struct {
	Timestamp string `json:"timestamp"`
}

// ErrorEnvelope wraps an error payload per patterns.md.
type ErrorEnvelope struct {
	Error ErrorBody `json:"error"`
}

// ErrorBody is the structured error body.
type ErrorBody struct {
	Code    string        `json:"code"`
	Message string        `json:"message"`
	Details []ErrorDetail `json:"details"`
}

// ErrorDetail describes a single field-level validation error.
type ErrorDetail struct {
	Field string `json:"field"`
	Issue string `json:"issue"`
}

// WriteJSON sends a JSON response with the mandatory envelope.
func WriteJSON(w http.ResponseWriter, status int, data any) {
	env := SuccessEnvelope{
		Data: data,
		Meta: Meta{Timestamp: time.Now().UTC().Format(time.RFC3339)},
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(env) //nolint:errcheck
}

// WriteError sends an error JSON response using the mandatory error envelope.
// The message is caller-controlled and must never include internals (INPUT-06).
func WriteError(w http.ResponseWriter, status int, code, message string, details []ErrorDetail) {
	if details == nil {
		details = []ErrorDetail{}
	}
	env := ErrorEnvelope{
		Error: ErrorBody{
			Code:    code,
			Message: message,
			Details: details,
		},
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(env) //nolint:errcheck
}

// Error codes per the contract error catalog (docs/contracts/README.md §6).
const (
	ErrValidation           = "VALIDATION_ERROR"
	ErrWeakPassword         = "WEAK_PASSWORD"
	ErrUnauthorized         = "UNAUTHORIZED"
	ErrInvalidCredentials   = "INVALID_CREDENTIALS"
	ErrRefreshTokenInvalid  = "REFRESH_TOKEN_INVALID"
	ErrRefreshTokenReused   = "REFRESH_TOKEN_REUSED"
	ErrWorkspaceForbidden   = "WORKSPACE_FORBIDDEN"
	ErrWorkspaceNotFound    = "WORKSPACE_NOT_FOUND"
	ErrTokenInvalidExpired  = "TOKEN_INVALID_OR_EXPIRED"
	ErrWorkspaceIDConflict  = "WORKSPACE_ID_CONFLICT"
	ErrPayloadTooLarge      = "PAYLOAD_TOO_LARGE"
	ErrRateLimited          = "RATE_LIMITED"
	ErrAccountLocked        = "ACCOUNT_LOCKED"
	ErrInternalError        = "INTERNAL_ERROR"
	ErrServiceUnavailable   = "SERVICE_UNAVAILABLE"
)
