import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/app_based_routing/model/app_package_info.dart';
import 'package:hiddify/features/app_based_routing/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/app_based_routing/model/pkg_flag.dart';
import 'package:hiddify/features/app_based_routing/overview/app_list_notifier.dart';
import 'package:hiddify/orbit/theme/orbit_theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:installed_apps/index.dart';

final _installedAppsProvider = FutureProvider.autoDispose.family<List<AppPackageInfo>, bool>((ref, hideSystem) async {
  final apps = await InstalledApps.getInstalledApps(hideSystem, true);
  return apps.map((e) => AppPackageInfo(packageName: e.packageName, name: e.name, icon: e.icon)).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
});

/// 08 · Which apps go through the tunnel.
class OrbitAppsPage extends HookConsumerWidget {
  const OrbitAppsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(Preferences.perAppProxyEnabled);
    final mode = ref.watch(Preferences.perAppProxyMode);
    final selected = ref.watch(AppListProvider(mode)).valueOrNull ?? const <String, int>{};
    final showSystem = useState(false);
    final apps = ref.watch(_installedAppsProvider(!showSystem.value));
    final query = useState('');

    bool isOn(String pkg) {
      final flag = selected[pkg];
      if (flag == null) return false;
      // apps picked by auto selection count as picked until the user takes them out
      return PkgFlag.checkboxValue(flag) ?? true;
    }

    final visible = apps.whenData((list) {
      final q = query.value.trim().toLowerCase();
      final filtered = q.isEmpty
          ? list.toList()
          : list.where((a) => a.name.toLowerCase().contains(q) || a.packageName.toLowerCase().contains(q)).toList();
      if (q.isEmpty) {
        // what is picked goes first, so the list opens on it
        filtered.sort((a, b) => (isOn(b.packageName) ? 1 : 0) - (isOn(a.packageName) ? 1 : 0));
      }
      return filtered;
    });

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text('Приложения через VPN', style: OrbitText.sheetTitle),
        actions: [
          Switch(
            value: enabled,
            onChanged: (v) => ref.read(Preferences.perAppProxyEnabled.notifier).update(v),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: OrbitColors.textSecondary),
            onSelected: (v) async {
              switch (v) {
                case 'system':
                  showSystem.value = !showSystem.value;
                case 'clear':
                  await ref.read(AppListProvider(mode).notifier).clearAll();
              }
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(value: 'system', checked: showSystem.value, child: const Text('Системные')),
              const PopupMenuItem(value: 'clear', child: Text('Снять все')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _ModeTab(
                  label: 'Только выбранные',
                  active: mode == AppProxyMode.include,
                  onTap: () => _setMode(ref, AppProxyMode.include),
                ),
                const SizedBox(width: 18),
                _ModeTab(
                  label: 'Кроме выбранных',
                  active: mode == AppProxyMode.exclude,
                  onTap: () => _setMode(ref, AppProxyMode.exclude),
                ),
              ],
            ),
          ),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Divider()),
          if (!enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text(
                'Сейчас через VPN идут все приложения. Выберите режим или включите переключатель сверху.',
                style: OrbitText.caption.copyWith(height: 1.4),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              onChanged: (v) => query.value = v,
              style: OrbitText.body,
              decoration: const InputDecoration(
                hintText: 'Поиск',
                hintStyle: TextStyle(color: OrbitColors.textTertiary),
                prefixIcon: Icon(Icons.search_rounded, size: 20, color: OrbitColors.textTertiary),
                prefixIconConstraints: BoxConstraints(minWidth: 32),
                border: UnderlineInputBorder(borderSide: BorderSide(color: OrbitColors.divider)),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: OrbitColors.divider)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: OrbitColors.accent)),
              ),
            ),
          ),
          Expanded(
            child: switch (visible) {
              AsyncData(value: final list) => ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final app = list[i];
                  final flag = selected[app.packageName];
                  final auto = flag != null && PkgFlag.autoSelection.check(flag) && !PkgFlag.userSelection.check(flag);
                  return _AppTile(
                    app: app,
                    checked: isOn(app.packageName),
                    auto: auto && isOn(app.packageName),
                    onTap: () async {
                      if (!enabled) await ref.read(Preferences.perAppProxyEnabled.notifier).update(true);
                      await ref.read(AppListProvider(mode).notifier).updatePkg(app.packageName);
                    },
                  );
                },
              ),
              AsyncError() => const Center(child: Text('Не удалось получить список приложений')),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }

  Future<void> _setMode(WidgetRef ref, AppProxyMode mode) async {
    await ref.read(Preferences.perAppProxyMode.notifier).update(mode);
    await ref.read(Preferences.perAppProxyEnabled.notifier).update(true);
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: active ? OrbitColors.accent : Colors.transparent, width: 2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          color: active ? OrbitColors.textPrimary : OrbitColors.textSecondary,
        ),
      ),
    ),
  );
}

class _AppTile extends StatelessWidget {
  const _AppTile({required this.app, required this.checked, required this.auto, required this.onTap});

  final AppPackageInfo app;
  final bool checked;
  final bool auto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox.square(
              dimension: 34,
              child: app.icon != null
                  ? Image.memory(app.icon!, cacheWidth: 96, cacheHeight: 96, gaplessPlayback: true)
                  : ColoredBox(
                      color: OrbitColors.surfaceHigh,
                      child: Center(
                        child: Text(
                          app.name.isEmpty ? '?' : app.name.characters.first.toUpperCase(),
                          style: OrbitText.caption.copyWith(color: OrbitColors.textPrimary),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(app.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: OrbitText.body),
          ),
          if (auto) Text('авто', style: OrbitText.caption.copyWith(color: OrbitColors.accent, fontSize: 11)),
          Checkbox(value: checked, onChanged: (_) => onTap()),
        ],
      ),
    ),
  );
}
