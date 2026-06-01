import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_icons.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/products/product_providers.dart';
import '../../data/drift/app_database.dart';
import '../../data/mock_data.dart' show productCats, stockStyle;
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/forms.dart';
import '../../widgets/primitives.dart';

String _stockLabel(Product p) =>
    p.quantity == 0 ? 'Hết hàng' : '${p.quantity} còn';

// ── Add-dish composer ────────────────────────────────────────────────

Future<bool?> showAddDishComposer(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: RM.cream,
    builder: (_) => const _AddDishComposer(),
  );
}

class _AddDishComposer extends ConsumerStatefulWidget {
  const _AddDishComposer();
  @override
  ConsumerState<_AddDishComposer> createState() => _AddDishComposerState();
}

class _AddDishComposerState extends ConsumerState<_AddDishComposer> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  String _cat = 'Mains';

  bool get _valid =>
      _name.text.trim().isNotEmpty && (int.tryParse(_price.text) ?? 0) > 0;

  Future<void> _create() async {
    await ref.read(productsNotifierProvider.notifier).createProduct(
          name: _name.text.trim(),
          price: int.parse(_price.text),
        );
    if (mounted) {
      Navigator.of(context).pop(true);
      rmToast(context, 'Đã thêm món vào thực đơn');
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
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
          const SheetHeader('Thêm món'),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Column(children: [
              RmTextField(
                label: 'TÊN MÓN',
                controller: _name,
                hint: 'VD: Phở bò tái',
                autofocus: true,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              RmTextField(
                label: 'GIÁ (₫)',
                controller: _price,
                hint: '55000',
                keyboard: TextInputType.number,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'CATEGORY',
                  style: RMType.body(
                    size: 12,
                    weight: FontWeight.w700,
                    color: RM.muted,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in productCats.where((c) => c != 'All'))
                    PillChip(
                      label: c,
                      active: c == _cat,
                      activeColor: RM.brand,
                      onTap: () => setState(() => _cat = c),
                    ),
                ],
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: SheetSubmit(
              label: 'Thêm vào thực đơn',
              enabled: _valid,
              onPressed: _create,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Low-stock banner ─────────────────────────────────────────────────

class _LowStockBanner extends StatelessWidget {
  const _LowStockBanner({required this.count, this.compact = false});
  final int count;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    if (compact) {
      return GestureDetector(
        onTap: () => rmToast(context, 'Reviewing low stock'),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: RM.goldSoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const RmIcon('box', size: 22, color: RM.gold),
              const SizedBox(height: 8),
              Text(
                '$count món sắp hết hàng',
                style:
                    RMType.body(size: 13.5, weight: FontWeight.w700),
              ),
              Text(
                'Xem và đặt lại',
                style: RMType.body(size: 12, color: RM.ink70),
              ),
            ],
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: () => rmToast(context, 'Reviewing low stock'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: RM.goldSoft,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          const RmIcon('box', size: 22, color: RM.gold),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count dishes need restocking',
                  style: RMType.body(size: 13.5, weight: FontWeight.w700),
                ),
                Text(
                  'Nhấn để xem và đặt lại nguyên liệu',
                  style: RMType.body(size: 12, color: RM.ink70),
                ),
              ],
            ),
          ),
          const RmIcon('chevR', size: 18, color: RM.gold),
        ]),
      ),
    );
  }
}

// ── MOBILE ───────────────────────────────────────────────────────────

class ProductsMobile extends ConsumerStatefulWidget {
  const ProductsMobile({super.key});
  @override
  ConsumerState<ProductsMobile> createState() => _ProductsMobileState();
}

class _ProductsMobileState extends ConsumerState<ProductsMobile> {
  String _cat = 'All';
  bool _searchOpen = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workspaceId =
        ref.watch(authNotifierProvider).activeWorkspaceId ?? '';
    final productsAsync = ref.watch(productsProvider(workspaceId));

    return productsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Text(
          'Failed to load products',
          style: RMType.body(size: 14, color: RM.muted),
        ),
      ),
      data: (products) {
        final q = _search.text.trim().toLowerCase();
        final list = products
            .where((p) =>
                (_cat == 'All' || p.cat == _cat) &&
                (q.isEmpty || p.name.toLowerCase().contains(q)))
            .toList();
        final lowCount =
            products.where((p) => p.status != 'ok' || p.quantity <= 8).length;

        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Thực đơn & Kho', style: RMType.display(size: 24)),
                    Text(
                      '${products.length} dishes · $lowCount món sắp hết hàng',
                      style: RMType.body(size: 12.5, color: RM.muted),
                    ),
                  ],
                ),
              ),
              _SquareBtn(
                icon: 'search',
                active: _searchOpen,
                onTap: () => setState(() {
                  _searchOpen = !_searchOpen;
                  _search.clear();
                }),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => showAddDishComposer(context)
                    .then((c) {
                  if (c == true) setState(() => _cat = 'All');
                }),
                style: FilledButton.styleFrom(
                  backgroundColor: RM.brand,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                icon: const Icon(Icons.add_rounded,
                    size: 18, color: Colors.white),
                label: Text(
                  'Add',
                  style: RMType.body(
                    size: 13.5,
                    weight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 100),
              children: [
                if (_searchOpen)
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: _SearchInline(
                      controller: _search,
                      hint: 'Tìm món…',
                      onChanged: () => setState(() {}),
                      onClose: () => setState(() {
                        _searchOpen = false;
                        _search.clear();
                      }),
                    ),
                  ),
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final c in productCats) ...[
                        PillChip(
                          label: c,
                          active: c == _cat,
                          onTap: () =>
                              setState(() => _cat = c),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ]),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: _LowStockBanner(count: lowCount),
                ),
                if (list.isEmpty)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        'Không tìm thấy món nào',
                        style: RMType.body(
                            size: 14, color: RM.muted),
                      ),
                    ),
                  )
                else
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(children: [
                      for (int i = 0; i < list.length; i++) ...[
                        if (i > 0)
                          const SizedBox(height: 10),
                        _ProductRow(p: list[i]),
                      ],
                    ]),
                  ),
              ],
            ),
          ),
        ]);
      },
    );
  }
}

class _ProductRow extends ConsumerWidget {
  const _ProductRow({required this.p});
  final Product p;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stockStyle[p.status]!;
    return Opacity(
      opacity: p.isActive ? 1 : 0.62,
      child: SoftCard(
        onTap: () => rmToast(context, 'Sửa · ${p.name}'),
        child: Row(children: [
          FoodSlot(seed: p.seed, width: 56, height: 56, radius: 13),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RMType.body(
                    size: 14.5,
                    weight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Row(children: [
                  Text(
                    vnd(p.price),
                    style: RMType.body(
                      size: 14,
                      weight: FontWeight.w800,
                      color: RM.brandDeep,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: s.bg,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      _stockLabel(p),
                      style: RMType.body(
                        size: 11.5,
                        weight: FontWeight.w700,
                        color: s.color,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 3),
                Text(
                  p.isActive
                      ? '${p.soldToday} sold today'
                      : 'Ẩn khỏi thực đơn',
                  style: RMType.body(size: 11.5, color: RM.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          RmToggle(
            value: p.isActive,
            onTap: () {
              // Toggle isActive locally via notifier.
              ref.read(productsNotifierProvider.notifier).deleteProduct(p.id);
            },
          ),
        ]),
      ),
    );
  }
}

// ── TABLET ───────────────────────────────────────────────────────────

class ProductsTablet extends ConsumerStatefulWidget {
  const ProductsTablet({super.key});
  @override
  ConsumerState<ProductsTablet> createState() => _ProductsTabletState();
}

class _ProductsTabletState extends ConsumerState<ProductsTablet> {
  String _cat = 'All';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final portrait = MediaQuery.sizeOf(context).height >
        MediaQuery.sizeOf(context).width;

    final workspaceId =
        ref.watch(authNotifierProvider).activeWorkspaceId ?? '';
    final productsAsync = ref.watch(productsProvider(workspaceId));

    return productsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Text(
          'Failed to load products',
          style: RMType.body(size: 15, color: RM.muted),
        ),
      ),
      data: (products) {
        final q = _search.text.trim().toLowerCase();
        final list = products
            .where((p) =>
                (_cat == 'All' || p.cat == _cat) &&
                (q.isEmpty || p.name.toLowerCase().contains(q)))
            .toList();
        final lowCount =
            products.where((p) => p.status != 'ok' || p.quantity <= 8).length;

        return Container(
          color: RM.cream,
          child: Row(children: [
            // category sidebar
            Container(
              width: portrait ? 184 : 210,
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: RM.line)),
              ),
              padding:
                  const EdgeInsets.fromLTRB(16, 22, 16, 16),
              child: ListView(children: [
                Text(
                  'CATEGORIES',
                  style: RMType.body(
                    size: 12,
                    weight: FontWeight.w700,
                    color: RM.muted,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 12),
                for (final c in productCats)
                  GestureDetector(
                    onTap: () => setState(() => _cat = c),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 11),
                      decoration: BoxDecoration(
                        color: c == _cat
                            ? RM.brandSoft
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Text(
                            c == 'All' ? 'Tất cả' : c,
                            style: RMType.body(
                              size: 14,
                              weight: c == _cat
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: c == _cat
                                  ? RM.brandDeep
                                  : RM.ink70,
                            ),
                          ),
                        ),
                        Text(
                          '${c == 'All' ? products.length : products.where((p) => p.cat == c).length}',
                          style: RMType.body(
                            size: 12,
                            weight: FontWeight.w700,
                            color: c == _cat ? RM.brand : RM.faint,
                          ),
                        ),
                      ]),
                    ),
                  ),
                const SizedBox(height: 16),
                _LowStockBanner(count: lowCount, compact: true),
              ]),
            ),
            // grid
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(26, 22, 26, 26),
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        'Thực đơn & Kho',
                        style: RMType.display(size: 26),
                      ),
                    ),
                    SizedBox(
                      width: portrait ? 200 : 260,
                      child: _SearchInline(
                        controller: _search,
                        hint: 'Tìm món…',
                        plain: true,
                        onChanged: () => setState(() {}),
                        onClose: () {},
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: () => showAddDishComposer(context)
                          .then((c) {
                        if (c == true) setState(() => _cat = 'All');
                      }),
                      style: FilledButton.styleFrom(
                        backgroundColor: RM.brand,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.add_rounded,
                          size: 18, color: Colors.white),
                      label: Text(
                        'Thêm món',
                        style: RMType.body(
                          size: 14,
                          weight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 18),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 60),
                      child: Center(
                        child: Text(
                          'Không tìm thấy món nào',
                          style: RMType.body(size: 15, color: RM.muted),
                        ),
                      ),
                    )
                  else
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: portrait ? 2 : 3,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.92,
                      children: [
                        for (final p in list) _ProductCardTablet(p: p)
                      ],
                    ),
                ],
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _ProductCardTablet extends ConsumerWidget {
  const _ProductCardTablet({required this.p});
  final Product p;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stockStyle[p.status]!;
    return Opacity(
      opacity: p.isActive ? 1 : 0.62,
      child: GestureDetector(
        onTap: () => rmToast(context, 'Sửa · ${p.name}'),
        child: Container(
          decoration: BoxDecoration(
            color: RM.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: RM.line),
            boxShadow: [
              BoxShadow(
                color: RM.ink.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              )
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(children: [
                FoodSlot(
                    seed: p.seed,
                    height: 120,
                    radius: 0,
                    width: double.infinity),
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _stockLabel(p),
                      style: RMType.body(
                        size: 11,
                        weight: FontWeight.w700,
                        color: s.color,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: RmToggle(
                    value: p.isActive,
                    onTap: () => ref
                        .read(productsNotifierProvider.notifier)
                        .deleteProduct(p.id),
                  ),
                ),
              ]),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RMType.body(
                          size: 15, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Row(children: [
                      Text(
                        vnd(p.price),
                        style: RMType.display(
                            size: 18, color: RM.brandDeep),
                      ),
                      const Spacer(),
                      Text(
                        '${p.soldToday} sold',
                        style: RMType.body(
                          size: 12,
                          weight: FontWeight.w600,
                          color: RM.muted,
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── small helpers ────────────────────────────────────────────────────

class _SquareBtn extends StatelessWidget {
  const _SquareBtn(
      {required this.icon, required this.active, required this.onTap});
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
        child: Icon(AppIcons.of(icon),
            size: 19, color: active ? RM.brand : RM.ink),
      ),
    );
  }
}

class _SearchInline extends StatelessWidget {
  const _SearchInline({
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onClose,
    this.plain = false,
  });
  final TextEditingController controller;
  final String hint;
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
                    color: RM.brandSoft,
                    blurRadius: 0,
                    spreadRadius: 3)
              ],
      ),
      child: Row(children: [
        RmIcon('search', size: 18, color: plain ? RM.muted : RM.brand),
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
              hintText: hint,
              hintStyle:
                  RMType.body(size: 13.5, color: RM.faint),
            ),
          ),
        ),
        if (!plain)
          GestureDetector(
            onTap: onClose,
            child: const RmIcon('close', size: 18, color: RM.muted),
          ),
      ]),
    );
  }
}
