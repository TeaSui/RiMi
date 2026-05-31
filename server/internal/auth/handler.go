// Package auth — HTTP handlers for auth endpoints.
// INPUT-03/04: all DTOs validated at the boundary.
// INPUT-05: body size limited by global middleware.
// INPUT-06: no internals in error responses.
// LOG-04: panics recovered by chi Recoverer middleware.
package auth

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/google/uuid"
	"github.com/rimi/server/internal/middleware"
)

// Handler holds auth HTTP handlers.
type Handler struct {
	svc *Service
}

// NewHandler creates a handler backed by the given service.
func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// --- /auth/register ---

type registerRequest struct {
	Email       string  `json:"email"`
	Password    string  `json:"password"`
	DisplayName string  `json:"display_name"`
	Phone       *string `json:"phone"`
}

func (h *Handler) Register(w http.ResponseWriter, r *http.Request) {
	var req registerRequest
	if err := decodeJSON(r, &req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "One or more fields are invalid.", nil)
		return
	}

	// INPUT-03: validate fields.
	var details []middleware.ErrorDetail
	req.Email = strings.TrimSpace(strings.ToLower(req.Email))
	if !isValidEmail(req.Email) {
		details = append(details, middleware.ErrorDetail{Field: "email", Issue: "invalid_format"})
	}
	if len(req.Email) > 254 {
		details = append(details, middleware.ErrorDetail{Field: "email", Issue: "too_long"})
	}
	if len(req.Password) < 8 || len(req.Password) > 256 {
		details = append(details, middleware.ErrorDetail{Field: "password", Issue: "invalid_length"})
	}
	if strings.TrimSpace(req.DisplayName) == "" || len(req.DisplayName) > 120 {
		details = append(details, middleware.ErrorDetail{Field: "display_name", Issue: "required_or_too_long"})
	}
	if req.Phone != nil && len(*req.Phone) > 20 {
		details = append(details, middleware.ErrorDetail{Field: "phone", Issue: "too_long"})
	}
	if len(details) > 0 {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "One or more fields are invalid.", details)
		return
	}

	// INPUT-04: ignore any privileged fields the client might send (email_verified, role, id).
	// Only the allow-listed fields above are used.

	var phone *string
	if req.Phone != nil && *req.Phone != "" {
		p := strings.TrimSpace(*req.Phone)
		phone = &p
	}

	if err := h.svc.Register(r.Context(), req.Email, req.Password, strings.TrimSpace(req.DisplayName), phone); err != nil {
		var ve *ValidationError
		if errors.As(err, &ve) {
			d := []middleware.ErrorDetail{{Field: ve.Field, Issue: ve.Issue}}
			middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "One or more fields are invalid.", d)
			return
		}
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong. Please try again.", nil)
		return
	}

	// AUTH-03: always 202 with registered:true regardless of whether email existed.
	middleware.WriteJSON(w, http.StatusAccepted, map[string]any{"registered": true})
}

// --- /auth/verify-email ---

type verifyEmailRequest struct {
	Token string `json:"token"`
}

func (h *Handler) VerifyEmail(w http.ResponseWriter, r *http.Request) {
	var req verifyEmailRequest
	if err := decodeJSON(r, &req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "One or more fields are invalid.", nil)
		return
	}
	if len(req.Token) < 16 || len(req.Token) > 512 {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "One or more fields are invalid.",
			[]middleware.ErrorDetail{{Field: "token", Issue: "invalid_length"}})
		return
	}

	if err := h.svc.VerifyEmail(r.Context(), req.Token); err != nil {
		if errors.Is(err, ErrTokenInvalidOrExpired) {
			middleware.WriteError(w, http.StatusGone, middleware.ErrTokenInvalidExpired, "This verification link is no longer valid.", nil)
			return
		}
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong. Please try again.", nil)
		return
	}

	middleware.WriteJSON(w, http.StatusOK, map[string]any{"verified": true})
}

// --- /auth/login ---

type loginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

func (h *Handler) Login(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if err := decodeJSON(r, &req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "One or more fields are invalid.", nil)
		return
	}

	// INPUT-03.
	req.Email = strings.TrimSpace(strings.ToLower(req.Email))
	var details []middleware.ErrorDetail
	if !isValidEmail(req.Email) {
		details = append(details, middleware.ErrorDetail{Field: "email", Issue: "invalid_format"})
	}
	if len(req.Password) < 1 || len(req.Password) > 256 {
		details = append(details, middleware.ErrorDetail{Field: "password", Issue: "required"})
	}
	if len(details) > 0 {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "One or more fields are invalid.", details)
		return
	}

	pair, err := h.svc.Login(r.Context(), req.Email, req.Password)
	if err != nil {
		switch {
		case errors.Is(err, ErrInvalidCredentials):
			middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrInvalidCredentials, "Email or password is incorrect.", nil)
		case errors.Is(err, ErrAccountLocked):
			middleware.WriteError(w, http.StatusTooManyRequests, middleware.ErrAccountLocked, "Too many attempts. Please try again later.", nil)
		default:
			middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong. Please try again.", nil)
		}
		return
	}

	middleware.WriteJSON(w, http.StatusOK, pair)
}

// --- /auth/refresh ---

type refreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

func (h *Handler) Refresh(w http.ResponseWriter, r *http.Request) {
	var req refreshRequest
	if err := decodeJSON(r, &req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "One or more fields are invalid.", nil)
		return
	}
	if len(req.RefreshToken) < 16 || len(req.RefreshToken) > 512 {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "One or more fields are invalid.",
			[]middleware.ErrorDetail{{Field: "refresh_token", Issue: "invalid_length"}})
		return
	}

	pair, err := h.svc.Refresh(r.Context(), req.RefreshToken)
	if err != nil {
		switch {
		case errors.Is(err, ErrRefreshTokenReused):
			middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrRefreshTokenReused, "Session expired. Please sign in again.", nil)
		case errors.Is(err, ErrRefreshTokenInvalid):
			middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrRefreshTokenInvalid, "Session expired. Please sign in again.", nil)
		default:
			middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong. Please try again.", nil)
		}
		return
	}

	middleware.WriteJSON(w, http.StatusOK, pair)
}

// --- /auth/logout ---

func (h *Handler) Logout(w http.ResponseWriter, r *http.Request) {
	var req refreshRequest
	if err := decodeJSON(r, &req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "One or more fields are invalid.", nil)
		return
	}
	if len(req.RefreshToken) < 16 || len(req.RefreshToken) > 512 {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "One or more fields are invalid.", nil)
		return
	}

	// Idempotent — always succeeds.
	_ = h.svc.Logout(r.Context(), req.RefreshToken)
	middleware.WriteJSON(w, http.StatusOK, map[string]any{"revoked": true})
}

// --- /auth/password-reset/request ---

type passwordResetRequestBody struct {
	Email string `json:"email"`
}

func (h *Handler) PasswordResetRequest(w http.ResponseWriter, r *http.Request) {
	var req passwordResetRequestBody
	if err := decodeJSON(r, &req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "One or more fields are invalid.", nil)
		return
	}
	req.Email = strings.TrimSpace(strings.ToLower(req.Email))
	if !isValidEmail(req.Email) || len(req.Email) > 254 {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "One or more fields are invalid.",
			[]middleware.ErrorDetail{{Field: "email", Issue: "invalid_format"}})
		return
	}

	// EMAIL-04: anti-enumeration — always return sent:true.
	_ = h.svc.RequestPasswordReset(r.Context(), req.Email)
	middleware.WriteJSON(w, http.StatusOK, map[string]any{"sent": true})
}

// --- /auth/password-reset/confirm ---

type passwordResetConfirmBody struct {
	Token       string `json:"token"`
	NewPassword string `json:"new_password"`
}

func (h *Handler) PasswordResetConfirm(w http.ResponseWriter, r *http.Request) {
	var req passwordResetConfirmBody
	if err := decodeJSON(r, &req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "One or more fields are invalid.", nil)
		return
	}

	var details []middleware.ErrorDetail
	if len(req.Token) < 16 || len(req.Token) > 512 {
		details = append(details, middleware.ErrorDetail{Field: "token", Issue: "invalid_length"})
	}
	if len(req.NewPassword) < 8 || len(req.NewPassword) > 256 {
		details = append(details, middleware.ErrorDetail{Field: "new_password", Issue: "too_short"})
	}
	if len(details) > 0 {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "One or more fields are invalid.", details)
		return
	}

	if err := h.svc.ConfirmPasswordReset(r.Context(), req.Token, req.NewPassword); err != nil {
		var ve *ValidationError
		switch {
		case errors.As(err, &ve):
			d := []middleware.ErrorDetail{{Field: ve.Field, Issue: ve.Issue}}
			middleware.WriteError(w, http.StatusBadRequest, middleware.ErrWeakPassword, "Password does not meet the minimum requirements.", d)
		case errors.Is(err, ErrTokenInvalidOrExpired):
			middleware.WriteError(w, http.StatusGone, middleware.ErrTokenInvalidExpired, "This reset link is no longer valid.", nil)
		default:
			middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong. Please try again.", nil)
		}
		return
	}

	middleware.WriteJSON(w, http.StatusOK, map[string]any{"reset": true})
}

// --- /auth/me ---

func (h *Handler) Me(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}

	userID, err := uuid.Parse(claims.Subject)
	if err != nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}

	profile, err := h.svc.GetMe(r.Context(), userID)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong. Please try again.", nil)
		return
	}

	// TENANCY-05: active workspace derived from the validated JWT claim (ADR-001).
	data := map[string]any{
		"profile":             profileToMap(profile),
		"active_workspace_id": claims.WorkspaceID,
	}
	middleware.WriteJSON(w, http.StatusOK, data)
}

// --- Helpers ---

func decodeJSON(r *http.Request, dst any) error {
	d := json.NewDecoder(r.Body)
	d.DisallowUnknownFields()
	return d.Decode(dst)
}

func isValidEmail(email string) bool {
	if email == "" {
		return false
	}
	at := strings.Index(email, "@")
	if at < 1 || at == len(email)-1 {
		return false
	}
	dot := strings.LastIndex(email[at:], ".")
	return dot > 1
}

func profileToMap(p *Profile) map[string]any {
	return map[string]any{
		"id":             p.ID.String(),
		"email":          p.Email,
		"display_name":   p.DisplayName,
		"phone":          p.Phone,
		"email_verified": p.EmailVerified,
		"created_at":     p.CreatedAt.UTC().Format("2006-01-02T15:04:05Z07:00"),
	}
}
