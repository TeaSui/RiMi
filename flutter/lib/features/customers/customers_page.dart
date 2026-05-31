import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/app_icons.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/customers/customer_providers.dart';
import '../../core/responsive.dart';
import '../../data/drift/app_database.dart' as drift;
import '../../data/mock_data.dart' show tiers;
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/forms.dart';
import '../../widgets/navigation.dart';
import '../../widgets/primitives.dart';

const _crmFilters = [
  ('all', 'All'),
  ('vip', 'VIP'),
  ('gold', 'Gold'),
  ('reg', 'Regular'),
  ('risk', 'At-risk')
];

// ─────────────────────────────────────────────────────────────────────
// Adapter — converts a Drift Customer to a display-friendly struct
// ─────────────────────────────────────────────────────────────────────

class CustDisplay {
  const CustDisplay({
    required this.id,
    required this.name,
    required this.phone,
    required this.area,
    required this.tier,
    required this.orderCount,
    required this.totalSpent,
    required this.seed,
  });

  final String id;
  final String name;
  final String phone;
  final String area;
  final String tier;
  final int orderCount;
  final String totalSpent;
  final int seed;
}

CustDisplay _toDisplay(drift.Customer d) {
  return CustDisplay(
    id: d.id,
    name: d.name ?? '—',
    phone: d.phone ?? '—',
    area: d.area ?? 'Walk-in',
    tier: d.tier,
    orderCount: d.orderCount,
    totalSpent: d.totalSpent,
    seed: d.id.hashCode.abs() % 5,
  );
}

// ── Add-customer composer ────────────────────────────────────────────

Future<bool?> showAddCustomerComposer(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: RM.cream,
    builder: (_) => const _AddCustomerComposer(),
  );
}

class _AddCustomerComposer extends ConsumerStatefulWidget {
  const _AddCustomerComposer();
  @override
  ConsumerState<_AddCustomerComposer> createState() =>
      _AddCustomerComposerState();
}

class _AddCustomerComposerState extends ConsumerState<_AddCustomerComposer> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _area = TextEditingController();
  String _tier = 'reg';

  Future<void> _create() async {
    await ref.read(customersNotifierProvider.notifier).createCustomer(
          name: _name.text.trim(),
          phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          area: _area.text.trim().isEmpty ? null : _area.text.trim(),
          tier: _tier,
        );
    if (mounted) {
      Navigator.of(context).pop(true);
      rmToast(context, 'Customer added');
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _area.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader('Add customer'),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Column(children: [
              RmTextField(
                label: 'NAME',
                controller: _name,
                hint: 'e.g. Chị Hương Lê',
                autofocus: true,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: RmTextField(
                    label: 'PHONE',
                    controller: _phone,
                    hint: '0909 …',
                    keyboard: TextInputType.phone,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: RmTextField(
                    label: 'AREA',
                    controller: _area,
                    hint: 'Q.1 / GrabFood',
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('TIER',
                    style: RMType.body(
                        size: 12, weight: FontWeight.w700, color: RM.muted)),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final t in [
                  ('reg', 'Regular'),
                  ('gold', 'Gold'),
                  ('vip', 'VIP'),
                  ('risk', 'At-risk')
                ])
                  PillChip(
                    label: t.$2,
                    active: t.$1 == _tier,
                    activeColor: tiers[t.$1]!.color,
                    onTap: () => setState(() => _tier = t.$1),
                  ),
              ]),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: SheetSubmit(
              label: 'Add customer',
              enabled: _name.text.trim().isNotEmpty,
              onPressed: _create,
            ),
          ),
        ],
      ),
    );
  }
}

// ── pieces ───────────────────────────────────────────────────────────

class _CustomerRow extends StatelessWidget {
  const _CustomerRow(
      {required this.c, this.selected = false, required this.onTap});
  final CustDisplay c;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = tiers[c.tier]!;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: RM.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? RM.brand : RM.line, width: 1.5),
        ),
        child: Row(children: [
          Avatar(name: c.name, seed: c.seed, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: RMType.body(
                              size: 14, weight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: t.bg,
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(t.label,
                          style: RMType.body(
                              size: 10,
                              weight: FontWeight.w800,
                              color: t.color)),
                    ),
                  ]),
                  Text(
                    '${c.orderCount} orders · ${c.totalSpent} · ${c.area}',
                    style: RMType.body(size: 12, color: RM.muted),
                  ),
                ]),
          ),
          GestureDetector(
            onTap: () =>
                rmToast(context, 'Calling ${c.name.split(' ').last}…'),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: RM.herbSoft,
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.call_outlined,
                  size: 17, color: RM.herb),
            ),
          ),
        ]),
      ),
    );
  }
}

class _CrmStats extends StatelessWidget {
  const _CrmStats({required this.total, required this.vipCount});
  final int total;
  final int vipCount;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      for (final s in [
        ('Total', '$total'),
        ('VIP', '$vipCount'),
        ('Repeat', '—'),
      ]) ...[
        Expanded(
          child: SoftCard(
            radius: 14,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.$2, style: RMType.display(size: 19)),
                  Text(s.$1,
                      style: RMType.body(
                          size: 11,
                          weight: FontWeight.w600,
                          color: RM.muted)),
                ]),
          ),
        ),
        if (s.$1 != 'Repeat') const SizedBox(width: 10),
      ],
    ]);
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.tier, required this.onChange});
  final String tier;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final f in _crmFilters) ...[
          PillChip(
              label: f.$2,
              active: f.$1 == tier,
              onTap: () => onChange(f.$1)),
          const SizedBox(width: 8),
        ],
      ]),
    );
  }
}

class CustomerDetail extends StatelessWidget {
  const CustomerDetail({super.key, required this.c});
  final CustDisplay? c;

  @override
  Widget build(BuildContext context) {
    final cust = c;
    if (cust == null) {
      return Center(
          child: Text('Select a customer',
              style: RMType.body(size: 14, color: RM.muted)));
    }
    final t = tiers[cust.tier]!;
    return Container(
      color: RM.card,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: RM.line))),
          child: Row(children: [
            Avatar(name: cust.name, seed: cust.seed, size: 56),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(cust.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: RMType.display(size: 21)),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                            color: t.bg,
                            borderRadius: BorderRadius.circular(7)),
                        child: Text(t.label,
                            style: RMType.body(
                                size: 11,
                                weight: FontWeight.w800,
                                color: t.color)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text('${cust.phone} · ${cust.area}',
                        style: RMType.body(size: 13, color: RM.muted)),
                  ]),
            ),
            GestureDetector(
              onTap: () => rmToast(context, 'Calling…'),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: RM.herbSoft,
                    borderRadius: BorderRadius.circular(13)),
                child: const Icon(Icons.call_outlined,
                    size: 20, color: RM.herb),
              ),
            ),
          ]),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            children: [
              Row(children: [
                for (final s in [
                  ('Orders', '${cust.orderCount}'),
                  ('Spent', cust.totalSpent),
                  ('Area', cust.area),
                ]) ...[
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 13),
                      decoration: BoxDecoration(
                          color: RM.cardAlt,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: RM.line)),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.$2,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: RMType.display(size: 19)),
                            Text(s.$1,
                                style: RMType.body(
                                    size: 11.5,
                                    weight: FontWeight.w600,
                                    color: RM.muted)),
                          ]),
                    ),
                  ),
                  if (s.$1 != 'Area') const SizedBox(width: 12),
                ],
              ]),
              if (cust.tier == 'risk') ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                      color: RM.dangerSoft,
                      borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    const Icon(Icons.auto_awesome_rounded,
                        size: 20, color: RM.danger),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                          "Hasn't ordered in a while — send a 15% win-back voucher?",
                          style: RMType.body(
                              size: 12.5, color: RM.ink70, height: 1.45)),
                    ),
                  ]),
                ),
              ],
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: RM.line))),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () =>
                    rmToast(context, 'Loyalty message sent'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: RM.ink70,
                  side: const BorderSide(color: RM.line, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Send message',
                    style: RMType.body(
                        size: 14.5,
                        weight: FontWeight.w700,
                        color: RM.ink70)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => rmToast(context, 'Voucher sent'),
                style: FilledButton.styleFrom(
                    backgroundColor: RM.brand,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14))),
                icon: const Icon(Icons.card_giftcard_rounded,
                    size: 18, color: Colors.white),
                label: Text('Send voucher',
                    style: RMType.body(
                        size: 14.5,
                        weight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Page (responsive) ────────────────────────────────────────────────

class CustomersPage extends ConsumerStatefulWidget {
  const CustomersPage({super.key});
  @override
  ConsumerState<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends ConsumerState<CustomersPage> {
  String _tier = 'all';
  bool _searchOpen = false;
  final _search = TextEditingController();
  String? _selId;

  @override
  void initState() {
    super.initState();
    // Refresh from server on mount (best-effort).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(customersNotifierProvider.notifier).refreshFromServer();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<CustDisplay> _filtered(List<drift.Customer> all) {
    final q = _search.text.trim().toLowerCase();
    return all
        .where((c) =>
            (_tier == 'all' || c.tier == _tier) &&
            (q.isEmpty ||
                '${c.name}${c.phone}${c.area}'
                    .toLowerCase()
                    .contains(q)))
        .map(_toDisplay)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final wsId =
        ref.watch(authNotifierProvider.select((s) => s.activeWorkspaceId)) ??
            '';
    final asyncCustomers = ref.watch(customersProvider(wsId));

    return Scaffold(
      backgroundColor: RM.cream,
      body: asyncCustomers.when(
        data: (all) =>
            isTablet(context) ? _tablet(context, all) : SafeArea(child: _mobile(context, all)),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
            child: Text('Could not load customers',
                style: RMType.body(size: 14, color: RM.muted))),
      ),
    );
  }

  // mobile ─────────────────────────────────────────────
  Widget _mobile(BuildContext context, List<drift.Customer> all) {
    final list = _filtered(all);
    final vipCount = all.where((c) => c.tier == 'vip').length;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
        child: Row(children: [
          GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: const RmIcon('arrowL', size: 22, color: RM.ink)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Customers', style: RMType.display(size: 24)),
              Text('${all.length} total · $vipCount VIP',
                  style: RMType.body(size: 12.5, color: RM.muted)),
            ]),
          ),
          _Sq(
            icon: 'search',
            active: _searchOpen,
            onTap: () => setState(() {
              _searchOpen = !_searchOpen;
              _search.clear();
            }),
          ),
          const SizedBox(width: 12),
          _Sq(
            icon: 'plus',
            filled: true,
            onTap: () => showAddCustomerComposer(context)
                .then((a) {
              if (a == true) setState(() => _tier = 'all');
            }),
          ),
        ]),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 30),
          children: [
            if (_searchOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: _SearchBox(
                  controller: _search,
                  onChanged: () => setState(() {}),
                  onClose: () => setState(() {
                    _searchOpen = false;
                    _search.clear();
                  }),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: _FilterChips(
                  tier: _tier,
                  onChange: (v) => setState(() => _tier = v)),
            ),
            if (!_searchOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: _CrmStats(
                    total: all.length, vipCount: vipCount),
              ),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                    child: Text('No customers found',
                        style: RMType.body(size: 14, color: RM.muted))),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(children: [
                  for (int i = 0; i < list.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    _CustomerRow(
                      c: list[i],
                      onTap: () =>
                          rmToast(context, '${list[i].name} · ${list[i].orderCount} orders'),
                    ),
                  ],
                ]),
              ),
          ],
        ),
      ),
    ]);
  }

  // tablet ─────────────────────────────────────────────
  Widget _tablet(BuildContext context, List<drift.Customer> all) {
    final list = _filtered(all);
    final vipCount = all.where((c) => c.tier == 'vip').length;

    CustDisplay? sel;
    if (_selId != null) {
      final matches = list.where((c) => c.id == _selId).toList();
      sel = matches.isNotEmpty ? matches.first : (list.isNotEmpty ? list.first : null);
    } else {
      sel = list.isNotEmpty ? list.first : null;
    }

    final portrait = MediaQuery.sizeOf(context).height >
        MediaQuery.sizeOf(context).width;

    final listPane = Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
        child: Row(children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Customers', style: RMType.display(size: 24)),
                  Text('${all.length} total · $vipCount VIP',
                      style: RMType.body(size: 12.5, color: RM.muted)),
                ]),
          ),
          _Sq(
              icon: 'plus',
              filled: true,
              onTap: () => showAddCustomerComposer(context)
                  .then((a) {
                if (a == true) setState(() => _tier = 'all');
              })),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 12),
        child: _SearchBox(
            controller: _search,
            plain: true,
            onChanged: () => setState(() {}),
            onClose: () {}),
      ),
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: _FilterChips(
              tier: _tier,
              onChange: (v) => setState(() => _tier = v))),
      const SizedBox(height: 12),
      Expanded(
        child: list.isEmpty
            ? Center(
                child: Text('No customers found',
                    style: RMType.body(size: 14, color: RM.muted)))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
                itemCount: list.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _CustomerRow(
                  c: list[i],
                  selected: list[i].id == sel?.id,
                  onTap: () => setState(() => _selId = list[i].id),
                ),
              ),
      ),
    ]);

    return Row(children: [
      TabletRail(
        activeIndex: 0,
        onTap: (i) => AppNav.goTab(i),
        onAi: () => AppNav.openAiTeam(),
      ),
      Expanded(
        child: Flex(
          direction: portrait ? Axis.vertical : Axis.horizontal,
          children: [
            SizedBox(
              width: portrait ? null : 420,
              height: portrait
                  ? MediaQuery.sizeOf(context).height * 0.48
                  : null,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    right: portrait
                        ? BorderSide.none
                        : const BorderSide(color: RM.line),
                    bottom: portrait
                        ? const BorderSide(color: RM.line)
                        : BorderSide.none,
                  ),
                ),
                child: listPane,
              ),
            ),
            Expanded(child: CustomerDetail(c: sel)),
          ],
        ),
      ),
    ]);
  }
}

class _Sq extends StatelessWidget {
  const _Sq(
      {required this.icon,
      this.active = false,
      this.filled = false,
      required this.onTap});
  final String icon;
  final bool active;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: filled ? RM.brand : (active ? RM.brandSoft : RM.card),
          borderRadius: BorderRadius.circular(13),
          border: filled
              ? null
              : Border.all(color: active ? RM.brand : RM.line),
        ),
        child: Icon(AppIcons.of(icon),
            size: filled ? 20 : 19,
            color: filled
                ? Colors.white
                : (active ? RM.brand : RM.ink)),
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox(
      {required this.controller,
      required this.onChanged,
      required this.onClose,
      this.plain = false});
  final TextEditingController controller;
  final VoidCallback onChanged;
  final VoidCallback onClose;
  final bool plain;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 2),
      decoration: BoxDecoration(
        color: RM.card,
        borderRadius: BorderRadius.circular(plain ? 12 : 13),
        border: Border.all(
            color: plain ? RM.line : RM.brand, width: plain ? 1 : 1.5),
        boxShadow: plain
            ? null
            : [
                const BoxShadow(
                    color: RM.brandSoft, blurRadius: 0, spreadRadius: 3)
              ],
      ),
      child: Row(children: [
        RmIcon('search',
            size: 18, color: plain ? RM.muted : RM.brand),
        const SizedBox(width: 9),
        Expanded(
          child: TextField(
            controller: controller,
            autofocus: !plain,
            onChanged: (_) => onChanged(),
            style: RMType.body(size: 13.5),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: 'Search name, phone, area…',
              hintStyle: RMType.body(size: 13.5, color: RM.faint),
            ),
          ),
        ),
        if (!plain)
          GestureDetector(
              onTap: onClose,
              child: const RmIcon('close', size: 18, color: RM.muted)),
      ]),
    );
  }
}
