import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_icons.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/finance/finance_providers.dart';
import '../../data/drift/app_database.dart' as drift;
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/primitives.dart';

// ── Helpers ──────────────────────────────────────────────────────────

/// Aggregates income and expense lists into bar-chart tuples by period.
///
/// Each tuple is (label, totalRevenue, totalExpense).
List<(String, double, double)> _buildChartData(
  String period,
  List<drift.IncomeEntry> income,
  List<drift.ExpenseEntry> expenses,
) {
  final now = DateTime.now();

  if (period == 'Day') {
    // Group by 2-hour blocks for today.
    final slots = <int, (double, double)>{};
    for (var h = 8; h <= 20; h += 2) {
      slots[h] = (0, 0);
    }
    for (final e in income) {
      final dt = DateTime.fromMillisecondsSinceEpoch(e.createdAt);
      if (dt.year == now.year &&
          dt.month == now.month &&
          dt.day == now.day) {
        final slot = (dt.hour ~/ 2) * 2;
        final key = slot < 8 ? 8 : (slot > 20 ? 20 : slot);
        final v = int.tryParse(e.amount.split('.').first) ?? 0;
        final cur = slots[key] ?? (0, 0);
        slots[key] = (cur.$1 + v / 1000000, cur.$2);
      }
    }
    for (final e in expenses) {
      final dt = DateTime.fromMillisecondsSinceEpoch(e.createdAt);
      if (dt.year == now.year &&
          dt.month == now.month &&
          dt.day == now.day) {
        final slot = (dt.hour ~/ 2) * 2;
        final key = slot < 8 ? 8 : (slot > 20 ? 20 : slot);
        final v = int.tryParse(e.amount.split('.').first) ?? 0;
        final cur = slots[key] ?? (0, 0);
        slots[key] = (cur.$1, cur.$2 + v / 1000000);
      }
    }
    final labels = ['8a', '10a', '12p', '2p', '4p', '6p', '8p'];
    final keys = [8, 10, 12, 14, 16, 18, 20];
    return [
      for (int i = 0; i < keys.length; i++)
        (labels[i], slots[keys[i]]!.$1, slots[keys[i]]!.$2),
    ];
  }

  if (period == 'Week') {
    // Monday-indexed days this week.
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final slots = List.generate(7, (_) => (0.0, 0.0));
    for (final e in income) {
      final dt = DateTime.fromMillisecondsSinceEpoch(e.createdAt);
      final diff = dt.difference(DateTime(weekStart.year, weekStart.month, weekStart.day)).inDays;
      if (diff >= 0 && diff < 7) {
        final v = int.tryParse(e.amount.split('.').first) ?? 0;
        slots[diff] = (slots[diff].$1 + v / 1000000, slots[diff].$2);
      }
    }
    for (final e in expenses) {
      final dt = DateTime.fromMillisecondsSinceEpoch(e.createdAt);
      final diff = dt.difference(DateTime(weekStart.year, weekStart.month, weekStart.day)).inDays;
      if (diff >= 0 && diff < 7) {
        final v = int.tryParse(e.amount.split('.').first) ?? 0;
        slots[diff] = (slots[diff].$1, slots[diff].$2 + v / 1000000);
      }
    }
    return [
      for (int i = 0; i < 7; i++) (dayLabels[i], slots[i].$1, slots[i].$2),
    ];
  }

  // Month — group by week number.
  final slots = <int, (double, double)>{1: (0, 0), 2: (0, 0), 3: (0, 0), 4: (0, 0)};
  for (final e in income) {
    final dt = DateTime.fromMillisecondsSinceEpoch(e.createdAt);
    if (dt.year == now.year && dt.month == now.month) {
      final week = ((dt.day - 1) ~/ 7) + 1;
      final v = int.tryParse(e.amount.split('.').first) ?? 0;
      final cur = slots[week] ?? (0, 0);
      slots[week] = (cur.$1 + v / 1000000, cur.$2);
    }
  }
  for (final e in expenses) {
    final dt = DateTime.fromMillisecondsSinceEpoch(e.createdAt);
    if (dt.year == now.year && dt.month == now.month) {
      final week = ((dt.day - 1) ~/ 7) + 1;
      final v = int.tryParse(e.amount.split('.').first) ?? 0;
      final cur = slots[week] ?? (0, 0);
      slots[week] = (cur.$1, cur.$2 + v / 1000000);
    }
  }
  return [for (int w = 1; w <= 4; w++) ('W$w', slots[w]!.$1, slots[w]!.$2)];
}

double _chartMax(List<(String, double, double)> data) {
  double max = 0.5;
  for (final d in data) {
    if (d.$2 > max) max = d.$2;
    if (d.$3 > max) max = d.$3;
  }
  return max * 1.15; // 15% headroom
}

// ── Bar chart ────────────────────────────────────────────────────────

class BarChart extends StatelessWidget {
  const BarChart(
      {super.key, required this.data, required this.max, this.height = 120});
  final List<(String, double, double)> data;
  final double max;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final p in data)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _Bar(
                            fraction: (p.$2 / max).clamp(0, 1),
                            widthFactor: 0.42,
                            revenue: true),
                        const SizedBox(width: 3),
                        _Bar(
                            fraction: (p.$3 / max).clamp(0, 1),
                            widthFactor: 0.42,
                            revenue: false),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(p.$1,
                      style: RMType.body(
                          size: 10.5,
                          weight: FontWeight.w600,
                          color: RM.muted)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar(
      {required this.fraction,
      required this.widthFactor,
      required this.revenue});
  final double fraction;
  final double widthFactor;
  final bool revenue;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: FractionallySizedBox(
        widthFactor: widthFactor * 2,
        heightFactor: fraction <= 0 ? 0.001 : fraction,
        alignment: Alignment.bottomCenter,
        child: Container(
          decoration: BoxDecoration(
            gradient: revenue
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [RM.brand, RM.brandDeep])
                : null,
            color: revenue ? null : RM.goldSoft,
            border: revenue ? null : Border.all(color: RM.gold),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(5)),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget item(Color fill, Border? border, String label) =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: fill,
                  border: border,
                  borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(label,
              style: RMType.body(size: 11.5, color: RM.muted)),
        ]);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      item(RM.brand, null, 'Doanh thu'),
      const SizedBox(width: 16),
      item(RM.goldSoft, Border.all(color: RM.gold), 'Chi phí'),
    ]);
  }
}

class PeriodToggle extends StatelessWidget {
  const PeriodToggle(
      {super.key, required this.value, required this.onChange});
  final String value;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
          color: RM.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: RM.line)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final p in ['Day', 'Week', 'Month'])
          GestureDetector(
            onTap: () => onChange(p),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                  color: p == value ? RM.ink : Colors.transparent,
                  borderRadius: BorderRadius.circular(999)),
              child: Text(p,
                  style: RMType.body(
                      size: 12.5,
                      weight: FontWeight.w700,
                      color: p == value ? Colors.white : RM.ink70)),
            ),
          ),
      ]),
    );
  }
}

// ── MOBILE ───────────────────────────────────────────────────────────

class FinanceMobile extends ConsumerStatefulWidget {
  const FinanceMobile({super.key});

  @override
  ConsumerState<FinanceMobile> createState() => _FinanceMobileState();
}

class _FinanceMobileState extends ConsumerState<FinanceMobile> {
  String _period = 'Week';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(financeNotifierProvider.notifier).refreshFromServer();
    });
  }

  @override
  Widget build(BuildContext context) {
    final wsId =
        ref.watch(authNotifierProvider.select((s) => s.activeWorkspaceId)) ??
            '';
    final summary = ref.watch(plSummaryProvider(wsId));
    final incomeAsync = ref.watch(incomeProvider(wsId));
    final expensesAsync = ref.watch(expensesProvider(wsId));

    final income = incomeAsync.maybeWhen(
        data: (v) => v, orElse: () => <drift.IncomeEntry>[]);
    final expenses = expensesAsync.maybeWhen(
        data: (v) => v, orElse: () => <drift.ExpenseEntry>[]);
    final chartData = _buildChartData(_period, income, expenses);
    final chartMax = _chartMax(chartData);

    final periodLabel = _periodLabel(_period);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
        child: Row(children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Finance', style: RMType.display(size: 24)),
                  Text(periodLabel,
                      style: RMType.body(size: 12.5, color: RM.muted)),
                ]),
          ),
          GestureDetector(
            onTap: () => rmToast(context, 'Đang xuất báo cáo…'),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: RM.card,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: RM.line)),
              child: const Icon(Icons.file_download_outlined,
                  size: 19, color: RM.ink),
            ),
          ),
        ]),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: PeriodToggle(
                  value: _period,
                  onChange: (p) => setState(() => _period = p)),
            ),
            const SizedBox(height: 14),
            SoftCard(
              radius: 20,
              padding: const EdgeInsets.all(18),
              shadow: true,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Lợi nhuận',
                        style: RMType.body(
                            size: 12.5,
                            weight: FontWeight.w600,
                            color: RM.muted)),
                    Text(summary.formattedProfit,
                        style: RMType.display(
                            size: 34,
                            letterSpacing: -1,
                            color: RM.herb)),
                    const SizedBox(height: 6),
                    Row(children: [
                      _inline('Doanh thu', summary.formattedIncome),
                      const SizedBox(width: 18),
                      _inline('Chi phí', summary.formattedExpense),
                    ]),
                    const SizedBox(height: 16),
                    BarChart(data: chartData, max: chartMax),
                    const SizedBox(height: 12),
                    const _Legend(),
                  ]),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _inline(String label, String value) => RichText(
        text: TextSpan(
            style: RMType.body(size: 12.5, color: RM.ink70),
            children: [
              TextSpan(text: '$label '),
              TextSpan(
                  text: value,
                  style: RMType.body(
                      size: 12.5,
                      weight: FontWeight.w700,
                      color: RM.ink)),
            ]),
      );
}

// ── TABLET ───────────────────────────────────────────────────────────

class FinanceTablet extends ConsumerStatefulWidget {
  const FinanceTablet({super.key});

  @override
  ConsumerState<FinanceTablet> createState() => _FinanceTabletState();
}

class _FinanceTabletState extends ConsumerState<FinanceTablet> {
  String _period = 'Week';
  static const _kicons = ['finance', 'tag', 'up', 'orders'];
  static const _kcol = [RM.brand, RM.gold, RM.herb, RM.info];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(financeNotifierProvider.notifier).refreshFromServer();
    });
  }

  @override
  Widget build(BuildContext context) {
    final wsId =
        ref.watch(authNotifierProvider.select((s) => s.activeWorkspaceId)) ??
            '';
    final summary = ref.watch(plSummaryProvider(wsId));
    final incomeAsync = ref.watch(incomeProvider(wsId));
    final expensesAsync = ref.watch(expensesProvider(wsId));

    final income = incomeAsync.maybeWhen(
        data: (v) => v, orElse: () => <drift.IncomeEntry>[]);
    final expenses = expensesAsync.maybeWhen(
        data: (v) => v, orElse: () => <drift.ExpenseEntry>[]);
    final chartData = _buildChartData(_period, income, expenses);
    final chartMax = _chartMax(chartData);
    final periodLabel = _periodLabel(_period);

    final kpiData = [
      ('Doanh thu', summary.formattedIncome, ''),
      ('Chi phí', summary.formattedExpense, ''),
      ('Lợi nhuận', summary.formattedProfit, ''),
      ('Đơn hàng', '—', ''),
    ];

    final portrait = MediaQuery.sizeOf(context).height >
        MediaQuery.sizeOf(context).width;

    return Container(
      color: RM.cream,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(26, 22, 26, 26),
        children: [
          Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Finance', style: RMType.display(size: 26)),
                    Text(periodLabel,
                        style: RMType.body(size: 13, color: RM.muted)),
                  ]),
            ),
            PeriodToggle(
                value: _period,
                onChange: (p) => setState(() => _period = p)),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => rmToast(context, 'Đang xuất báo cáo…'),
              style: OutlinedButton.styleFrom(
                foregroundColor: RM.ink,
                side: const BorderSide(color: RM.line),
                backgroundColor: RM.card,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.file_download_outlined,
                  size: 18, color: RM.ink),
              label: Text('Xuất báo cáo',
                  style: RMType.body(
                      size: 14,
                      weight: FontWeight.w700,
                      color: RM.ink)),
            ),
          ]),
          const SizedBox(height: 18),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: portrait ? 2 : 4,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 1.7,
            children: [
              for (int i = 0; i < kpiData.length; i++)
                SoftCard(
                  radius: 18,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                                color:
                                    _kcol[i].withValues(alpha: 0.1),
                                borderRadius:
                                    BorderRadius.circular(11)),
                            child: Icon(
                                AppIcons.of(_kicons[i]),
                                size: 18,
                                color: _kcol[i]),
                          ),
                          const Spacer(),
                          if (kpiData[i].$3.isNotEmpty)
                            Text(kpiData[i].$3,
                                style: RMType.body(
                                    size: 11.5,
                                    weight: FontWeight.w700,
                                    color: RM.herb)),
                        ]),
                        const SizedBox(height: 10),
                        Text(kpiData[i].$2,
                            style: RMType.display(
                                size: 26, letterSpacing: -0.5)),
                        Text(kpiData[i].$1,
                            style: RMType.body(
                                size: 12.5,
                                weight: FontWeight.w600,
                                color: RM.muted)),
                      ]),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Flex(
            direction: portrait ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: portrait ? 0 : 15,
                child: SoftCard(
                  radius: 20,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text('Doanh thu & Chi phí',
                                style: RMType.body(
                                    size: 16,
                                    weight: FontWeight.w700)),
                          ),
                          const _Legend(),
                        ]),
                        const SizedBox(height: 16),
                        BarChart(
                            data: chartData,
                            max: chartMax,
                            height: portrait ? 200 : 230),
                      ]),
                ),
              ),
              SizedBox(
                  width: portrait ? 0 : 18, height: portrait ? 18 : 0),
              Expanded(
                flex: portrait ? 0 : 10,
                child: SoftCard(
                  radius: 20,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Tổng hợp',
                            style: RMType.body(
                                size: 16,
                                weight: FontWeight.w700)),
                        const SizedBox(height: 14),
                        for (final row in [
                          ('Thu nhập', '${income.length}'),
                          ('Chi phí', '${expenses.length}'),
                          ('Lợi nhuận', summary.formattedProfit),
                        ]) ...[
                          Row(children: [
                            Expanded(
                              child: Text(row.$1,
                                  style: RMType.body(
                                      size: 13.5,
                                      weight: FontWeight.w600)),
                            ),
                            Text(row.$2,
                                style: RMType.body(
                                    size: 13.5,
                                    weight: FontWeight.w700,
                                    color: RM.brandDeep)),
                          ]),
                          const SizedBox(height: 10),
                        ],
                      ]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────

String _periodLabel(String period) {
  final now = DateTime.now();
  if (period == 'Day') {
    return 'Hôm nay · ${now.day} ${_monthName(now.month)}';
  }
  if (period == 'Week') {
    final start = now.subtract(Duration(days: now.weekday - 1));
    return 'Tuần này · ${start.day}–${now.day} ${_monthName(now.month)}';
  }
  return '${_monthName(now.month)} ${now.year}';
}

String _monthName(int m) {
  const names = [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return names[m];
}
