enum SyncOpType { create, update, delete, inventoryDelta }

enum SyncResultStatus { applied, conflict, rejected }

class SyncOperationRequest {
  const SyncOperationRequest({
    required this.opId,
    required this.entityType,
    required this.entityId,
    required this.opType,
    required this.clientTs,
    this.payload,
    this.delta,
  });

  final String opId;
  final String entityType;
  final String entityId;
  final SyncOpType opType;
  final int clientTs;
  final Map<String, dynamic>? payload;
  final int? delta;

  Map<String, dynamic> toJson() => {
        'op_id': opId,
        'entity_type': entityType,
        'entity_id': entityId,
        'op_type': switch (opType) {
          SyncOpType.create => 'create',
          SyncOpType.update => 'update',
          SyncOpType.delete => 'delete',
          SyncOpType.inventoryDelta => 'inventory_delta',
        },
        'payload': payload,
        'delta': delta,
        'client_ts': clientTs,
      };
}

class SyncOpResult {
  const SyncOpResult({
    required this.opId,
    required this.status,
    required this.resolvedValue,
    required this.serverUpdatedAt,
    required this.error,
  });

  final String opId;
  final SyncResultStatus status;
  final int? resolvedValue;
  final DateTime? serverUpdatedAt;
  final SyncError? error;

  factory SyncOpResult.fromJson(Map<String, dynamic> json) {
    return SyncOpResult(
      opId: json['op_id'] as String,
      status: switch (json['status'] as String) {
        'applied' => SyncResultStatus.applied,
        'conflict' => SyncResultStatus.conflict,
        'rejected' => SyncResultStatus.rejected,
        final value => throw FormatException('unknown sync status: $value'),
      },
      resolvedValue: json['resolved_value'] as int?,
      serverUpdatedAt: json['server_updated_at'] == null
          ? null
          : DateTime.parse(json['server_updated_at'] as String),
      error: json['error'] == null
          ? null
          : SyncError.fromJson(json['error'] as Map<String, dynamic>),
    );
  }
}

class SyncError {
  const SyncError({required this.code, required this.message});

  final String code;
  final String message;

  factory SyncError.fromJson(Map<String, dynamic> json) {
    return SyncError(
      code: json['code'] as String,
      message: json['message'] as String,
    );
  }
}

class DriftPatch {
  const DriftPatch({required this.entityType, required this.value});

  final String entityType;
  final int value;
}
