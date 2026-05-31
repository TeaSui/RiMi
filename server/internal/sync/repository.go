package sync

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// PGRepository implements Repository and provides pull query support using Postgres.
type PGRepository struct {
	pool *pgxpool.Pool
}

// NewRepository creates a PGRepository backed by the given connection pool.
func NewRepository(pool *pgxpool.Pool) *PGRepository {
	return &PGRepository{pool: pool}
}

// WithEntityGroupTx opens a transaction, sets tenancy GUCs (TENANCY-06 / SYNC-SEC-15),
// acquires per-op advisory locks in sorted order (SYNC-SEC-09), acquires the entity
// advisory lock (SYNC-SEC-10), and delegates to fn. Commits on success, rolls back on error.
func (r *PGRepository) WithEntityGroupTx(ctx context.Context, userID, workspaceID, entityID string, opIDs []string, fn func(TxRepository) error) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	// Set tenancy GUCs first — required before any RLS-protected statement (TENANCY-06 / SYNC-SEC-15).
	if _, err := tx.Exec(ctx,
		"SELECT set_config('rimi.user_id', $1, true), set_config('rimi.workspace_id', $2, true)",
		userID, workspaceID,
	); err != nil {
		return fmt.Errorf("set tenancy gucs: %w", err)
	}

	// Acquire per-op advisory locks in sorted order (SYNC-SEC-09).
	// Caller (Service.ApplyBatch) guarantees opIDs are already sorted.
	for _, opID := range opIDs {
		if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtext($1))`, workspaceID+":"+opID); err != nil {
			return fmt.Errorf("lock op %s: %w", opID, err)
		}
	}

	// Acquire entity-level advisory lock (workspace-scoped, SYNC-SEC-10).
	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtext($1))`, workspaceID+":"+entityID); err != nil {
		return fmt.Errorf("lock entity: %w", err)
	}

	if err := fn(&pgTxRepository{tx: tx}); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// pgTxRepository wraps a pgx.Tx and implements TxRepository.
type pgTxRepository struct {
	tx pgx.Tx
}

// CachedResult checks sync_applied_ops for a previously applied op result.
// Returns nil, nil if no row found (cache miss).
func (r *pgTxRepository) CachedResult(ctx context.Context, workspaceID, opID string) (*Result, error) {
	var raw []byte
	err := r.tx.QueryRow(ctx,
		`SELECT result FROM sync_applied_ops WHERE workspace_id = $1 AND op_id = $2`,
		workspaceID, opID,
	).Scan(&raw)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var result Result
	if err := json.Unmarshal(raw, &result); err != nil {
		return nil, err
	}
	return &result, nil
}

// ApplyInventoryDelta atomically increments inventory quantity and returns the new value.
func (r *pgTxRepository) ApplyInventoryDelta(ctx context.Context, workspaceID, entityID string, delta int) (int, error) {
	var quantity int
	err := r.tx.QueryRow(ctx, `
		UPDATE inventory_items
		SET quantity = quantity + $3
		WHERE workspace_id = $1 AND id = $2
		RETURNING quantity
	`, workspaceID, entityID, delta).Scan(&quantity)
	if err != nil {
		return 0, err
	}
	return quantity, nil
}

// InsertResult persists an op result in sync_applied_ops for idempotency (SYNC-SEC-11).
func (r *pgTxRepository) InsertResult(ctx context.Context, workspaceID string, result Result) error {
	raw, err := json.Marshal(result)
	if err != nil {
		return err
	}
	_, err = r.tx.Exec(ctx,
		`INSERT INTO sync_applied_ops (workspace_id, op_id, result) VALUES ($1, $2, $3)`,
		workspaceID, result.OpID, raw,
	)
	return err
}

// PullProducts returns product rows changed since the composite cursor (afterUpdatedAtMs, afterID).
// Workspace is derived from the transaction's rimi.workspace_id GUC (already set by callers).
// Results are ordered by (updated_at ASC, id ASC) for stable pagination.
func (r *PGRepository) PullProducts(ctx context.Context, tx pgx.Tx, workspaceID string, afterUpdatedAtMs int64, afterID string, limit int) ([]PullRow, error) {
	rows, err := tx.Query(ctx, `
		SELECT id::text, name, description, updated_at::text, deleted_at::text
		FROM products
		WHERE workspace_id = $1
		  AND (updated_at > to_timestamp($2::double precision / 1000.0)
		    OR (updated_at = to_timestamp($2::double precision / 1000.0) AND id::text > $3))
		ORDER BY updated_at ASC, id ASC
		LIMIT $4
	`, workspaceID, afterUpdatedAtMs, afterID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []PullRow
	for rows.Next() {
		var id, name, updatedAt string
		var description, deletedAt *string
		if err := rows.Scan(&id, &name, &description, &updatedAt, &deletedAt); err != nil {
			return nil, err
		}
		out = append(out, PullRow{
			ID:         id,
			EntityType: "product",
			Payload:    map[string]any{"id": id, "name": name, "description": description},
			UpdatedAt:  updatedAt,
			DeletedAt:  deletedAt,
		})
	}
	return out, rows.Err()
}
