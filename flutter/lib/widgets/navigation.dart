import 'package:flutter/material.dart';
import '../core/app_icons.dart';
import '../theme/tokens.dart';
import 'primitives.dart';

/// The five primary destinations (mirrors NAV_TABS in tokens.jsx).
const navTabs = [
  ('home', 'Home', 'home'),
  ('orders', 'Orders', 'orders'),
  ('products', 'Menu', 'products'),
  ('content', 'Content', 'content'),
  ('finance', 'Finance', 'finance'),
];

/// Flat bottom navigation bar with active soft-pill + optional badge.
class RiMiBottomNav extends StatelessWidget {
  const RiMiBottomNav({
    super.key,
    required this.activeIndex,
    required this.onTap,
    this.badges = const {},
  });
  final int activeIndex;
  final ValueChanged<int> onTap;
  final Map<int, int> badges; // index -> count

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: RM.card,
        border: Border(top: BorderSide(color: RM.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (int i = 0; i < navTabs.length; i++)
                Expanded(child: _Tab(
                  icon: navTabs[i].$3,
                  label: navTabs[i].$2,
                  active: i == activeIndex,
                  badge: badges[i],
                  onTap: () => onTap(i),
                )),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.icon, required this.label, required this.active, required this.onTap, this.badge});
  final String icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final color = active ? RM.brand : RM.ink70;
    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: active ? 1 : 0.62,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? RM.brandSoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(AppIcons.of(icon), size: 23, color: color),
                ),
                if (badge != null && badge! > 0)
                  Positioned(
                    top: -4,
                    right: 0,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 16),
                      height: 16,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: RM.brand,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: RM.card, width: 2),
                      ),
                      child: Text('${badge!}',
                          style: RMType.body(size: 10, weight: FontWeight.w800, color: Colors.white)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(label,
                style: RMType.body(
                    size: 10.5,
                    weight: active ? FontWeight.w700 : FontWeight.w500,
                    color: color)),
          ],
        ),
      ),
    );
  }
}

/// Left navigation rail used by every tablet layout.
class TabletRail extends StatelessWidget {
  const TabletRail({super.key, required this.activeIndex, required this.onTap, required this.onAi});
  final int activeIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onAi;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: RM.line)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const SizedBox(height: 14),
            const RiMiMark(size: 42, radius: 14),
            const SizedBox(height: 14),
            for (int i = 0; i < navTabs.length; i++)
              _RailItem(
                icon: navTabs[i].$3,
                label: navTabs[i].$2,
                active: i == activeIndex,
                onTap: () => onTap(i),
              ),
            const Spacer(),
            GestureDetector(
              onTap: onAi,
              child: Container(
                width: 54,
                height: 54,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [RM.gold, RM.brand]),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [BoxShadow(color: RM.brand.withValues(alpha: 0.27), blurRadius: 18, offset: const Offset(0, 8))],
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 26),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({required this.icon, required this.label, required this.active, required this.onTap});
  final String icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? RM.brand : RM.ink70;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? RM.brandSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(AppIcons.of(icon), size: 22, color: color),
            const SizedBox(height: 3),
            Text(label,
                style: RMType.body(
                    size: 9.5,
                    weight: active ? FontWeight.w700 : FontWeight.w500,
                    color: color)),
          ],
        ),
      ),
    );
  }
}

/// Floating, draggable AI orb — tap to open AI Team, drag to reposition,
/// snaps to the nearest side. Lives in a Stack overlay over the body.
class DraggableAiOrb extends StatefulWidget {
  const DraggableAiOrb({super.key, required this.onOpen});
  final VoidCallback onOpen;

  @override
  State<DraggableAiOrb> createState() => _DraggableAiOrbState();
}

class _DraggableAiOrbState extends State<DraggableAiOrb> {
  static const double _size = 56;
  Offset? _pos; // top-left within the stack
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth, h = c.maxHeight;
      _pos ??= Offset(w - _size - 16, h - _size - 24);

      double clampX(double x) => x.clamp(12.0, w - _size - 12);
      double clampY(double y) => y.clamp(12.0, h - _size - 12);

      return Stack(
        children: [
          AnimatedPositioned(
            duration: _dragging ? Duration.zero : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            left: clampX(_pos!.dx),
            top: clampY(_pos!.dy),
            child: GestureDetector(
              onTap: widget.onOpen,
              onPanStart: (_) => setState(() => _dragging = true),
              onPanUpdate: (e) => setState(() => _pos = _pos! + e.delta),
              onPanEnd: (_) => setState(() {
                _dragging = false;
                final snapLeft = _pos!.dx + _size / 2 < w / 2;
                _pos = Offset(snapLeft ? 12 : w - _size - 12, clampY(_pos!.dy));
              }),
              child: Container(
                width: _size,
                height: _size,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [RM.gold, RM.brand],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2.5),
                  boxShadow: [BoxShadow(color: RM.brand.withValues(alpha: 0.4), blurRadius: 22, offset: const Offset(0, 10))],
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 26),
              ),
            ),
          ),
        ],
      );
    });
  }
}
