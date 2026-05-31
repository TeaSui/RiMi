// Package finance — database repository for income/expense/receivables/payments.
// All queries use the TenantTx pattern (middleware.TxFromContext).
package finance

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/rimi/server/internal/middleware"
)

// Repository handles finance DB operations.
type Repository struct{}

// NewRepository creates a finance repository.
func NewRepository() *Repository { return &Repository{} }

// ── Income ────────────────────────────────────────────────────────────

// ListIncome returns all income entries for a workspace, most recent first.
func (r *Repository) ListIncome(ctx context.Context, workspaceID string) ([]IncomeEntry, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("finance: no transaction in context")
	}
	rows, err := tx.Query(ctx, `
		SELECT id::text, workspace_id::text, amount::text, category, description,
		       order_id::text, created_at, updated_at
		FROM income_entries
		WHERE workspace_id = $1
		ORDER BY created_at DESC
	`, workspaceID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []IncomeEntry
	for rows.Next() {
		var e IncomeEntry
		if err := rows.Scan(&e.ID, &e.WorkspaceID, &e.Amount, &e.Category,
			&e.Description, &e.OrderID, &e.CreatedAt, &e.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	if out == nil {
		out = []IncomeEntry{}
	}
	return out, rows.Err()
}

// CreateIncome inserts a new income entry.
func (r *Repository) CreateIncome(ctx context.Context, id, workspaceID, amount string, category, description, orderID *string) (*IncomeEntry, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("finance: no transaction in context")
	}
	var e IncomeEntry
	err := tx.QueryRow(ctx, `
		INSERT INTO income_entries (id, workspace_id, amount, category, description, order_id)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id::text, workspace_id::text, amount::text, category, description,
		          order_id::text, created_at, updated_at
	`, id, workspaceID, amount, category, description, orderID).Scan(
		&e.ID, &e.WorkspaceID, &e.Amount, &e.Category,
		&e.Description, &e.OrderID, &e.CreatedAt, &e.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &e, nil
}

// ── Expenses ──────────────────────────────────────────────────────────

// ListExpenses returns all expense entries for a workspace, most recent first.
func (r *Repository) ListExpenses(ctx context.Context, workspaceID string) ([]ExpenseEntry, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("finance: no transaction in context")
	}
	rows, err := tx.Query(ctx, `
		SELECT id::text, workspace_id::text, amount::text, category, description,
		       created_at, updated_at
		FROM expense_entries
		WHERE workspace_id = $1
		ORDER BY created_at DESC
	`, workspaceID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []ExpenseEntry
	for rows.Next() {
		var e ExpenseEntry
		if err := rows.Scan(&e.ID, &e.WorkspaceID, &e.Amount, &e.Category,
			&e.Description, &e.CreatedAt, &e.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	if out == nil {
		out = []ExpenseEntry{}
	}
	return out, rows.Err()
}

// CreateExpense inserts a new expense entry.
func (r *Repository) CreateExpense(ctx context.Context, id, workspaceID, amount string, category, description *string) (*ExpenseEntry, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("finance: no transaction in context")
	}
	var e ExpenseEntry
	err := tx.QueryRow(ctx, `
		INSERT INTO expense_entries (id, workspace_id, amount, category, description)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id::text, workspace_id::text, amount::text, category, description,
		          created_at, updated_at
	`, id, workspaceID, amount, category, description).Scan(
		&e.ID, &e.WorkspaceID, &e.Amount, &e.Category,
		&e.Description, &e.CreatedAt, &e.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &e, nil
}

// ── P&L Summary ────────────────────────────────────────────────────────

// GetPLSummary returns income, expense totals and net for the given period.
// period must be in YYYY-MM format (monthly) or YYYY (annual).
func (r *Repository) GetPLSummary(ctx context.Context, workspaceID, period string) (*PLSummary, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("finance: no transaction in context")
	}

	var incomeTotal, expenseTotal float64

	// Use DATE_TRUNC to filter by month or year.
	trunc := "month"
	if len(period) == 4 {
		trunc = "year"
	}

	err := tx.QueryRow(ctx, `
		SELECT COALESCE(SUM(amount), 0)
		FROM income_entries
		WHERE workspace_id = $1
		  AND DATE_TRUNC($2, created_at) = DATE_TRUNC($2, $3::timestamptz)
	`, workspaceID, trunc, period+"-01").Scan(&incomeTotal)
	if err != nil {
		return nil, err
	}

	err = tx.QueryRow(ctx, `
		SELECT COALESCE(SUM(amount), 0)
		FROM expense_entries
		WHERE workspace_id = $1
		  AND DATE_TRUNC($2, created_at) = DATE_TRUNC($2, $3::timestamptz)
	`, workspaceID, trunc, period+"-01").Scan(&expenseTotal)
	if err != nil {
		return nil, err
	}

	net := incomeTotal - expenseTotal
	return &PLSummary{
		Period:       period,
		TotalIncome:  fmt.Sprintf("%.2f", incomeTotal),
		TotalExpense: fmt.Sprintf("%.2f", expenseTotal),
		NetProfit:    fmt.Sprintf("%.2f", net),
	}, nil
}

// ── Receivables ───────────────────────────────────────────────────────

// ListReceivables returns receivables for a workspace.
func (r *Repository) ListReceivables(ctx context.Context, workspaceID string) ([]Receivable, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("finance: no transaction in context")
	}
	rows, err := tx.Query(ctx, `
		SELECT id::text, workspace_id::text, amount::text, customer_id::text,
		       status, due_date::text, description, created_at, updated_at
		FROM receivables
		WHERE workspace_id = $1
		ORDER BY created_at DESC
	`, workspaceID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []Receivable
	for rows.Next() {
		var rec Receivable
		if err := rows.Scan(&rec.ID, &rec.WorkspaceID, &rec.Amount, &rec.CustomerID,
			&rec.Status, &rec.DueDate, &rec.Description,
			&rec.CreatedAt, &rec.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, rec)
	}
	if out == nil {
		out = []Receivable{}
	}
	return out, rows.Err()
}

// CreateReceivable inserts a new receivable.
func (r *Repository) CreateReceivable(ctx context.Context, id, workspaceID, amount string, customerID, dueDate, description *string) (*Receivable, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("finance: no transaction in context")
	}
	var rec Receivable
	err := tx.QueryRow(ctx, `
		INSERT INTO receivables (id, workspace_id, amount, customer_id, due_date, description, status)
		VALUES ($1, $2, $3, $4, $5, $6, 'open')
		RETURNING id::text, workspace_id::text, amount::text, customer_id::text,
		          status, due_date::text, description, created_at, updated_at
	`, id, workspaceID, amount, customerID, dueDate, description).Scan(
		&rec.ID, &rec.WorkspaceID, &rec.Amount, &rec.CustomerID,
		&rec.Status, &rec.DueDate, &rec.Description,
		&rec.CreatedAt, &rec.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &rec, nil
}

// MarkReceivable updates a receivable's status.
// Returns nil, nil if the receivable does not exist.
func (r *Repository) MarkReceivable(ctx context.Context, id, workspaceID, status string) (*Receivable, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("finance: no transaction in context")
	}
	var rec Receivable
	err := tx.QueryRow(ctx, `
		UPDATE receivables
		SET status = $3
		WHERE id = $1 AND workspace_id = $2
		RETURNING id::text, workspace_id::text, amount::text, customer_id::text,
		          status, due_date::text, description, created_at, updated_at
	`, id, workspaceID, status).Scan(
		&rec.ID, &rec.WorkspaceID, &rec.Amount, &rec.CustomerID,
		&rec.Status, &rec.DueDate, &rec.Description,
		&rec.CreatedAt, &rec.UpdatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &rec, nil
}

// ── Payment Records ───────────────────────────────────────────────────

// ListPayments returns payment records for a workspace.
func (r *Repository) ListPayments(ctx context.Context, workspaceID string) ([]PaymentRecord, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("finance: no transaction in context")
	}
	rows, err := tx.Query(ctx, `
		SELECT id::text, workspace_id::text, amount::text, method,
		       order_id::text, status, note, created_at, updated_at
		FROM payment_records
		WHERE workspace_id = $1
		ORDER BY created_at DESC
	`, workspaceID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []PaymentRecord
	for rows.Next() {
		var p PaymentRecord
		if err := rows.Scan(&p.ID, &p.WorkspaceID, &p.Amount, &p.Method,
			&p.OrderID, &p.Status, &p.Note,
			&p.CreatedAt, &p.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	if out == nil {
		out = []PaymentRecord{}
	}
	return out, rows.Err()
}

// CreatePayment inserts a new payment record.
func (r *Repository) CreatePayment(ctx context.Context, id, workspaceID, amount, method string, orderID, note *string) (*PaymentRecord, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("finance: no transaction in context")
	}
	var p PaymentRecord
	err := tx.QueryRow(ctx, `
		INSERT INTO payment_records (id, workspace_id, amount, method, order_id, note, status)
		VALUES ($1, $2, $3, $4, $5, $6, 'completed')
		RETURNING id::text, workspace_id::text, amount::text, method,
		          order_id::text, status, note, created_at, updated_at
	`, id, workspaceID, amount, method, orderID, note).Scan(
		&p.ID, &p.WorkspaceID, &p.Amount, &p.Method,
		&p.OrderID, &p.Status, &p.Note,
		&p.CreatedAt, &p.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &p, nil
}

// newUUID generates a new UUID string.
func newUUID() string { return uuid.New().String() }
