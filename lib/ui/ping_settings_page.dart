import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbit/data/settings.dart';
import 'package:orbit/state/providers.dart';
import 'package:orbit/theme/orbit_theme.dart';
import 'package:orbit/widgets/orbit_widgets.dart';

/// Пинг: how the server list measures servers.
class PingSettingsPage extends ConsumerWidget {
  const PingSettingsPage({super.key});

  static const _types = {
    PingType.proxyGet: 'GET-запрос к URL-тесту через сервер',
    PingType.proxyHead: 'То же, но HEAD: без тела ответа',
    PingType.tcp: 'Время подключения к порту сервера, напрямую',
    PingType.icmp: 'Эхо-запрос до адреса сервера, напрямую',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final viaProxy = s.pingType.viaProxy;
    final note = OrbitText.caption.copyWith(height: 1.45);

    return Scaffold(
      appBar: AppBar(titleSpacing: 0, title: const Text('Пинг', style: OrbitText.sheetTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          const SectionLabel('Тип пинга'),
          for (final (i, e) in _types.entries.indexed)
            _Choice(
              title: e.key.label,
              subtitle: e.value,
              selected: s.pingType == e.key,
              divider: i != _types.length - 1,
              onTap: () => notifier.change((s) => s.copyWith(pingType: e.key)),
            ),
          const SectionLabel('Режим (via Proxy)'),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: viaProxy ? 1 : .45,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, mode) in PingMode.values.indexed)
                  _Choice(
                    title: mode.label,
                    selected: s.pingMode == mode,
                    divider: i != PingMode.values.length - 1,
                    onTap: viaProxy ? () => notifier.change((s) => s.copyWith(pingMode: mode)) : null,
                  ),
                const SizedBox(height: 8),
                Text(
                  'Применяется только к режимам пинга через прокси. Берётся лучший результат из 2 '
                  'выполненных запросов.',
                  style: note,
                ),
                const SizedBox(height: 8),
                Text(
                  'Double: запросы отправляются в рамках одной сессии ядра с отключенным Keep-Alive. '
                  'Второй запрос выполняется быстрее за счёт кэширования DNS.',
                  style: note,
                ),
                const SizedBox(height: 8),
                Text(
                  'KeepAlive: запросы отправляются в рамках одной сессии ядра и одного инстанса '
                  'транспорта. Второй запрос замеряет чистую скорость ответа через уже установленное '
                  'TLS-соединение.',
                  style: note,
                ),
              ],
            ),
          ),
          const SectionLabel('Тайм-аут пинга'),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: s.pingTimeout.toDouble(),
                  min: 5,
                  max: 15,
                  divisions: 10,
                  label: '${s.pingTimeout} сек',
                  onChanged: (v) => notifier.change((s) => s.copyWith(pingTimeout: v.round())),
                ),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  '${s.pingTimeout} сек',
                  textAlign: TextAlign.end,
                  style: OrbitText.mono.copyWith(color: OrbitColors.textPrimary, fontSize: 13),
                ),
              ),
            ],
          ),
          Text('Сколько ждать ответа от сервера, прежде чем считать его недоступным.', style: note),
          const SectionLabel('Настройки URL-теста'),
          const SizedBox(height: 6),
          _UrlField(
            url: s.pingUrl,
            onChanged: (v) => notifier.change((s) => s.copyWith(pingUrl: v)),
          ),
          const SizedBox(height: 8),
          Text(
            'Адрес, который запрашивается через сервер при пинге через прокси. Лучше всего подходит '
            'быстрый ответ без содержимого, например код 204.',
            style: note,
          ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.title, this.subtitle, required this.selected, required this.onTap, this.divider = true});

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) => OrbitTile(
    title: title,
    subtitle: subtitle,
    divider: divider,
    onTap: onTap,
    trailing: selected
        ? Icon(Icons.check_rounded, color: OrbitColors.accent, size: 20)
        : const SizedBox(width: 20),
  );
}

/// The test URL; saved when it looks like an http(s) address, with a way back to the default.
class _UrlField extends StatefulWidget {
  const _UrlField({required this.url, required this.onChanged});

  final String url;
  final ValueChanged<String> onChanged;

  @override
  State<_UrlField> createState() => _UrlFieldState();
}

class _UrlFieldState extends State<_UrlField> {
  late final _controller = TextEditingController(text: widget.url);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save(String text) {
    final url = text.trim();
    final uri = Uri.tryParse(url);
    final valid = uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
    setState(() => _error = valid ? null : 'Нужен адрес вида https://…');
    if (valid && url != widget.url) widget.onChanged(url);
  }

  void _reset() {
    _controller.text = defaultPingUrl;
    _save(defaultPingUrl);
  }

  @override
  Widget build(BuildContext context) {
    final border = _error != null ? OrbitColors.danger : OrbitColors.surfaceHighest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          keyboardType: TextInputType.url,
          autocorrect: false,
          style: OrbitText.mono.copyWith(color: OrbitColors.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            filled: true,
            fillColor: OrbitColors.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            suffixIcon: IconButton(
              tooltip: 'По умолчанию',
              icon: const Icon(Icons.restart_alt_rounded, size: 20, color: OrbitColors.textSecondary),
              onPressed: _reset,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _error != null ? OrbitColors.danger : OrbitColors.accent, width: 1.4),
            ),
          ),
          onChanged: _save,
          onSubmitted: _save,
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: OrbitText.caption.copyWith(color: OrbitColors.danger)),
        ],
      ],
    );
  }
}
