import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbit/core/native.dart';
import 'package:orbit/data/settings.dart';
import 'package:orbit/state/providers.dart';
import 'package:orbit/theme/orbit_theme.dart';

final _appsProvider = FutureProvider.autoDispose<List<InstalledApp>>((ref) async {
  final apps = await Native.installedApps();
  return apps..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
});

/// 08 · Which apps go through the tunnel.
class AppsPage extends ConsumerStatefulWidget {
  const AppsPage({super.key});

  @override
  ConsumerState<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends ConsumerState<AppsPage> {
  String _query = '';
  bool _showSystem = false;

  /// Picked apps go first; the order is fixed when the page opens so rows do not jump on a tap.
  late final Set<String> _pickedAtOpen = {...ref.read(settingsProvider).apps};

  Future<void> _setMode(AppsMode mode) =>
      ref.read(settingsProvider.notifier).change((s) => s.copyWith(appsMode: mode), reconnect: true);

  Future<void> _toggle(String package) => ref
      .read(settingsProvider.notifier)
      .change(
        (s) => s.copyWith(
          apps: s.apps.contains(package) ? ({...s.apps}..remove(package)) : {...s.apps, package},
          // picking an app while everything goes through the tunnel means "only these"
          appsMode: s.appsMode == AppsMode.all ? AppsMode.include : s.appsMode,
        ),
        reconnect: true,
      );

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final apps = ref.watch(_appsProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text('Приложения через VPN', style: OrbitText.sheetTitle),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: OrbitColors.textSecondary),
            onSelected: (v) async {
              switch (v) {
                case 'system':
                  setState(() => _showSystem = !_showSystem);
                case 'all':
                  await _setMode(AppsMode.all);
                case 'clear':
                  await ref.read(settingsProvider.notifier).change((s) => s.copyWith(apps: {}), reconnect: true);
              }
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(value: 'system', checked: _showSystem, child: const Text('Системные')),
              const PopupMenuItem(value: 'all', child: Text('Все через VPN')),
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
                  active: settings.appsMode == AppsMode.include,
                  onTap: () => _setMode(AppsMode.include),
                ),
                const SizedBox(width: 18),
                _ModeTab(
                  label: 'Кроме выбранных',
                  active: settings.appsMode == AppsMode.exclude,
                  onTap: () => _setMode(AppsMode.exclude),
                ),
              ],
            ),
          ),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Divider()),
          if (settings.appsMode == AppsMode.all)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text(
                'Сейчас через VPN идут все приложения. Выберите режим или отметьте приложения.',
                style: OrbitText.caption.copyWith(height: 1.4),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
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
            child: switch (apps) {
              AsyncData(value: final list) => () {
                final visible =
                    list
                        .where((a) => _showSystem || !a.system || settings.apps.contains(a.package))
                        .where(
                          (a) =>
                              _query.isEmpty ||
                              a.name.toLowerCase().contains(_query) ||
                              a.package.toLowerCase().contains(_query),
                        )
                        .toList()
                      ..sort(
                        (a, b) => (_pickedAtOpen.contains(b.package) ? 1 : 0) - (_pickedAtOpen.contains(a.package) ? 1 : 0),
                      );
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  itemCount: visible.length,
                  itemBuilder: (context, i) => _AppTile(
                    app: visible[i],
                    checked: settings.apps.contains(visible[i].package),
                    onTap: () => _toggle(visible[i].package),
                  ),
                );
              }(),
              AsyncError(:final error) => Center(child: Text('Не удалось получить список: $error')),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
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
  const _AppTile({required this.app, required this.checked, required this.onTap});

  final InstalledApp app;
  final bool checked;
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
                  ? Image.memory(app.icon!, gaplessPlayback: true)
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
          Checkbox(value: checked, onChanged: (_) => onTap()),
        ],
      ),
    ),
  );
}
