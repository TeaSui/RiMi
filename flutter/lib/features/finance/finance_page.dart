import 'package:flutter/material.dart';
import '../../core/app_icons.dart';
import '../../data/mock_data.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/primitives.dart';

// ── Bar chart ────────────────────────────────────────────────────────

class BarChart extends StatelessWidget {
  const BarChart({super.key, required this.data, required this.max, this.height = 120});
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
                        _Bar(fraction: (p.$2 / max).clamp(0, 1), widthFactor: 0.42, revenue: true),
                        const SizedBox(width: 3),
                        _Bar(fraction: (p.$3 / max).clamp(0, 1), widthFactor: 0.42, revenue: false),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(p.$1, style: RMType.body(size: 10.5, weight: FontWeight.w600, color: RM.muted)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.widthFactor, required this.revenue});
  final double fraction;
  final double widthFactor;
  final bool revenue;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: FractionallySizedBox(
        widthFactor: widthFactor * 2, // within the half-slot
        heightFactor: fraction <= 0 ? 0.001 : fraction,
        alignment: Alignment.bottomCenter,
        child: Container(
          decoration: BoxDecoration(
            gradient: revenue ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [RM.brand, RM.brandDeep]) : null,
            color: revenue ? null : RM.goldSoft,
            border: revenue ? null : Border.all(color: RM.gold),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
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
    Widget item(Color fill, Border? border, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: fill, border: border, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(label, style: RMType.body(size: 11.5, color: RM.muted)),
        ]);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      item(RM.brand, null, 'Revenue'),
      const SizedBox(width: 16),
      item(RM.goldSoft, Border.all(color: RM.gold), 'Expenses'),
    ]);
  }
}

class PeriodToggle extends StatelessWidget {
  const PeriodToggle({super.key, required this.value, required this.onChange});
  final String value;
  final ValueChanged<String> onChange;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: RM.card, borderRadius: BorderRadius.circular(999), border: Border.all(color: RM.line)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final p in ['Day', 'Week', 'Month'])
          GestureDetector(
            onTap: () => onChange(p),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(color: p == value ? RM.ink : Colors.transparent, borderRadius: BorderRadius.circular(999)),
              child: Text(p, style: RMType.body(size: 12.5, weight: FontWeight.w700, color: p == value ? Colors.white : RM.ink70)),
            ),
          ),
      ]),
    );
  }
}

// ── MOBILE ───────────────────────────────────────────────────────────

class FinanceMobile extends StatefulWidget {
  const FinanceMobile({super.key});
  @override
  State<FinanceMobile> createState() => _FinanceMobileState();
}

class _FinanceMobileState extends State<FinanceMobile> {
  String _period = 'Week';
  @override
  Widget build(BuildContext context) {
    final f = finance[_period]!;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Finance', style: RMType.display(size: 24)),
              Text(f.label, style: RMType.body(size: 12.5, color: RM.muted)),
            ]),
          ),
          GestureDetector(
            onTap: () => rmToast(context, 'Exporting report…'),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: RM.card, borderRadius: BorderRadius.circular(13), border: Border.all(color: RM.line)),
              child: const Icon(Icons.file_download_outlined, size: 19, color: RM.ink),
            ),
          ),
        ]),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          children: [
            Align(alignment: Alignment.centerLeft, child: PeriodToggle(value: _period, onChange: (p) => setState(() => _period = p))),
            const SizedBox(height: 14),
            SoftCard(
              radius: 20,
              padding: const EdgeInsets.all(18),
              shadow: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Net profit', style: RMType.body(size: 12.5, weight: FontWeight.w600, color: RM.muted)),
                Text(f.profit, style: RMType.display(size: 34, letterSpacing: -1, color: RM.herb)),
                const SizedBox(height: 6),
                Row(children: [
                  _inline('Revenue', f.rev),
                  const SizedBox(width: 18),
                  _inline('Expenses', f.exp),
                ]),
                const SizedBox(height: 16),
                BarChart(data: f.data, max: f.max),
                const SizedBox(height: 12),
                const _Legend(),
              ]),
            ),
            const SizedBox(height: 16),
            const SectionHead('Where money goes'),
            for (int i = 0; i < f.spend.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _SpendBar(row: f.spend[i]),
            ],
          ],
        ),
      ),
    ]);
  }

  Widget _inline(String label, String value) => RichText(
        text: TextSpan(style: RMType.body(size: 12.5, color: RM.ink70), children: [
          TextSpan(text: '$label '),
          TextSpan(text: value, style: RMType.body(size: 12.5, weight: FontWeight.w700, color: RM.ink)),
        ]),
      );
}

class _SpendBar extends StatelessWidget {
  const _SpendBar({required this.row});
  final (String, String, int, Color) row;
  @override
  Widget build(BuildContext context) {
    return SoftCard(
      radius: 14,
      onTap: () => rmToast(context, '${row.$1} · ${row.$2}'),
      child: Column(children: [
        Row(children: [
          Expanded(child: Text(row.$1, style: RMType.body(size: 13.5, weight: FontWeight.w600))),
          Text(row.$2, style: RMType.body(size: 13.5, weight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: row.$3 / 100, minHeight: 7, backgroundColor: RM.line, color: row.$4),
        ),
      ]),
    );
  }
}

// ── TABLET ───────────────────────────────────────────────────────────

class FinanceTablet extends StatefulWidget {
  const FinanceTablet({super.key});
  @override
  State<FinanceTablet> createState() => _FinanceTabletState();
}

class _FinanceTabletState extends State<FinanceTablet> {
  String _period = 'Week';
  static const _kicons = ['finance', 'tag', 'up', 'orders'];
  static const _kcol = [RM.brand, RM.gold, RM.herb, RM.info];

  @override
  Widget build(BuildContext context) {
    final f = finance[_period]!;
    final portrait = MediaQuery.sizeOf(context).height > MediaQuery.sizeOf(context).width;
    return Container(
      color: RM.cream,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(26, 22, 26, 26),
        children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Finance', style: RMType.display(size: 26)),
                Text(f.label, style: RMType.body(size: 13, color: RM.muted)),
              ]),
            ),
            PeriodToggle(value: _period, onChange: (p) => setState(() => _period = p)),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => rmToast(context, 'Exporting report…'),
              style: OutlinedButton.styleFrom(
                foregroundColor: RM.ink,
                side: const BorderSide(color: RM.line),
                backgroundColor: RM.card,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.file_download_outlined, size: 18, color: RM.ink),
              label: Text('Export', style: RMType.body(size: 14, weight: FontWeight.w700, color: RM.ink)),
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
              for (int i = 0; i < f.kpi.length; i++)
                SoftCard(
                  radius: 18,
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Row(children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(color: _kcol[i].withValues(alpha: 0.1), borderRadius: BorderRadius.circular(11)),
                        child: Icon(AppIcons.of(_kicons[i]), size: 18, color: _kcol[i]),
                      ),
                      const Spacer(),
                      Text(f.kpi[i].$3, style: RMType.body(size: 11.5, weight: FontWeight.w700, color: RM.herb)),
                    ]),
                    const SizedBox(height: 10),
                    Text(f.kpi[i].$2, style: RMType.display(size: 26, letterSpacing: -0.5)),
                    Text(f.kpi[i].$1, style: RMType.body(size: 12.5, weight: FontWeight.w600, color: RM.muted)),
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
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('Revenue vs expenses', style: RMType.body(size: 16, weight: FontWeight.w700))),
                      const _Legend(),
                    ]),
                    const SizedBox(height: 16),
                    BarChart(data: f.data, max: f.max, height: portrait ? 200 : 230),
                  ]),
                ),
              ),
              SizedBox(width: portrait ? 0 : 18, height: portrait ? 18 : 0),
              Expanded(
                flex: portrait ? 0 : 10,
                child: SoftCard(
                  radius: 20,
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Top dishes by revenue', style: RMType.body(size: 16, weight: FontWeight.w700)),
                    const SizedBox(height: 14),
                    for (int i = 0; i < topDishes.length; i++) ...[
                      if (i > 0) const SizedBox(height: 13),
                      GestureDetector(
                        onTap: () => rmToast(context, '${topDishes[i].$1} · ${topDishes[i].$2}'),
                        child: Row(children: [
                          SizedBox(width: 18, child: Text('${i + 1}', style: RMType.display(size: 16, color: RM.faint))),
                          const SizedBox(width: 12),
                          FoodSlot(seed: topDishes[i].$3, width: 40, height: 40, radius: 11),
                          const SizedBox(width: 12),
                          Expanded(child: Text(topDishes[i].$1, style: RMType.body(size: 13.5, weight: FontWeight.w600))),
                          Text(topDishes[i].$2, style: RMType.body(size: 13.5, weight: FontWeight.w700, color: RM.brandDeep)),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      decoration: BoxDecoration(color: RM.herbSoft, borderRadius: BorderRadius.circular(14)),
                      child: Row(children: [
                        const Icon(Icons.auto_awesome_rounded, size: 20, color: RM.herb),
                        const SizedBox(width: 10),
                        Expanded(child: Text('Weekend revenue is up 23%. Stock 20% more sườn for Sat–Sun.', style: RMType.body(size: 12.5, color: RM.ink70, height: 1.45))),
                      ]),
                    ),
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
