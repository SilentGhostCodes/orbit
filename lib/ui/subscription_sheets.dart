import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbit/data/models.dart';
import 'package:orbit/state/providers.dart';
import 'package:orbit/theme/orbit_theme.dart';
import 'package:orbit/ui/qr_scanner.dart';
import 'package:orbit/util/format.dart';
import 'package:orbit/widgets/orbit_widgets.dart';

Future<T?> _sheet<T>(BuildContext context, Widget child) => showModalBottomSheet<T>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  backgroundColor: OrbitColors.surface,
  barrierColor: Colors.black.withValues(alpha: .55),
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(top: false, child: child),
  ),
);

Future<void> showSubscriptionsSheet(BuildContext context) => _sheet(context, const SubscriptionsSheet());

Future<void> showAddSubscriptionSheet(BuildContext context, {String? initial}) =>
    _sheet(context, AddSubscriptionSheet(initial: initial));

void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

/// 04 · The list of subscriptions, with the active one ticked.
class SubscriptionsSheet extends ConsumerStatefulWidget {
  const SubscriptionsSheet({super.key});

  @override
  ConsumerState<SubscriptionsSheet> createState() => _SubscriptionsSheetState();
}

class _SubscriptionsSheetState extends ConsumerState<SubscriptionsSheet> {
  bool _updating = false;

  Future<void> _updateAll() async {
    setState(() => _updating = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final notifier = ref.read(subscriptionsProvider.notifier);
    var failed = 0;
    for (final s in ref.read(subscriptionsProvider)) {
      if (s.url == null) continue;
      try {
        await notifier.refresh(s.id);
      } on Object {
        failed++;
      }
    }
    if (mounted) setState(() => _updating = false);
    messenger?.showSnackBar(
      SnackBar(content: Text(failed == 0 ? 'Подписки обновлены' : 'Не обновилось: $failed')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subs = ref.watch(subscriptionsProvider);
    final activeId = ref.watch(activeSubscriptionProvider)?.id;
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
                if (_updating)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  HeaderIconButton(
                    icon: Icons.sync_rounded,
                    tooltip: 'Обновить все',
                    color: OrbitColors.textSecondary,
                    onPressed: _updateAll,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: subs.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, i) => _SubscriptionTile(sub: subs[i], active: subs[i].id == activeId),
              ),
            ),
            const SizedBox(height: 16),
            OrbitOutlinedButton(
              label: 'Добавить подписку',
              icon: Icons.add_rounded,
              onPressed: () {
                Navigator.of(context).pop();
                showAddSubscriptionSheet(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SubscriptionTile extends ConsumerWidget {
  const _SubscriptionTile({required this.sub, required this.active});

  final Subscription sub;
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = summarize(sub);
    final updating = ref.watch(updatingProvider).contains(sub.id);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        Navigator.of(context).pop();
        if (active) return;
        await ref.read(settingsProvider.notifier).change((s) => s.copyWith(activeSubscription: sub.id));
        await ref.read(connectionProvider.notifier).reconnectIfConnected();
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
                    sub.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OrbitText.bodyStrong.copyWith(
                      fontSize: 14,
                      color: active ? OrbitColors.accent : OrbitColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text.rich(
                    TextSpan(
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
                        TextSpan(text: ' · ${serversLabel(sub.servers.length)}'),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (updating)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (active)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.check_rounded, color: OrbitColors.accent, size: 20),
              ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, size: 20, color: OrbitColors.textSecondary),
              onSelected: (action) async {
                final notifier = ref.read(subscriptionsProvider.notifier);
                switch (action) {
                  case 'update':
                    try {
                      await notifier.refresh(sub.id);
                      if (context.mounted) _toast(context, 'Обновлено');
                    } on Object catch (e) {
                      if (context.mounted) _toast(context, e.toString());
                    }
                  case 'copy':
                    await Clipboard.setData(ClipboardData(text: sub.url!));
                    if (context.mounted) _toast(context, 'Ссылка скопирована');
                  case 'auto':
                    await notifier.setAutoUpdate(sub.id, !sub.autoUpdate);
                  case 'delete':
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Удалить подписку?', style: OrbitText.sheetTitle),
                        content: Text('«${sub.name}» и её серверы пропадут.', style: OrbitText.body),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Удалить', style: TextStyle(color: OrbitColors.danger)),
                          ),
                        ],
                      ),
                    );
                    if (ok ?? false) await notifier.remove(sub.id);
                }
              },
              itemBuilder: (_) => [
                if (sub.url != null) const PopupMenuItem(value: 'update', child: Text('Обновить')),
                if (sub.url != null) const PopupMenuItem(value: 'copy', child: Text('Скопировать ссылку')),
                if (sub.url != null)
                  CheckedPopupMenuItem(value: 'auto', checked: sub.autoUpdate, child: const Text('Автообновление')),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Удалить', style: TextStyle(color: OrbitColors.danger)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 05 · Adding a subscription by link, from the clipboard or a QR code.
class AddSubscriptionSheet extends ConsumerStatefulWidget {
  const AddSubscriptionSheet({super.key, this.initial});

  final String? initial;

  @override
  ConsumerState<AddSubscriptionSheet> createState() => _AddSubscriptionSheetState();
}

class _AddSubscriptionSheetState extends ConsumerState<AddSubscriptionSheet> {
  late final _controller = TextEditingController(text: widget.initial);
  bool _autoUpdate = true;
  bool _adding = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _adding) return;
    setState(() => _adding = true);
    try {
      final sub = await ref.read(subscriptionsProvider.notifier).add(text, autoUpdate: _autoUpdate);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop();
      messenger?.showSnackBar(SnackBar(content: Text('«${sub.name}»: ${serversLabel(sub.servers.length)}')));
    } on Object catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final empty = _controller.text.trim().isEmpty;
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
            controller: _controller,
            autofocus: widget.initial == null,
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
                borderSide: BorderSide(
                  color: _error != null
                      ? OrbitColors.danger
                      : (empty ? OrbitColors.surfaceHighest : OrbitColors.accent),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _error != null ? OrbitColors.danger : OrbitColors.accent, width: 1.4),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: OrbitText.caption.copyWith(color: OrbitColors.danger)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OrbitTonalButton(
                  label: 'Вставить',
                  icon: Icons.content_paste_rounded,
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    final clip = data?.text?.trim();
                    if (clip != null && clip.isNotEmpty) _controller.text = clip;
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OrbitTonalButton(
                  label: 'QR-код',
                  icon: Icons.qr_code_scanner_rounded,
                  onPressed: () async {
                    final scanned = await scanQr(context);
                    if (scanned != null) _controller.text = scanned;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          OrbitSwitchTile(
            title: 'Автообновление',
            subtitle: 'Каждые 12 часов',
            value: _autoUpdate,
            divider: false,
            onChanged: (v) => setState(() => _autoUpdate = v),
          ),
          const SizedBox(height: 14),
          OrbitPrimaryButton(label: 'Добавить', loading: _adding, onPressed: empty ? null : _submit),
        ],
      ),
    );
  }
}
