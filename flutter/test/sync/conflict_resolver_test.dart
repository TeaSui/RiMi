import 'package:flutter_test/flutter_test.dart';
import 'package:rimi/core/sync/conflict_resolver.dart';
import 'package:rimi/core/sync/sync_operation.dart';

void main() {
  test('inventory resolver returns authoritative quantity update', () async {
    final resolver = InventoryDeltaResolver();
    final result = SyncOpResult(
      opId: 'op-1',
      status: SyncResultStatus.applied,
      resolvedValue: 18,
      serverUpdatedAt: DateTime.utc(2026, 5, 31, 12),
      error: null,
    );

    final patch = await resolver.resolve(result);

    expect(patch.entityType, 'inventory_item');
    expect(patch.value, 18);
  });

  test('inventory resolver throws when resolvedValue is null', () async {
    final resolver = InventoryDeltaResolver();
    final result = SyncOpResult(
      opId: 'op-2',
      status: SyncResultStatus.rejected,
      resolvedValue: null,
      serverUpdatedAt: null,
      error: const SyncError(code: 'not_found', message: 'item not found'),
    );

    expect(() => resolver.resolve(result), throwsStateError);
  });
}
