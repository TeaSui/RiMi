// Package orders — database repository for order management.
// All queries use the TenantTx pattern (middleware.TxFromContext) so that RLS GUCs
// are already set by the TenantTx middleware before handlers call these methods.
package orders

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/rimi/server/internal/middleware"
)

// Repository handles order DB operations.
type Repository struct{}

// NewRepository creates an orders repository.
func NewRepository() *Repository { return &Repository{} }

// ListOrders returns all orders in a workspace ordered by created_at DESC,
// with a count of their line items.
func (r *Repository) ListOrders(ctx context.Context, workspaceID string) ([]Order, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("orders: no transaction in context")
	}
	rows, err := tx.Query(ctx, `
		SELECT
			o.id::text,
			o.workspace_id::text,
			o.status,
			o.channel,
			o.customer_name,
			o.note,
			o.total_amount::text,
			COUNT(oi.id) AS item_count,
			o.created_at,
			o.updated_at
		FROM orders o
		LEFT JOIN order_items oi
			ON oi.order_id = o.id AND oi.workspace_id = o.workspace_id
		WHERE o.workspace_id = $1
		GROUP BY o.id, o.workspace_id, o.status, o.channel, o.customer_name,
		         o.note, o.total_amount, o.created_at, o.updated_at
		ORDER BY o.created_at DESC
	`, workspaceID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Order
	for rows.Next() {
		var o Order
		if err := rows.Scan(
			&o.ID, &o.WorkspaceID, &o.Status, &o.Channel,
			&o.CustomerName, &o.Note, &o.TotalAmount, &o.ItemCount,
			&o.CreatedAt, &o.UpdatedAt,
		); err != nil {
			return nil, err
		}
		out = append(out, o)
	}
	if out == nil {
		out = []Order{}
	}
	return out, rows.Err()
}

// GetOrder returns a single order with its line items.
// Returns nil, nil if the order does not exist in the workspace.
func (r *Repository) GetOrder(ctx context.Context, id, workspaceID string) (*OrderDetail, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("orders: no transaction in context")
	}
	var o OrderDetail
	err := tx.QueryRow(ctx, `
		SELECT
			o.id::text,
			o.workspace_id::text,
			o.status,
			o.channel,
			o.customer_name,
			o.note,
			o.total_amount::text,
			o.created_at,
			o.updated_at
		FROM orders o
		WHERE o.id = $1 AND o.workspace_id = $2
	`, id, workspaceID).Scan(
		&o.ID, &o.WorkspaceID, &o.Status, &o.Channel,
		&o.CustomerName, &o.Note, &o.TotalAmount,
		&o.CreatedAt, &o.UpdatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	// Load line items.
	rows, err := tx.Query(ctx, `
		SELECT id::text, workspace_id::text, order_id::text, variant_id::text,
		       qty, unit_price::text, created_at
		FROM order_items
		WHERE order_id = $1 AND workspace_id = $2
		ORDER BY created_at ASC
	`, id, workspaceID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var item OrderItem
		if err := rows.Scan(
			&item.ID, &item.WorkspaceID, &item.OrderID, &item.VariantID,
			&item.Qty, &item.UnitPrice, &item.CreatedAt,
		); err != nil {
			return nil, err
		}
		o.Items = append(o.Items, item)
	}
	if o.Items == nil {
		o.Items = []OrderItem{}
	}
	o.ItemCount = len(o.Items)
	return &o, rows.Err()
}

// CreateOrder inserts a new order and returns the created row.
func (r *Repository) CreateOrder(ctx context.Context, id, workspaceID, channel, totalAmount string, customerName, note *string) (*Order, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("orders: no transaction in context")
	}
	var o Order
	err := tx.QueryRow(ctx, `
		INSERT INTO orders (id, workspace_id, status, channel, customer_name, note, total_amount)
		VALUES ($1, $2, 'new', $3, $4, $5, $6)
		RETURNING id::text, workspace_id::text, status, channel, customer_name, note,
		          total_amount::text, created_at, updated_at
	`, id, workspaceID, channel, customerName, note, totalAmount).Scan(
		&o.ID, &o.WorkspaceID, &o.Status, &o.Channel,
		&o.CustomerName, &o.Note, &o.TotalAmount,
		&o.CreatedAt, &o.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	o.ItemCount = 0
	return &o, nil
}

// AdvanceStatus updates an order's status and inserts an order_status_events row.
// Returns nil, nil if the order does not exist in the workspace.
func (r *Repository) AdvanceStatus(ctx context.Context, id, workspaceID, newStatus string) (*Order, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("orders: no transaction in context")
	}

	var o Order
	var fromStatus string
	// Use a CTE to capture the old status before the UPDATE applies.
	err := tx.QueryRow(ctx, `
		WITH old AS (SELECT status FROM orders WHERE id = $1 AND workspace_id = $2)
		UPDATE orders
		SET status = $3, updated_at = now()
		WHERE id = $1 AND workspace_id = $2
		RETURNING id::text, workspace_id::text, status, channel, customer_name, note,
		          total_amount::text, created_at, updated_at,
		          (SELECT status FROM old)
	`, id, workspaceID, newStatus).Scan(
		&o.ID, &o.WorkspaceID, &o.Status, &o.Channel,
		&o.CustomerName, &o.Note, &o.TotalAmount,
		&o.CreatedAt, &o.UpdatedAt, &fromStatus,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	// Insert status event. The `status` column mirrors `to_status` (required NOT NULL).
	eventID := newUUID()
	_, err = tx.Exec(ctx, `
		INSERT INTO order_status_events (id, workspace_id, order_id, from_status, to_status, status)
		VALUES ($1, $2, $3, $4, $5, $5)
	`, eventID, workspaceID, id, fromStatus, newStatus)
	if err != nil {
		return nil, err
	}

	return &o, nil
}

// newUUID generates a new UUID string.
func newUUID() string { return uuid.New().String() }
