import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbit/core/native.dart';
import 'package:orbit/data/settings.dart';
import 'package:orbit/state/providers.dart';
import 'package:orbit/theme/orbit_theme.dart';
import 'package:orbit/ui/about_page.dart';
import 'package:orbit/ui/appearance_page.dart';
import 'package:orbit/ui/apps_page.dart';
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

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            const Text('Настройки', style: OrbitText.title),
            const SectionLabel('Подключение'),
            OrbitTile(
              title: 'Маршрутизация',
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
              value: s.dnsChoice.label,
              onTap: () => pick<String>(
                context,
                title: 'DNS',
                current: s.dns,
                options: {for (final d in DnsChoice.all) d.id: (d.label, '${d.subtitle}, DNS over HTTPS')},
                onSelected: (v) => notifier.change((s) => s.copyWith(dns: v), reconnect: true),
              ),
            ),
            OrbitSwitchTile(
              title: 'Фрагментация TLS',
              subtitle: 'Помогает, если сервер режет DPI',
              value: s.fragment,
              onChanged: (v) => notifier.change((s) => s.copyWith(fragment: v), reconnect: true),
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
                  ? const Icon(Icons.check_rounded, color: OrbitColors.accent, size: 20)
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
