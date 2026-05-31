package sync

import "time"

// Allowed values — enforced before any DB access (SYNC-SEC-04).
var allowedEntityTypes = map[string]bool{"product": true, "inventory_item": true}
var allowedOpTypes = map[string]bool{"create": true, "update": true, "delete": true, "inventory_delta": true}

// Operation represents a single offline operation from the client.
type Operation struct {
	OpID       string         `json:"op_id"`
	EntityType string         `json:"entity_type"`
	EntityID   string         `json:"entity_id"`
	OpType     string         `json:"op_type"`
	Delta      *int           `json:"delta"`
	Payload    map[string]any `json:"payload"`
	ClientTS   int64          `json:"client_ts"`
}

// BatchRequest is the POST /v1/sync/batch request body.
type BatchRequest struct {
	Ops []Operation `json:"ops"`
}

// Result is the per-op outcome returned to the client.
type Result struct {
	OpID            string     `json:"op_id"`
	Status          string     `json:"status"` // "applied", "conflict", "rejected"
	ResolvedValue   *int       `json:"resolved_value,omitempty"`
	ServerUpdatedAt *time.Time `json:"server_updated_at,omitempty"`
	Error           *ErrorBody `json:"error,omitempty"`
}

// ErrorBody carries a structured error inside a Result.
type ErrorBody struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// PullRow is one entity row returned by the pull endpoint.
type PullRow struct {
	ID         string         `json:"id"`
	EntityType string         `json:"entity_type"`
	Payload    map[string]any `json:"payload"`
	UpdatedAt  string         `json:"updated_at"`
	DeletedAt  *string        `json:"deleted_at,omitempty"`
}
