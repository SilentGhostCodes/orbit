import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbit/core/deep_links.dart';
import 'package:orbit/core/native.dart';
import 'package:orbit/state/providers.dart';
import 'package:orbit/theme/orbit_theme.dart';
import 'package:orbit/ui/home_page.dart';
import 'package:orbit/ui/servers_page.dart';
import 'package:orbit/ui/settings_page.dart';
import 'package:orbit/ui/subscription_sheets.dart';

final tabProvider = NotifierProvider<TabNotifier, int>(TabNotifier.new);

/// Whether Orbit is on screen. Anything that ticks on its own (the connection timer, subscription
/// updates) stops while it is not, so the app does not wake the phone in the background.
final appVisibleProvider = NotifierProvider<AppVisibleNotifier, bool>(AppVisibleNotifier.new);

class AppVisibleNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool visible) => state = visible;
}

class TabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void go(int index) => state = index;
}

/// The three tabs: Главная, Серверы, Настройки.
class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});

  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> with WidgetsBindingObserver {
  static const _tabs = [
    (icon: Icons.shield_outlined, selected: Icons.shield_rounded, label: 'Главная'),
    (icon: Icons.language_rounded, selected: Icons.language_rounded, label: 'Серверы'),
    (icon: Icons.tune_rounded, selected: Icons.tune_rounded, label: 'Настройки'),
  ];

  /// Subscriptions due for an update while the app stays open (intervals go down to an hour).
  Timer? _updates;

  /// happ:// and incy:// links arriving while Orbit is open.
  StreamSubscription<void>? _links;
  var _openingLink = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onLaunch());
    _links = DeepLinks.available.listen((_) => _openLink());
    _startUpdates();
  }

  void _startUpdates() {
    _updates?.cancel();
    _updates = Timer.periodic(
      const Duration(minutes: 10),
      (_) => ref.read(subscriptionsProvider.notifier).refreshAll(onlyDue: true),
    );
  }

  @override
  void dispose() {
    _updates?.cancel();
    _links?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state == AppLifecycleState.resumed;
    ref.read(appVisibleProvider.notifier).set(visible);
    if (visible) {
      ref.invalidate(vkAccountProvider);
      ref.read(subscriptionsProvider.notifier).refreshAll(onlyDue: true);
      _startUpdates();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      // nothing to update on screen: the next opening catches up on what is due
      _updates?.cancel();
      _updates = null;
    }
  }

  /// Opens a waiting happ:// or incy:// link as a new subscription, adding it straight away.
  Future<void> _openLink() async {
    if (_openingLink) return; // the one being opened takes any newer link after it
    _openingLink = true;
    try {
      while (true) {
        final link = await DeepLinks.take();
        if (link == null || !mounted) break;
        ref.read(tabProvider.notifier).go(0);
        await showAddSubscriptionSheet(context, initial: link, submit: true);
      }
    } finally {
      _openingLink = false;
    }
  }

  Future<void> _onLaunch() async {
    // opened from «Открыть в приложении»: the link first, auto-connect waits for nothing
    unawaited(_openLink());
    final status = await Native.status();
    if (!mounted) return;
    if (ref.read(settingsProvider).autoConnect && status.state == VpnState.disconnected) {
      await ref.read(connectionProvider.notifier).connect();
    }
    await ref.read(subscriptionsProvider.notifier).refreshAll(onlyDue: true);
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(tabProvider);
    final hasSubscriptions = ref.watch(subscriptionsProvider).isNotEmpty;
    // the first run screen has no tabs
    final showNav = hasSubscriptions || index != 0;

    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(tabProvider.notifier).go(0);
      },
      child: Scaffold(
        body: IndexedStack(
          index: index,
          children: [
            // a hidden tab's animations (the connect button's orbit) stop instead of drawing unseen
            for (final (i, page) in const [HomePage(), ServersPage(), SettingsPage()].indexed)
              TickerMode(enabled: i == index, child: page),
          ],
        ),
        bottomNavigationBar: showNav
            ? _NavBar(
                tabs: _tabs,
                index: index,
                onTap: (i) {
                  if (i == index) return;
                  HapticFeedback.selectionClick();
                  ref.read(tabProvider.notifier).go(i);
                },
              )
            : null,
      ),
    );
  }
}

/// The tab bar: a pill slides under the tab you go to, and its icon and label fade into the
/// selected colours, instead of jumping.
class _NavBar extends StatelessWidget {
  const _NavBar({required this.tabs, required this.index, required this.onTap});

  final List<({IconData icon, IconData selected, String label})> tabs;
  final int index;
  final ValueChanged<int> onTap;

  static const _duration = Duration(milliseconds: 320);
  static const _curve = Curves.easeOutCubic;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: OrbitColors.background,
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 64,
        child: Stack(
          children: [
            // the pill: one tab wide, sliding to the selected one
            AnimatedAlign(
              duration: _duration,
              curve: _curve,
              alignment: Alignment(tabs.length == 1 ? 0 : -1 + 2 * index / (tabs.length - 1), 0),
              child: FractionallySizedBox(
                widthFactor: 1 / tabs.length,
                child: Center(
                  child: Container(
                    width: 72,
                    height: 50,
                    decoration: BoxDecoration(
                      color: OrbitColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (final (i, tab) in tabs.indexed)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onTap(i),
                      child: TweenAnimationBuilder<double>(
                        duration: _duration,
                        curve: _curve,
                        tween: Tween(end: i == index ? 1 : 0),
                        builder: (context, t, _) {
                          final color = Color.lerp(OrbitColors.textSecondary, OrbitColors.textPrimary, t)!;
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(t > .5 ? tab.selected : tab.icon, size: 21, color: color),
                              const SizedBox(height: 4),
                              Text(
                                tab.label,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.lerp(FontWeight.w500, FontWeight.w700, t),
                                  color: color,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
