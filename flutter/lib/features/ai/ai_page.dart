import 'package:flutter/material.dart';
import '../../app.dart';
import '../../core/app_icons.dart';
import '../../core/responsive.dart';
import '../../data/mock_data.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/navigation.dart';
import '../../widgets/primitives.dart';

// ── chat scripts (per bot) ───────────────────────────────────────────

class ChatScript {
  const ChatScript({required this.user, required this.reply, this.card = false, required this.sugg});
  final String user;
  final List<TextSpan> reply;
  final bool card;
  final List<String> sugg;
}

TextSpan _b(String t) => TextSpan(text: t, style: RMType.body(size: 13.5, weight: FontWeight.w700, height: 1.55));

final Map<String, ChatScript> chatScripts = {
  'sales': ChatScript(
    user: 'How are sales going today?',
    reply: [
      const TextSpan(text: "You're at "),
      _b('2.84M₫'),
      const TextSpan(text: ' from 38 orders — up '),
      _b('12%'),
      const TextSpan(text: " on yesterday. "),
      _b('Cơm tấm sườn bì'),
      const TextSpan(text: " is today's top seller (31 sold). 🎯"),
    ],
    sugg: ["Today's summary", 'Top items', 'Set a target'],
  ),
  'mkt': ChatScript(
    user: "Write a Facebook post for today's bún bò, it's raining 🌧️",
    reply: [
      const TextSpan(text: "Here's a warm, rainy-day post for "),
      _b('Bếp Nhà Hằng'),
      const TextSpan(text: ' 👇'),
    ],
    card: true,
    sugg: ['Make it shorter', 'Add a discount', 'Schedule 5pm'],
  ),
  'acct': ChatScript(
    user: "How's my profit this week?",
    reply: [
      const TextSpan(text: 'Net profit is '),
      _b('+12.64M₫'),
      const TextSpan(text: ' this week. Ingredients are 30% of revenue — healthy for a kitchen. Want a breakdown? 📊'),
    ],
    sugg: ['This month', 'Tax estimate', 'Cash flow'],
  ),
  'stock': ChatScript(
    user: "What's running low?",
    reply: [
      const TextSpan(text: '3 dishes are low: '),
      _b('Bún bò'),
      const TextSpan(text: ' (8 left), '),
      _b('Chả giò'),
      const TextSpan(text: ' (5), '),
      _b('Nước mía'),
      const TextSpan(text: ' (out). I can draft a supplier order for tomorrow. 📦'),
    ],
    sugg: ['Draft reorder', 'Set alerts', 'Supplier list'],
  ),
  'care': ChatScript(
    user: 'Anything from customers today?',
    reply: [
      const TextSpan(text: '2 new '),
      _b('5★'),
      const TextSpan(text: ' reviews and 1 question on Zalo about delivery time. Want me to draft friendly replies? 💬'),
    ],
    sugg: ['Draft replies', 'Loyalty message', 'View reviews'],
  ),
};

// ── chat bubble ──────────────────────────────────────────────────────

class _Bubble extends StatelessWidget {
  const _Bubble({this.me = false, this.bot, this.children, this.text});
  final bool me;
  final Bot? bot;
  final List<TextSpan>? children;
  final String? text;
  @override
  Widget build(BuildContext context) {
    if (me) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.7),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: RM.brand,
              borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(4)),
            ),
            child: Text(text ?? '', style: RMType.body(size: 13.5, color: Colors.white, height: 1.5)),
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (bot != null) ...[BotIconView(bot: bot!, size: 30), const SizedBox(width: 8)],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: RM.card,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16), bottomLeft: Radius.circular(4), bottomRight: Radius.circular(16)),
                border: Border.all(color: RM.line),
              ),
              child: RichText(text: TextSpan(style: RMType.body(size: 13.5, color: RM.ink, height: 1.55), children: children)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({this.maxWidth = 320});
  final double maxWidth;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 38),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Container(
            decoration: BoxDecoration(color: RM.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: RM.line)),
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FoodSlot(label: 'Bún bò Huế', seed: 1, height: 110, radius: 0, width: double.infinity),
              Padding(
                padding: const EdgeInsets.all(13),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Trời mưa lành lạnh, làm tô bún bò Huế nóng hổi cho ấm bụng nha cả nhà! 🍜 Đặt ngay, giao tận nơi trong 30 phút.', style: RMType.body(size: 13, height: 1.55)),
                  const SizedBox(height: 6),
                  Text('#bunbohue #anngon #giaohang', style: RMType.body(size: 12.5, color: RM.info)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SuggRow extends StatelessWidget {
  const _SuggRow({required this.items});
  final List<String> items;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 38),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in items)
          GestureDetector(
            onTap: () => rmToast(context, s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: RM.card, borderRadius: BorderRadius.circular(999), border: Border.all(color: RM.brandSoft)),
              child: Text(s, style: RMType.body(size: 12, weight: FontWeight.w600, color: RM.brand)),
            ),
          ),
      ]),
    );
  }
}

class _ChatInput extends StatelessWidget {
  const _ChatInput({required this.botName});
  final String botName;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: const BoxDecoration(color: RM.card, border: Border(top: BorderSide(color: RM.line))),
      child: SafeArea(
        top: false,
        child: Row(children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: RM.cream, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Expanded(child: Text('Message $botName…', style: RMType.body(size: 14, color: RM.muted))),
                const RmIcon('mic', size: 19, color: RM.muted),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => rmToast(context, 'Message sent'),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: RM.brand, borderRadius: BorderRadius.circular(15)),
              child: const Icon(Icons.send_rounded, size: 20, color: Colors.white),
            ),
          ),
        ]),
      ),
    );
  }
}

Widget _chatThread(BuildContext context, Bot b, {required double cardWidth}) {
  final s = chatScripts[b.id] ?? chatScripts['mkt']!;
  return ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Center(child: Text('TODAY 10:24', style: RMType.body(size: 11, weight: FontWeight.w600, color: RM.muted))),
      const SizedBox(height: 12),
      _Bubble(me: true, text: s.user),
      const SizedBox(height: 12),
      _Bubble(bot: b, children: s.reply),
      if (s.card) ...[const SizedBox(height: 12), _PostCard(maxWidth: cardWidth)],
      const SizedBox(height: 12),
      _SuggRow(items: s.sugg),
    ],
  );
}

// ── AI TEAM (roster) ─────────────────────────────────────────────────

class AiTeamPage extends StatelessWidget {
  const AiTeamPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RM.cream,
      body: isTablet(context) ? const _AiTablet() : SafeArea(child: _mobile(context)),
    );
  }

  Widget _mobile(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
        child: Row(children: [
          GestureDetector(onTap: () => Navigator.of(context).maybePop(), child: const RmIcon('arrowL', size: 22, color: RM.ink)),
          const SizedBox(width: 8),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [RM.gold, RM.brand]), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.auto_awesome_rounded, size: 26, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('AI Team', style: RMType.display(size: 23)),
              Text('5 assistants working for you', style: RMType.body(size: 12.5, color: RM.muted)),
            ]),
          ),
        ]),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [RM.ink, Color(0xFF4A372C)]),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('ASK ANYTHING', style: RMType.body(size: 12, weight: FontWeight.w700, color: RM.gold, letterSpacing: 0.4)),
                const SizedBox(height: 5),
                Text('“How much did I earn this week, and what should I cook more of?”', style: RMType.body(size: 15, color: Colors.white, height: 1.5)),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AiChatPage(bot: bots[0]))),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.mic_none_rounded, size: 16, color: RM.brand),
                      const SizedBox(width: 6),
                      Text('Ask RiMi', style: RMType.body(size: 13, weight: FontWeight.w700, color: RM.ink)),
                    ]),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            const SectionHead('Your assistants'),
            for (int i = 0; i < bots.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _BotRow(b: bots[i], onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AiChatPage(bot: bots[i])))),
            ],
          ],
        ),
      ),
    ]);
  }
}

class _BotRow extends StatelessWidget {
  const _BotRow({required this.b, required this.onTap});
  final Bot b;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return SoftCard(
      onTap: onTap,
      child: Row(children: [
        BotIconView(bot: b, size: 46),
        const SizedBox(width: 13),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RichText(
              text: TextSpan(style: RMType.body(size: 14.5, weight: FontWeight.w700), children: [
                TextSpan(text: b.name),
                TextSpan(text: ' · ${b.vn}', style: RMType.body(size: 12, weight: FontWeight.w500, color: RM.muted)),
              ]),
            ),
            Text(b.desc, maxLines: 1, overflow: TextOverflow.ellipsis, style: RMType.body(size: 12.5, color: RM.ink70)),
          ]),
        ),
        const RmIcon('chevR', size: 18, color: RM.faint),
      ]),
    );
  }
}

// ── AI CHAT (mobile full page) ───────────────────────────────────────

class AiChatPage extends StatelessWidget {
  const AiChatPage({super.key, required this.bot});
  final Bot bot;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6EFE6),
      body: SafeArea(
        child: Column(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
            decoration: const BoxDecoration(color: RM.card, border: Border(bottom: BorderSide(color: RM.line))),
            child: Row(children: [
              GestureDetector(onTap: () => Navigator.of(context).maybePop(), child: const RmIcon('arrowL', size: 22, color: RM.ink)),
              const SizedBox(width: 11),
              BotIconView(bot: bot, size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  RichText(text: TextSpan(style: RMType.body(size: 15, weight: FontWeight.w700), children: [
                    TextSpan(text: bot.name),
                    TextSpan(text: ' · ${bot.vn}', style: RMType.body(size: 11.5, weight: FontWeight.w500, color: RM.muted)),
                  ])),
                  Row(children: [
                    const StatusDot(RM.herb, size: 7),
                    const SizedBox(width: 4),
                    Text('Online', style: RMType.body(size: 11.5, weight: FontWeight.w600, color: RM.herb)),
                  ]),
                ]),
              ),
              GestureDetector(onTap: () => rmToast(context, 'Chat options'), child: const RmIcon('more', size: 22, color: RM.muted)),
            ]),
          ),
          Expanded(child: _chatThread(context, bot, cardWidth: 300)),
          _ChatInput(botName: bot.name),
        ]),
      ),
    );
  }
}

// ── AI TABLET (team + chat split, with rail) ─────────────────────────

class _AiTablet extends StatefulWidget {
  const _AiTablet();
  @override
  State<_AiTablet> createState() => _AiTabletState();
}

class _AiTabletState extends State<_AiTablet> {
  int _sel = 1;
  @override
  Widget build(BuildContext context) {
    final b = bots[_sel];
    final portrait = MediaQuery.sizeOf(context).height > MediaQuery.sizeOf(context).width;
    return Row(children: [
      TabletRail(
        activeIndex: -1,
        onTap: (i) => AppNav.goTab(i),
        onAi: () {},
      ),
      // team list
      Container(
        width: portrait ? 250 : 320,
        decoration: const BoxDecoration(border: Border(right: BorderSide(color: RM.line))),
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('AI Team', style: RMType.display(size: 24)),
          Text('5 assistants working for you', style: RMType.body(size: 13, color: RM.muted)),
          const SizedBox(height: 18),
          Expanded(
            child: ListView.separated(
              itemCount: bots.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final on = i == _sel;
                return GestureDetector(
                  onTap: () => setState(() => _sel = i),
                  child: Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(color: on ? RM.brandSoft : RM.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: on ? RM.brand : RM.line)),
                    child: Row(children: [
                      BotIconView(bot: bots[i], size: 42),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(bots[i].name, style: RMType.body(size: 14, weight: FontWeight.w700)),
                          Text(bots[i].desc, maxLines: 1, overflow: TextOverflow.ellipsis, style: RMType.body(size: 12, color: RM.muted)),
                        ]),
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
      // chat
      Expanded(
        child: Container(
          color: const Color(0xFFF6EFE6),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(color: RM.card, border: Border(bottom: BorderSide(color: RM.line))),
              child: Row(children: [
                BotIconView(bot: b, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${b.name} assistant', style: RMType.body(size: 17, weight: FontWeight.w700)),
                    Row(children: [
                      const StatusDot(RM.herb, size: 7),
                      const SizedBox(width: 4),
                      Text('${b.vn} · Ready to help', style: RMType.body(size: 12, weight: FontWeight.w600, color: RM.herb)),
                    ]),
                  ]),
                ),
                FilledButton(
                  onPressed: () => rmToast(context, 'New chat'),
                  style: FilledButton.styleFrom(backgroundColor: RM.brandSoft, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)), elevation: 0),
                  child: Text('New chat', style: RMType.body(size: 13, weight: FontWeight.w700, color: RM.brandDeep)),
                ),
              ]),
            ),
            Expanded(child: _chatThread(context, b, cardWidth: 440)),
            _ChatInput(botName: b.name),
          ]),
        ),
      ),
    ]);
  }
}
