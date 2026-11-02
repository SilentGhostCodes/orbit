import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbit/data/models.dart';
import 'package:orbit/data/qwdtt.dart';
import 'package:orbit/state/providers.dart';
import 'package:orbit/theme/orbit_theme.dart';
import 'package:orbit/ui/subscription_sheets.dart';
import 'package:orbit/util/format.dart';
import 'package:orbit/widgets/orbit_widgets.dart';

/// 06 · Servers of the active subscription.
class ServersPage extends ConsumerWidget {
  const ServersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(activeSubscriptionProvider);
    return Scaffold(
      body: SafeArea(
        child: sub == null
            ? const Center(child: Text('Сначала добавьте подписку', style: OrbitText.caption))
            : _Servers(sub: sub),
      ),
    );
  }
}

class _Servers extends ConsumerWidget {
  const _Servers({required this.sub});

  final Subscription sub;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pings = ref.watch(pingsProvider);
    final picked = ref.watch(settingsProvider.select((s) => s.selectedServers[sub.id]));
    final pinging = sub.servers.any((s) => pings.running.contains(Pings.key(sub.id, s.name)));
    final controller = ref.read(connectionProvider.notifier);

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
                              sub.name,
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
              if (pinging)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                HeaderIconButton(
                  icon: Icons.bolt_rounded,
                  tooltip: 'Проверить пинг',
                  onPressed: () => ref.read(pingsProvider.notifier).pingAll(sub),
                ),
            ],
          ),
        ),
        if (pings.error != null && !pinging)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(
              'Пинг не удался: ${pings.error}',
              style: OrbitText.caption.copyWith(color: OrbitColors.danger),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        Expanded(
          child: sub.servers.isEmpty
              ? const Center(child: Text('В подписке нет серверов', style: OrbitText.caption))
              : RefreshIndicator(
                  onRefresh: () => ref.read(pingsProvider.notifier).pingAll(sub),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      _ServerTile(
                        name: 'Авто',
                        protocol: 'Лучший по пингу',
                        auto: true,
                        selected: picked == null,
                        onTap: () => controller.choose(sub, null),
                      ),
                      for (final (i, s) in sub.servers.indexed)
                        _ServerTile(
                          name: s.displayName,
                          protocol: s.isQwdtt ? _qwdttLine(s) : s.protocol,
                          country: s.country,
                          qwdtt: s.isQwdtt,
                          delay: pings.shown(sub.id, s.name),
                          selected: picked == s.name,
                          last: i == sub.servers.length - 1,
                          onTap: () => controller.choose(sub, s.name),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.name,
    required this.protocol,
    required this.selected,
    required this.onTap,
    this.country,
    this.delay,
    this.auto = false,
    this.last = false,
    this.qwdtt = false,
  });

  final String name;
  final String protocol;
  final String? country;
  final int? delay;
  final bool selected;
  final bool auto;
  final bool last;

  /// Reached through VK calls: a phone badge, and no ping (it would take a call to measure).
  final bool qwdtt;
  final VoidCallback onTap;

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
          if (auto)
            const AutoBadge(size: 28)
          else if (qwdtt)
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(color: OrbitColors.surfaceHighest, shape: BoxShape.circle),
              child: Icon(Icons.phone_in_talk_rounded, size: 15, color: OrbitColors.accent),
            )
          else
            FlagBadge(countryCode: country),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OrbitText.bodyStrong.copyWith(
                    fontSize: 14,
                    color: selected && !auto ? OrbitColors.accent : OrbitColors.textPrimary,
                  ),
                ),
                if (protocol.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(protocol, style: OrbitText.caption.copyWith(fontSize: 11.5)),
                ],
              ],
            ),
          ),
          if (qwdtt)
            Text('через ВК', style: OrbitText.caption.copyWith(fontSize: 12))
          else if (!auto)
            PingLabel(delay: delay),
          SizedBox(
            width: 30,
            child: selected
                ? Align(
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

/// «qWDTT · 2 звонка · 16 потоков».
String _qwdttLine(Server s) {
  final p = QwdttProfile.of(s);
  if (p == null) return 'qWDTT';
  final calls = p.hashes.length;
  return 'qWDTT · $calls ${plural(calls, 'звонок', 'звонка', 'звонков')} · '
      '${p.workers} ${plural(p.workers, 'поток', 'потока', 'потоков')}';
}
