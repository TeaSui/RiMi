// Package customers — types for CRM customer management.
package customers

import "time"

// Customer is a CRM customer profile in a workspace.
type Customer struct {
	ID          string     `json:"id"`
	WorkspaceID string     `json:"workspace_id"`
	Name        *string    `json:"name"`
	Phone       *string    `json:"phone"`
	Tier        string     `json:"tier"`
	Area        *string    `json:"area"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
}

// CustomerNote is a free-text note attached to a customer.
type CustomerNote struct {
	ID          string    `json:"id"`
	WorkspaceID string    `json:"workspace_id"`
	CustomerID  string    `json:"customer_id"`
	Note        string    `json:"note"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// CustomerDetail bundles a customer with their notes and order summary.
type CustomerDetail struct {
	Customer
	Notes      []CustomerNote `json:"notes"`
	OrderCount int            `json:"order_count"`
	TotalSpent string         `json:"total_spent"` // NUMERIC as string
}

// CreateCustomerRequest is the validated body for POST /v1/customers.
type CreateCustomerRequest struct {
	ID    *string `json:"id"`    // client UUID for offline-first
	Name  *string `json:"name"`
	Phone *string `json:"phone"`
	Tier  *string `json:"tier"`
	Area  *string `json:"area"`
}

// UpdateCustomerRequest is the validated body for PATCH /v1/customers/{id}.
type UpdateCustomerRequest struct {
	Name  *string `json:"name"`
	Phone *string `json:"phone"`
	Tier  *string `json:"tier"`
	Area  *string `json:"area"`
}

// AddNoteRequest is the validated body for POST /v1/customers/{id}/notes.
type AddNoteRequest struct {
	ID   *string `json:"id"`   // client UUID for offline-first
	Note string  `json:"note"`
}

// validTiers is the allowed set of customer tiers.
var validTiers = map[string]bool{
	"reg":  true,
	"gold": true,
	"vip":  true,
	"risk": true,
}
