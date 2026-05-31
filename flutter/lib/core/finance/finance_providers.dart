import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/drift/app_database.dart';
import '../auth/auth_notifier.dart';
import '../network/dio_client.dart';
import '../sync/sync_providers.dart';

/// Stream of income entries from local Drift DB for the given workspace,
/// newest-first.
final incomeProvider =
    StreamProvider.family<List<IncomeEntry>, String>((ref, workspaceId) {
  final db = ref.watch(appDatabaseProvider);
  return db.financeDao.watchIncomeByWorkspace(workspaceId);
});

/// Stream of expense entries from local Drift DB for the given workspace,
/// newest-first.
final expensesProvider =
    StreamProvider.family<List<ExpenseEntry>, String>((ref, workspaceId) {
  final db = ref.watch(appDatabaseProvider);
  return db.financeDao.watchExpensesByWorkspace(workspaceId);
});

/// Derived P&L summary for the given workspace computed from cached entries.
///
/// Returns a [PLSummary] with total income, total expenses, and net profit
/// as VND-formatted strings.
final plSummaryProvider =
    Provider.family<PLSummary, String>((ref, workspaceId) {
  final incomeAsync = ref.watch(incomeProvider(workspaceId));
  final expensesAsync = ref.watch(expensesProvider(workspaceId));

  final incomeList =
      incomeAsync.maybeWhen(data: (v) => v, orElse: () => <IncomeEntry>[]);
  final expenseList =
      expensesAsync.maybeWhen(data: (v) => v, orElse: () => <ExpenseEntry>[]);

  final totalIncome = incomeList.fold<int>(
    0,
    (sum, e) => sum + (int.tryParse(e.amount.split('.').first) ?? 0),
  );
  final totalExpense = expenseList.fold<int>(
    0,
    (sum, e) => sum + (int.tryParse(e.amount.split('.').first) ?? 0),
  );
  final netProfit = totalIncome - totalExpense;

  return PLSummary(
    totalIncome: totalIncome,
    totalExpense: totalExpense,
    netProfit: netProfit,
  );
});

/// In-memory P&L summary (not a Drift model — computed from cached data).
class PLSummary {
  const PLSummary({
    required this.totalIncome,
    required this.totalExpense,
    required this.netProfit,
  });

  final int totalIncome; // VND integer
  final int totalExpense; // VND integer
  final int netProfit; // VND integer

  String get formattedIncome => _fmt(totalIncome);
  String get formattedExpense => _fmt(totalExpense);
  String get formattedProfit =>
      '${netProfit >= 0 ? '+' : ''}${_fmt(netProfit)}';

  static String _fmt(int vnd) {
    if (vnd.abs() >= 1000000) {
      final m = (vnd / 1000000).toStringAsFixed(1);
      return '${m}M₫';
    }
    if (vnd.abs() >= 1000) {
      final k = (vnd / 1000).toStringAsFixed(0);
      return '${k}k₫';
    }
    return '$vnd₫';
  }
}

/// Notifier for finance write operations (income and expense creation).
class FinanceNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(appDatabaseProvider);
  Dio get _dio => ref.read(dioClientProvider);

  String get _workspaceId {
    final auth = ref.read(authNotifierProvider);
    return auth.activeWorkspaceId ?? '';
  }

  /// Records an income entry locally and pushes to server best-effort.
  Future<void> createIncome({
    required String amount,
    String? category,
    String? description,
    String? orderId,
  }) async {
    final id = const Uuid().v4();
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    await _db.financeDao.upsertIncome(
      IncomeEntriesCompanion.insert(
        id: id,
        workspaceId: _workspaceId,
        amount: amount,
        category: Value(category),
        description: Value(description),
        orderId: Value(orderId),
        createdAt: nowMs,
        updatedAt: nowMs,
      ),
    );

    try {
      await _dio.post<dynamic>('/v1/finance/income', data: <String, dynamic>{
        'id': id,
        'amount': amount,
        'category': category,
        'description': description,
        'order_id': orderId,
      });
    } on DioException {
      // Offline — local write persisted.
    }
  }

  /// Records an expense entry locally and pushes to server best-effort.
  Future<void> createExpense({
    required String amount,
    String? category,
    String? description,
  }) async {
    final id = const Uuid().v4();
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    await _db.financeDao.upsertExpense(
      ExpenseEntriesCompanion.insert(
        id: id,
        workspaceId: _workspaceId,
        amount: amount,
        category: Value(category),
        description: Value(description),
        createdAt: nowMs,
        updatedAt: nowMs,
      ),
    );

    try {
      await _dio.post<dynamic>('/v1/finance/expenses', data: <String, dynamic>{
        'id': id,
        'amount': amount,
        'category': category,
        'description': description,
      });
    } on DioException {
      // Offline — local write persisted.
    }
  }

  /// Fetches income entries from the server and merges into Drift.
  Future<void> refreshFromServer() async {
    final wsId = _workspaceId;
    if (wsId.isEmpty) return;
    try {
      final incResp =
          await _dio.get<Map<String, dynamic>>('/v1/finance/income');
      final incData = incResp.data?['data'] as Map<String, dynamic>?;
      final incList =
          (incData?['income'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      final incRows = incList.map((e) {
        final createdAtMs = _parseMs(e['created_at'] as String?);
        final updatedAtMs = _parseMs(e['updated_at'] as String?);
        return IncomeEntriesCompanion.insert(
          id: e['id'] as String,
          workspaceId: wsId,
          amount: e['amount'] as String? ?? '0',
          category: Value(e['category'] as String?),
          description: Value(e['description'] as String?),
          orderId: Value(e['order_id'] as String?),
          createdAt: createdAtMs,
          updatedAt: updatedAtMs,
        );
      }).toList();

      if (incRows.isNotEmpty) {
        await _db.financeDao.upsertAllIncome(incRows);
      }

      final expResp =
          await _dio.get<Map<String, dynamic>>('/v1/finance/expenses');
      final expData = expResp.data?['data'] as Map<String, dynamic>?;
      final expList =
          (expData?['expenses'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      final expRows = expList.map((e) {
        final createdAtMs = _parseMs(e['created_at'] as String?);
        final updatedAtMs = _parseMs(e['updated_at'] as String?);
        return ExpenseEntriesCompanion.insert(
          id: e['id'] as String,
          workspaceId: wsId,
          amount: e['amount'] as String? ?? '0',
          category: Value(e['category'] as String?),
          description: Value(e['description'] as String?),
          createdAt: createdAtMs,
          updatedAt: updatedAtMs,
        );
      }).toList();

      if (expRows.isNotEmpty) {
        await _db.financeDao.upsertAllExpenses(expRows);
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

final financeNotifierProvider =
    AsyncNotifierProvider<FinanceNotifier, void>(FinanceNotifier.new);
