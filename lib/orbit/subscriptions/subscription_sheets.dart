import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/orbit/state/orbit_providers.dart';
import 'package:hiddify/orbit/theme/orbit_theme.dart';
import 'package:hiddify/orbit/utils/orbit_format.dart';
import 'package:hiddify/orbit/widgets/orbit_widgets.dart';
import 'package:hiddify/utils/link_parsers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

Future<T?> _showOrbitSheet<T>(BuildContext? context, Widget child) {
  final ctx = context ?? rootNavKey.currentContext!;
  return showModalBottomSheet<T>(
    context: ctx,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: OrbitColors.surface,
    barrierColor: Colors.black.withValues(alpha: .55),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(top: false, child: child),
    ),
  );
}

Future<void> showSubscriptionsSheet([BuildContext? context]) => _showOrbitSheet(context, const SubscriptionsSheet());

Future<void> showAddSubscriptionSheet([BuildContext? context, String? url]) =>
    _showOrbitSheet(context, AddSubscriptionSheet(initialUrl: url));

/// 04 · The list of subscriptions, with the active one ticked.
class SubscriptionsSheet extends HookConsumerWidget {
  const SubscriptionsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profilesNotifierProvider);
    final updating = useState(false);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            Row(
              children: [
                const Expanded(child: Text('Подписки', style: OrbitText.sheetTitle)),
                if (updating.value)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  HeaderIconButton(
                    icon: Icons.sync_rounded,
                    tooltip: 'Обновить все',
                    color: OrbitColors.textSecondary,
                    onPressed: () async {
                      updating.value = true;
                      try {
                        await ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger();
                      } finally {
                        if (context.mounted) updating.value = false;
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: switch (profiles) {
                AsyncData(value: final list) => ListView.separated(
                  shrinkWrap: true,
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, i) => _SubscriptionTile(profile: list[i]),
                ),
                AsyncError() => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Не удалось загрузить подписки', style: OrbitText.caption),
                ),
                _ => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              },
            ),
            const SizedBox(height: 16),
            OrbitOutlinedButton(
              label: 'Добавить подписку',
              icon: Icons.add_rounded,
              onPressed: () {
                Navigator.of(context).pop();
                showAddSubscriptionSheet();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SubscriptionTile extends HookConsumerWidget {
  const _SubscriptionTile({required this.profile});

  final ProfileEntity profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = summarize(profile);
    final servers = ref.watch(profileServersProvider(profile.id)).valueOrNull;
    final update = profile is RemoteProfileEntity ? ref.watch(updateProfileNotifierProvider(profile.id)) : null;

    final details = TextSpan(
      style: OrbitText.caption.copyWith(fontSize: 11.5),
      children: [
        TextSpan(text: summary.traffic),
        if (summary.days != null) ...[
          const TextSpan(text: ' · '),
          TextSpan(
            text: summary.days,
            style: summary.daysLow ? const TextStyle(color: OrbitColors.warning) : null,
          ),
        ],
        if (servers != null && servers.isNotEmpty) TextSpan(text: ' · ${serversLabel(servers.length)}'),
      ],
    );

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        if (!profile.active) await ref.read(profilesNotifierProvider.notifier).selectActiveProfile(profile.id);
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OrbitText.bodyStrong.copyWith(
                      fontSize: 14,
                      color: profile.active ? OrbitColors.accent : OrbitColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text.rich(details, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (update?.isLoading ?? false)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (profile.active)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.check_rounded, color: OrbitColors.accent, size: 20),
              ),
            _SubscriptionMenu(profile: profile),
          ],
        ),
      ),
    );
  }
}

class _SubscriptionMenu extends ConsumerWidget {
  const _SubscriptionMenu({required this.profile});

  final ProfileEntity profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remote = profile is RemoteProfileEntity ? profile as RemoteProfileEntity : null;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, size: 20, color: OrbitColors.textSecondary),
      onSelected: (action) async {
        switch (action) {
          case 'update':
            await ref.read(updateProfileNotifierProvider(profile.id).notifier).updateProfile(remote!);
          case 'copy':
            await Clipboard.setData(ClipboardData(text: remote!.url));
            if (context.mounted) {
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Ссылка скопирована')));
            }
          case 'delete':
            final confirmed = await ref
                .read(dialogNotifierProvider.notifier)
                .showConfirmation(title: 'Удалить подписку?', message: '«${profile.name}» и её серверы пропадут.');
            if (confirmed) await ref.read(profilesNotifierProvider.notifier).deleteProfile(profile);
        }
      },
      itemBuilder: (_) => [
        if (remote != null) const PopupMenuItem(value: 'update', child: Text('Обновить')),
        if (remote != null) const PopupMenuItem(value: 'copy', child: Text('Скопировать ссылку')),
        const PopupMenuItem(
          value: 'delete',
          child: Text('Удалить', style: TextStyle(color: OrbitColors.danger)),
        ),
      ],
    );
  }
}

/// 05 · Adding a subscription by link, from the clipboard or a QR code.
class AddSubscriptionSheet extends HookConsumerWidget {
  const AddSubscriptionSheet({super.key, this.initialUrl});

  final String? initialUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useTextEditingController(text: initialUrl);
    final text = useValueListenable(controller).text.trim();
    final autoUpdate = useState(true);
    final hours = ref.watch(OrbitPrefs.defaultUpdateHours);
    final adding = ref.watch(addProfileNotifierProvider).isLoading;

    ref.listen(addProfileNotifierProvider, (prev, next) {
      final added = next is AsyncData && next.value != null;
      if ((prev?.isLoading ?? false) && added && context.mounted) Navigator.of(context).pop();
    });

    Future<void> submit() async {
      if (text.isEmpty) return;
      final notifier = ref.read(addProfileNotifierProvider.notifier);
      final link = LinkParser.parse(text);
      if (link != null) {
        await notifier.addManual(
          url: link.url,
          userOverride: UserOverride(
            name: link.name.isNotEmpty ? link.name : null,
            updateInterval: hours,
            isAutoUpdateDisable: !autoUpdate.value,
          ),
        );
      } else {
        // raw vless://, trojan:// … lines or a whole config
        await notifier.addClipboard(text);
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHandle(),
          const Text('Новая подписка', style: OrbitText.sheetTitle),
          const SizedBox(height: 18),
          const Text('Ссылка', style: OrbitText.caption),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            autofocus: initialUrl == null,
            minLines: 1,
            maxLines: 3,
            keyboardType: TextInputType.url,
            style: OrbitText.mono.copyWith(color: OrbitColors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'https://sub.example.com/…',
              hintStyle: OrbitText.mono.copyWith(color: OrbitColors.textTertiary, fontSize: 13),
              filled: true,
              fillColor: OrbitColors.background,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: text.isEmpty ? OrbitColors.surfaceHighest : OrbitColors.accent),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: OrbitColors.accent, width: 1.4),
              ),
            ),
            onSubmitted: (_) => submit(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OrbitTonalButton(
                  label: 'Вставить',
                  icon: Icons.content_paste_rounded,
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text case final clip? when clip.trim().isNotEmpty) controller.text = clip.trim();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OrbitTonalButton(
                  label: 'QR-код',
                  icon: Icons.qr_code_scanner_rounded,
                  onPressed: () async {
                    final scanned = await ref.read(dialogNotifierProvider.notifier).showQrScanner();
                    if (scanned != null && scanned.isNotEmpty) controller.text = scanned;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          OrbitSwitchTile(
            title: 'Автообновление',
            subtitle: 'Каждые $hours ${plural(hours, 'час', 'часа', 'часов')}',
            value: autoUpdate.value,
            divider: false,
            onChanged: (v) => autoUpdate.value = v,
          ),
          const SizedBox(height: 14),
          OrbitPrimaryButton(label: 'Добавить', loading: adding, onPressed: text.isEmpty ? null : submit),
        ],
      ),
    );
  }
}
