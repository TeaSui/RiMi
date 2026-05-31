// Package middleware — structured logger with PII masking.
// PII-01: email, phone, tokens are never logged in plaintext.
package middleware

import (
	"log/slog"
	"net/http"
	"strings"
	"time"
)

// MaskEmail replaces an email address with a safe masked form (PII-01).
// Example: user@example.com → us***@***.com; a@b.co → a***@***.co
func MaskEmail(email string) string {
	parts := strings.SplitN(email, "@", 2)
	if len(parts) != 2 {
		return "***"
	}
	local := parts[0]
	if len(local) == 0 {
		local = "***"
	} else if len(local) == 1 {
		local = local + "***"
	} else {
		local = local[:2] + "***"
	}
	domainParts := strings.SplitN(parts[1], ".", 2)
	if len(domainParts) == 2 {
		return local + "@***." + domainParts[1]
	}
	return local + "@***"
}

// MaskPhone masks a phone number for logging (PII-01).
// Example: +84912345678 → +84****5678
func MaskPhone(phone string) string {
	if len(phone) < 6 {
		return "***"
	}
	return phone[:3] + "****" + phone[len(phone)-4:]
}

// requestLogger is a simple structured logging middleware.
// It does NOT log Authorization headers or token values (SECRETS-04/PII-01).
func RequestLogger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rw := &responseWriter{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rw, r)
		slog.Info("request",
			slog.String("method", r.Method),
			// EMAIL-06: tokens must never appear in paths logged; our token
			// consumption routes use POST bodies — log the path safely.
			slog.String("path", r.URL.Path),
			slog.Int("status", rw.status),
			slog.Duration("duration", time.Since(start)),
			slog.String("request_id", r.Header.Get("X-Request-Id")),
		)
	})
}

type responseWriter struct {
	http.ResponseWriter
	status int
}

func (rw *responseWriter) WriteHeader(status int) {
	rw.status = status
	rw.ResponseWriter.WriteHeader(status)
}
