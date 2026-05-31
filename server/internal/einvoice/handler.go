// Package einvoice — HTTP handlers for e-invoice (hóa đơn điện tử) endpoints.
// EINV-01..05: toggle, issue, validate fields, cancel, store ma_tra_cuu.
package einvoice

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/rimi/server/internal/middleware"
)

// Handler holds e-invoice HTTP handlers.
type Handler struct {
	repo *Repository
}

// NewHandler creates an einvoice handler.
func NewHandler(repo *Repository) *Handler {
	return &Handler{repo: repo}
}

// ListInvoices handles GET /v1/einvoices
func (h *Handler) ListInvoices(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	invoices, err := h.repo.ListInvoices(r.Context(), *claims.WorkspaceID)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusOK, map[string]any{"invoices": invoices})
}

// GetInvoice handles GET /v1/einvoices/{id}
func (h *Handler) GetInvoice(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	invoiceID := chi.URLParam(r, "id")
	if _, err := uuid.Parse(invoiceID); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid invoice ID.", nil)
		return
	}
	detail, err := h.repo.GetInvoice(r.Context(), invoiceID, *claims.WorkspaceID)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	if detail == nil {
		middleware.WriteError(w, http.StatusNotFound, middleware.ErrWorkspaceNotFound, "Invoice not found.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusOK, detail)
}

// CreateInvoice handles POST /v1/einvoices
func (h *Handler) CreateInvoice(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	var req CreateInvoiceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid request body.", nil)
		return
	}

	// Validate provider if provided.
	if req.Provider != nil && !validProviders[*req.Provider] {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid provider. Must be one of: viettel_s, misa.", nil)
		return
	}

	// Validate line item quantities.
	for i, item := range req.Items {
		if item.Quantity < 1 {
			middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation,
				"items["+itoa(i)+"]: quantity must be at least 1.", nil)
			return
		}
		if item.ID != nil {
			if _, err := uuid.Parse(*item.ID); err != nil {
				middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation,
					"items["+itoa(i)+"]: invalid item ID.", nil)
				return
			}
		}
	}

	id := newUUID()
	if req.ID != nil {
		if _, err := uuid.Parse(*req.ID); err != nil {
			middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid invoice ID.", nil)
			return
		}
		id = *req.ID
	}

	detail, err := h.repo.CreateInvoice(r.Context(), req, id, *claims.WorkspaceID)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusCreated, detail)
}

// UpdateStatus handles PUT /v1/einvoices/{id}/status
func (h *Handler) UpdateStatus(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	invoiceID := chi.URLParam(r, "id")
	if _, err := uuid.Parse(invoiceID); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid invoice ID.", nil)
		return
	}
	var req UpdateInvoiceStatusRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid request body.", nil)
		return
	}
	if !validIssueStatuses[req.Status] {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid status. Must be one of: issued, cancelled.", nil)
		return
	}

	inv, err := h.repo.UpdateInvoiceStatus(r.Context(), invoiceID, *claims.WorkspaceID, req.Status, req.MaTraCuu)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	if inv == nil {
		middleware.WriteError(w, http.StatusNotFound, middleware.ErrWorkspaceNotFound, "Invoice not found.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusOK, inv)
}

// itoa converts an int to string without importing strconv.
func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	buf := make([]byte, 0, 20)
	for n > 0 {
		buf = append([]byte{byte('0' + n%10)}, buf...)
		n /= 10
	}
	if neg {
		buf = append([]byte{'-'}, buf...)
	}
	return string(buf)
}
