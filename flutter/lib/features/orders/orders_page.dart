import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_icons.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/customers/customer_providers.dart';
import '../../core/orders/order_providers.dart';
import '../../core/products/product_providers.dart';
import '../../data/drift/app_database.dart' as drift;
import '../../data/mock_data.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/primitives.dart';

// ─────────────────────────────────────────────────────────────────────
// Adapter — converts a Drift Order to the mock Order model used by UI
// ─────────────────────────────────────────────────────────────────────

// Public adapter used by home_page.dart and any widget that needs a mock-compatible Order.
Order toUiOrder(drift.Order d) => _toUiOrder(d);

Order _toUiOrder(drift.Order d) {
  final diff = DateTime.now().millisecondsSinceEpoch - d.createdAt;
  final mins = diff ~/ 60000;
  final timeStr = mins < 1
      ? 'vừa xong'
      : mins < 60
          ? '$mins min'
          : '${mins ~/ 60}h';

  return Order(
    id: d.id,
    cust: d.customerName ?? 'Khách lẻ',
    ch: d.channel,
    items: d.itemsSummary,
    total: d.totalAmount,
    status: d.status,
    time: timeStr,
    late: d.isLate,
    seed: d.id.hashCode.abs() % 6,
    note: d.note,
  );
}

// ─────────────────────────────────────────────────────────────────────
// Shared filter widgets
// ─────────────────────────────────────────────────────────────────────

class ChannelChips extends StatelessWidget {
  const ChannelChips({super.key, required this.value, required this.onChange});
  final String value;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final c in channels) ...[
            _Chip(
              label: c.$2,
              dot: c.$3,
              active: c.$1 == value,
              onTap: () => onChange(c.$1),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.active, required this.onTap, this.dot});
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: active ? RM.ink : RM.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? RM.ink : RM.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot != null) ...[StatusDot(dot!, size: 7), const SizedBox(width: 6)],
          Text(label, style: RMType.body(size: 12.5, weight: FontWeight.w600, color: active ? Colors.white : RM.ink70)),
        ]),
      ),
    );
  }
}

class StatusTabs extends StatelessWidget {
  const StatusTabs({super.key, required this.value, required this.onChange, required this.counts});
  final String value;
  final ValueChanged<String> onChange;
  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: RM.line))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final t in statusTabs)
              GestureDetector(
                onTap: () => onChange(t.$1),
                child: Container(
                  margin: const EdgeInsets.only(right: 18),
                  padding: const EdgeInsets.only(bottom: 11),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: t.$1 == value ? RM.brand : Colors.transparent, width: 2.5)),
                  ),
                  child: Row(children: [
                    Text(t.$2, style: RMType.body(size: 13.5, weight: t.$1 == value ? FontWeight.w700 : FontWeight.w600, color: t.$1 == value ? RM.brand : RM.muted)),
                    const SizedBox(width: 6),
                    Container(
                      constraints: const BoxConstraints(minWidth: 18),
                      height: 18,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: t.$1 == value ? RM.brand : RM.line,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text('${counts[t.$1] ?? 0}',
                          style: RMType.body(size: 11, weight: FontWeight.w800, color: t.$1 == value ? Colors.white : RM.muted)),
                    ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.controller, required this.onChanged, required this.onClose, this.hint = 'Tìm theo #, khách, món…'});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 4),
      decoration: BoxDecoration(
        color: RM.card,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: RM.brand, width: 1.5),
        boxShadow: [const BoxShadow(color: RM.brandSoft, blurRadius: 0, spreadRadius: 3)],
      ),
      child: Row(children: [
        const RmIcon('search', size: 19, color: RM.brand),
        const SizedBox(width: 9),
        Expanded(
          child: TextField(
            controller: controller,
            autofocus: true,
            onChanged: onChanged,
            style: RMType.body(size: 14),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: hint,
              hintStyle: RMType.body(size: 14, color: RM.faint),
            ),
          ),
        ),
        GestureDetector(onTap: onClose, child: const RmIcon('close', size: 18, color: RM.muted)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Order cards
// ─────────────────────────────────────────────────────────────────────

class OrderCard extends StatelessWidget {
  const OrderCard(
      {super.key,
      required this.o,
      required this.onOpen,
      this.onAdvance});
  final Order o;
  final VoidCallback onOpen;
  final VoidCallback? onAdvance;

  @override
  Widget build(BuildContext context) {
    final ss = statusStyle[o.status]!;
    return Container(
      decoration: BoxDecoration(
        color: RM.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RM.line),
        boxShadow: [BoxShadow(color: RM.ink.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 10),
              child: Row(children: [
                Expanded(
                  child: Text(
                    o.items.isNotEmpty ? o.items : '#${o.id.substring(0, 8).toUpperCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RMType.body(size: 14.5, weight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: channelColor[o.ch]!.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    StatusDot(channelColor[o.ch]!, size: 6),
                    const SizedBox(width: 3),
                    Text(channelLabel[o.ch]!, style: RMType.body(size: 10.5, weight: FontWeight.w700, color: channelColor[o.ch]!)),
                  ]),
                ),
                const SizedBox(width: 5),
                Icon(AppIcons.of('clock'), size: 12, color: o.late ? RM.danger : RM.muted),
                const SizedBox(width: 2),
                Text(o.late ? '${o.time}·trễ' : o.time, style: RMType.body(size: 11, weight: FontWeight.w600, color: o.late ? RM.danger : RM.muted)),
              ]),
            ),
          ),
          InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FoodSlot(seed: o.seed, width: 54, height: 54, radius: 12),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(o.cust, style: RMType.body(size: 14, weight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(o.items, style: RMType.body(size: 12.5, color: RM.ink70, height: 1.45)),
                  ]),
                ),
              ]),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: const BoxDecoration(
              color: RM.cardAlt,
              border: Border(top: BorderSide(color: RM.line)),
            ),
            child: Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Tổng', style: RMType.body(size: 11, color: RM.muted)),
                Text(vnd(o.total), style: RMType.body(size: 15, weight: FontWeight.w800)),
              ]),
              const SizedBox(width: 10),
              const Spacer(),
              OutlinedButton(
                onPressed: onOpen,
                style: OutlinedButton.styleFrom(
                  foregroundColor: RM.ink70,
                  side: const BorderSide(color: RM.line),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                ),
                child: Text('Details', style: RMType.body(size: 13, weight: FontWeight.w700, color: RM.ink70)),
              ),
              if (o.status != 'done') ...[
                const SizedBox(width: 8),
                Flexible(
                  child: FilledButton(
                    onPressed: () {
                      onAdvance?.call();
                      rmToast(context, '#${o.id} → ${statusStyle[nextStatus[o.status]]!.label}');
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: ss.color,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.check_rounded, size: 15, color: Colors.white),
                      const SizedBox(width: 5),
                      Flexible(child: Text(nextAction[o.status]!, maxLines: 1, overflow: TextOverflow.ellipsis, style: RMType.body(size: 13, weight: FontWeight.w700, color: Colors.white))),
                    ]),
                  ),
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}

class DenseRow extends StatelessWidget {
  const DenseRow(
      {super.key,
      required this.o,
      required this.onOpen,
      this.onAdvance});
  final Order o;
  final VoidCallback onOpen;
  final VoidCallback? onAdvance;

  @override
  Widget build(BuildContext context) {
    final ss = statusStyle[o.status]!;
    return InkWell(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: RM.line))),
        child: Row(children: [
          Container(width: 4, height: 40, decoration: BoxDecoration(color: channelColor[o.ch], borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('#${o.id.substring(0,8).toUpperCase()}', style: RMType.body(size: 13.5, weight: FontWeight.w800)),
                const SizedBox(width: 7),
                Flexible(child: Text(o.cust, maxLines: 1, overflow: TextOverflow.ellipsis, style: RMType.body(size: 12.5, weight: FontWeight.w600, color: RM.ink70))),
                if (o.late) ...[
                  const SizedBox(width: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: RM.dangerSoft, borderRadius: BorderRadius.circular(6)),
                    child: Text('LATE', style: RMType.body(size: 10, weight: FontWeight.w800, color: RM.danger)),
                  ),
                ],
              ]),
              Text(o.items, maxLines: 1, overflow: TextOverflow.ellipsis, style: RMType.body(size: 12, color: RM.muted)),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(vnd(o.total), style: RMType.body(size: 13, weight: FontWeight.w700)),
            Text('${ss.label} · ${o.time}', style: RMType.body(size: 10.5, weight: FontWeight.w700, color: ss.color)),
          ]),
          if (o.status != 'done') ...[
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () {
                onAdvance?.call();
                rmToast(context, '#${o.id} advanced');
              },
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: ss.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.check_rounded, size: 18, color: ss.color),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Order detail body (shared by detail page + tablet pane)
// ─────────────────────────────────────────────────────────────────────

List<({String name, int qty})> _parseLines(String items) {
  return items.split(',').map((s) {
    final m = RegExp(r'^(.*?)\s*×\s*(\d+)$').firstMatch(s.trim());
    if (m != null) return (name: m.group(1)!, qty: int.parse(m.group(2)!));
    return (name: s.trim(), qty: 1);
  }).toList();
}

class OrderDetailBody extends StatelessWidget {
  const OrderDetailBody({super.key, required this.o, this.showBack = false});
  final Order? o;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final order = o;
    if (order == null) {
      return Center(child: Text('Select an order', style: RMType.body(size: 14, color: RM.muted)));
    }
    final ss = statusStyle[order.status]!;
    final lines = _parseLines(order.items);
    return Column(
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(showBack ? 16 : 24, showBack ? 2 : 20, 20, 14),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: RM.line))),
          child: Row(children: [
            if (showBack) ...[
              GestureDetector(onTap: () => Navigator.of(context).maybePop(), child: const RmIcon('arrowL', size: 22, color: RM.ink)),
              const SizedBox(width: 11),
            ],
            Text('Order #${order.id}', style: RMType.display(size: showBack ? 19 : 24)),
            const SizedBox(width: 11),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(color: ss.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(9)),
              child: Text(ss.label, style: RMType.body(size: 11.5, weight: FontWeight.w700, color: ss.color)),
            ),
            if (order.late) ...[
              const Spacer(),
              const RmIcon('clock', size: 14, color: RM.danger),
              const SizedBox(width: 5),
              Text('Running late', style: RMType.body(size: 12, weight: FontWeight.w700, color: RM.danger)),
            ],
          ]),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.symmetric(horizontal: showBack ? 20 : 24, vertical: showBack ? 16 : 18),
            children: [
              SoftCard(
                child: Row(children: [
                  Avatar(name: order.cust, seed: order.seed, size: 40),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(order.cust, style: RMType.body(size: 14.5, weight: FontWeight.w700)),
                      Text('${channelLabel[order.ch]} · ${order.time}', style: RMType.body(size: 12, color: RM.muted)),
                    ]),
                  ),
                  GestureDetector(
                    onTap: () => rmToast(context, 'Calling customer…'),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: RM.herbSoft, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.call_outlined, size: 18, color: RM.herb),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              Text('ITEMS', style: RMType.body(size: 12, weight: FontWeight.w700, color: RM.muted, letterSpacing: 0.4)),
              const SizedBox(height: 8),
              for (int i = 0; i < lines.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: RM.line))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 30, child: Text('${lines[i].qty}×', style: RMType.body(size: 14, weight: FontWeight.w800, color: RM.brand))),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(lines[i].name, style: RMType.body(size: 14.5, weight: FontWeight.w600)),
                        if (i == 0 && order.note != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text('“${order.note}”', style: RMType.body(size: 12.5, color: RM.muted)),
                          ),
                      ]),
                    ),
                  ]),
                ),
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Tổng', style: RMType.body(size: 16, weight: FontWeight.w700)),
                Text(vnd(order.total), style: RMType.display(size: 22, color: RM.brandDeep)),
              ]),
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(showBack ? 20 : 24, 14, showBack ? 20 : 24, showBack ? 22 : 16),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: RM.line))),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => rmToast(context, 'Bill sent to printer'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: RM.ink70,
                  side: const BorderSide(color: RM.line, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Print bill', style: RMType.body(size: 14.5, weight: FontWeight.w700, color: RM.ink70)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: order.status != 'done'
                  ? Consumer(builder: (context, ref, _) {
                      return FilledButton.icon(
                        onPressed: () {
                          final ns = nextStatus[order.status];
                          if (ns != null) {
                            ref
                                .read(ordersNotifierProvider.notifier)
                                .advanceStatus(order.id, ns);
                          }
                          rmToast(context, '#${order.id} → ${statusStyle[nextStatus[order.status]]!.label}');
                          if (showBack) Navigator.of(context).maybePop();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: RM.herb,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.check_rounded, size: 18, color: Colors.white),
                        label: Text(nextAction[order.status]!, style: RMType.body(size: 14.5, weight: FontWeight.w700, color: Colors.white)),
                      );
                    })
                  : FilledButton(
                      onPressed: null,
                      style: FilledButton.styleFrom(
                        disabledBackgroundColor: RM.line,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('Completed', style: RMType.body(size: 14.5, weight: FontWeight.w700, color: RM.faint)),
                    ),
            ),
          ]),
        ),
      ],
    );
  }
}

class OrderDetailPage extends ConsumerWidget {
  const OrderDetailPage({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authNotifierProvider);
    final workspaceId = auth.activeWorkspaceId ?? '';
    final ordersAsync = ref.watch(ordersProvider(workspaceId));

    return Scaffold(
      backgroundColor: RM.cream,
      body: SafeArea(
        child: ordersAsync.when(
          data: (driftOrders) {
            final uiOrders = driftOrders.map(_toUiOrder).toList();
            final o = uiOrders.isEmpty
                ? null
                : uiOrders.firstWhere((x) => x.id == id,
                    orElse: () => uiOrders.first);
            return OrderDetailBody(o: o, showBack: true);
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, s) => const Center(child: Text('Không tải được đơn hàng')),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// New-order composer (bottom sheet)
// ─────────────────────────────────────────────────────────────────────

Future<bool?> showNewOrderComposer(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: RM.cream,
    builder: (_) => const _NewOrderComposer(),
  );
}

class _NewOrderComposer extends ConsumerStatefulWidget {
  const _NewOrderComposer();
  @override
  ConsumerState<_NewOrderComposer> createState() => _NewOrderComposerState();
}

class _NewOrderComposerState extends ConsumerState<_NewOrderComposer> {
  final Map<String, int> _qty = {};
  final _name = TextEditingController();

  // Compute total from actual product prices in the live menu.
  int _computeTotal(List<drift.Product> menu) =>
      menu.fold(0, (s, p) => s + (_qty[p.id] ?? 0) * p.price);

  int get _count => _qty.values.fold(0, (s, n) => s + n);

  void _bump(String id, int d) {
    setState(() {
      final v = ((_qty[id] ?? 0) + d).clamp(0, 99);
      if (v == 0) {
        _qty.remove(id);
      } else {
        _qty[id] = v;
      }
    });
  }

  void _create(List<drift.Product> menu) {
    final items = menu
        .where((p) => _qty[p.id] != null)
        .map((p) => '${p.name} ×${_qty[p.id]}')
        .join(', ');
    final custName = _name.text.trim().isEmpty ? 'Khách lẻ · Walk-in' : _name.text.trim();
    ref.read(ordersNotifierProvider.notifier).createOrder(
      channel: 'walkin',
      customerName: custName,
      itemsSummary: items,
      totalAmount: _computeTotal(menu),
    );
    Navigator.of(context).pop(true);
    rmToast(context, 'Đã tạo đơn hàng');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wsId = ref.watch(authNotifierProvider).activeWorkspaceId ?? '';
    final custAsync = ref.watch(customersProvider(wsId));
    final suggestions = custAsync.maybeWhen(data: (d) => d.take(6).toList(), orElse: () => []);
    final menu = ref.watch(productsProvider(wsId)).maybeWhen(
      data: (d) => d.where((p) => p.isActive).toList(),
      orElse: () => <drift.Product>[],
    );
    final total = _computeTotal(menu);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.86),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(children: [
                Expanded(child: Text('New order', style: RMType.display(size: 20))),
                GestureDetector(onTap: () => Navigator.of(context).pop(), child: const RmIcon('close', size: 24, color: RM.ink)),
              ]),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                shrinkWrap: true,
                children: [
                  SoftCard(
                    radius: 14,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('CUSTOMER', style: RMType.body(size: 12, weight: FontWeight.w700, color: RM.muted, letterSpacing: 0.4)),
                      const SizedBox(height: 9),
                      _Field(controller: _name, hint: 'Walk-in — or type a name', fill: RM.cream),
                      if (suggestions.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(children: [
                            for (final c in suggestions) ...[
                              Builder(builder: (context) {
                                final on = _name.text == c.name;
                                return GestureDetector(
                                  onTap: () => setState(() => _name.text = on ? '' : c.name),
                                  child: Container(
                                    padding: const EdgeInsets.fromLTRB(5, 5, 11, 5),
                                    decoration: BoxDecoration(
                                      color: on ? RM.brandSoft : RM.card,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(color: on ? RM.brand : RM.line),
                                    ),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      Avatar(name: c.name, seed: c.seed, size: 22),
                                      const SizedBox(width: 6),
                                      Text(c.name.split(' ').reversed.take(2).toList().reversed.join(' '),
                                          style: RMType.body(size: 12.5, weight: FontWeight.w600, color: on ? RM.brandDeep : RM.ink70)),
                                    ]),
                                  ),
                                );
                              }),
                              const SizedBox(width: 8),
                            ],
                          ]),
                        ),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 10),
                  if (menu.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: Text('No products yet — add some from Menu & Stock.', style: RMType.body(size: 13, color: RM.muted))),
                    )
                  else
                    for (final p in menu) ...[
                      SoftCard(
                        radius: 14,
                        padding: const EdgeInsets.all(10),
                        child: Row(children: [
                          FoodSlot(seed: p.id.hashCode.abs() % 6, width: 46, height: 46, radius: 11),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(p.name, style: RMType.body(size: 14, weight: FontWeight.w700)),
                              Text(vnd(p.price), style: RMType.body(size: 12.5, weight: FontWeight.w700, color: RM.brandDeep)),
                            ]),
                          ),
                          _Stepper(n: _qty[p.id] ?? 0, onMinus: () => _bump(p.id, -1), onPlus: () => _bump(p.id, 1)),
                        ]),
                      ),
                      const SizedBox(height: 10),
                    ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: RM.line))),
              child: Row(children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$_count item${_count == 1 ? '' : 's'}', style: RMType.body(size: 11.5, color: RM.muted)),
                  Text(vnd(total), style: RMType.display(size: 22, color: RM.brandDeep)),
                ]),
                const SizedBox(width: 14),
                Expanded(
                  child: FilledButton(
                    onPressed: _count > 0 ? () => _create(menu) : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: RM.brand,
                      disabledBackgroundColor: RM.line,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text('Create order', style: RMType.body(size: 15, weight: FontWeight.w700, color: _count > 0 ? Colors.white : RM.faint)),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.n, required this.onMinus, required this.onPlus});
  final int n;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _RoundBtn(label: '−', filled: false, enabled: n > 0, onTap: onMinus),
      SizedBox(width: 32, child: Text('$n', textAlign: TextAlign.center, style: RMType.body(size: 15, weight: FontWeight.w700))),
      _RoundBtn(label: '+', filled: true, enabled: true, onTap: onPlus),
    ]);
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.label, required this.filled, required this.enabled, required this.onTap});
  final String label;
  final bool filled;
  final bool enabled;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? RM.brand : RM.card,
          borderRadius: BorderRadius.circular(9),
          border: filled ? null : Border.all(color: RM.line),
        ),
        child: Text(label, style: RMType.body(size: 19, weight: FontWeight.w700, color: filled ? Colors.white : (enabled ? RM.ink : RM.faint))),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.hint, this.fill = RM.card});
  final TextEditingController controller;
  final String hint;
  final Color fill;
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: RMType.body(size: 14),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: fill,
        hintText: hint,
        hintStyle: RMType.body(size: 14, color: RM.faint),
        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: RM.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: RM.brand, width: 1.5)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// MOBILE
// ─────────────────────────────────────────────────────────────────────

class OrdersMobile extends ConsumerStatefulWidget {
  const OrdersMobile({super.key, this.dense = false});
  final bool dense;
  @override
  ConsumerState<OrdersMobile> createState() => _OrdersMobileState();
}

class _OrdersMobileState extends ConsumerState<OrdersMobile> {
  String _channel = 'all';
  String _status = 'cooking';
  bool _searchOpen = false;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Sync from server on screen mount so local Drift stays up-to-date.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(ordersNotifierProvider.notifier).refreshFromServer();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authNotifierProvider);
    final workspaceId = auth.activeWorkspaceId ?? '';
    final ordersAsync = ref.watch(ordersProvider(workspaceId));

    return ordersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => const Center(child: Text('Không tải được danh sách đơn')),
      data: (driftOrders) {
        final orders = driftOrders.map(_toUiOrder).toList();
        final byChannel = orders
            .where((o) => _channel == 'all' || o.ch == _channel)
            .toList();
        final counts = {
          for (final t in statusTabs)
            t.$1: byChannel.where((o) => o.status == t.$1).length
        };
        final q = _search.text.trim().toLowerCase();
        final list = byChannel
            .where((o) =>
                o.status == _status &&
                (q.isEmpty ||
                    ('${o.id}${o.cust}${o.items}')
                        .toLowerCase()
                        .contains(q)))
            .toList();
        final activeCount =
            orders.where((o) => o.status != 'done').length;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Orders', style: RMType.display(size: 24)),
                        Text(
                            '${orders.length} today · $activeCount active',
                            style: RMType.body(
                                size: 12.5, color: RM.muted)),
                      ]),
                ),
                _IconBtn(
                    icon: 'search',
                    active: _searchOpen,
                    onTap: () => setState(() {
                          _searchOpen = !_searchOpen;
                          _search.clear();
                        })),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () => showNewOrderComposer(context).then(
                      (created) {
                    if (created == true) setState(() => _status = 'new');
                  }),
                  style: FilledButton.styleFrom(
                      backgroundColor: RM.brand,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13))),
                  icon: const Icon(Icons.add_rounded,
                      size: 18, color: Colors.white),
                  label: Text('Mới',
                      style: RMType.body(
                          size: 13.5,
                          weight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (_searchOpen)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: SearchField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          onClose: () => setState(() {
                                _searchOpen = false;
                                _search.clear();
                              })),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: ChannelChips(
                        value: _channel,
                        onChange: (v) => setState(() => _channel = v)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: StatusTabs(
                        value: _status,
                        onChange: (v) => setState(() => _status = v),
                        counts: counts),
                  ),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(30, 60, 30, 60),
                      child: Column(children: [
                        Icon(AppIcons.of('orders'),
                            size: 40, color: RM.faint),
                        const SizedBox(height: 12),
                        Text(
                            'Không có đơn ${statusStyle[_status]!.label.toLowerCase()}',
                            style: RMType.body(
                                size: 14,
                                weight: FontWeight.w600,
                                color: RM.muted)),
                      ]),
                    )
                  else if (widget.dense)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 100),
                      child: Column(
                          children: [
                        for (final o in list)
                          DenseRow(
                            o: o,
                            onOpen: () => _open(o),
                            onAdvance: nextStatus[o.status] != null
                                ? () => ref
                                    .read(ordersNotifierProvider.notifier)
                                    .advanceStatus(
                                        o.id, nextStatus[o.status]!)
                                : null,
                          )
                      ]),
                    )
                  else
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(20, 14, 20, 100),
                      child: Column(children: [
                        for (int i = 0; i < list.length; i++) ...[
                          if (i > 0) const SizedBox(height: 12),
                          OrderCard(
                            o: list[i],
                            onOpen: () => _open(list[i]),
                            onAdvance: nextStatus[list[i].status] != null
                                ? () => ref
                                    .read(ordersNotifierProvider.notifier)
                                    .advanceStatus(list[i].id,
                                        nextStatus[list[i].status]!)
                                : null,
                          ),
                        ],
                      ]),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _open(Order o) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => OrderDetailPage(id: o.id)));
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.active, required this.onTap});
  final String icon;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: active ? RM.brandSoft : RM.card,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: active ? RM.brand : RM.line),
        ),
        child: Icon(AppIcons.of(icon), size: 20, color: active ? RM.brand : RM.ink),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// TABLET — list + detail split view
// ─────────────────────────────────────────────────────────────────────

class OrdersTablet extends ConsumerStatefulWidget {
  const OrdersTablet({super.key});
  @override
  ConsumerState<OrdersTablet> createState() => _OrdersTabletState();
}

class _OrdersTabletState extends ConsumerState<OrdersTablet> {
  String _channel = 'all';
  String _status = 'cooking';
  String _selId = '1042';
  bool _searchOpen = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final portrait =
        MediaQuery.sizeOf(context).height > MediaQuery.sizeOf(context).width;
    final auth = ref.watch(authNotifierProvider);
    final workspaceId = auth.activeWorkspaceId ?? '';
    final ordersAsync = ref.watch(ordersProvider(workspaceId));

    return ordersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => const Center(child: Text('Không tải được danh sách đơn')),
      data: (driftOrders) {
        final orders = driftOrders.map(_toUiOrder).toList();
        final byChannel = orders
            .where((o) => _channel == 'all' || o.ch == _channel)
            .toList();
        final counts = {
          for (final t in statusTabs)
            t.$1: byChannel.where((o) => o.status == t.$1).length
        };
        final q = _search.text.trim().toLowerCase();
        final list = byChannel
            .where((o) =>
                o.status == _status &&
                (q.isEmpty ||
                    ('${o.id}${o.cust}${o.items}')
                        .toLowerCase()
                        .contains(q)))
            .toList();
        final matches = orders.where((o) => o.id == _selId).toList();
        final sel = matches.isEmpty ? null : matches.first;

        final listPane = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
              child: Row(children: [
                Expanded(
                    child:
                        Text('Orders', style: RMType.display(size: 24))),
                _IconBtn(
                    icon: 'search',
                    active: _searchOpen,
                    onTap: () => setState(() {
                          _searchOpen = !_searchOpen;
                          _search.clear();
                        })),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () =>
                      showNewOrderComposer(context).then((c) {
                    if (c == true) setState(() => _status = 'new');
                  }),
                  style: FilledButton.styleFrom(
                      backgroundColor: RM.brand,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  icon: const Icon(Icons.add_rounded,
                      size: 18, color: Colors.white),
                  label: Text('Đơn mới',
                      style: RMType.body(
                          size: 14,
                          weight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ]),
            ),
            if (_searchOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
                child: SearchField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    onClose: () => setState(() {
                          _searchOpen = false;
                          _search.clear();
                        })),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
              child: ChannelChips(
                  value: _channel,
                  onChange: (v) => setState(() => _channel = v)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: StatusTabs(
                  value: _status,
                  onChange: (v) => setState(() => _status = v),
                  counts: counts),
            ),
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Text('Chưa có đơn hàng',
                          style:
                              RMType.body(size: 14, color: RM.muted)))
                  : ListView.separated(
                      padding:
                          const EdgeInsets.fromLTRB(22, 14, 22, 22),
                      itemCount: list.length,
                      separatorBuilder: (ctx, idx) =>
                          const SizedBox(height: 11),
                      itemBuilder: (context, i) => _TabletOrderRow(
                          o: list[i],
                          selected: list[i].id == _selId,
                          onTap: () =>
                              setState(() => _selId = list[i].id)),
                    ),
            ),
          ],
        );

        return Container(
          color: RM.cream,
          child: Flex(
            direction: portrait ? Axis.vertical : Axis.horizontal,
            children: [
              SizedBox(
                width: portrait ? null : 470,
                height: portrait
                    ? MediaQuery.sizeOf(context).height * 0.46
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
              Expanded(
                  child: Container(
                      color: RM.card,
                      child: OrderDetailBody(o: sel))),
            ],
          ),
        );
      },
    );
  }
}

class _TabletOrderRow extends StatelessWidget {
  const _TabletOrderRow({required this.o, required this.selected, required this.onTap});
  final Order o;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? RM.card : RM.cardAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? RM.brand : RM.line, width: 1.5),
        ),
        child: Row(children: [
          FoodSlot(seed: o.seed, width: 56, height: 56, radius: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('#${o.id.substring(0,8).toUpperCase()}', style: RMType.body(size: 15, weight: FontWeight.w800)),
                const SizedBox(width: 7),
                StatusDot(channelColor[o.ch]!, size: 7),
                const SizedBox(width: 4),
                Text(channelLabel[o.ch]!, style: RMType.body(size: 11, weight: FontWeight.w700, color: channelColor[o.ch]!)),
                if (o.late) ...[
                  const SizedBox(width: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: RM.dangerSoft, borderRadius: BorderRadius.circular(6)),
                    child: Text('LATE', style: RMType.body(size: 10, weight: FontWeight.w800, color: RM.danger)),
                  ),
                ],
              ]),
              Text(o.cust, style: RMType.body(size: 12.5, color: RM.ink70)),
              Text(o.items, maxLines: 1, overflow: TextOverflow.ellipsis, style: RMType.body(size: 12, color: RM.muted)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(vnd(o.total), style: RMType.body(size: 14, weight: FontWeight.w800)),
            Text(statusStyle[o.status]!.label, style: RMType.body(size: 11, weight: FontWeight.w700, color: statusStyle[o.status]!.color)),
          ]),
        ]),
      ),
    );
  }
}
