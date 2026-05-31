// Package finance — HTTP handlers for income/expense/P&L/receivables/payment endpoints.
package finance

import (
	"encoding/json"
	"net/http"
	"regexp"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/rimi/server/internal/middleware"
)

// periodRE matches YYYY-MM or YYYY.
var periodRE = regexp.MustCompile(`^\d{4}(-\d{2})?$`)

// Handler holds finance HTTP handlers.
type Handler struct {
	repo *Repository
}

// NewHandler creates a finance handler.
func NewHandler(repo *Repository) *Handler {
	return &Handler{repo: repo}
}

// ── Income ────────────────────────────────────────────────────────────

// ListIncome handles GET /v1/finance/income
func (h *Handler) ListIncome(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	entries, err := h.repo.ListIncome(r.Context(), *claims.WorkspaceID)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusOK, map[string]any{"income": entries})
}

// CreateIncome handles POST /v1/finance/income
func (h *Handler) CreateIncome(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	var req CreateIncomeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid request body.", nil)
		return
	}
	if strings.TrimSpace(req.Amount) == "" {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "amount is required.", nil)
		return
	}

	id := newUUID()
	if req.ID != nil {
		if _, err := uuid.Parse(*req.ID); err != nil {
			middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid income ID.", nil)
			return
		}
		id = *req.ID
	}

	e, err := h.repo.CreateIncome(r.Context(), id, *claims.WorkspaceID, req.Amount, req.Category, req.Description, req.OrderID)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusCreated, e)
}

// ── Expenses ──────────────────────────────────────────────────────────

// ListExpenses handles GET /v1/finance/expenses
func (h *Handler) ListExpenses(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	entries, err := h.repo.ListExpenses(r.Context(), *claims.WorkspaceID)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusOK, map[string]any{"expenses": entries})
}

// CreateExpense handles POST /v1/finance/expenses
func (h *Handler) CreateExpense(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	var req CreateExpenseRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid request body.", nil)
		return
	}
	if strings.TrimSpace(req.Amount) == "" {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "amount is required.", nil)
		return
	}

	id := newUUID()
	if req.ID != nil {
		if _, err := uuid.Parse(*req.ID); err != nil {
			middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid expense ID.", nil)
			return
		}
		id = *req.ID
	}

	e, err := h.repo.CreateExpense(r.Context(), id, *claims.WorkspaceID, req.Amount, req.Category, req.Description)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusCreated, e)
}

// ── P&L ───────────────────────────────────────────────────────────────

// GetPL handles GET /v1/finance/pl?period=YYYY-MM
func (h *Handler) GetPL(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	period := strings.TrimSpace(r.URL.Query().Get("period"))
	if !periodRE.MatchString(period) {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid period. Use YYYY-MM or YYYY.", nil)
		return
	}

	summary, err := h.repo.GetPLSummary(r.Context(), *claims.WorkspaceID, period)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusOK, summary)
}

// ── Receivables ───────────────────────────────────────────────────────

// ListReceivables handles GET /v1/finance/receivables
func (h *Handler) ListReceivables(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	recs, err := h.repo.ListReceivables(r.Context(), *claims.WorkspaceID)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusOK, map[string]any{"receivables": recs})
}

// CreateReceivable handles POST /v1/finance/receivables
func (h *Handler) CreateReceivable(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	var req CreateReceivableRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid request body.", nil)
		return
	}
	if strings.TrimSpace(req.Amount) == "" {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "amount is required.", nil)
		return
	}

	id := newUUID()
	if req.ID != nil {
		if _, err := uuid.Parse(*req.ID); err != nil {
			middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid receivable ID.", nil)
			return
		}
		id = *req.ID
	}

	rec, err := h.repo.CreateReceivable(r.Context(), id, *claims.WorkspaceID, req.Amount, req.CustomerID, req.DueDate, req.Description)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusCreated, rec)
}

// MarkReceivable handles PUT /v1/finance/receivables/{id}/status
func (h *Handler) MarkReceivable(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	recID := chi.URLParam(r, "id")
	if _, err := uuid.Parse(recID); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid receivable ID.", nil)
		return
	}
	var req MarkReceivablePaidRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid request body.", nil)
		return
	}
	if !validReceivableStatuses[req.Status] {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid status. Must be one of: paid, written_off.", nil)
		return
	}

	rec, err := h.repo.MarkReceivable(r.Context(), recID, *claims.WorkspaceID, req.Status)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	if rec == nil {
		middleware.WriteError(w, http.StatusNotFound, middleware.ErrWorkspaceNotFound, "Receivable not found.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusOK, rec)
}

// ── Payments ──────────────────────────────────────────────────────────

// ListPayments handles GET /v1/finance/payments
func (h *Handler) ListPayments(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	payments, err := h.repo.ListPayments(r.Context(), *claims.WorkspaceID)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusOK, map[string]any{"payments": payments})
}

// CreatePayment handles POST /v1/finance/payments
func (h *Handler) CreatePayment(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}
	var req CreatePaymentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid request body.", nil)
		return
	}
	if strings.TrimSpace(req.Amount) == "" {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "amount is required.", nil)
		return
	}
	if !validMethods[req.Method] {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid method. Must be one of: cash, momo, zalopay, vnpay, bank.", nil)
		return
	}

	id := newUUID()
	if req.ID != nil {
		if _, err := uuid.Parse(*req.ID); err != nil {
			middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid payment ID.", nil)
			return
		}
		id = *req.ID
	}

	p, err := h.repo.CreatePayment(r.Context(), id, *claims.WorkspaceID, req.Amount, req.Method, req.OrderID, req.Note)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong.", nil)
		return
	}
	middleware.WriteJSON(w, http.StatusCreated, p)
}
