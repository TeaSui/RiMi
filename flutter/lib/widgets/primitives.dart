import 'package:flutter/material.dart';
import '../core/app_icons.dart';
import '../theme/tokens.dart';
import '../data/mock_data.dart';

/// Brand logo mark — rounded saffron tile with a noodle-bowl glyph.
class RiMiMark extends StatelessWidget {
  const RiMiMark({super.key, this.size = 40, this.radius = 13});
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: RM.brand,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(Icons.ramen_dining_rounded, color: Colors.white, size: size * 0.58),
    );
  }
}

/// Small status dot.
class StatusDot extends StatelessWidget {
  const StatusDot(this.color, {super.key, this.size = 8});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// Initials avatar with a tint derived from a seed.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.seed = 0, this.size = 38});
  final String name;
  final int seed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tint = RM.avatarTints[seed % RM.avatarTints.length];
    final parts = name.trim().split(RegExp(r'\s+'));
    final initials = parts
        .sublist(parts.length >= 2 ? parts.length - 2 : 0)
        .map((w) => w.isEmpty ? '' : w[0])
        .join()
        .toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: tint[1], shape: BoxShape.circle),
      child: Text(
        initials,
        style: RMType.body(size: size * 0.36, weight: FontWeight.w700, color: tint[0]),
      ),
    );
  }
}

/// Warm duotone food placeholder with a faint utensil watermark.
class FoodSlot extends StatelessWidget {
  const FoodSlot({
    super.key,
    this.seed = 0,
    this.width,
    this.height = 96,
    this.radius = 14,
    this.label,
    this.badge,
  });
  final int seed;
  final double? width;
  final double height;
  final double radius;
  final String? label;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final tint = RM.foodTints[seed % RM.foodTints.length];
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [tint[0], tint[1]],
                ),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 6,
              child: Icon(Icons.restaurant_rounded,
                  size: height * 0.34, color: Colors.white.withValues(alpha: 0.4)),
            ),
            if (badge != null)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(badge!,
                      style: RMType.body(size: 10, weight: FontWeight.w800, color: RM.brandDeep)),
                ),
              ),
            if (label != null)
              Positioned(
                left: 10,
                bottom: 9,
                right: 10,
                child: Text(
                  label!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RMType.body(size: 11, weight: FontWeight.w600, color: Colors.white).copyWith(
                    shadows: const [Shadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1))],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Role-bot icon with the sparkle "AI" badge.
class BotIconView extends StatelessWidget {
  const BotIconView({super.key, required this.bot, this.size = 48});
  final Bot bot;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: bot.bg,
              borderRadius: BorderRadius.circular(size * 0.32),
            ),
            child: Icon(AppIcons.of(bot.icon), size: size * 0.5, color: bot.color),
          ),
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              width: size * 0.34,
              height: size * 0.34,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [RM.gold, RM.brand]),
                borderRadius: BorderRadius.circular(size),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(Icons.auto_awesome_rounded, size: size * 0.18, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// White card with hairline border — the default surface in RiMi.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 16,
    this.color = RM.card,
    this.border = RM.line,
    this.onTap,
    this.shadow = false,
  });
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color color;
  final Color border;
  final VoidCallback? onTap;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border),
        boxShadow: shadow
            ? [BoxShadow(color: RM.ink.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))]
            : null,
      ),
      child: child,
    );
    if (onTap == null) return box;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: box,
    );
  }
}

/// Section header with optional trailing action.
class SectionHead extends StatelessWidget {
  const SectionHead(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(child: Text(title, style: RMType.body(size: 17, weight: FontWeight.w700))),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Text(action!, style: RMType.body(size: 13, weight: FontWeight.w600, color: RM.brand)),
            ),
        ],
      ),
    );
  }
}
