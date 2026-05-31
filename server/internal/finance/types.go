// Package finance — types for income/expense recording, receivables, and payment records.
package finance

import "time"

// IncomeEntry records a single income event.
type IncomeEntry struct {
	ID          string    `json:"id"`
	WorkspaceID string    `json:"workspace_id"`
	Amount      string    `json:"amount"` // NUMERIC as string
	Category    *string   `json:"category"`
	Description *string   `json:"description"`
	OrderID     *string   `json:"order_id"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// ExpenseEntry records a single expense event.
type ExpenseEntry struct {
	ID          string    `json:"id"`
	WorkspaceID string    `json:"workspace_id"`
	Amount      string    `json:"amount"` // NUMERIC as string
	Category    *string   `json:"category"`
	Description *string   `json:"description"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// Receivable tracks money owed by a customer.
type Receivable struct {
	ID          string     `json:"id"`
	WorkspaceID string     `json:"workspace_id"`
	Amount      string     `json:"amount"` // NUMERIC as string
	CustomerID  *string    `json:"customer_id"`
	Status      string     `json:"status"` // open | paid | written_off
	DueDate     *string    `json:"due_date"`
	Description *string    `json:"description"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
}

// PaymentRecord records a payment received for an order.
type PaymentRecord struct {
	ID          string    `json:"id"`
	WorkspaceID string    `json:"workspace_id"`
	Amount      string    `json:"amount"` // NUMERIC as string
	Method      string    `json:"method"` // cash | momo | zalopay | vnpay | bank
	OrderID     *string   `json:"order_id"`
	Status      string    `json:"status"` // completed | pending | refunded
	Note        *string   `json:"note"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// PLSummary is the P&L report for a period.
type PLSummary struct {
	Period      string `json:"period"` // YYYY-MM or YYYY
	TotalIncome string `json:"total_income"`
	TotalExpense string `json:"total_expense"`
	NetProfit   string `json:"net_profit"`
}

// CreateIncomeRequest is the validated body for POST /v1/finance/income.
type CreateIncomeRequest struct {
	ID          *string `json:"id"`
	Amount      string  `json:"amount"`
	Category    *string `json:"category"`
	Description *string `json:"description"`
	OrderID     *string `json:"order_id"`
}

// CreateExpenseRequest is the validated body for POST /v1/finance/expenses.
type CreateExpenseRequest struct {
	ID          *string `json:"id"`
	Amount      string  `json:"amount"`
	Category    *string `json:"category"`
	Description *string `json:"description"`
}

// CreateReceivableRequest is the validated body for POST /v1/finance/receivables.
type CreateReceivableRequest struct {
	ID          *string `json:"id"`
	Amount      string  `json:"amount"`
	CustomerID  *string `json:"customer_id"`
	DueDate     *string `json:"due_date"`
	Description *string `json:"description"`
}

// MarkReceivablePaidRequest is the body for PUT /v1/finance/receivables/{id}/paid.
type MarkReceivablePaidRequest struct {
	Status string `json:"status"` // paid | written_off
}

// CreatePaymentRequest is the validated body for POST /v1/finance/payments.
type CreatePaymentRequest struct {
	ID      *string `json:"id"`
	Amount  string  `json:"amount"`
	Method  string  `json:"method"`
	OrderID *string `json:"order_id"`
	Note    *string `json:"note"`
}

// validMethods is the allowed set of payment methods.
var validMethods = map[string]bool{
	"cash":    true,
	"momo":    true,
	"zalopay": true,
	"vnpay":   true,
	"bank":    true,
}

// validReceivableStatuses is the allowed set of receivable statuses for the update endpoint.
var validReceivableStatuses = map[string]bool{
	"paid":        true,
	"written_off": true,
}
