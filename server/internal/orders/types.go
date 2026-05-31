// Package orders — types for order management.
package orders

import "time"

// Order represents a customer order in a workspace.
type Order struct {
	ID           string    `json:"id"`
	WorkspaceID  string    `json:"workspace_id"`
	Status       string    `json:"status"`
	Channel      string    `json:"channel"`
	CustomerName *string   `json:"customer_name"`
	Note         *string   `json:"note"`
	TotalAmount  string    `json:"total_amount"` // NUMERIC as string to avoid float rounding
	ItemCount    int       `json:"item_count"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// OrderItem is a single line item within an order.
type OrderItem struct {
	ID          string    `json:"id"`
	WorkspaceID string    `json:"workspace_id"`
	OrderID     string    `json:"order_id"`
	VariantID   string    `json:"variant_id"`
	Qty         int       `json:"qty"`
	UnitPrice   string    `json:"unit_price"` // NUMERIC as string
	CreatedAt   time.Time `json:"created_at"`
}

// OrderDetail is an order with its line items.
type OrderDetail struct {
	Order
	Items []OrderItem `json:"items"`
}

// CreateOrderRequest is the validated body for POST /v1/orders.
type CreateOrderRequest struct {
	ID           *string `json:"id"`           // client UUID for offline-first
	Channel      string  `json:"channel"`      // online | app | phone | walkin
	CustomerName *string `json:"customer_name"`
	Note         *string `json:"note"`
	TotalAmount  string  `json:"total_amount"`
}

// AdvanceStatusRequest is the validated body for PUT /v1/orders/{id}/status.
type AdvanceStatusRequest struct {
	Status string `json:"status"`
}

// validStatuses is the allowed set of order statuses.
var validStatuses = map[string]bool{
	"new":        true,
	"cooking":    true,
	"ready":      true,
	"delivering": true,
	"done":       true,
}

// validChannels is the allowed set of order channels.
var validChannels = map[string]bool{
	"online": true,
	"app":    true,
	"phone":  true,
	"walkin": true,
}
