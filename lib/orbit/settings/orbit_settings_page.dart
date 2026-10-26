import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/model/region.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/app_based_routing/model/pkg_flag.dart';
import 'package:hiddify/features/app_based_routing/overview/app_list_notifier.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/gen/translations.g.dart';
import 'package:hiddify/orbit/state/orbit_providers.dart';
import 'package:hiddify/orbit/theme/orbit_theme.dart';
import 'package:hiddify/orbit/widgets/orbit_widgets.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 07 · Settings.
class OrbitSettingsPage extends ConsumerWidget {
  const OrbitSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(ConfigOptions.serviceMode);
    final region = ref.watch(ConfigOptions.region);
    final dns = ref.watch(ConfigOptions.remoteDnsAddress);
    final fragment = ref.watch(ConfigOptions.enableTlsFragment);
    final autoConnect = ref.watch(OrbitPrefs.autoConnect);
    final killSwitch = ref.watch(OrbitPrefs.killSwitch);
    final locale = ref.watch(localePreferencesProvider);
    final appsMode = ref.watch(Preferences.perAppProxyModeInUse);
    final apps = ref.watch(AppListProvider(appsMode)).valueOrNull;
    final appsCount = apps?.values.where((f) => PkgFlag.checkboxValue(f) ?? true).length;
    final version = ref.watch(appInfoProvider).valueOrNull?.presentVersion;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            const Text('Настройки', style: OrbitText.title),
            const SectionLabel('Подключение'),
            OrbitTile(
              title: 'Режим',
              value: mode == ServiceMode.tun ? 'VPN' : 'Прокси',
              onTap: () => _pick<ServiceMode>(
                context,
                title: 'Режим',
                current: mode,
                options: {
                  ServiceMode.tun: ('VPN', 'Весь трафик телефона через туннель'),
                  ServiceMode.proxy: ('Прокси', 'Только локальный прокси, без VPN'),
                },
                onSelected: (v) => ref.read(ConfigOptions.serviceMode.notifier).update(v),
              ),
            ),
            OrbitTile(
              title: 'Маршрутизация',
              value: _regionLabel(region),
              onTap: () => _pick<Region>(
                context,
                title: 'Маршрутизация',
                current: region,
                options: {
                  Region.ru: ('Обход RU', 'Российские сайты и IP напрямую'),
                  Region.other: ('Всё через VPN', 'Без исключений'),
                  Region.cn: ('Обход CN', 'Китайские сайты напрямую'),
                  Region.ir: ('Обход IR', 'Иранские сайты напрямую'),
                  Region.tr: ('Обход TR', 'Турецкие сайты напрямую'),
                },
                onSelected: (v) => ref.read(ConfigOptions.region.notifier).update(v),
              ),
            ),
            OrbitTile(
              title: 'Приложения через VPN',
              value: appsMode == null ? 'Все' : '${appsCount ?? ''}',
              onTap: () => context.goNamed('orbitApps'),
            ),
            OrbitSwitchTile(
              title: 'Автоподключение',
              value: autoConnect,
              onChanged: (v) => ref.read(OrbitPrefs.autoConnect.notifier).update(v),
            ),
            OrbitSwitchTile(
              title: 'Kill Switch',
              value: killSwitch,
              divider: false,
              onChanged: (v) async {
                await ref.read(OrbitPrefs.killSwitch.notifier).update(v);
                if (context.mounted) await _explainKillSwitch(context, v);
              },
            ),
            const SectionLabel('Сеть'),
            OrbitTile(
              title: 'DNS',
              value: _dnsLabel(dns),
              onTap: () => _pick<String>(
                context,
                title: 'DNS',
                current: dns,
                options: {
                  'https://1.1.1.1/dns-query': ('1.1.1.1', 'Cloudflare, DNS over HTTPS'),
                  'tcp://1.1.1.1': ('1.1.1.1 TCP', 'Cloudflare'),
                  'tcp://8.8.8.8': ('8.8.8.8', 'Google'),
                  'https://dns.google/dns-query': ('dns.google', 'Google, DNS over HTTPS'),
                  'https://dns.adguard-dns.com/dns-query': ('AdGuard', 'Блокирует рекламу'),
                  'local': ('Системный', 'DNS провайдера'),
                },
                onSelected: (v) => ref.read(ConfigOptions.remoteDnsAddress.notifier).update(v),
              ),
            ),
            OrbitSwitchTile(
              title: 'Фрагментация TLS',
              value: fragment,
              onChanged: (v) => ref.read(ConfigOptions.enableTlsFragment.notifier).update(v),
            ),
            OrbitSwitchTile(
              title: 'Ядро Xray',
              subtitle: 'Для XHTTP и серверов за CDN',
              value: ref.watch(ConfigOptions.useXrayCoreWhenPossible),
              divider: false,
              onChanged: (v) async {
                await ref.read(ConfigOptions.useXrayCoreWhenPossible.notifier).update(v);
                // the panel picks the config format by the user agent of the next download
                await ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Подписки обновлены. Переподключитесь, если VPN включён')),
                  );
                }
              },
            ),
            const SectionLabel('Приложение'),
            OrbitTile(
              title: 'Язык',
              value: locale == AppLocale.ru ? 'Русский' : 'English',
              onTap: () => _pick<AppLocale>(
                context,
                title: 'Язык',
                current: locale,
                options: {AppLocale.ru: ('Русский', null), AppLocale.en: ('English', null)},
                onSelected: (v) => ref.read(localePreferencesProvider.notifier).changeLocale(v),
              ),
            ),
            OrbitTile(title: 'Логи', onTap: () => context.goNamed('logs')),
            OrbitTile(
              title: 'Дополнительно',
              subtitle: 'Все параметры ядра sing-box',
              trailing: const Icon(Icons.chevron_right_rounded, color: OrbitColors.textSecondary),
              onTap: () => context.goNamed('advanced'),
              divider: false,
            ),
            const SizedBox(height: 28),
            Center(
              child: Text(
                'Orbit${version == null || version.isEmpty ? '' : ' $version'} · на основе Hiddify',
                style: OrbitText.section,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _regionLabel(Region r) => switch (r) {
    Region.other => 'Всё через VPN',
    _ => 'Обход ${r.name.toUpperCase()}',
  };

  static String _dnsLabel(String address) {
    if (address == 'local') return 'Системный';
    final uri = Uri.tryParse(address);
    return (uri?.host.isNotEmpty ?? false) ? uri!.host : address;
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
            openAndroidVpnSettings();
          },
          child: const Text('Открыть настройки'),
        ),
      ],
    ),
  );
}

Future<void> _pick<T>(
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
