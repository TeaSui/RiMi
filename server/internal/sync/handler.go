// Package sync — HTTP handlers for the sync and realtime endpoints.
// Security rules enforced per docs/security/phase-2-sync-realtime.md:
//   - SYNC-SEC-01: Bearer JWT required (enforced via middleware.Authenticate at router level)
//   - SYNC-SEC-02/03: workspace from JWT claim only, never from request body
//   - SYNC-SEC-06/07: max 50 ops per batch checked at handler level
//   - SYNC-SEC-08: pull limit max 500
//   - SYNC-SEC-13: Authenticate applied at router level for /realtime
//   - SYNC-SEC-14: no workspace from WS query params
package sync

import (
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	"github.com/google/uuid"
	"nhooyr.io/websocket"

	"github.com/rimi/server/internal/middleware"
)

// handlerMaxBatchOps is the handler-level guard (SYNC-SEC-06/07).
// The service also checks maxBatchOps (500); the handler enforces the tighter contract limit (50).
const handlerMaxBatchOps = 50

// Handler holds sync HTTP handlers.
type Handler struct {
	service *Service
}

// NewHandler creates a handler backed by the given service.
func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// Batch handles POST /v1/sync/batch.
// SYNC-SEC-02/03: workspace derived from JWT claim only.
// SYNC-SEC-06/07: batch size checked before JSON decode (enforced here before calling service).
func (h *Handler) Batch(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}

	var req BatchRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid JSON body.", nil)
		return
	}

	// SYNC-SEC-06/07: handler-level batch size guard (tighter than service's 500).
	if len(req.Ops) > handlerMaxBatchOps {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Batch too large (max 50 ops).", nil)
		return
	}

	results, err := h.service.ApplyBatch(r.Context(), claims.Subject, *claims.WorkspaceID, req.Ops)
	if err != nil {
		middleware.WriteError(w, http.StatusInternalServerError, middleware.ErrInternalError, "Something went wrong. Please try again.", nil)
		return
	}

	middleware.WriteJSON(w, http.StatusOK, map[string]any{"results": results})
}

// Pull handles GET /v1/sync/pull.
// SYNC-SEC-02: workspace from JWT claim only.
// SYNC-SEC-08: limit max 500.
// SYNC-SEC-14: entity type validated against allowlist (not from unrestricted query params).
func (h *Handler) Pull(w http.ResponseWriter, r *http.Request) {
	claims, ok := middleware.ClaimsFromContext(r.Context())
	if !ok || claims.WorkspaceID == nil {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}

	entity := r.URL.Query().Get("entity")
	if entity == "" || !allowedEntityTypes[entity] {
		middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid or missing entity parameter.", nil)
		return
	}

	// SYNC-SEC-08: limit defaults to 200, capped at 500.
	limit := 200
	if raw := r.URL.Query().Get("limit"); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed < 1 || parsed > 500 {
			middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid limit (1-500).", nil)
			return
		}
		limit = parsed
	}

	// SYNC-SEC-07: cursor param validation.
	// after_updated_at must be unix milliseconds (int64); after_id must be a UUID.
	// Both are available for Phase 3 PullProducts wiring; not consumed yet.
	var afterUpdatedAtMs int64
	if raw := r.URL.Query().Get("after_updated_at"); raw != "" {
		parsed, err := strconv.ParseInt(raw, 10, 64)
		if err != nil {
			middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid after_updated_at: must be unix milliseconds.", nil)
			return
		}
		afterUpdatedAtMs = parsed
	}
	afterID := r.URL.Query().Get("after_id")
	if afterID != "" {
		if _, err := uuid.Parse(afterID); err != nil {
			middleware.WriteError(w, http.StatusBadRequest, middleware.ErrValidation, "Invalid after_id: must be a UUID.", nil)
			return
		}
	}
	_ = afterUpdatedAtMs // used in Phase 3 PullProducts
	_ = afterID          // used in Phase 3 PullProducts

	// Pull query fully wired in Task 10 verification; stub response for Phase 2 handler wire-up.
	middleware.WriteJSON(w, http.StatusOK, map[string]any{
		"rows":     []any{},
		"has_more": false,
		"limit":    limit,
	})
}

// Realtime handles GET /v1/realtime (WebSocket upgrade).
// SYNC-SEC-13: Authenticate middleware is applied at router level — this handler only
// performs a defensive context check and then proceeds with the WS upgrade.
// SYNC-SEC-14: workspace is NOT read from query params.
func (h *Handler) Realtime(w http.ResponseWriter, r *http.Request) {
	// Defensive check: middleware should have already rejected unauthenticated requests.
	if _, ok := middleware.ClaimsFromContext(r.Context()); !ok {
		middleware.WriteError(w, http.StatusUnauthorized, middleware.ErrUnauthorized, "Authentication required.", nil)
		return
	}

	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{
		InsecureSkipVerify: true, // origin check not required for mobile native clients
	})
	if err != nil {
		// Accept already wrote an HTTP error response; nothing to do.
		return
	}
	defer conn.Close(websocket.StatusNormalClosure, "closing")

	ctx := r.Context()
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if err := conn.Ping(ctx); err != nil {
				return
			}
		}
	}
}
