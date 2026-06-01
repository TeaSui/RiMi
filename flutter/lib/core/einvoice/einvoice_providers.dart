import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/drift/app_database.dart';
import '../auth/auth_notifier.dart';
import '../network/dio_client.dart';
import '../sync/sync_providers.dart';

/// Stream of invoices from local Drift DB for the given workspace,
/// newest-first.
final invoicesProvider =
    StreamProvider.family<List<Invoice>, String>((ref, workspaceId) {
  final db = ref.watch(appDatabaseProvider);
  return db.einvoiceDao.watchByWorkspace(workspaceId);
});

/// Notifier for e-invoice CRUD operations.
class EinvoiceNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(appDatabaseProvider);
  Dio get _dio => ref.read(dioClientProvider);

  String get _workspaceId {
    final auth = ref.read(authNotifierProvider);
    return auth.activeWorkspaceId ?? '';
  }

  /// Creates a draft invoice locally and pushes to the server best-effort.
  Future<void> createInvoice({
    String? orderId,
    String? provider,
    String? buyerName,
    String? buyerTaxCode,
    String? totalAmount,
    String? taxAmount,
  }) async {
    final id = const Uuid().v4();
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    await _db.einvoiceDao.upsert(
      InvoicesCompanion.insert(
        id: id,
        workspaceId: _workspaceId,
        orderId: Value(orderId),
        status: const Value('draft'),
        provider: Value(provider),
        buyerName: Value(buyerName),
        buyerTaxCode: Value(buyerTaxCode),
        totalAmount: Value(totalAmount),
        taxAmount: Value(taxAmount),
        createdAt: nowMs,
        updatedAt: nowMs,
      ),
    );

    try {
      await _dio.post<dynamic>('/einvoices', data: <String, dynamic>{
        'id': id,
        'order_id': orderId,
        'provider': provider,
        'buyer_name': buyerName,
        'buyer_tax_code': buyerTaxCode,
        'total_amount': totalAmount,
        'tax_amount': taxAmount,
      });
    } on DioException {
      // Offline — local write persisted.
    }
  }

  /// Fetches invoices from the server and merges into Drift.
  Future<void> refreshFromServer() async {
    final wsId = _workspaceId;
    if (wsId.isEmpty) return;
    try {
      final resp =
          await _dio.get<Map<String, dynamic>>('/einvoices');
      final data = resp.data?['data'] as Map<String, dynamic>?;
      final list =
          (data?['invoices'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      final rows = list.map((inv) {
        final createdAtMs = _parseMs(inv['created_at'] as String?);
        final updatedAtMs = _parseMs(inv['updated_at'] as String?);
        final issuedAtMs = inv['issued_at'] != null
            ? _parseMs(inv['issued_at'] as String?)
            : null;
        return InvoicesCompanion.insert(
          id: inv['id'] as String,
          workspaceId: wsId,
          orderId: Value(inv['order_id'] as String?),
          status: Value((inv['status'] as String?) ?? 'draft'),
          provider: Value(inv['provider'] as String?),
          invoiceNumber: Value(inv['invoice_number'] as String?),
          buyerName: Value(inv['buyer_name'] as String?),
          buyerTaxCode: Value(inv['buyer_tax_code'] as String?),
          totalAmount: Value(inv['total_amount'] as String?),
          taxAmount: Value(inv['tax_amount'] as String?),
          maTraCuu: Value(inv['ma_tra_cuu'] as String?),
          issuedAt: Value(issuedAtMs),
          createdAt: createdAtMs,
          updatedAt: updatedAtMs,
        );
      }).toList();

      if (rows.isNotEmpty) {
        await _db.einvoiceDao.upsertAll(rows);
      }
    } on DioException {
      // Offline — use cached data.
    }
  }

  static int _parseMs(String? iso) {
    if (iso == null || iso.isEmpty) return 0;
    return DateTime.tryParse(iso)?.millisecondsSinceEpoch ?? 0;
  }
}

final einvoiceNotifierProvider =
    AsyncNotifierProvider<EinvoiceNotifier, void>(EinvoiceNotifier.new);
