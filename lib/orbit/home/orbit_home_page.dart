import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/orbit/state/orbit_providers.dart';
import 'package:hiddify/orbit/subscriptions/subscription_sheets.dart';
import 'package:hiddify/orbit/theme/orbit_theme.dart';
import 'package:hiddify/orbit/utils/orbit_format.dart';
import 'package:hiddify/orbit/utils/server_meta.dart';
import 'package:hiddify/orbit/widgets/flower_button.dart';
import 'package:hiddify/orbit/widgets/orbit_widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class OrbitHomePage extends ConsumerWidget {
  const OrbitHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasAny = ref.watch(hasAnyProfileProvider);
    final active = ref.watch(activeProfileProvider);
    return Scaffold(
      body: SafeArea(
        child: switch ((hasAny, active)) {
          (AsyncData(value: false), _) => const _FirstRun(),
          (_, AsyncData(value: final profile?)) => _Home(profile: profile),
          (AsyncData(value: true), AsyncData(value: null)) => const _NoActive(),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }
}

/// 01 · Nothing added yet.
class _FirstRun extends ConsumerWidget {
  const _FirstRun();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
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
            final scanned = await ref.read(dialogNotifierProvider.notifier).showQrScanner();
            if (scanned == null || scanned.isEmpty || !context.mounted) return;
            await showAddSubscriptionSheet(context, scanned);
          },
          child: const Text('Сканировать QR-код', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

class _NoActive extends StatelessWidget {
  const _NoActive();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Подписка не выбрана', style: OrbitText.sheetTitle),
          const SizedBox(height: 16),
          OrbitOutlinedButton(label: 'Выбрать подписку', onPressed: () => showSubscriptionsSheet(context)),
        ],
      ),
    ),
  );
}

/// 02 / 03 · The connect screen.
class _Home extends ConsumerWidget {
  const _Home({required this.profile});

  final ProfileEntity profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionNotifierProvider);
    final connected = status.valueOrNull is Connected;
    final summary = summarize(profile);

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
          child: _SubscriptionHeader(profile: profile, summary: summary, connected: connected),
        ),
        Expanded(child: Center(child: _ConnectArea(status: status))),
        Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), child: _ServerCard(profile: profile)),
      ],
    );
  }
}

class _SubscriptionHeader extends ConsumerWidget {
  const _SubscriptionHeader({required this.profile, required this.summary, required this.connected});

  final ProfileEntity profile;
  final SubscriptionSummary summary;
  final bool connected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updating = profile is RemoteProfileEntity && ref.watch(updateProfileNotifierProvider(profile.id)).isLoading;
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
                    profile.name,
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
  const _ConnectArea({required this.status});

  final AsyncValue<ConnectionStatus> status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = status.valueOrNull;
    final failed = status.hasError || (value is Disconnected && value.connectionFailure != null);
    final flower = switch (value) {
      Connected() => FlowerState.on,
      Connecting() || Disconnecting() => FlowerState.busy,
      _ => FlowerState.off,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FlowerButton(
          state: flower,
          onTap: () => ref.read(connectionNotifierProvider.notifier).toggleConnection(),
        ),
        // the glow around the flower takes room of its own; pull the text up into it
        Transform.translate(
          offset: const Offset(0, -44),
          child: SizedBox(
            height: 48,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: switch (value) {
                Connected() => const _Connected(key: ValueKey('on')),
                Connecting() => const _Status(key: ValueKey('connecting'), title: 'Подключение…'),
                Disconnecting() => const _Status(key: ValueKey('disconnecting'), title: 'Отключение…'),
                _ when failed => const _Status(
                  key: ValueKey('failed'),
                  title: 'Не удалось подключиться',
                  subtitle: 'Нажмите, чтобы повторить',
                  color: OrbitColors.danger,
                ),
                _ => const _Status(
                  key: ValueKey('off'),
                  title: 'Отключено',
                  subtitle: 'Нажмите, чтобы подключиться',
                ),
              },
            ),
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
  Widget build(BuildContext context) => Column(
    children: [
      Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
      if (subtitle != null) ...[const SizedBox(height: 6), Text(subtitle!, style: OrbitText.caption)],
    ],
  );
}

class _Connected extends ConsumerWidget {
  const _Connected({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final since = ref.watch(connectedSinceProvider);
    final now = ref.watch(tickerProvider).valueOrNull ?? DateTime.now();
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
  const _ServerCard({required this.profile});

  final ProfileEntity profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(serviceRunningProvider);
    final list = ref.watch(serverListProvider(profile)).valueOrNull;
    final selected = list?.selected;

    String name;
    String? country;
    int? delay;
    if (connected) {
      // the outbound in use, which under "Авто" is whichever server won the ping test
      final activeProxy = ref.watch(activeProxyNotifierProvider).valueOrNull;
      final tag = activeProxy == null || activeProxy.tag.isEmpty
          ? null
          : (activeProxy.groupSelectedTagDisplay.isNotEmpty
                ? activeProxy.groupSelectedTagDisplay
                : (activeProxy.tagDisplay.isNotEmpty ? activeProxy.tagDisplay : activeProxy.tag));
      name = tag != null ? displayName(tag) : (selected?.name ?? 'Сервер');
      country = guessCountry(tag ?? selected?.tag ?? '', ipCountry: activeProxy?.ipinfo.countryCode);
      delay = activeProxy?.urlTestDelay;
      if (selected?.isAuto ?? false) name = 'Авто · $name';
    } else {
      name = selected == null ? 'Авто' : selected.name;
      country = selected?.country;
    }

    return Material(
      color: OrbitColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.goNamed('servers'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              if (selected?.isAuto ?? true) ...[
                if (connected && country != null)
                  FlagBadge(countryCode: country, size: 26)
                else
                  const _AutoBadge(),
              ] else
                FlagBadge(countryCode: country, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              if (connected) PingLabel(delay: delay, unit: true, highlight: true),
              const SizedBox(width: 10),
              const Icon(Icons.chevron_right_rounded, size: 20, color: OrbitColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _AutoBadge extends StatelessWidget {
  const _AutoBadge();

  @override
  Widget build(BuildContext context) => Container(
    width: 26,
    height: 19,
    decoration: BoxDecoration(color: OrbitColors.surfaceHighest, borderRadius: BorderRadius.circular(4)),
    child: const Icon(Icons.bolt_rounded, size: 14, color: OrbitColors.accent),
  );
}
