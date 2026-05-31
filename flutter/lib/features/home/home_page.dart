import 'package:flutter/material.dart';
import '../../app.dart';
import '../../core/app_icons.dart';
import '../../data/mock_data.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/primitives.dart';
import '../customers/customers_page.dart';
import '../orders/orders_page.dart';
import '../workspace/workspace_chip.dart';

// Quick-action descriptors (icon, label, fg, bg, destination key).
const _quick = [
  ('plus', 'New order', RM.brand, RM.brandSoft, 'orders'),
  ('content', 'Make post', RM.gold, RM.goldSoft, 'content'),
  ('products', 'Add dish', RM.herb, RM.herbSoft, 'products'),
  ('users', 'Customers', RM.info, Color(0xFFE1ECF8), 'crm'),
];

void _quickGo(BuildContext context, String key) {
  switch (key) {
    case 'orders':
      AppNav.goTab(1);
    case 'content':
      AppNav.goTab(3);
    case 'products':
      AppNav.goTab(2);
    case 'crm':
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CustomersPage()));
  }
}

// ── shared pieces ────────────────────────────────────────────────────

class _SearchAiBar extends StatelessWidget {
  const _SearchAiBar();
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => AppNav.openAiTeam(),
      child: SoftCard(
        radius: 15,
        shadow: true,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            const RmIcon('search', size: 20, color: RM.muted),
            const SizedBox(width: 10),
            Expanded(child: Text('Search or ask RiMi AI…', style: RMType.body(size: 14, color: RM.muted))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [RM.gold, RM.brand]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.auto_awesome_rounded, size: 15, color: Colors.white),
                const SizedBox(width: 5),
                Text('AI', style: RMType.body(size: 12, weight: FontWeight.w700, color: Colors.white)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _RevenueHero extends StatelessWidget {
  const _RevenueHero({this.big = false});
  final bool big;
  @override
  Widget build(BuildContext context) {
    final stats = big
        ? const [('38', 'Orders'), ('74.700₫', 'Avg / order'), ('6', 'In kitchen'), ('96%', 'On-time')]
        : const [('38', 'Orders'), ('74.700₫', 'Avg / order'), ('6', 'In kitchen')];
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: EdgeInsets.all(big ? 24 : 20),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [RM.brandDeep, RM.brand, RM.gold],
            stops: [0.0, 0.65, 1.0],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -30,
              top: -30,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), shape: BoxShape.circle),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Revenue today', style: RMType.body(size: 13, weight: FontWeight.w600, color: Colors.white70)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.north_east_rounded, size: 13, color: Colors.white),
                        const SizedBox(width: 3),
                        Text(big ? '+12% vs yesterday' : '+12%', style: RMType.body(size: 12, weight: FontWeight.w700, color: Colors.white)),
                      ]),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('2.840.000₫', style: RMType.display(size: big ? 46 : 38, letterSpacing: -1, color: Colors.white)),
                SizedBox(height: big ? 22 : 14),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      for (final s in stats)
                        Padding(
                          padding: EdgeInsets.only(right: big ? 30 : 22),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s.$1, style: RMType.body(size: big ? 20 : 16, weight: FontWeight.w700, color: Colors.white)),
                            Text(s.$2, style: RMType.body(size: big ? 12 : 11.5, color: Colors.white70)),
                          ]),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < _quick.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: SoftCard(
              onTap: () => _quickGo(context, _quick[i].$5),
              padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 6),
              child: Column(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: _quick[i].$4, borderRadius: BorderRadius.circular(13)),
                  child: Icon(AppIcons.of(_quick[i].$1), size: 21, color: _quick[i].$3),
                ),
                const SizedBox(height: 7),
                Text(_quick[i].$2,
                    textAlign: TextAlign.center,
                    style: RMType.body(size: 11.5, weight: FontWeight.w600, color: RM.ink70)),
              ]),
            ),
          ),
        ],
      ],
    );
  }
}

class _ActiveOrderRow extends StatelessWidget {
  const _ActiveOrderRow(this.o);
  final Order o;
  @override
  Widget build(BuildContext context) {
    final ss = statusStyle[o.status]!;
    return SoftCard(
      radius: 16,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrderDetailPage(id: o.id))),
      child: Row(
        children: [
          FoodSlot(seed: o.seed, width: 48, height: 48, radius: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Order #${o.id}', style: RMType.body(size: 14.5, weight: FontWeight.w700)),
                Text(o.items, maxLines: 1, overflow: TextOverflow.ellipsis, style: RMType.body(size: 12.5, color: RM.muted)),
                const SizedBox(height: 4),
                Row(children: [
                  StatusDot(channelColor[o.ch]!, size: 7),
                  const SizedBox(width: 4),
                  Text(channelLabel[o.ch]!, style: RMType.body(size: 11, weight: FontWeight.w700, color: channelColor[o.ch]!)),
                  Text(' · ${o.time}', style: RMType.body(size: 11, color: RM.faint)),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(vnd(o.total), style: RMType.body(size: 14, weight: FontWeight.w700)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: ss.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(7)),
                child: Text(ss.label, style: RMType.body(size: 10.5, weight: FontWeight.w700, color: ss.color)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActiveOrders extends StatelessWidget {
  const _ActiveOrders({this.limit = 2});
  final int limit;
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: OrderStore.instance,
      builder: (context, _) {
        final active = OrderStore.instance.all.where((o) => o.status != 'done').take(limit).toList();
        return Column(
          children: [
            for (int i = 0; i < active.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _ActiveOrderRow(active[i]),
            ],
          ],
        );
      },
    );
  }
}

// ── MOBILE ───────────────────────────────────────────────────────────

class HomeMobile extends StatelessWidget {
  const HomeMobile({super.key});
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 120),
      children: [
        Row(
          children: [
            const RiMiMark(size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Good morning,', style: RMType.body(size: 12.5, weight: FontWeight.w600, color: RM.muted)),
                  Text('Bếp Nhà Hằng', style: RMType.body(size: 17, weight: FontWeight.w700, height: 1.1)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(color: RM.herbSoft, borderRadius: BorderRadius.circular(999)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const StatusDot(RM.herb),
                const SizedBox(width: 7),
                Text('Open', style: RMType.body(size: 12, weight: FontWeight.w700, color: RM.herb)),
              ]),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => rmToast(context, 'No new notifications'),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: RM.card, borderRadius: BorderRadius.circular(13), border: Border.all(color: RM.line)),
                child: const Icon(Icons.notifications_outlined, size: 20, color: RM.ink),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const WorkspaceChip(),
        const SizedBox(height: 10),
        const _SearchAiBar(),
        const SizedBox(height: 16),
        const _RevenueHero(),
        const SizedBox(height: 16),
        const _QuickActions(),
        const SizedBox(height: 18),
        SectionHead('Active orders', action: 'See all', onAction: () => AppNav.goTab(1)),
        const _ActiveOrders(limit: 2),
      ],
    );
  }
}

// ── TABLET ───────────────────────────────────────────────────────────

class HomeTablet extends StatelessWidget {
  const HomeTablet({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      color: RM.cream,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(26, 22, 26, 40),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Good morning, Hằng', style: RMType.display(size: 26)),
                    Text('Tuesday, 30 May · Bếp Nhà Hằng', style: RMType.body(size: 13.5, color: RM.muted)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                decoration: BoxDecoration(color: RM.herbSoft, borderRadius: BorderRadius.circular(12)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const StatusDot(RM.herb),
                  const SizedBox(width: 7),
                  Text('Store open', style: RMType.body(size: 12.5, weight: FontWeight.w700, color: RM.herb)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(flex: 14, child: _RevenueHero(big: true)),
              const SizedBox(width: 18),
              Expanded(
                flex: 10,
                child: GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.55,
                  children: [
                    for (final q in _quick)
                      SoftCard(
                        radius: 18,
                        padding: const EdgeInsets.all(16),
                        onTap: () => _quickGo(context, q.$5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(color: q.$4, borderRadius: BorderRadius.circular(13)),
                              child: Icon(AppIcons.of(q.$1), size: 22, color: q.$3),
                            ),
                            const SizedBox(height: 10),
                            Text(q.$2, style: RMType.body(size: 13.5, weight: FontWeight.w700)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHead('Active orders', action: 'See all', onAction: () => AppNav.goTab(1)),
                    const _ActiveOrders(limit: 3),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                flex: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHead('RiMi AI'),
                    SoftCard(
                      radius: 18,
                      border: RM.goldSoft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [RM.gold, RM.brand]),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.auto_awesome_rounded, size: 21, color: Colors.white),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Text('Rain forecast at 5pm — bún bò sells 2× faster. Push a flash promo?',
                                    style: RMType.body(size: 13.5, color: RM.ink70)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 13),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: RM.brand,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () => AppNav.openAiTeam(),
                              child: Text('Create promo', style: RMType.body(size: 13.5, weight: FontWeight.w700, color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
