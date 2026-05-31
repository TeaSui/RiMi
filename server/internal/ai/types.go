// Package ai — types for AI usage logging and content generation.
package ai

import "time"

// UsageRecord logs a single AI API call.
type UsageRecord struct {
	ID          string    `json:"id"`
	WorkspaceID string    `json:"workspace_id"`
	Model       string    `json:"model"`
	Feature     *string   `json:"feature"`
	TokensIn    int       `json:"tokens_in"`
	TokensOut   int       `json:"tokens_out"`
	CostUSD     *string   `json:"cost_usd"` // NUMERIC as string
	CreatedAt   time.Time `json:"created_at"`
}

// UsageSummary is the monthly AI usage summary per workspace.
type UsageSummary struct {
	Period      string `json:"period"` // YYYY-MM
	TotalCalls  int    `json:"total_calls"`
	TotalTokens int    `json:"total_tokens"`
	TotalCostUSD string `json:"total_cost_usd"`
}

// GenerateRequest is the validated body for POST /v1/ai/generate.
type GenerateRequest struct {
	Feature   string `json:"feature"`   // caption | menu_copy
	ProductID string `json:"product_id"`
	Prompt    string `json:"prompt"`
}

// GenerateResponse wraps the AI-generated content.
type GenerateResponse struct {
	Content   string `json:"content"`
	TokensIn  int    `json:"tokens_in"`
	TokensOut int    `json:"tokens_out"`
	UsageID   string `json:"usage_id"`
}

// LogUsageRequest is the internal body for POST /v1/ai/usage (server-to-server or internal).
type LogUsageRequest struct {
	ID        *string  `json:"id"`
	Model     string   `json:"model"`
	Feature   *string  `json:"feature"`
	TokensIn  int      `json:"tokens_in"`
	TokensOut int      `json:"tokens_out"`
	CostUSD   *float64 `json:"cost_usd"`
}

// validFeatures is the allowed set of AI features.
var validFeatures = map[string]bool{
	"caption":   true,
	"menu_copy": true,
}
