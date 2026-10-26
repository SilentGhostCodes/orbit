import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbit/core/native.dart';
import 'package:orbit/data/models.dart';
import 'package:orbit/state/providers.dart';
import 'package:orbit/theme/orbit_theme.dart';
import 'package:orbit/ui/qr_scanner.dart';
import 'package:orbit/ui/shell.dart';
import 'package:orbit/ui/subscription_sheets.dart';
import 'package:orbit/util/format.dart';
import 'package:orbit/util/server_meta.dart';
import 'package:orbit/widgets/flower_button.dart';
import 'package:orbit/widgets/orbit_widgets.dart';

final _tickerProvider = StreamProvider.autoDispose<DateTime>(
  (ref) => Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()),
);

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(activeSubscriptionProvider);
    return Scaffold(body: SafeArea(child: sub == null ? const _FirstRun() : _Home(sub: sub)));
  }
}

/// 01 · Nothing added yet.
class _FirstRun extends StatelessWidget {
  const _FirstRun();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
    child: Column(
      children: [
        const Spacer(flex: 5),
        const OrbitLogo(size: 64),
        const SizedBox(height: 24),
        const Text('Нет подписок', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Text(
          'Добавьте ссылку на подписку,\nчтобы начать',
          textAlign: TextAlign.center,
          style: OrbitText.caption.copyWith(fontSize: 14, height: 1.4),
        ),
        const Spacer(flex: 6),
        OrbitPrimaryButton(label: 'Добавить подписку', onPressed: () => showAddSubscriptionSheet(context)),
        const SizedBox(height: 8),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: OrbitColors.textPrimary),
          onPressed: () async {
            final scanned = await scanQr(context);
            if (scanned != null && context.mounted) await showAddSubscriptionSheet(context, initial: scanned);
          },
          child: const Text('Сканировать QR-код', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

/// 02 / 03 · The connect screen.
class _Home extends ConsumerWidget {
  const _Home({required this.sub});

  final Subscription sub;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(vpnStateProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
          child: Row(
            children: [
              const OrbitLogo(size: 16),
              const SizedBox(width: 8),
              const Text('Orbit', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const Spacer(),
              HeaderIconButton(
                icon: Icons.add_rounded,
                tooltip: 'Добавить подписку',
                onPressed: () => showAddSubscriptionSheet(context),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _SubscriptionHeader(sub: sub, connected: state == VpnState.connected),
        ),
        const Expanded(child: Center(child: _ConnectArea())),
        Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), child: _ServerCard(sub: sub)),
      ],
    );
  }
}

class _SubscriptionHeader extends ConsumerWidget {
  const _SubscriptionHeader({required this.sub, required this.connected});

  final Subscription sub;
  final bool connected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = summarize(sub);
    final updating = ref.watch(updatingProvider).contains(sub.id);
    return InkWell(
      onTap: () => showSubscriptionsSheet(context),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    sub.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: OrbitColors.textSecondary),
                if (updating) ...[
                  const SizedBox(width: 6),
                  const SizedBox.square(dimension: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
                ],
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: connected ? OrbitColors.accent : const Color(0xFF8A8B90)),
                duration: const Duration(milliseconds: 400),
                builder: (context, color, _) => LinearProgressIndicator(
                  value: summary.ratio ?? 1,
                  minHeight: 2.5,
                  color: color,
                  backgroundColor: OrbitColors.surfaceHighest,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: summary.traffic),
                  if (summary.days != null) ...[
                    const TextSpan(text: ' · '),
                    TextSpan(
                      text: summary.days,
                      style: summary.daysLow ? const TextStyle(color: OrbitColors.warning) : null,
                    ),
                  ],
                ],
              ),
              style: OrbitText.caption.copyWith(fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectArea extends ConsumerWidget {
  const _ConnectArea();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(vpnStatusProvider).value ?? VpnStatus.disconnected;
    final ui = ref.watch(connectionProvider);
    final error = ui.error ?? status.error;
    final busy = ui.picking || status.state == VpnState.connecting || status.state == VpnState.disconnecting;
    final flower = switch (status.state) {
      VpnState.connected => FlowerState.on,
      _ when busy => FlowerState.busy,
      _ => FlowerState.off,
    };

    final Widget label = switch (status.state) {
      VpnState.connected => const _Connected(key: ValueKey('on')),
      VpnState.connecting => const _Status(key: ValueKey('connecting'), title: 'Подключение…'),
      VpnState.disconnecting => const _Status(key: ValueKey('disconnecting'), title: 'Отключение…'),
      _ when ui.picking => const _Status(
        key: ValueKey('picking'),
        title: 'Подбираю сервер…',
        subtitle: 'Проверяю пинг',
      ),
      _ when error != null => _Status(
        key: const ValueKey('failed'),
        title: 'Не удалось подключиться',
        subtitle: error,
        color: OrbitColors.danger,
      ),
      _ => const _Status(key: ValueKey('off'), title: 'Отключено', subtitle: 'Нажмите, чтобы подключиться'),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FlowerButton(
          state: flower,
          onTap: ui.picking ? null : () => ref.read(connectionProvider.notifier).toggle(),
        ),
        // the glow around the flower takes room of its own; pull the text up into it
        Transform.translate(
          offset: const Offset(0, -44),
          child: SizedBox(
            height: 64,
            child: AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: label),
          ),
        ),
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({super.key, required this.title, this.subtitle, this.color = OrbitColors.textPrimary});

  final String title;
  final String? subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32),
    child: Column(
      children: [
        Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: OrbitText.caption,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    ),
  );
}

class _Connected extends ConsumerWidget {
  const _Connected({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final since = ref.watch(vpnStatusProvider).value?.since;
    final now = ref.watch(_tickerProvider).value ?? DateTime.now();
    final elapsed = since == null ? Duration.zero : now.difference(since);
    return Column(
      children: [
        const Text(
          'Подключено',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: OrbitColors.accent),
        ),
        const SizedBox(height: 6),
        Text(
          formatElapsed(elapsed.isNegative ? Duration.zero : elapsed),
          style: OrbitText.mono.copyWith(color: OrbitColors.textSecondary, fontSize: 13),
        ),
      ],
    );
  }
}

class _ServerCard extends ConsumerWidget {
  const _ServerCard({required this.sub});

  final Subscription sub;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentServerProvider);
    final connected = ref.watch(vpnStateProvider) == VpnState.connected;
    final delay = current.name == null ? null : ref.watch(pingsProvider).shown(sub.id, current.name!);
    final name = current.name == null
        ? 'Авто'
        : (current.auto && connected ? 'Авто · ${displayNameOf(current.name!)}' : displayNameOf(current.name!));

    return Material(
      color: OrbitColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => ref.read(tabProvider.notifier).go(1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              if (current.name == null) const AutoBadge() else FlagBadge(countryCode: guessCountry(current.name!), size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              PingLabel(delay: delay, unit: true, highlight: connected),
              const SizedBox(width: 10),
              const Icon(Icons.chevron_right_rounded, size: 20, color: OrbitColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
