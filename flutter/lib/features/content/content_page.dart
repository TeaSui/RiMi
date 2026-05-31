import 'package:flutter/material.dart';
import '../../app.dart';
import '../../core/app_icons.dart';
import '../../data/mock_data.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/primitives.dart';

const _caption = 'Trời mưa lành lạnh, làm tô bún bò Huế nóng hổi cho ấm bụng nha cả nhà! 🍜 Giao tận nơi trong 30 phút.';
const _hashtags = '#bunbohue #anngon #bepnhahang';

// (name, color)
const _platforms = [
  ('Facebook', RM.info),
  ('Zalo', Color(0xFF0068FF)),
  ('TikTok', RM.ink),
  ('Instagram', Color(0xFFC13584)),
];

class _AiRewriteChip extends StatelessWidget {
  const _AiRewriteChip();
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => AppNav.openChat(bots[1]),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(color: RM.brandSoft, borderRadius: BorderRadius.circular(9)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.auto_awesome_rounded, size: 14, color: RM.brand),
          const SizedBox(width: 5),
          Text('Rewrite with AI', style: RMType.body(size: 12, weight: FontWeight.w700, color: RM.brand)),
        ]),
      ),
    );
  }
}

class _PlatformTile extends StatelessWidget {
  const _PlatformTile({required this.name, required this.color, required this.on, required this.onTap});
  final String name;
  final Color color;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: on ? color.withValues(alpha: 0.08) : RM.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: on ? color : RM.line, width: 1.5),
          ),
          child: Stack(
            children: [
              Column(children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.chat_bubble_outline_rounded, size: 17, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(name, style: RMType.body(size: 10.5, weight: FontWeight.w600, color: on ? color : RM.ink70)),
              ]),
              if (on)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 15,
                    height: 15,
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.check_rounded, size: 11, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow();
  @override
  Widget build(BuildContext context) {
    return SoftCard(
      radius: 14,
      onTap: () => rmToast(context, 'Schedule · Today 17:00'),
      child: Row(children: [
        const RmIcon('calendar', size: 20, color: RM.brand),
        const SizedBox(width: 10),
        Expanded(child: Text('Schedule for later', style: RMType.body(size: 13.5, weight: FontWeight.w600))),
        Text('Today 17:00', style: RMType.body(size: 12.5, color: RM.muted)),
        const SizedBox(width: 6),
        const RmIcon('chevR', size: 17, color: RM.faint),
      ]),
    );
  }
}

// ── MOBILE ───────────────────────────────────────────────────────────

class ContentMobile extends StatefulWidget {
  const ContentMobile({super.key});
  @override
  State<ContentMobile> createState() => _ContentMobileState();
}

class _ContentMobileState extends State<ContentMobile> {
  final Set<String> _picked = {'Facebook'};

  void _toggle(String n) => setState(() => _picked.contains(n) ? _picked.remove(n) : _picked.add(n));

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
        child: Row(children: [
          Expanded(child: Text('New post', style: RMType.display(size: 22))),
          FilledButton(
            onPressed: () => rmToast(context, _picked.isEmpty ? 'Pick a platform first' : 'Posted to ${_picked.join(', ')} 🎉'),
            style: FilledButton.styleFrom(backgroundColor: RM.brand, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text('Post', style: RMType.body(size: 13, weight: FontWeight.w700, color: Colors.white)),
          ),
        ]),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          children: [
            Text('FEATURED DISH', style: RMType.body(size: 12, weight: FontWeight.w700, color: RM.muted, letterSpacing: 0.4)),
            const SizedBox(height: 9),
            Stack(children: [
              const FoodSlot(label: 'Bún bò Huế đặc biệt', seed: 1, height: 150, radius: 18, width: double.infinity),
              Positioned(
                bottom: 10,
                right: 10,
                child: GestureDetector(
                  onTap: () => rmToast(context, 'Pick another dish photo'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(10)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.photo_camera_outlined, size: 15, color: RM.brandDeep),
                      const SizedBox(width: 5),
                      Text('Change', style: RMType.body(size: 12, weight: FontWeight.w700, color: RM.brandDeep)),
                    ]),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: Text('CAPTION', style: RMType.body(size: 12, weight: FontWeight.w700, color: RM.muted, letterSpacing: 0.4))),
              const _AiRewriteChip(),
            ]),
            const SizedBox(height: 9),
            SoftCard(
              radius: 14,
              child: RichText(
                text: TextSpan(style: RMType.body(size: 13.5, color: RM.ink, height: 1.55), children: [
                  const TextSpan(text: '$_caption\n'),
                  TextSpan(text: _hashtags, style: RMType.body(size: 13.5, color: RM.info, height: 1.55)),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            Text('POST TO', style: RMType.body(size: 12, weight: FontWeight.w700, color: RM.muted, letterSpacing: 0.4)),
            const SizedBox(height: 9),
            Row(children: [
              for (int i = 0; i < _platforms.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                _PlatformTile(name: _platforms[i].$1, color: _platforms[i].$2, on: _picked.contains(_platforms[i].$1), onTap: () => _toggle(_platforms[i].$1)),
              ],
            ]),
            const SizedBox(height: 14),
            const _ScheduleRow(),
          ],
        ),
      ),
    ]);
  }
}

// ── TABLET ───────────────────────────────────────────────────────────

class ContentTablet extends StatefulWidget {
  const ContentTablet({super.key});
  @override
  State<ContentTablet> createState() => _ContentTabletState();
}

class _ContentTabletState extends State<ContentTablet> {
  final Set<String> _picked = {'Facebook'};
  void _toggle(String n) => setState(() => _picked.contains(n) ? _picked.remove(n) : _picked.add(n));

  @override
  Widget build(BuildContext context) {
    final portrait = MediaQuery.sizeOf(context).height > MediaQuery.sizeOf(context).width;
    final preview = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PREVIEW', style: RMType.body(size: 12, weight: FontWeight.w700, color: RM.muted, letterSpacing: 0.4)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: RM.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: RM.line),
            boxShadow: [BoxShadow(color: RM.ink.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 4))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                const RiMiMark(size: 40),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Bếp Nhà Hằng', style: RMType.body(size: 14.5, weight: FontWeight.w700)),
                  Text('Sponsored · Just now', style: RMType.body(size: 12, color: RM.muted)),
                ]),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: RichText(
                text: TextSpan(style: RMType.body(size: 14, color: RM.ink, height: 1.55), children: [
                  const TextSpan(text: '$_caption\n'),
                  TextSpan(text: _hashtags, style: RMType.body(size: 14, color: RM.info, height: 1.55)),
                ]),
              ),
            ),
            Stack(children: [
              FoodSlot(label: 'Bún bò Huế đặc biệt', seed: 1, height: portrait ? 240 : 280, radius: 0, width: double.infinity),
              Positioned(
                bottom: 12,
                right: 12,
                child: GestureDetector(
                  onTap: () => rmToast(context, 'Pick another dish photo'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(11)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.photo_camera_outlined, size: 15, color: RM.brandDeep),
                      const SizedBox(width: 5),
                      Text('Change photo', style: RMType.body(size: 12.5, weight: FontWeight.w700, color: RM.brandDeep)),
                    ]),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ],
    );

    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: Text('CAPTION', style: RMType.body(size: 12, weight: FontWeight.w700, color: RM.muted, letterSpacing: 0.4))),
          const _AiRewriteChip(),
        ]),
        const SizedBox(height: 9),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 90),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: RM.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: RM.line)),
          child: Text(_caption, style: RMType.body(size: 14, color: RM.ink, height: 1.55)),
        ),
        const SizedBox(height: 18),
        Text('POST TO', style: RMType.body(size: 12, weight: FontWeight.w700, color: RM.muted, letterSpacing: 0.4)),
        const SizedBox(height: 9),
        Row(children: [
          for (int i = 0; i < _platforms.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            _PlatformTile(name: _platforms[i].$1, color: _platforms[i].$2, on: _picked.contains(_platforms[i].$1), onTap: () => _toggle(_platforms[i].$1)),
          ],
        ]),
        const SizedBox(height: 18),
        const _ScheduleRow(),
      ],
    );

    return Container(
      color: RM.cream,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
        children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('New post', style: RMType.display(size: 26)),
                Text('Compose once, publish everywhere', style: RMType.body(size: 13, color: RM.muted)),
              ]),
            ),
            FilledButton(
              onPressed: () => rmToast(context, _picked.isEmpty ? 'Pick a platform first' : 'Posted to ${_picked.join(', ')} 🎉'),
              style: FilledButton.styleFrom(backgroundColor: RM.brand, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))),
              child: Text('Post now', style: RMType.body(size: 15, weight: FontWeight.w700, color: Colors.white)),
            ),
          ]),
          const SizedBox(height: 20),
          if (portrait) ...[
            preview,
            const SizedBox(height: 22),
            controls,
          ] else
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: preview),
              const SizedBox(width: 22),
              Expanded(child: controls),
            ]),
        ],
      ),
    );
  }
}
