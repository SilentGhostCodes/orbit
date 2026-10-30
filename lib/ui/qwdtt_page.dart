import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbit/core/native.dart';
import 'package:orbit/data/models.dart';
import 'package:orbit/data/qwdtt.dart';
import 'package:orbit/data/settings.dart';
import 'package:orbit/state/providers.dart';
import 'package:orbit/theme/orbit_theme.dart';
import 'package:orbit/ui/settings_page.dart';
import 'package:orbit/util/format.dart';
import 'package:orbit/widgets/orbit_widgets.dart';

/// Настройки → qWDTT: how qWDTT reaches VK, and the profiles' call hashes.
class QwdttPage extends ConsumerWidget {
  const QwdttPage({super.key});

  static const _workerChoices = [0, 4, 8, 16, 24, 32];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final profiles = [
      for (final sub in ref.watch(subscriptionsProvider))
        for (final server in sub.servers)
          if (server.isQwdtt) (sub: sub, server: server),
    ];
    final captcha = QwdttCaptcha.byId(s.qwdttCaptcha);

    return Scaffold(
      appBar: AppBar(titleSpacing: 0, title: const Text('qWDTT', style: OrbitText.sheetTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Text(
            'WireGuard через звонки ВК — для мобильного интернета с белыми списками. Бета.',
            style: OrbitText.caption.copyWith(fontSize: 13, height: 1.4),
          ),
          const SectionLabel('Вход в ВК'),
          const Text('Откуда брать доступ к звонкам', style: OrbitText.caption),
          const SizedBox(height: 8),
          _Segmented(
            options: const ['Анонимно', 'Мой аккаунт'],
            selected: s.qwdttVkAccount ? 1 : 0,
            onChanged: (i) async {
              final account = i == 1;
              if (account == s.qwdttVkAccount) return;
              await notifier.change((s) => s.copyWith(qwdttVkAccount: account), reconnect: true);
              // no session yet: straight to signing in
              if (account && !(ref.read(vkAccountProvider).value ?? false)) await Native.vkLogin();
            },
          ),
          const SizedBox(height: 6),
          if (s.qwdttVkAccount) const _VkAccountTile() else const SizedBox(height: 4),
          const SectionLabel('Подключение'),
          OrbitTile(
            title: 'Потоки',
            subtitle: s.qwdttVkAccount
                ? 'С аккаунтом ВК — не больше 4 на звонок'
                : 'Больше — быстрее, но чаще капча',
            value: s.qwdttWorkers == 0 ? 'Из профиля' : '${s.qwdttWorkers}',
            onTap: () => pick<int>(
              context,
              title: 'Потоки',
              current: s.qwdttWorkers,
              options: {
                for (final n in _workerChoices)
                  n: n == 0
                      ? ('Из профиля', 'Сколько указано в ссылке qWDTT')
                      : ('$n ${plural(n, 'поток', 'потока', 'потоков')}', null),
              },
              onSelected: (v) => notifier.change((s) => s.copyWith(qwdttWorkers: v), reconnect: true),
            ),
          ),
          OrbitTile(
            title: 'Капча',
            subtitle: captcha.hint,
            value: captcha.label,
            onTap: () => pick<String>(
              context,
              title: 'Капча ВК',
              current: captcha.id,
              options: {for (final c in QwdttCaptcha.values) c.id: (c.label, c.hint)},
              onSelected: (v) => notifier.change((s) => s.copyWith(qwdttCaptcha: v), reconnect: true),
            ),
          ),
          OrbitTile(
            title: 'DNS для ВК',
            subtitle: 'Через него qWDTT находит серверы звонков',
            value: QwdttDns.byId(s.qwdttDns).label,
            divider: false,
            onTap: () => pick<String>(
              context,
              title: 'DNS для ВК',
              current: s.qwdttDns,
              options: {
                for (final d in QwdttDns.values)
                  d.id: (d.label, d == QwdttDns.yandex ? 'Работает при белых списках' : 'Обычный DNS'),
              },
              onSelected: (v) => notifier.change((s) => s.copyWith(qwdttDns: v), reconnect: true),
            ),
          ),
          const SectionLabel('Хеши звонков'),
          if (profiles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Профилей qWDTT пока нет: добавь ссылку qwdtt:// или wdtt:// через «Новая подписка».',
                style: OrbitText.caption.copyWith(height: 1.4),
              ),
            )
          else
            for (final (i, p) in profiles.indexed)
              _ProfileTile(sub: p.sub, server: p.server, last: i == profiles.length - 1),
          const SizedBox(height: 16),
          OrbitOutlinedButton(
            label: 'Как получить хеш звонка',
            icon: Icons.help_outline_rounded,
            onPressed: () => showHashHelp(context),
          ),
        ],
      ),
    );
  }
}

/// «Анонимно | Мой аккаунт».
class _Segmented extends StatelessWidget {
  const _Segmented({required this.options, required this.selected, required this.onChanged});

  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(color: OrbitColors.surfaceHigh, borderRadius: BorderRadius.circular(12)),
    child: Row(
      children: [
        for (final (i, label) in options.indexed)
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: i == selected ? OrbitColors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: OrbitText.body.copyWith(
                    fontSize: 13.5,
                    color: i == selected ? OrbitColors.onAccent : OrbitColors.textSecondary,
                    fontWeight: i == selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// The VK session qWDTT's account mode uses: sign in, or sign out.
class _VkAccountTile extends ConsumerWidget {
  const _VkAccountTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(vkAccountProvider).value ?? false;
    return OrbitTile(
      title: signedIn ? 'Аккаунт ВК подключён' : 'Войти в ВК',
      subtitle: signedIn ? 'Нажми, чтобы выйти' : 'Без входа qWDTT не подключится в этом режиме',
      value: signedIn ? null : 'Войти',
      divider: false,
      trailing: signedIn ? null : const Icon(Icons.chevron_right_rounded, color: OrbitColors.textSecondary),
      onTap: () async {
        if (!signedIn) return Native.vkLogin();
        final out = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Выйти из ВК?', style: OrbitText.sheetTitle),
            content: const Text('qWDTT в режиме аккаунта не подключится, пока не войдёшь снова.', style: OrbitText.body),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Выйти')),
            ],
          ),
        );
        if (out != true) return;
        await Native.vkLogout();
        // the sign-out runs in the VPN process: ask again in a moment
        await Future<void>.delayed(const Duration(milliseconds: 600));
        ref.invalidate(vkAccountProvider);
      },
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({required this.sub, required this.server, required this.last});

  final Subscription sub;
  final Server server;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = QwdttProfile.of(server);
    final calls = p?.hashes.length ?? 0;
    return OrbitTile(
      title: server.displayName,
      subtitle: '${sub.name} · $calls ${plural(calls, 'звонок', 'звонка', 'звонков')}',
      divider: !last,
      trailing: const Icon(Icons.chevron_right_rounded, color: OrbitColors.textSecondary),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => QwdttProfilePage(subscriptionId: sub.id, serverName: server.name)),
      ),
    );
  }
}

/// One qWDTT profile: its name, call hashes (up to [QwdttProfile.maxHashes]) and streams.
class QwdttProfilePage extends ConsumerStatefulWidget {
  const QwdttProfilePage({super.key, required this.subscriptionId, required this.serverName});

  final String subscriptionId;
  final String serverName;

  @override
  ConsumerState<QwdttProfilePage> createState() => _QwdttProfilePageState();
}

class _QwdttProfilePageState extends ConsumerState<QwdttProfilePage> {
  late final TextEditingController _name;
  final _hashes = <TextEditingController>[];
  late int _workers;
  String? _error;
  bool _saving = false;

  QwdttProfile? _original;
  bool _fromUrl = false;

  @override
  void initState() {
    super.initState();
    final sub = ref.read(subscriptionsProvider).where((s) => s.id == widget.subscriptionId).firstOrNull;
    final server = sub?.servers.where((s) => s.name == widget.serverName).firstOrNull;
    _original = server == null ? null : QwdttProfile.of(server);
    _fromUrl = sub?.url != null;
    _name = TextEditingController(text: _original?.name ?? widget.serverName);
    for (final h in _original?.hashes ?? const <String>[]) {
      _hashes.add(TextEditingController(text: h));
    }
    if (_hashes.isEmpty) _hashes.add(TextEditingController());
    _workers = _original?.workers ?? QwdttProfile.defaultWorkers;
  }

  @override
  void dispose() {
    _name.dispose();
    for (final c in _hashes) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final original = _original;
    if (original == null || _saving) return;
    final QwdttProfile edited;
    try {
      edited = Qwdtt.validated(
        QwdttProfile(
          name: _name.text.trim().isEmpty ? original.name : _name.text.trim(),
          peer: original.peer,
          hashes: [for (final c in _hashes) c.text],
          password: original.password,
          workers: _workers,
          port: original.port,
        ),
      );
    } on QwdttException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    // names are the servers' keys within a subscription
    final sub = ref.read(subscriptionsProvider).where((s) => s.id == widget.subscriptionId).firstOrNull;
    if (sub == null) return;
    if (edited.name != widget.serverName && sub.servers.any((s) => s.name == edited.name)) {
      setState(() => _error = 'В подписке уже есть сервер «${edited.name}»');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(subscriptionsProvider.notifier).updateServer(widget.subscriptionId, widget.serverName, edited.toServer());
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final original = _original;
    return Scaffold(
      appBar: AppBar(titleSpacing: 0, title: const Text('Профиль qWDTT', style: OrbitText.sheetTitle)),
      body: original == null
          ? const Center(child: Text('Профиль не найден', style: OrbitText.caption))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                if (_fromUrl)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: OrbitColors.warning.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Профиль из подписки: при её обновлении правки заменятся тем, что пришлёт сервер.',
                      style: OrbitText.caption.copyWith(color: OrbitColors.warning, height: 1.4),
                    ),
                  ),
                const Text('Название', style: OrbitText.caption),
                const SizedBox(height: 8),
                _Field(controller: _name, hint: original.name, onChanged: () => setState(() => _error = null)),
                const SizedBox(height: 14),
                OrbitTile(title: 'Сервер', value: original.peer, divider: false),
                const SectionLabel('Хеши звонков'),
                Text(
                  'До ${QwdttProfile.maxHashes}. Хеш или вся ссылка vk.com/call/join/… — Orbit возьмёт хеш сам.',
                  style: OrbitText.caption.copyWith(height: 1.4),
                ),
                const SizedBox(height: 10),
                for (final (i, c) in _hashes.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: _Field(
                            controller: c,
                            hint: 'Хеш звонка ${i + 1}',
                            mono: true,
                            onChanged: () => setState(() => _error = null),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Вставить',
                          icon: const Icon(Icons.content_paste_rounded, size: 20, color: OrbitColors.textSecondary),
                          onPressed: () async {
                            final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
                            if (text != null && text.isNotEmpty) setState(() => c.text = text);
                          },
                        ),
                        if (_hashes.length > 1)
                          IconButton(
                            tooltip: 'Убрать',
                            icon: const Icon(Icons.close_rounded, size: 20, color: OrbitColors.textSecondary),
                            onPressed: () {
                              final removed = _hashes.removeAt(i);
                              setState(() => _error = null);
                              // the field lets go of it in this frame
                              WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
                            },
                          ),
                      ],
                    ),
                  ),
                if (_hashes.length < QwdttProfile.maxHashes)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _hashes.add(TextEditingController())),
                      icon: Icon(Icons.add_rounded, size: 18, color: OrbitColors.accent),
                      label: Text('Добавить звонок', style: OrbitText.body.copyWith(color: OrbitColors.accent)),
                    ),
                  ),
                const SectionLabel('Потоки'),
                OrbitTile(
                  title: 'Потоков в профиле',
                  subtitle: ref.watch(settingsProvider.select((s) => s.qwdttWorkers)) > 0
                      ? 'Сейчас действует число из настроек qWDTT'
                      : 'Больше — быстрее, но чаще капча',
                  value: '$_workers',
                  divider: false,
                  onTap: () => pick<int>(
                    context,
                    title: 'Потоков в профиле',
                    current: _workers,
                    options: {
                      for (final n in {4, 8, 12, 16, 18, 24, 32, _workers}.toList()..sort())
                        n: ('$n ${plural(n, 'поток', 'потока', 'потоков')}', null),
                    },
                    onSelected: (v) => setState(() => _workers = v),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: OrbitText.caption.copyWith(color: OrbitColors.danger)),
                ],
                const SizedBox(height: 20),
                OrbitPrimaryButton(label: 'Сохранить', loading: _saving, onPressed: _save),
                const SizedBox(height: 10),
                OrbitOutlinedButton(
                  label: 'Как получить хеш звонка',
                  icon: Icons.help_outline_rounded,
                  onPressed: () => showHashHelp(context),
                ),
              ],
            ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.hint, required this.onChanged, this.mono = false});

  final TextEditingController controller;
  final String hint;
  final VoidCallback onChanged;
  final bool mono;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: (_) => onChanged(),
    style: mono ? OrbitText.mono.copyWith(color: OrbitColors.textPrimary, fontSize: 13) : OrbitText.body,
    decoration: InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: OrbitColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    ),
  );
}

/// «Как получить хеш звонка».
Future<void> showHashHelp(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  backgroundColor: OrbitColors.surface,
  builder: (context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetHandle(),
          const Text('Как получить хеш звонка', style: OrbitText.sheetTitle),
          const SizedBox(height: 14),
          for (final (i, step) in const [
            'Открой ВКонтакте (приложение или vk.com) и создай звонок: «Звонки» → «Создать звонок».',
            'Скопируй ссылку на звонок — она выглядит как vk.com/call/join/…',
            'Вставь её целиком в поле хеша: Orbit сам возьмёт часть после join/.',
            'Выходи из звонка кнопкой «Выйти», а не «Завершить для всех» — иначе ссылка перестанет работать.',
            'Лучше 2–4 звонка в профиле: если ВК закроет один, qWDTT возьмёт другой.',
          ].indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: OrbitColors.accent.withValues(alpha: .16), shape: BoxShape.circle),
                    child: Text('${i + 1}', style: OrbitText.caption.copyWith(color: OrbitColors.accent, fontSize: 12)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(step, style: OrbitText.body.copyWith(height: 1.4))),
                ],
              ),
            ),
        ],
      ),
    ),
  ),
);
