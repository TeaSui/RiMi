// Package customers — HTTP handlers for CRM customer management endpoints.
package customers

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/rimi/server/internal/middleware"
)

// Handler holds customer HTTP handlers.
type Handler struct {
	repo *Repository
}

// NewHandler creates a customers handler.
func NewHandler(repo *Repository) *Handler {
	return &Handler{repo: repo}
}

// ListCustomers handles GET /v1/customers
// Optional query param: ?q=<search>
func (h *Handler) ListCustomers(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	search := strings.TrimSpace(r.URL.Query().Get("q"))
	customers, err := h.repo.ListCustomers(r.Context(), *claims.WorkspaceID, search)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusOK, map[string]any{"customers": customers})
}

// GetCustomer handles GET /v1/customers/{id}
func (h *Handler) GetCustomer(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	customerID := chi.URLParam(r, "id")
	if _, err := uuid.Parse(customerID); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid customer ID.", nil)
		return
	}
	detail, err := h.repo.GetCustomer(r.Context(), customerID, *claims.WorkspaceID)
	if err != nil {
		// Log actual DB error server-side only (never send to client — INPUT-06).
		slog.Error("GetCustomer failed", slog.String("error", err.Error()))
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	if detail == nil {
		middleware.WriteError(w, http.StatusNotFound, middleware.ErrWorkspaceNotFound, "Customer not found.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusOK, detail)
}

// CreateCustomer handles POST /v1/customers
func (h *Handler) CreateCustomer(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	var req CreateCustomerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid request body.", nil)
		return
	}

	// At least name or phone is required.
	nameEmpty := req.Name == nil || strings.TrimSpace(*req.Name) == ""
	phoneEmpty := req.Phone == nil || strings.TrimSpace(*req.Phone) == ""
	if nameEmpty && phoneEmpty {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "At least one of name or phone is required.", nil)
		return
	}

	// Validate tier if provided.
	tier := "reg"
	if req.Tier != nil {
		if !validTiers[*req.Tier] {
			middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid tier. Must be one of: reg, gold, vip, risk.", nil)
			return
		}
		tier = *req.Tier
	}

	// Resolve or generate customer ID.
	id := newUUID()
	if req.ID != nil {
		if _, err := uuid.Parse(*req.ID); err != nil {
			middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid customer ID.", nil)
			return
		}
		id = *req.ID
	}

	c, err := h.repo.CreateCustomer(r.Context(), id, *claims.WorkspaceID, req.Name, req.Phone, req.Area, tier)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusCreated, c)
}

// UpdateCustomer handles PATCH /v1/customers/{id}
func (h *Handler) UpdateCustomer(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	customerID := chi.URLParam(r, "id")
	if _, err := uuid.Parse(customerID); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid customer ID.", nil)
		return
	}
	var req UpdateCustomerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid request body.", nil)
		return
	}

	if req.Tier != nil && !validTiers[*req.Tier] {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid tier. Must be one of: reg, gold, vip, risk.", nil)
		return
	}

	c, err := h.repo.UpdateCustomer(r.Context(), customerID, *claims.WorkspaceID, req)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	if c == nil {
		middleware.WriteError(w, http.StatusNotFound, middleware.ErrWorkspaceNotFound, "Customer not found.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusOK, c)
}

// AddNote handles POST /v1/customers/{id}/notes
func (h *Handler) AddNote(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	customerID := chi.URLParam(r, "id")
	if _, err := uuid.Parse(customerID); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid customer ID.", nil)
		return
	}
	var req AddNoteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid request body.", nil)
		return
	}
	if strings.TrimSpace(req.Note) == "" {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "note is required.", nil)
		return
	}

	noteID := newUUID()
	if req.ID != nil {
		if _, err := uuid.Parse(*req.ID); err != nil {
			middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid note ID.", nil)
			return
		}
		noteID = *req.ID
	}

	n, err := h.repo.AddNote(r.Context(), noteID, *claims.WorkspaceID, customerID, req.Note)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusCreated, n)
}
