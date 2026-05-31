// Package products — database repository for product catalog and inventory.
// All queries use the TenantTx pattern (middleware.TxFromContext) so that RLS GUCs
// are already set by the TenantTx middleware before handlers call these methods.
package products

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/rimi/server/internal/middleware"
)

// Repository handles product and inventory DB operations.
type Repository struct{}

// NewRepository creates a product repository.
func NewRepository() *Repository { return &Repository{} }

// ListProducts returns all non-deleted products in a workspace ordered by created_at DESC.
func (r *Repository) ListProducts(ctx context.Context, workspaceID string) ([]Product, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("products: no transaction in context")
	}
	rows, err := tx.Query(ctx, `
		SELECT id::text, workspace_id::text, name, description, created_at, updated_at, deleted_at
		FROM products
		WHERE workspace_id = $1 AND deleted_at IS NULL
		ORDER BY created_at DESC
	`, workspaceID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Product
	for rows.Next() {
		var p Product
		if err := rows.Scan(&p.ID, &p.WorkspaceID, &p.Name, &p.Description,
			&p.CreatedAt, &p.UpdatedAt, &p.DeletedAt); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	if out == nil {
		out = []Product{}
	}
	return out, rows.Err()
}

// CreateProduct inserts a new product and returns the created row.
func (r *Repository) CreateProduct(ctx context.Context, id, workspaceID, name string, description *string) (*Product, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("products: no transaction in context")
	}
	var p Product
	err := tx.QueryRow(ctx, `
		INSERT INTO products (id, workspace_id, name, description)
		VALUES ($1, $2, $3, $4)
		RETURNING id::text, workspace_id::text, name, description, created_at, updated_at, deleted_at
	`, id, workspaceID, name, description).Scan(
		&p.ID, &p.WorkspaceID, &p.Name, &p.Description,
		&p.CreatedAt, &p.UpdatedAt, &p.DeletedAt,
	)
	if err != nil {
		return nil, err
	}
	return &p, nil
}

// UpdateProduct updates name/description of a non-deleted product.
// Returns nil, nil if the product does not exist or is deleted.
func (r *Repository) UpdateProduct(ctx context.Context, id, workspaceID string, name *string, description *string) (*Product, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("products: no transaction in context")
	}
	var p Product
	err := tx.QueryRow(ctx, `
		UPDATE products
		SET name        = COALESCE($3, name),
		    description = COALESCE($4, description)
		WHERE id = $1 AND workspace_id = $2 AND deleted_at IS NULL
		RETURNING id::text, workspace_id::text, name, description, created_at, updated_at, deleted_at
	`, id, workspaceID, name, description).Scan(
		&p.ID, &p.WorkspaceID, &p.Name, &p.Description,
		&p.CreatedAt, &p.UpdatedAt, &p.DeletedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	return &p, err
}

// DeleteProduct soft-deletes a product by setting deleted_at = now().
// Returns pgx.ErrNoRows if the product does not exist or is already deleted.
func (r *Repository) DeleteProduct(ctx context.Context, id, workspaceID string) error {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return fmt.Errorf("products: no transaction in context")
	}
	cmd, err := tx.Exec(ctx, `
		UPDATE products SET deleted_at = now()
		WHERE id = $1 AND workspace_id = $2 AND deleted_at IS NULL
	`, id, workspaceID)
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		return pgx.ErrNoRows
	}
	return nil
}

// ListInventory returns all inventory items in a workspace ordered by updated_at DESC.
func (r *Repository) ListInventory(ctx context.Context, workspaceID string) ([]InventoryItem, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("products: no transaction in context")
	}
	rows, err := tx.Query(ctx, `
		SELECT id::text, workspace_id::text, variant_id::text, quantity, updated_at
		FROM inventory_items
		WHERE workspace_id = $1
		ORDER BY updated_at DESC
	`, workspaceID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []InventoryItem
	for rows.Next() {
		var item InventoryItem
		if err := rows.Scan(&item.ID, &item.WorkspaceID, &item.VariantID,
			&item.Quantity, &item.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, item)
	}
	if out == nil {
		out = []InventoryItem{}
	}
	return out, rows.Err()
}

// AdjustInventory inserts an adjustment record and updates the item quantity atomically.
// Returns nil, nil if the inventory item does not exist.
func (r *Repository) AdjustInventory(ctx context.Context, itemID, workspaceID string, delta int, reason string) (*InventoryItem, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("products: no transaction in context")
	}
	adjID := newUUID()
	_, err := tx.Exec(ctx, `
		INSERT INTO inventory_adjustments (id, workspace_id, item_id, delta, reason)
		VALUES ($1, $2, $3, $4, $5)
	`, adjID, workspaceID, itemID, delta, reason)
	if err != nil {
		return nil, err
	}
	var item InventoryItem
	err = tx.QueryRow(ctx, `
		UPDATE inventory_items
		SET quantity = quantity + $3
		WHERE id = $1 AND workspace_id = $2
		RETURNING id::text, workspace_id::text, variant_id::text, quantity, updated_at
	`, itemID, workspaceID, delta).Scan(
		&item.ID, &item.WorkspaceID, &item.VariantID,
		&item.Quantity, &item.UpdatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	return &item, err
}

// newUUID generates a new UUID string.
func newUUID() string { return uuid.New().String() }
