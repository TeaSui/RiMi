// Package einvoice — types for hóa đơn điện tử (NĐ 123/2020/NĐ-CP) management.
package einvoice

import "time"

// Invoice is an e-invoice record in a workspace.
type Invoice struct {
	ID            string     `json:"id"`
	WorkspaceID   string     `json:"workspace_id"`
	OrderID       *string    `json:"order_id"`
	Status        string     `json:"status"` // draft | issued | cancelled | replaced
	Provider      *string    `json:"provider"`
	InvoiceNumber *string    `json:"invoice_number"`
	BuyerName     *string    `json:"buyer_name"`
	BuyerTaxCode  *string    `json:"buyer_tax_code"`
	BuyerAddress  *string    `json:"buyer_address"`
	BuyerEmail    *string    `json:"buyer_email"`
	TotalAmount   *string    `json:"total_amount"` // NUMERIC as string
	TaxAmount     *string    `json:"tax_amount"`   // NUMERIC as string
	MaTraCuu      *string    `json:"ma_tra_cuu"`   // provider lookup code
	IssuedAt      *time.Time `json:"issued_at"`
	CreatedAt     time.Time  `json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
}

// InvoiceLineItem is a single line in an e-invoice.
type InvoiceLineItem struct {
	ID          string    `json:"id"`
	WorkspaceID string    `json:"workspace_id"`
	InvoiceID   string    `json:"invoice_id"`
	Description *string   `json:"description"`
	Quantity    int       `json:"quantity"`
	UnitPrice   *string   `json:"unit_price"` // NUMERIC as string
	VATRate     string    `json:"vat_rate"`   // NUMERIC as string, e.g. "0.10"
	CreatedAt   time.Time `json:"created_at"`
}

// InvoiceDetail bundles an invoice with its line items.
type InvoiceDetail struct {
	Invoice
	Items []InvoiceLineItem `json:"items"`
}

// CreateInvoiceRequest is the validated body for POST /v1/einvoices.
type CreateInvoiceRequest struct {
	ID           *string           `json:"id"` // client UUID for offline-first
	OrderID      *string           `json:"order_id"`
	Provider     *string           `json:"provider"`     // viettel_s | misa
	BuyerName    *string           `json:"buyer_name"`
	BuyerTaxCode *string           `json:"buyer_tax_code"`
	BuyerAddress *string           `json:"buyer_address"`
	BuyerEmail   *string           `json:"buyer_email"`
	TotalAmount  *string           `json:"total_amount"`
	TaxAmount    *string           `json:"tax_amount"`
	Items        []CreateItemInput `json:"items"`
}

// CreateItemInput is a single line item in a CreateInvoiceRequest.
type CreateItemInput struct {
	ID          *string  `json:"id"`
	Description *string  `json:"description"`
	Quantity    int      `json:"quantity"`
	UnitPrice   *string  `json:"unit_price"`
	VATRate     *float64 `json:"vat_rate"` // e.g. 0.10 for 10%
}

// UpdateInvoiceStatusRequest is the body for PUT /v1/einvoices/{id}/status.
type UpdateInvoiceStatusRequest struct {
	Status    string  `json:"status"`     // issued | cancelled
	MaTraCuu  *string `json:"ma_tra_cuu"` // required when status=issued
}

// validStatuses for invoice status transitions.
var validIssueStatuses = map[string]bool{
	"issued":    true,
	"cancelled": true,
}

// validProviders is the allowed set of e-invoice providers.
var validProviders = map[string]bool{
	"viettel_s": true,
	"misa":      true,
}
