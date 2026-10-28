import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbit/core/native.dart';
import 'package:orbit/state/providers.dart';
import 'package:orbit/theme/orbit_theme.dart';
import 'package:orbit/ui/home_page.dart';
import 'package:orbit/ui/servers_page.dart';
import 'package:orbit/ui/settings_page.dart';

final tabProvider = NotifierProvider<TabNotifier, int>(TabNotifier.new);

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onLaunch());
    _updates = Timer.periodic(
      const Duration(minutes: 10),
      (_) => ref.read(subscriptionsProvider.notifier).refreshAll(onlyDue: true),
    );
  }

  @override
  void dispose() {
    _updates?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(subscriptionsProvider.notifier).refreshAll(onlyDue: true);
    }
  }

  Future<void> _onLaunch() async {
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
        body: IndexedStack(index: index, children: const [HomePage(), ServersPage(), SettingsPage()]),
        bottomNavigationBar: showNav
            ? ColoredBox(
                color: OrbitColors.background,
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    height: 64,
                    child: Row(
                      children: [
                        for (final (i, tab) in _tabs.indexed)
                          Expanded(
                            child: InkResponse(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                ref.read(tabProvider.notifier).go(i);
                              },
                              radius: 36,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    i == index ? tab.selected : tab.icon,
                                    size: 21,
                                    color: i == index ? OrbitColors.textPrimary : OrbitColors.textSecondary,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    tab.label,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: i == index ? FontWeight.w700 : FontWeight.w500,
                                      color: i == index ? OrbitColors.textPrimary : OrbitColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}
