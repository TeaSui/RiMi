// Package workspace — HTTP handlers for workspace endpoints (AUTH-05/06/07).
// TENANCY-05/08: all workspace scoping from JWT claim, never from client inputs.
// AUTH-13: role is server-set, never from request body.
package workspace

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/rimi/server/internal/auth"
	"github.com/rimi/server/internal/middleware"
)

// Handler holds workspace HTTP handlers.
type Handler struct {
	repo    *Repository
	authSvc *auth.Service
}

// NewHandler creates a workspace handler.
func NewHandler(repo *Repository, authSvc *auth.Service) *Handler {
	return &Handler{repo: repo, authSvc: authSvc}
}

// --- POST /workspaces ---

type createWorkspaceRequest struct {
	ID   *string `json:"id"`   // client-supplied UUID (offline-first, optional)
	Name string  `json:"name"`
}

func (h *Handler) CreateWorkspace(w http.ResponseWriter, r *http.Request) {
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

	var req createWorkspaceRequest
	d := json.NewDecoder(r.Body)
	d.DisallowUnknownFields()
	if err := d.Decode(&req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "One or more fields are invalid.", nil)
		return
	}

	// INPUT-03: validate.
	name := strings.TrimSpace(req.Name)
	var details []middleware.ErrorDetail
	if name == "" || len(name) > 120 {
		details = append(details, middleware.ErrorDetail{Field: "name", Issue: "required_or_too_long"})
	}
	var wsID uuid.UUID
	if req.ID != nil {
		var parseErr error
		wsID, parseErr = uuid.Parse(*req.ID)
		if parseErr != nil {
			details = append(details, middleware.ErrorDetail{Field: "id", Issue: "invalid_uuid"})
		}
	} else {
		wsID = uuid.New() // server generates if not client-supplied
	}
	if len(details) > 0 {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "One or more fields are invalid.", details)
		return
	}

	ws, err := h.repo.CreateWorkspace(r.Context(), wsID, name, userID)
	if err != nil {
		if errors.Is(err, ErrConflict) {
			middleware.WriteError(w, http.StatusConflict, middleware.ErrWorkspaceIDConflict, "A workspace with this id already exists.", nil)
			return
		}
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong. Please try again.", nil)
		return
	}

	// Issue a new access token with workspace_id claim (ADR-001, SESSION-08).
	// Refresh token is NOT rotated (ADR-001: workspace switch is access-token-only).
	wsIDStr := ws.ID.String()
	pair, err := h.authSvc.IssueWorkspaceScopedTokenPair(r.Context(), userID, &wsIDStr)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong. Please try again.", nil)
		return
	}

	data := map[string]any{
		"workspace": workspaceToMap(ws, "owner"),
		"tokens":    pair,
	}
	middleware.WriteJSON(w, http.StatusCreated, data)
}

// --- GET /workspaces ---

func (h *Handler) ListWorkspaces(w http.ResponseWriter, r *http.Request) {
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

	// TENANCY-05: scoped to the caller's user_id from the JWT claim.
	memberships, err := h.repo.ListWorkspaces(r.Context(), userID)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong. Please try again.", nil)
		return
	}

	list := make([]map[string]any, 0, len(memberships))
	for _, m := range memberships {
		list = append(list, map[string]any{
			"id":         m.WorkspaceID.String(),
			"name":       m.Name,
			"role":       m.Role,
			"created_at": m.CreatedAt.UTC().Format("2006-01-02T15:04:05Z07:00"),
		})
	}
	middleware.WriteJSON(w, http.StatusOK, map[string]any{"workspaces": list})
}

// --- POST /workspaces/{id}/switch ---

func (h *Handler) SwitchWorkspace(w http.ResponseWriter, r *http.Request) {
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

	// Path parameter: target workspace UUID.
	wsIDStr := chi.URLParam(r, "id")
	wsID, err := uuid.Parse(wsIDStr)
	if err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "One or more fields are invalid.",
			[]middleware.ErrorDetail{{Field: "id", Issue: "invalid_uuid"}})
		return
	}

	// SESSION-08/TENANCY-08: verify the caller is a member of the target workspace.
	// We NEVER read workspace_id from the request body/header for scoping (CLIENT-04).
	role, err := h.repo.IsMember(r.Context(), userID, wsID)
	if err != nil {
		// TENANCY-08: collapse 404 and 403 into WORKSPACE_FORBIDDEN to avoid existence leak.
		middleware.WriteError(w, http.StatusForbidden, middleware.ErrWorkspaceForbidden, "You do not have access to this workspace.", nil)
		return
	}

	// Get workspace details for the response.
	ws, err := h.repo.GetWorkspaceForUser(r.Context(), wsID, userID)
	if err != nil {
		middleware.WriteError(w, http.StatusForbidden, middleware.ErrWorkspaceForbidden, "You do not have access to this workspace.", nil)
		return
	}

	// Issue a new access token with the new workspace_id claim (ADR-001).
	// Refresh token is NOT rotated.
	wsIDStrPtr := wsID.String()
	pair, err := h.authSvc.IssueWorkspaceScopedTokenPair(r.Context(), userID, &wsIDStrPtr)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong. Please try again.", nil)
		return
	}

	data := map[string]any{
		"workspace": workspaceToMap(ws, role),
		"tokens":    pair,
	}
	middleware.WriteJSON(w, http.StatusOK, data)
}

// workspaceToMap converts a workspace to the API response shape.
func workspaceToMap(ws *Workspace, role string) map[string]any {
	return map[string]any{
		"id":         ws.ID.String(),
		"name":       ws.Name,
		"role":       role,
		"created_at": ws.CreatedAt.UTC().Format("2006-01-02T15:04:05Z07:00"),
	}
}
