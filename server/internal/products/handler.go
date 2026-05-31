// Package products — HTTP handlers for product catalog and inventory endpoints.
package products

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

// Handler holds product and inventory HTTP handlers.
type Handler struct {
	repo *Repository
}

// NewHandler creates a products handler.
func NewHandler(repo *Repository) *Handler {
	return &Handler{repo: repo}
}

// ListProducts handles GET /v1/products
func (h *Handler) ListProducts(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	products, err := h.repo.ListProducts(r.Context(), *claims.WorkspaceID)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusOK, map[string]any{"products": products})
}

// CreateProduct handles POST /v1/products
func (h *Handler) CreateProduct(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	var req CreateProductRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid request body.", nil)
		return
	}
	name := strings.TrimSpace(req.Name)
	if name == "" || len(name) > 200 {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Name is required (max 200 chars).", nil)
		return
	}
	id := uuid.New().String()
	if req.ID != nil {
		if _, err := uuid.Parse(*req.ID); err != nil {
			middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid product ID.", nil)
			return
		}
		id = *req.ID
	}
	p, err := h.repo.CreateProduct(r.Context(), id, *claims.WorkspaceID, name, req.Description)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusCreated, p)
}

// UpdateProduct handles PUT /v1/products/{id}
func (h *Handler) UpdateProduct(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	productID := chi.URLParam(r, "id")
	if _, err := uuid.Parse(productID); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid product ID.", nil)
		return
	}
	var req UpdateProductRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid request body.", nil)
		return
	}
	p, err := h.repo.UpdateProduct(r.Context(), productID, *claims.WorkspaceID, req.Name, req.Description)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	if p == nil {
		middleware.WriteError(w, http.StatusNotFound, middleware.ErrWorkspaceNotFound, "Product not found.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusOK, p)
}

// DeleteProduct handles DELETE /v1/products/{id}
func (h *Handler) DeleteProduct(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	productID := chi.URLParam(r, "id")
	if _, err := uuid.Parse(productID); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid product ID.", nil)
		return
	}
	err := h.repo.DeleteProduct(r.Context(), productID, *claims.WorkspaceID)
	if errors.Is(err, pgx.ErrNoRows) {
		middleware.WriteError(w, http.StatusNotFound, middleware.ErrWorkspaceNotFound, "Product not found.", nil)
		return
	}
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusOK, map[string]any{"deleted": true})
}

// AdjustInventory handles POST /v1/inventory/{id}/adjust
func (h *Handler) AdjustInventory(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	itemID := chi.URLParam(r, "id")
	if _, err := uuid.Parse(itemID); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid item ID.", nil)
		return
	}
	var req AdjustInventoryRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid request body.", nil)
		return
	}
	if req.Delta == 0 {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Delta must be non-zero.", nil)
		return
	}
	item, err := h.repo.AdjustInventory(r.Context(), itemID, *claims.WorkspaceID, req.Delta, req.Reason)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	if item == nil {
		middleware.WriteError(w, http.StatusNotFound, middleware.ErrWorkspaceNotFound, "Inventory item not found.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusOK, item)
}
