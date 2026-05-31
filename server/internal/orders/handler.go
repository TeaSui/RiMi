// Package orders — HTTP handlers for order management endpoints.
package orders

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/rimi/server/internal/middleware"
)

// Handler holds order HTTP handlers.
type Handler struct {
	repo *Repository
}

// NewHandler creates an orders handler.
func NewHandler(repo *Repository) *Handler {
	return &Handler{repo: repo}
}

// ListOrders handles GET /v1/orders
func (h *Handler) ListOrders(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	orders, err := h.repo.ListOrders(r.Context(), *claims.WorkspaceID)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusOK, map[string]any{"orders": orders})
}

// GetOrder handles GET /v1/orders/{id}
func (h *Handler) GetOrder(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	orderID := chi.URLParam(r, "id")
	if _, err := uuid.Parse(orderID); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid order ID.", nil)
		return
	}
	order, err := h.repo.GetOrder(r.Context(), orderID, *claims.WorkspaceID)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	if order == nil {
		middleware.WriteError(w, http.StatusNotFound, middleware.ErrWorkspaceNotFound, "Order not found.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusOK, order)
}

// CreateOrder handles POST /v1/orders
func (h *Handler) CreateOrder(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	var req CreateOrderRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid request body.", nil)
		return
	}

	// Validate channel.
	if !validChannels[req.Channel] {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid channel. Must be one of: online, app, phone, walkin.", nil)
		return
	}

	// Validate total_amount is non-empty.
	totalAmount := strings.TrimSpace(req.TotalAmount)
	if totalAmount == "" {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "total_amount is required.", nil)
		return
	}

	// Resolve or generate order ID.
	id := uuid.New().String()
	if req.ID != nil {
		if _, err := uuid.Parse(*req.ID); err != nil {
			middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid order ID.", nil)
			return
		}
		id = *req.ID
	}

	o, err := h.repo.CreateOrder(r.Context(), id, *claims.WorkspaceID, req.Channel, totalAmount, req.CustomerName, req.Note)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusCreated, o)
}

// AdvanceStatus handles PUT /v1/orders/{id}/status
func (h *Handler) AdvanceStatus(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	orderID := chi.URLParam(r, "id")
	if _, err := uuid.Parse(orderID); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid order ID.", nil)
		return
	}
	var req AdvanceStatusRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid request body.", nil)
		return
	}
	if !validStatuses[req.Status] {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid status. Must be one of: new, cooking, ready, delivering, done.", nil)
		return
	}

	o, err := h.repo.AdvanceStatus(r.Context(), orderID, *claims.WorkspaceID, req.Status)
	if errors.Is(err, pgx.ErrNoRows) {
		middleware.WriteError(w, http.StatusNotFound, middleware.ErrWorkspaceNotFound, "Order not found.", nil)
		return
	}
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	if o == nil {
		middleware.WriteError(w, http.StatusNotFound, middleware.ErrWorkspaceNotFound, "Order not found.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusOK, o)
}
