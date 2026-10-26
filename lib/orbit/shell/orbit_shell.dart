import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/orbit/state/orbit_providers.dart';
import 'package:hiddify/orbit/theme/orbit_theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The three tabs: Главная, Серверы, Настройки.
class OrbitShell extends ConsumerWidget {
  const OrbitShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _tabs = [
    (icon: Icons.shield_outlined, selectedIcon: Icons.shield_rounded, label: 'Главная'),
    (icon: Icons.language_rounded, selectedIcon: Icons.language_rounded, label: 'Серверы'),
    (icon: Icons.tune_rounded, selectedIcon: Icons.tune_rounded, label: 'Настройки'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // picks the server chosen while disconnected once the core is up
    ref.watch(pendingServerApplier);
    ref.watch(autoConnectOnLaunchProvider);
    // the first run screen has no tabs
    final hasAny = ref.watch(hasAnyProfileProvider).valueOrNull ?? true;
    final showNav = hasAny || navigationShell.currentIndex != 0;

    // Owns the back press at the root of each tab: back to Главная first, then out of the app.
    // canPop stays false so Android always asks Flutter (see Hiddify's MyAdaptiveLayout).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (navigationShell.currentIndex != 0) {
          navigationShell.goBranch(0);
        } else {
          SystemNavigator.pop();
        }
      },
      child: NotificationListener<NavigationNotification>(
        onNotification: (notification) {
          if (notification.canHandlePop) return false;
          const NavigationNotification(canHandlePop: true).dispatch(context);
          return true;
        },
        child: Scaffold(
          body: navigationShell,
          bottomNavigationBar: showNav
              ? _OrbitNavBar(
                  index: navigationShell.currentIndex,
                  onTap: (i) => navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex),
                )
              : null,
        ),
      ),
    );
  }
}

class _OrbitNavBar extends StatelessWidget {
  const _OrbitNavBar({required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: OrbitColors.background,
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            for (final (i, tab) in OrbitShell._tabs.indexed)
              Expanded(
                child: InkResponse(
                  onTap: () => onTap(i),
                  radius: 36,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        i == index ? tab.selectedIcon : tab.icon,
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
  );
}
