import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/responsive.dart';
import 'core/router/app_router.dart';
import 'core/sync/sync_providers.dart';
import 'data/mock_data.dart';
import 'theme/app_theme.dart';
import 'widgets/navigation.dart';
import 'features/home/home_page.dart';
import 'features/orders/orders_page.dart';
import 'features/products/products_page.dart';
import 'features/content/content_page.dart';
import 'features/finance/finance_page.dart';
import 'features/ai/ai_page.dart';

/// Global navigation controller — switch tabs or open AI from anywhere,
/// including pushed routes. Mirrors the prototype's `nav` context.
///
/// [navKey] is now bound to the nested Navigator inside [RootShell]
/// (not MaterialApp.navigatorKey — that is owned by GoRouter). This preserves
/// the AI orb push + tab pop-to-first behaviour with zero feature-page edits.
abstract final class AppNav {
  static final navKey = GlobalKey<NavigatorState>();
  static final tab = ValueNotifier<int>(0);

  static void goTab(int i) {
    navKey.currentState?.popUntil((r) => r.isFirst);
    tab.value = i;
  }

  static void push(Widget page) =>
      navKey.currentState?.push(MaterialPageRoute(builder: (_) => page));

  static void openAiTeam() => push(const AiTeamPage());
  static void openChat(Bot bot) => push(AiChatPage(bot: bot));
}

/// Root app widget — MaterialApp.router driven by GoRouter.
///
/// GoRouter owns the top-level Navigator. AppNav.navKey is wired to
/// a nested Navigator inside [RootShell] so AppNav.push/goTab still work.
class RiMiApp extends ConsumerStatefulWidget {
  const RiMiApp({super.key});

  @override
  ConsumerState<RiMiApp> createState() => _RiMiAppState();
}

class _RiMiAppState extends ConsumerState<RiMiApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = createRouter(ref);
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Warm sync + realtime providers eagerly so offline infrastructure is
    // live before any feature page tries to enqueue an operation.
    ref.watch(appDatabaseProvider);
    ref.watch(connectivityWatcherProvider);
    ref.watch(syncFlusherProvider);
    ref.watch(realtimeManagerProvider);

    return MaterialApp.router(
      title: 'RiMi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: _router,
    );
  }
}

/// Shell wrapping the in-app tab UI.
///
/// Uses a nested [Navigator] keyed to [AppNav.navKey] so that:
///  - AppNav.push() / AppNav.openAiTeam() push onto the in-shell navigator.
///  - AppNav.goTab() pops to root then switches tabs.
/// This is completely decoupled from GoRouter's top-level navigator.
class RootShell extends StatelessWidget {
  const RootShell({super.key});

  static const _mobile = [
    HomeMobile(),
    OrdersMobile(),
    ProductsMobile(),
    ContentMobile(),
    FinanceMobile(),
  ];
  static const _tablet = [
    HomeTablet(),
    OrdersTablet(),
    ProductsTablet(),
    ContentTablet(),
    FinanceTablet(),
  ];

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: AppNav.navKey,
      onGenerateRoute: (_) => MaterialPageRoute(
        builder: (_) => const _ShellBody(),
      ),
    );
  }
}

class _ShellBody extends StatelessWidget {
  const _ShellBody();

  static const _mobile = RootShell._mobile;
  static const _tablet = RootShell._tablet;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppNav.tab,
      builder: (context, tab, _) {
        if (isTablet(context)) {
          return Scaffold(
            body: Row(
              children: [
                TabletRail(
                  activeIndex: tab,
                  onTap: (i) => AppNav.tab.value = i,
                  onAi: AppNav.openAiTeam,
                ),
                Expanded(child: IndexedStack(index: tab, children: _tablet)),
              ],
            ),
          );
        }
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Stack(
              children: [
                IndexedStack(index: tab, children: _mobile),
                if (tab != 3)
                  const Positioned.fill(
                    child: DraggableAiOrb(onOpen: AppNav.openAiTeam),
                  ),
              ],
            ),
          ),
          bottomNavigationBar: ListenableBuilder(
            listenable: OrderStore.instance,
            builder: (context, _) => RiMiBottomNav(
              activeIndex: tab,
              onTap: (i) => AppNav.tab.value = i,
              badges: {1: OrderStore.instance.activeCount},
            ),
          ),
        );
      },
    );
  }
}
