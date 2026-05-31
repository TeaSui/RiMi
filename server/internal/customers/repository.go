// Package customers — database repository for CRM customer management.
// All queries use the TenantTx pattern (middleware.TxFromContext) so that
// RLS GUCs are already set by the TenantTx middleware before handlers call these.
package customers

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/rimi/server/internal/middleware"
)

// Repository handles customer DB operations.
type Repository struct{}

// NewRepository creates a customers repository.
func NewRepository() *Repository { return &Repository{} }

// ListCustomers returns all customers in a workspace ordered by name ASC.
// Optional phone search filters results.
func (r *Repository) ListCustomers(ctx context.Context, workspaceID, search string) ([]Customer, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("customers: no transaction in context")
	}

	var rows pgx.Rows
	var err error
	if search == "" {
		rows, err = tx.Query(ctx, `
			SELECT id::text, workspace_id::text, name, phone, tier, area, created_at, updated_at
			FROM customers
			WHERE workspace_id = $1
			ORDER BY name ASC NULLS LAST, created_at DESC
		`, workspaceID)
	} else {
		rows, err = tx.Query(ctx, `
			SELECT id::text, workspace_id::text, name, phone, tier, area, created_at, updated_at
			FROM customers
			WHERE workspace_id = $1
			  AND (
			      name  ILIKE '%' || $2 || '%'
			   OR phone ILIKE '%' || $2 || '%'
			  )
			ORDER BY name ASC NULLS LAST, created_at DESC
		`, workspaceID, search)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []Customer
	for rows.Next() {
		var c Customer
		if err := rows.Scan(&c.ID, &c.WorkspaceID, &c.Name, &c.Phone, &c.Tier, &c.Area,
			&c.CreatedAt, &c.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	if out == nil {
		out = []Customer{}
	}
	return out, rows.Err()
}

// GetCustomer returns a customer with notes and order summary.
// Returns nil, nil if the customer does not exist in the workspace.
func (r *Repository) GetCustomer(ctx context.Context, id, workspaceID string) (*CustomerDetail, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("customers: no transaction in context")
	}

	var c CustomerDetail
	err := tx.QueryRow(ctx, `
		SELECT id::text, workspace_id::text, name, phone, tier, area, created_at, updated_at
		FROM customers
		WHERE id = $1 AND workspace_id = $2
	`, id, workspaceID).Scan(
		&c.ID, &c.WorkspaceID, &c.Name, &c.Phone, &c.Tier, &c.Area,
		&c.CreatedAt, &c.UpdatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	// Load notes.
	noteRows, err := tx.Query(ctx, `
		SELECT id::text, workspace_id::text, customer_id::text, note, created_at, updated_at
		FROM customer_notes
		WHERE customer_id = $1 AND workspace_id = $2
		ORDER BY created_at DESC
	`, id, workspaceID)
	if err != nil {
		return nil, err
	}
	defer noteRows.Close()
	for noteRows.Next() {
		var n CustomerNote
		if err := noteRows.Scan(&n.ID, &n.WorkspaceID, &n.CustomerID,
			&n.Note, &n.CreatedAt, &n.UpdatedAt); err != nil {
			return nil, err
		}
		c.Notes = append(c.Notes, n)
	}
	if err := noteRows.Err(); err != nil {
		return nil, err
	}
	if c.Notes == nil {
		c.Notes = []CustomerNote{}
	}

	// Load order summary.
	err = tx.QueryRow(ctx, `
		SELECT COUNT(*)::int, COALESCE(SUM(total_amount), 0)::text
		FROM orders
		WHERE customer_id = $1 AND workspace_id = $2
	`, id, workspaceID).Scan(&c.OrderCount, &c.TotalSpent)
	if err != nil {
		return nil, err
	}

	return &c, nil
}

// CreateCustomer inserts a new customer and returns the created row.
func (r *Repository) CreateCustomer(ctx context.Context, id, workspaceID string, name, phone, area *string, tier string) (*Customer, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("customers: no transaction in context")
	}

	var c Customer
	err := tx.QueryRow(ctx, `
		INSERT INTO customers (id, workspace_id, name, phone, tier, area)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id::text, workspace_id::text, name, phone, tier, area, created_at, updated_at
	`, id, workspaceID, name, phone, tier, area).Scan(
		&c.ID, &c.WorkspaceID, &c.Name, &c.Phone, &c.Tier, &c.Area,
		&c.CreatedAt, &c.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &c, nil
}

// UpdateCustomer applies a partial update to a customer.
// Returns nil, nil if the customer does not exist in the workspace.
func (r *Repository) UpdateCustomer(ctx context.Context, id, workspaceID string, req UpdateCustomerRequest) (*Customer, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("customers: no transaction in context")
	}

	var c Customer
	err := tx.QueryRow(ctx, `
		UPDATE customers
		SET
			name  = COALESCE($3, name),
			phone = COALESCE($4, phone),
			tier  = COALESCE($5, tier),
			area  = COALESCE($6, area)
		WHERE id = $1 AND workspace_id = $2
		RETURNING id::text, workspace_id::text, name, phone, tier, area, created_at, updated_at
	`, id, workspaceID, req.Name, req.Phone, req.Tier, req.Area).Scan(
		&c.ID, &c.WorkspaceID, &c.Name, &c.Phone, &c.Tier, &c.Area,
		&c.CreatedAt, &c.UpdatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &c, nil
}

// AddNote inserts a new customer note.
func (r *Repository) AddNote(ctx context.Context, id, workspaceID, customerID, note string) (*CustomerNote, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("customers: no transaction in context")
	}

	var n CustomerNote
	err := tx.QueryRow(ctx, `
		INSERT INTO customer_notes (id, workspace_id, customer_id, note)
		VALUES ($1, $2, $3, $4)
		RETURNING id::text, workspace_id::text, customer_id::text, note, created_at, updated_at
	`, id, workspaceID, customerID, note).Scan(
		&n.ID, &n.WorkspaceID, &n.CustomerID, &n.Note, &n.CreatedAt, &n.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &n, nil
}

// newUUID generates a new UUID string.
func newUUID() string { return uuid.New().String() }
