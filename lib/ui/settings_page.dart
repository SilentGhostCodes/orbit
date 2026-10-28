import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbit/core/native.dart';
import 'package:orbit/data/settings.dart';
import 'package:orbit/state/providers.dart';
import 'package:orbit/theme/orbit_theme.dart';
import 'package:orbit/ui/about_page.dart';
import 'package:orbit/ui/appearance_page.dart';
import 'package:orbit/ui/apps_page.dart';
import 'package:orbit/ui/fragment_page.dart';
import 'package:orbit/ui/logs_page.dart';
import 'package:orbit/ui/ping_settings_page.dart';
import 'package:orbit/widgets/orbit_widgets.dart';

/// 07 · Settings.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    // whether the panel's rules are what routes right now
    final panelRouting =
        s.subscriptionRouting && (ref.watch(activeSubscriptionProvider)?.servers.any((x) => x.routing != null) ?? false);
    final panelDns =
        panelRouting && (ref.watch(activeSubscriptionProvider)?.servers.any((x) => x.dns != null) ?? false);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            const Text('Настройки', style: OrbitText.title),
            const SectionLabel('Подключение'),
            OrbitSwitchTile(
              title: 'Роутинг подписки',
              subtitle: 'Правила и DNS из Xray JSON подписки',
              value: s.subscriptionRouting,
              onChanged: (v) async {
                if (!v && !await _confirmRoutingOff(context)) return;
                await notifier.change((s) => s.copyWith(subscriptionRouting: v), reconnect: true);
              },
            ),
            OrbitTile(
              title: 'Маршрутизация',
              subtitle: panelRouting ? 'Сейчас действуют правила подписки' : null,
              value: s.routing == RoutingMode.bypassRu ? 'Обход RU' : 'Всё через VPN',
              onTap: () => pick<RoutingMode>(
                context,
                title: 'Маршрутизация',
                current: s.routing,
                options: const {
                  RoutingMode.bypassRu: ('Обход RU', 'Российские сайты и IP напрямую'),
                  RoutingMode.all: ('Всё через VPN', 'Без исключений'),
                },
                onSelected: (v) => notifier.change((s) => s.copyWith(routing: v), reconnect: true),
              ),
            ),
            OrbitTile(
              title: 'Приложения через VPN',
              value: switch (s.appsMode) {
                AppsMode.all => 'Все',
                AppsMode.include => 'Только ${s.apps.length}',
                AppsMode.exclude => 'Кроме ${s.apps.length}',
              },
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AppsPage())),
            ),
            OrbitSwitchTile(
              title: 'Автоподключение',
              subtitle: 'При запуске приложения и телефона',
              value: s.autoConnect,
              onChanged: (v) async {
                await notifier.change((s) => s.copyWith(autoConnect: v));
                await Native.setAutoConnect(v);
              },
            ),
            OrbitSwitchTile(
              title: 'Kill Switch',
              value: s.killSwitch,
              divider: false,
              onChanged: (v) async {
                await notifier.change((s) => s.copyWith(killSwitch: v));
                if (context.mounted) await _explainKillSwitch(context, v);
              },
            ),
            const SectionLabel('Сеть'),
            OrbitTile(
              title: 'DNS',
              subtitle: panelDns ? 'Сейчас действует DNS подписки' : null,
              value: s.dnsChoice.label,
              onTap: () => pick<String>(
                context,
                title: 'DNS',
                current: s.dns,
                options: {for (final d in DnsChoice.all) d.id: (d.label, '${d.subtitle}, DNS over HTTPS')},
                onSelected: (v) => notifier.change((s) => s.copyWith(dns: v), reconnect: true),
              ),
            ),
            OrbitTile(
              title: 'Фрагментация TLS',
              subtitle: 'Помогает, если сервер режет DPI',
              value: s.fragment ? 'Вкл' : 'Выкл',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FragmentPage())),
            ),
            OrbitTile(
              title: 'Пинг',
              value: s.pingType.label,
              divider: false,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PingSettingsPage())),
            ),
            const SectionLabel('Приложение'),
            OrbitTile(
              title: 'Оформление',
              value: 'Кнопка: ${s.buttonStyle.label}',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AppearancePage())),
            ),
            OrbitTile(
              title: 'Логи',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LogsPage())),
            ),
            OrbitTile(
              title: 'О приложении',
              divider: false,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutPage())),
            ),
          ],
        ),
      ),
    );
  }

  static Future<bool> _confirmRoutingOff(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Отключить роутинг подписки?', style: OrbitText.sheetTitle),
          content: Text(
            'Правила, которые прислала подписка, перестанут действовать — Orbit будет направлять трафик '
            'по своей настройке «Маршрутизация». Некоторые сервисы снова могут жаловаться на VPN или '
            'открываться медленнее.',
            style: OrbitText.body.copyWith(color: OrbitColors.textSecondary, height: 1.4),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Оставить')),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: OrbitColors.danger),
              child: const Text('Отключить'),
            ),
          ],
        ),
      ) ??
      false;

  static Future<void> _explainKillSwitch(BuildContext context, bool enabled) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(enabled ? 'Включите в Android' : 'Выключите в Android', style: OrbitText.sheetTitle),
      content: Text(
        enabled
            ? 'Kill Switch на Android включается в системе: Настройки → VPN → Orbit → «Постоянная VPN» и '
                  '«Блокировать соединения без VPN». Тогда интернет пропадёт, если туннель упадёт.'
            : 'Отключите «Блокировать соединения без VPN» для Orbit в системных настройках VPN.',
        style: OrbitText.body.copyWith(color: OrbitColors.textSecondary, height: 1.4),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Позже')),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            Native.openVpnSettings();
          },
          child: const Text('Открыть настройки'),
        ),
      ],
    ),
  );
}

/// A bottom sheet with one choice per row.
Future<void> pick<T>(
  BuildContext context, {
  required String title,
  required T current,
  required Map<T, (String, String?)> options,
  required ValueChanged<T> onSelected,
}) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  backgroundColor: OrbitColors.surface,
  builder: (context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHandle(),
          Text(title, style: OrbitText.sheetTitle),
          const SizedBox(height: 8),
          for (final (i, entry) in options.entries.indexed)
            OrbitTile(
              title: entry.value.$1,
              subtitle: entry.value.$2,
              divider: i != options.length - 1,
              trailing: entry.key == current
                  ? Icon(Icons.check_rounded, color: OrbitColors.accent, size: 20)
                  : null,
              onTap: () {
                onSelected(entry.key);
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
    ),
  ),
);
