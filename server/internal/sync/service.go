package sync

import (
	"context"
	"fmt"
	"sort"
)

// Repository is implemented by PGRepository and fakes in tests.
type Repository interface {
	WithEntityGroupTx(ctx context.Context, userID, workspaceID, entityID string, opIDs []string, fn func(TxRepository) error) error
}

// TxRepository operations within a single entity-group transaction.
type TxRepository interface {
	CachedResult(ctx context.Context, workspaceID, opID string) (*Result, error)
	ApplyInventoryDelta(ctx context.Context, workspaceID, entityID string, delta int) (int, error)
	InsertResult(ctx context.Context, workspaceID string, result Result) error
}

// Service owns the sync batch application logic.
type Service struct {
	repo Repository
}

// NewService constructs a Service with the given repository.
func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

// ApplyBatch groups ops by entityID, acquires sorted advisory locks, and applies
// fresh deltas atomically per group. Cached ops return their ledger result unchanged.
func (s *Service) ApplyBatch(ctx context.Context, userID, workspaceID string, ops []Operation) ([]Result, error) {
	// Group by entityID — Phase 2 only handles inventory_delta.
	groups := map[string][]Operation{}
	for _, op := range ops {
		groups[op.EntityID] = append(groups[op.EntityID], op)
	}

	// Process entity groups in sorted order to avoid cross-group deadlocks.
	entityIDs := make([]string, 0, len(groups))
	for eid := range groups {
		entityIDs = append(entityIDs, eid)
	}
	sort.Strings(entityIDs)

	results := make([]Result, 0, len(ops))

	for _, entityID := range entityIDs {
		group := groups[entityID]

		// Sort op IDs before acquiring locks (SYNC-SEC-09).
		opIDs := make([]string, 0, len(group))
		for _, op := range group {
			opIDs = append(opIDs, op.OpID)
		}
		sort.Strings(opIDs)

		err := s.repo.WithEntityGroupTx(ctx, userID, workspaceID, entityID, opIDs, func(tx TxRepository) error {
			fresh := make([]Operation, 0, len(group))
			for _, op := range group {
				cached, err := tx.CachedResult(ctx, workspaceID, op.OpID)
				if err != nil {
					return err
				}
				if cached != nil {
					results = append(results, *cached)
					continue
				}
				fresh = append(fresh, op)
			}
			if len(fresh) == 0 {
				return nil
			}

			sum := 0
			for _, op := range fresh {
				if op.Delta == nil {
					return fmt.Errorf("inventory_delta op %s missing delta", op.OpID)
				}
				sum += *op.Delta
			}

			resolved, err := tx.ApplyInventoryDelta(ctx, workspaceID, entityID, sum)
			if err != nil {
				return err
			}

			for _, op := range fresh {
				r := Result{OpID: op.OpID, Status: "applied", ResolvedValue: &resolved}
				if err := tx.InsertResult(ctx, workspaceID, r); err != nil {
					return err
				}
				results = append(results, r)
			}
			return nil
		})
		if err != nil {
			return nil, err
		}
	}
	return results, nil
}
