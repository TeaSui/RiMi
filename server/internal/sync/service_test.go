package sync

import (
	"context"
	"testing"
)

// fakeRepository implements Repository and TxRepository for unit tests.
// It simulates a single entity-group transaction with an in-memory cache and quantity.
type fakeRepository struct {
	// appliedDelta accumulates the total delta applied via ApplyInventoryDelta.
	appliedDelta int
	// baseQuantity is the starting inventory level.
	baseQuantity int
	// cache simulates sync_applied_ops ledger.
	cache map[string]*Result
	// insertOrder records the opIDs passed in sorted order to WithEntityGroupTx.
	insertOrder []string
}

func (r *fakeRepository) WithEntityGroupTx(
	ctx context.Context,
	userID, workspaceID, entityID string,
	opIDs []string,
	fn func(TxRepository) error,
) error {
	// Record sorted opIDs for lock-ordering assertions.
	r.insertOrder = append(r.insertOrder, opIDs...)
	return fn(r)
}

func (r *fakeRepository) CachedResult(ctx context.Context, workspaceID, opID string) (*Result, error) {
	if res, ok := r.cache[opID]; ok {
		return res, nil
	}
	return nil, nil
}

func (r *fakeRepository) ApplyInventoryDelta(ctx context.Context, workspaceID, entityID string, delta int) (int, error) {
	r.appliedDelta += delta
	r.baseQuantity += delta
	return r.baseQuantity, nil
}

func (r *fakeRepository) InsertResult(ctx context.Context, workspaceID string, result Result) error {
	r.cache[result.OpID] = &result
	return nil
}

// newFakeRepo creates a fakeRepository with the given starting quantity.
func newFakeRepo(startQty int) *fakeRepository {
	return &fakeRepository{
		baseQuantity: startQty,
		cache:        map[string]*Result{},
	}
}

// intPtr is a helper to get a pointer to an int literal.
func intPtr(v int) *int { return &v }

func TestApplyBatch_FreshDeltaSummedOnce(t *testing.T) {
	repo := newFakeRepo(10)
	svc := NewService(repo)

	ops := []Operation{
		{OpID: "op-a", EntityType: "inventory_item", EntityID: "entity-1", OpType: "inventory_delta", Delta: intPtr(-3)},
		{OpID: "op-b", EntityType: "inventory_item", EntityID: "entity-1", OpType: "inventory_delta", Delta: intPtr(-2)},
	}

	results, err := svc.ApplyBatch(context.Background(), "user-1", "ws-1", ops)
	if err != nil {
		t.Fatalf("ApplyBatch error: %v", err)
	}

	// Two fresh ops → both applied, delta summed (-3 + -2 = -5 → quantity = 5).
	if len(results) != 2 {
		t.Fatalf("expected 2 results, got %d", len(results))
	}
	for _, r := range results {
		if r.Status != "applied" {
			t.Errorf("op %s: expected status=applied, got %s", r.OpID, r.Status)
		}
		if r.ResolvedValue == nil || *r.ResolvedValue != 5 {
			t.Errorf("op %s: expected resolved_value=5, got %v", r.OpID, r.ResolvedValue)
		}
	}

	// ApplyInventoryDelta called once with combined delta.
	if repo.appliedDelta != -5 {
		t.Errorf("expected appliedDelta=-5, got %d", repo.appliedDelta)
	}
}

func TestApplyBatch_CachedOpsReturnLedgerNotReSummed(t *testing.T) {
	repo := newFakeRepo(10)
	cachedValue := 8
	// Pre-populate cache simulating a prior commit.
	repo.cache["op-replay"] = &Result{OpID: "op-replay", Status: "applied", ResolvedValue: &cachedValue}

	svc := NewService(repo)

	// Submit one cached op and one fresh op in the same entity group.
	ops := []Operation{
		{OpID: "op-replay", EntityType: "inventory_item", EntityID: "entity-1", OpType: "inventory_delta", Delta: intPtr(-2)},
		{OpID: "op-fresh", EntityType: "inventory_item", EntityID: "entity-1", OpType: "inventory_delta", Delta: intPtr(-1)},
	}

	results, err := svc.ApplyBatch(context.Background(), "user-1", "ws-1", ops)
	if err != nil {
		t.Fatalf("ApplyBatch error: %v", err)
	}

	if len(results) != 2 {
		t.Fatalf("expected 2 results, got %d", len(results))
	}

	// Find results by opID.
	resultsByID := map[string]Result{}
	for _, r := range results {
		resultsByID[r.OpID] = r
	}

	// Cached op must return ledger value (8), not re-apply delta.
	cached := resultsByID["op-replay"]
	if cached.ResolvedValue == nil || *cached.ResolvedValue != 8 {
		t.Errorf("cached op: expected resolved_value=8, got %v", cached.ResolvedValue)
	}

	// Only the fresh op's delta was applied: -1 → quantity = 9.
	if repo.appliedDelta != -1 {
		t.Errorf("expected appliedDelta=-1 (only fresh), got %d", repo.appliedDelta)
	}

	fresh := resultsByID["op-fresh"]
	if fresh.ResolvedValue == nil || *fresh.ResolvedValue != 9 {
		t.Errorf("fresh op: expected resolved_value=9, got %v", fresh.ResolvedValue)
	}
}

func TestApplyBatch_OpIDsSortedBeforeLockAcquisition(t *testing.T) {
	repo := newFakeRepo(10)
	svc := NewService(repo)

	// ops in reverse alphabetical order by OpID to verify sort.
	ops := []Operation{
		{OpID: "op-z", EntityType: "inventory_item", EntityID: "entity-1", OpType: "inventory_delta", Delta: intPtr(-1)},
		{OpID: "op-a", EntityType: "inventory_item", EntityID: "entity-1", OpType: "inventory_delta", Delta: intPtr(-1)},
		{OpID: "op-m", EntityType: "inventory_item", EntityID: "entity-1", OpType: "inventory_delta", Delta: intPtr(-1)},
	}

	_, err := svc.ApplyBatch(context.Background(), "user-1", "ws-1", ops)
	if err != nil {
		t.Fatalf("ApplyBatch error: %v", err)
	}

	// insertOrder should be sorted: op-a, op-m, op-z.
	expected := []string{"op-a", "op-m", "op-z"}
	if len(repo.insertOrder) != len(expected) {
		t.Fatalf("expected %d opIDs in insertOrder, got %d", len(expected), len(repo.insertOrder))
	}
	for i, want := range expected {
		if repo.insertOrder[i] != want {
			t.Errorf("insertOrder[%d]: expected %q, got %q", i, want, repo.insertOrder[i])
		}
	}
}

func TestApplyBatch_MultipleEntitiesProcessedInSortedOrder(t *testing.T) {
	repo := newFakeRepo(20)
	svc := NewService(repo)

	// Two entity groups: entity-b and entity-a (submitted in reverse order).
	ops := []Operation{
		{OpID: "op-b1", EntityType: "inventory_item", EntityID: "entity-b", OpType: "inventory_delta", Delta: intPtr(-5)},
		{OpID: "op-a1", EntityType: "inventory_item", EntityID: "entity-a", OpType: "inventory_delta", Delta: intPtr(-3)},
	}

	results, err := svc.ApplyBatch(context.Background(), "user-1", "ws-1", ops)
	if err != nil {
		t.Fatalf("ApplyBatch error: %v", err)
	}

	if len(results) != 2 {
		t.Fatalf("expected 2 results, got %d", len(results))
	}

	// Both deltas applied: -3 then -5 (entity-a before entity-b).
	if repo.appliedDelta != -8 {
		t.Errorf("expected total appliedDelta=-8, got %d", repo.appliedDelta)
	}
}

func TestApplyBatch_EmptyBatchReturnsEmptyResults(t *testing.T) {
	repo := newFakeRepo(10)
	svc := NewService(repo)

	results, err := svc.ApplyBatch(context.Background(), "user-1", "ws-1", []Operation{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(results) != 0 {
		t.Errorf("expected empty results, got %d", len(results))
	}
}
