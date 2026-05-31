// Package ai — database repository for AI usage logging.
// All queries use the TenantTx pattern (middleware.TxFromContext).
package ai

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"github.com/rimi/server/internal/middleware"
)

// Repository handles AI usage DB operations.
type Repository struct{}

// NewRepository creates an AI repository.
func NewRepository() *Repository { return &Repository{} }

// LogUsage inserts a new AI usage record.
func (r *Repository) LogUsage(ctx context.Context, id, workspaceID, model string, feature *string, tokensIn, tokensOut int, costUSD *float64) (*UsageRecord, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("ai: no transaction in context")
	}

	var rec UsageRecord
	err := tx.QueryRow(ctx, `
		INSERT INTO ai_usage (id, workspace_id, model, feature, tokens_in, tokens_out, cost_usd)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING id::text, workspace_id::text, model, feature,
		          tokens_in, tokens_out, cost_usd::text, created_at
	`, id, workspaceID, model, feature, tokensIn, tokensOut, costUSD).Scan(
		&rec.ID, &rec.WorkspaceID, &rec.Model, &rec.Feature,
		&rec.TokensIn, &rec.TokensOut, &rec.CostUSD, &rec.CreatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &rec, nil
}

// GetUsageSummary returns the monthly AI usage summary for a workspace.
func (r *Repository) GetUsageSummary(ctx context.Context, workspaceID, period string) (*UsageSummary, error) {
	tx, ok := middleware.TxFromContext(ctx)
	if !ok {
		return nil, fmt.Errorf("ai: no transaction in context")
	}

	var totalCalls, totalTokens int
	var totalCostUSD float64

	err := tx.QueryRow(ctx, `
		SELECT
			COUNT(*),
			COALESCE(SUM(tokens_in + tokens_out), 0),
			COALESCE(SUM(cost_usd), 0)
		FROM ai_usage
		WHERE workspace_id = $1
		  AND DATE_TRUNC('month', created_at) = DATE_TRUNC('month', $2::timestamptz)
	`, workspaceID, period+"-01").Scan(&totalCalls, &totalTokens, &totalCostUSD)
	if err != nil {
		return nil, err
	}

	return &UsageSummary{
		Period:       period,
		TotalCalls:   totalCalls,
		TotalTokens:  totalTokens,
		TotalCostUSD: fmt.Sprintf("%.6f", totalCostUSD),
	}, nil
}

// newUUID generates a new UUID string.
func newUUID() string { return uuid.New().String() }
