// Package products — types for product catalog and inventory management.
package products

import "time"

// Product is a menu item in a workspace.
type Product struct {
	ID          string     `json:"id"`
	WorkspaceID string     `json:"workspace_id"`
	Name        string     `json:"name"`
	Description *string    `json:"description"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
	DeletedAt   *time.Time `json:"deleted_at,omitempty"`
}

// Variant is a product variant (e.g. size, flavour).
type Variant struct {
	ID          string    `json:"id"`
	WorkspaceID string    `json:"workspace_id"`
	ProductID   string    `json:"product_id"`
	SKU         *string   `json:"sku"`
	Price       string    `json:"price"` // NUMERIC as string to avoid float rounding
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// InventoryItem tracks the stock level of a variant.
type InventoryItem struct {
	ID          string    `json:"id"`
	WorkspaceID string    `json:"workspace_id"`
	VariantID   string    `json:"variant_id"`
	Quantity    int       `json:"quantity"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// CreateProductRequest is the validated body for POST /products.
type CreateProductRequest struct {
	ID          *string `json:"id"`   // client UUID for offline-first
	Name        string  `json:"name"`
	Description *string `json:"description"`
}

// UpdateProductRequest is the validated body for PUT /products/{id}.
type UpdateProductRequest struct {
	Name        *string `json:"name"`
	Description *string `json:"description"`
}

// AdjustInventoryRequest is the validated body for POST /inventory/{id}/adjust.
type AdjustInventoryRequest struct {
	Delta  int    `json:"delta"`
	Reason string `json:"reason"`
}
