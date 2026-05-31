// Package einvoice — database repository for e-invoice management.
// All queries use the TenantTx pattern (middleware.TxFromContext).
package einvoice

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/rimi/server/internal/middleware"
)

// Repository handles e-invoice DB operations.
type Repository struct{}

// NewRepository creates an einvoice repository.
func NewRepository() *Repository { return &Repository{} }

// ListInvoices returns all e-invoices for a workspace, most recent first.
func (r *Repository) ListInvoices(ctx context.Context, workspaceID string) ([]Invoice, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("einvoice: no transaction in context")
	}
	rows, err := tx.Query(ctx, `
		SELECT id::text, workspace_id::text, order_id::text, status, provider,
		       invoice_number, buyer_name, buyer_tax_code, buyer_address, buyer_email,
		       total_amount::text, tax_amount::text, ma_tra_cuu,
		       issued_at, created_at, updated_at
		FROM einvoices
		WHERE workspace_id = $1
		ORDER BY created_at DESC
	`, workspaceID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []Invoice
	for rows.Next() {
		var inv Invoice
		if err := rows.Scan(
			&inv.ID, &inv.WorkspaceID, &inv.OrderID, &inv.Status, &inv.Provider,
			&inv.InvoiceNumber, &inv.BuyerName, &inv.BuyerTaxCode, &inv.BuyerAddress, &inv.BuyerEmail,
			&inv.TotalAmount, &inv.TaxAmount, &inv.MaTraCuu,
			&inv.IssuedAt, &inv.CreatedAt, &inv.UpdatedAt,
		); err != nil {
			return nil, err
		}
		out = append(out, inv)
	}
	if out == nil {
		out = []Invoice{}
	}
	return out, rows.Err()
}

// GetInvoice returns a single invoice with its line items.
// Returns nil, nil if the invoice does not exist in the workspace.
func (r *Repository) GetInvoice(ctx context.Context, id, workspaceID string) (*InvoiceDetail, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("einvoice: no transaction in context")
	}

	var inv InvoiceDetail
	err := tx.QueryRow(ctx, `
		SELECT id::text, workspace_id::text, order_id::text, status, provider,
		       invoice_number, buyer_name, buyer_tax_code, buyer_address, buyer_email,
		       total_amount::text, tax_amount::text, ma_tra_cuu,
		       issued_at, created_at, updated_at
		FROM einvoices
		WHERE id = $1 AND workspace_id = $2
	`, id, workspaceID).Scan(
		&inv.ID, &inv.WorkspaceID, &inv.OrderID, &inv.Status, &inv.Provider,
		&inv.InvoiceNumber, &inv.BuyerName, &inv.BuyerTaxCode, &inv.BuyerAddress, &inv.BuyerEmail,
		&inv.TotalAmount, &inv.TaxAmount, &inv.MaTraCuu,
		&inv.IssuedAt, &inv.CreatedAt, &inv.UpdatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	// Load line items.
	rows, err := tx.Query(ctx, `
		SELECT id::text, workspace_id::text, einvoice_id::text, description,
		       quantity, unit_price::text, vat_rate::text, created_at
		FROM einvoice_line_items
		WHERE einvoice_id = $1 AND workspace_id = $2
		ORDER BY created_at ASC
	`, id, workspaceID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var item InvoiceLineItem
		if err := rows.Scan(
			&item.ID, &item.WorkspaceID, &item.InvoiceID, &item.Description,
			&item.Quantity, &item.UnitPrice, &item.VATRate, &item.CreatedAt,
		); err != nil {
			return nil, err
		}
		inv.Items = append(inv.Items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if inv.Items == nil {
		inv.Items = []InvoiceLineItem{}
	}
	return &inv, nil
}

// CreateInvoice inserts a new e-invoice and its line items.
func (r *Repository) CreateInvoice(ctx context.Context, req CreateInvoiceRequest, id, workspaceID string) (*InvoiceDetail, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("einvoice: no transaction in context")
	}

	var inv InvoiceDetail
	err := tx.QueryRow(ctx, `
		INSERT INTO einvoices (
			id, workspace_id, order_id, status, provider,
			buyer_name, buyer_tax_code, buyer_address, buyer_email,
			total_amount, tax_amount
		) VALUES ($1, $2, $3, 'draft', $4, $5, $6, $7, $8, $9, $10)
		RETURNING id::text, workspace_id::text, order_id::text, status, provider,
		          invoice_number, buyer_name, buyer_tax_code, buyer_address, buyer_email,
		          total_amount::text, tax_amount::text, ma_tra_cuu,
		          issued_at, created_at, updated_at
	`, id, workspaceID, req.OrderID, req.Provider,
		req.BuyerName, req.BuyerTaxCode, req.BuyerAddress, req.BuyerEmail,
		req.TotalAmount, req.TaxAmount).Scan(
		&inv.ID, &inv.WorkspaceID, &inv.OrderID, &inv.Status, &inv.Provider,
		&inv.InvoiceNumber, &inv.BuyerName, &inv.BuyerTaxCode, &inv.BuyerAddress, &inv.BuyerEmail,
		&inv.TotalAmount, &inv.TaxAmount, &inv.MaTraCuu,
		&inv.IssuedAt, &inv.CreatedAt, &inv.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}

	// Insert line items.
	for _, item := range req.Items {
		itemID := newUUID()
		if item.ID != nil {
			itemID = *item.ID
		}
		vatRate := 0.10 // default 10%
		if item.VATRate != nil {
			vatRate = *item.VATRate
		}
		var li InvoiceLineItem
		err := tx.QueryRow(ctx, `
			INSERT INTO einvoice_line_items (id, workspace_id, einvoice_id, description, quantity, unit_price, vat_rate)
			VALUES ($1, $2, $3, $4, $5, $6, $7)
			RETURNING id::text, workspace_id::text, einvoice_id::text, description,
			          quantity, unit_price::text, vat_rate::text, created_at
		`, itemID, workspaceID, inv.ID, item.Description, item.Quantity, item.UnitPrice, vatRate).Scan(
			&li.ID, &li.WorkspaceID, &li.InvoiceID, &li.Description,
			&li.Quantity, &li.UnitPrice, &li.VATRate, &li.CreatedAt,
		)
		if err != nil {
			return nil, err
		}
		inv.Items = append(inv.Items, li)
	}
	if inv.Items == nil {
		inv.Items = []InvoiceLineItem{}
	}
	return &inv, nil
}

// UpdateInvoiceStatus transitions an invoice status.
// Returns nil, nil if the invoice does not exist in the workspace.
func (r *Repository) UpdateInvoiceStatus(ctx context.Context, id, workspaceID, status string, maTraCuu *string) (*Invoice, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("einvoice: no transaction in context")
	}

	var issuedAt *string // will be set for issued status
	if status == "issued" {
		now := "now()"
		issuedAt = &now
	}
	_ = issuedAt // used in SQL

	var inv Invoice
	var err error
	if status == "issued" {
		err = tx.QueryRow(ctx, `
			UPDATE einvoices
			SET status = $3, ma_tra_cuu = COALESCE($4, ma_tra_cuu), issued_at = now()
			WHERE id = $1 AND workspace_id = $2
			RETURNING id::text, workspace_id::text, order_id::text, status, provider,
			          invoice_number, buyer_name, buyer_tax_code, buyer_address, buyer_email,
			          total_amount::text, tax_amount::text, ma_tra_cuu,
			          issued_at, created_at, updated_at
		`, id, workspaceID, status, maTraCuu).Scan(
			&inv.ID, &inv.WorkspaceID, &inv.OrderID, &inv.Status, &inv.Provider,
			&inv.InvoiceNumber, &inv.BuyerName, &inv.BuyerTaxCode, &inv.BuyerAddress, &inv.BuyerEmail,
			&inv.TotalAmount, &inv.TaxAmount, &inv.MaTraCuu,
			&inv.IssuedAt, &inv.CreatedAt, &inv.UpdatedAt,
		)
	} else {
		err = tx.QueryRow(ctx, `
			UPDATE einvoices
			SET status = $3
			WHERE id = $1 AND workspace_id = $2
			RETURNING id::text, workspace_id::text, order_id::text, status, provider,
			          invoice_number, buyer_name, buyer_tax_code, buyer_address, buyer_email,
			          total_amount::text, tax_amount::text, ma_tra_cuu,
			          issued_at, created_at, updated_at
		`, id, workspaceID, status).Scan(
			&inv.ID, &inv.WorkspaceID, &inv.OrderID, &inv.Status, &inv.Provider,
			&inv.InvoiceNumber, &inv.BuyerName, &inv.BuyerTaxCode, &inv.BuyerAddress, &inv.BuyerEmail,
			&inv.TotalAmount, &inv.TaxAmount, &inv.MaTraCuu,
			&inv.IssuedAt, &inv.CreatedAt, &inv.UpdatedAt,
		)
	}
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &inv, nil
}

// newUUID generates a new UUID string.
func newUUID() string { return uuid.New().String() }
