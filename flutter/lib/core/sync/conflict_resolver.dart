import 'sync_operation.dart';

abstract class ConflictResolver {
  Future<DriftPatch> resolve(SyncOpResult result);
}

class InventoryDeltaResolver implements ConflictResolver {
  @override
  Future<DriftPatch> resolve(SyncOpResult result) async {
    final value = result.resolvedValue;
    if (value == null) {
      throw StateError('inventory_delta result missing resolved_value');
    }
    return DriftPatch(entityType: 'inventory_item', value: value);
  }
}
