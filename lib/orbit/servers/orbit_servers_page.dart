import 'package:flutter/material.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/orbit/state/orbit_providers.dart';
import 'package:hiddify/orbit/subscriptions/subscription_sheets.dart';
import 'package:hiddify/orbit/theme/orbit_theme.dart';
import 'package:hiddify/orbit/widgets/orbit_widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 06 · Servers of the active subscription.
class OrbitServersPage extends ConsumerWidget {
  const OrbitServersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(activeProfileProvider).valueOrNull;
    return Scaffold(
      body: SafeArea(
        child: profile == null
            ? const Center(child: Text('Сначала добавьте подписку', style: OrbitText.caption))
            : _Servers(profile: profile),
      ),
    );
  }
}

class _Servers extends ConsumerWidget {
  const _Servers({required this.profile});

  final ProfileEntity profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(serverListProvider(profile));
    final running = ref.watch(serviceRunningProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Серверы', style: OrbitText.title),
                    const SizedBox(height: 2),
                    InkWell(
                      onTap: () => showSubscriptionsSheet(context),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              profile.name,
                              style: OrbitText.caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: OrbitColors.textSecondary),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              HeaderIconButton(
                icon: Icons.bolt_rounded,
                tooltip: 'Проверить пинг',
                color: running ? OrbitColors.textPrimary : OrbitColors.textTertiary,
                onPressed: () {
                  final group = list.valueOrNull?.groupTag;
                  if (!running || group == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Пинг проверяется при включённом VPN')),
                    );
                    return;
                  }
                  ref.read(proxiesOverviewNotifierProvider.notifier).urlTest(group);
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (list) {
            AsyncData(value: final servers) when servers.rows.length <= 1 => const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Список серверов появится после подключения',
                  textAlign: TextAlign.center,
                  style: OrbitText.caption,
                ),
              ),
            ),
            AsyncData(value: final servers) => ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              itemCount: servers.rows.length,
              itemBuilder: (context, i) => _ServerTile(
                row: servers.rows[i],
                last: i == servers.rows.length - 1,
                onTap: () => _select(ref, servers, servers.rows[i]),
              ),
            ),
            AsyncError() => const Center(child: Text('Не удалось прочитать серверы', style: OrbitText.caption)),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ],
    );
  }

  Future<void> _select(WidgetRef ref, ServerList servers, ServerRow row) async {
    if (servers.live && servers.groupTag != null) {
      await ref.read(proxiesOverviewNotifierProvider.notifier).changeProxy(servers.groupTag!, row.tag);
      return;
    }
    // not connected: remember the choice, and pick it in the core once the tunnel is up
    ref.read(pendingServerProvider.notifier).set(row.tag);
    await ref.read(OrbitPrefs.lastServer.notifier).update(row.tag);
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({required this.row, required this.onTap, required this.last});

  final ServerRow row;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: OrbitColors.divider)),
      ),
      child: Row(
        children: [
          if (row.isAuto)
            Container(
              width: 28,
              height: 20,
              decoration: BoxDecoration(color: OrbitColors.surfaceHighest, borderRadius: BorderRadius.circular(4)),
              child: const Icon(Icons.bolt_rounded, size: 14, color: OrbitColors.accent),
            )
          else
            FlagBadge(countryCode: row.country),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OrbitText.bodyStrong.copyWith(
                    fontSize: 14,
                    color: row.selected && !row.isAuto ? OrbitColors.accent : OrbitColors.textPrimary,
                  ),
                ),
                if (row.protocol.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(row.protocol, style: OrbitText.caption.copyWith(fontSize: 11.5)),
                ],
              ],
            ),
          ),
          if (!row.isAuto) PingLabel(delay: row.delay),
          SizedBox(
            width: 30,
            child: row.selected
                ? const Align(
                    alignment: Alignment.centerRight,
                    child: Icon(Icons.check_rounded, size: 18, color: OrbitColors.accent),
                  )
                : null,
          ),
        ],
      ),
    ),
  );
}
