import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbit/data/settings.dart';
import 'package:orbit/state/providers.dart';
import 'package:orbit/theme/orbit_theme.dart';
import 'package:orbit/widgets/orbit_widgets.dart';

/// Фрагментация TLS: on or off, and how the packets are cut. Changes to the numbers take effect
/// when the page is left, so typing does not reconnect on every key.
class FragmentPage extends ConsumerStatefulWidget {
  const FragmentPage({super.key});

  @override
  ConsumerState<FragmentPage> createState() => _FragmentPageState();
}

class _FragmentPageState extends ConsumerState<FragmentPage> {
  late final Fragment _initial = ref.read(settingsProvider).fragmentSettings;
  late final _packets = TextEditingController(text: _initial.packets);
  late final _length = TextEditingController(text: _initial.length);
  late final _interval = TextEditingController(text: _initial.interval);

  static const _packetPresets = {
    'tlshello': 'Только TLS Hello',
    '1-1': 'Первый пакет',
    '1-3': 'Пакеты 1–3',
    '1-5': 'Пакеты 1–5',
  };

  @override
  void dispose() {
    _packets.dispose();
    _length.dispose();
    _interval.dispose();
    super.dispose();
  }

  /// Saves the fields that are valid; the others keep their last good value.
  void _save() {
    final current = ref.read(settingsProvider).fragmentSettings;
    final next = Fragment(
      packets: Fragment.validPackets(_packets.text) ? _packets.text.trim() : current.packets,
      length: Fragment.validRange(_length.text) ? _length.text.trim() : current.length,
      interval: Fragment.validRange(_interval.text) ? _interval.text.trim() : current.interval,
    );
    setState(() {});
    if (next != current) ref.read(settingsProvider.notifier).change((s) => s.copyWith(fragmentSettings: next));
  }

  void _reset() {
    _packets.text = Fragment.defaults.packets;
    _length.text = Fragment.defaults.length;
    _interval.text = Fragment.defaults.interval;
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final note = OrbitText.caption.copyWith(height: 1.45);

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && s.fragment && s.fragmentSettings != _initial) {
          ref.read(connectionProvider.notifier).reconnectIfConnected();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: const Text('Фрагментация', style: OrbitText.sheetTitle),
          actions: [
            TextButton(onPressed: _reset, child: const Text('Сбросить')),
            const SizedBox(width: 8),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            OrbitSwitchTile(
              title: 'Фрагментация TLS',
              subtitle: 'Помогает, если сервер режет DPI',
              value: s.fragment,
              divider: false,
              onChanged: (v) => notifier.change((s) => s.copyWith(fragment: v), reconnect: true),
            ),
            const SizedBox(height: 4),
            Text(
              'Первые пакеты соединения режутся на куски с паузами, чтобы DPI не увидел имя сайта '
              'в TLS Hello целиком. Если сервер на своей стороне уже настроил фрагментацию, '
              'используется его настройка.',
              style: note,
            ),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: s.fragment ? 1 : .45,
              child: IgnorePointer(
                ignoring: !s.fragment,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionLabel('Пакеты'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final e in _packetPresets.entries)
                          _Preset(
                            label: e.value,
                            selected: _packets.text.trim() == e.key,
                            onTap: () {
                              _packets.text = e.key;
                              _save();
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _Field(
                      controller: _packets,
                      hint: 'tlshello',
                      valid: Fragment.validPackets(_packets.text),
                      error: '«tlshello» или номера пакетов, например 1-3',
                      onChanged: _save,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'TLS Hello: режется только первое сообщение TLS с именем сайта. Номера пакетов '
                      '(1-3) режут сами первые пакеты соединения, это грубее, но иногда помогает там, '
                      'где TLS Hello не спасает.',
                      style: note,
                    ),
                    const SectionLabel('Длина кусков, байт'),
                    const SizedBox(height: 6),
                    _Field(
                      controller: _length,
                      hint: '100-200',
                      valid: Fragment.validRange(_length.text),
                      error: 'Число или диапазон, например 100-200',
                      onChanged: _save,
                    ),
                    const SizedBox(height: 8),
                    Text('Каждый кусок берёт случайную длину из диапазона.', style: note),
                    const SectionLabel('Интервал, мс'),
                    const SizedBox(height: 6),
                    _Field(
                      controller: _interval,
                      hint: '10-20',
                      valid: Fragment.validRange(_interval.text),
                      error: 'Число или диапазон, например 10-20',
                      onChanged: _save,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Пауза между кусками. Больше — надёжнее против DPI, но медленнее открываются сайты; '
                      '0 — без пауз.',
                      style: note,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Preset extends StatelessWidget {
  const _Preset({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? OrbitColors.accent.withValues(alpha: .14) : OrbitColors.surface,
    shape: StadiumBorder(side: BorderSide(color: selected ? OrbitColors.accent : OrbitColors.divider)),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          label,
          style: OrbitText.body.copyWith(fontSize: 13, color: selected ? OrbitColors.accent : OrbitColors.textPrimary),
        ),
      ),
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.valid,
    required this.error,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final bool valid;
  final String error;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: controller,
        autocorrect: false,
        style: OrbitText.mono.copyWith(color: OrbitColors.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: OrbitText.mono.copyWith(color: OrbitColors.textTertiary, fontSize: 13),
          filled: true,
          fillColor: OrbitColors.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: valid ? OrbitColors.surfaceHighest : OrbitColors.danger),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: valid ? OrbitColors.accent : OrbitColors.danger, width: 1.4),
          ),
        ),
        onChanged: (_) => onChanged(),
      ),
      if (!valid) ...[
        const SizedBox(height: 6),
        Text(error, style: OrbitText.caption.copyWith(color: OrbitColors.danger)),
      ],
    ],
  );
}
