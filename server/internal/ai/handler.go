// Package ai — HTTP handlers for AI usage logging and content generation.
// AI-01/02/03: logs every call, enforces cap, sanitises input.
package ai

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/google/uuid"
	"github.com/rimi/server/internal/middleware"
)

// Handler holds AI HTTP handlers.
type Handler struct {
	repo *Repository
}

// NewHandler creates an AI handler.
func NewHandler(repo *Repository) *Handler {
	return &Handler{repo: repo}
}

// LogUsage handles POST /v1/ai/usage
// Records a completed AI call (called internally by the Generate handler or directly).
func (h *Handler) LogUsage(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	var req LogUsageRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid request body.", nil)
		return
	}
	if strings.TrimSpace(req.Model) == "" {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "model is required.", nil)
		return
	}
	if req.TokensIn < 0 || req.TokensOut < 0 {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "token counts must be non-negative.", nil)
		return
	}

	id := newUUID()
	if req.ID != nil {
		if _, err := uuid.Parse(*req.ID); err != nil {
			middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid usage ID.", nil)
			return
		}
		id = *req.ID
	}

	rec, err := h.repo.LogUsage(r.Context(), id, *claims.WorkspaceID, req.Model, req.Feature, req.TokensIn, req.TokensOut, req.CostUSD)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusCreated, rec)
}

// GetUsageSummary handles GET /v1/ai/usage?period=YYYY-MM
func (h *Handler) GetUsageSummary(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	period := strings.TrimSpace(r.URL.Query().Get("period"))
	if len(period) != 7 || period[4] != '-' {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid period. Use YYYY-MM.", nil)
		return
	}

	summary, err := h.repo.GetUsageSummary(r.Context(), *claims.WorkspaceID, period)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusOK, summary)
}
