import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbit/data/settings.dart';
import 'package:orbit/state/providers.dart';
import 'package:orbit/theme/orbit_theme.dart';
import 'package:orbit/widgets/orbit_button.dart';
import 'package:orbit/widgets/orbit_widgets.dart';
import 'package:orbit/widgets/power_button.dart';

/// Оформление: the accent colour and how the connect button looks.
class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(settingsProvider.select((s) => s.buttonStyle));
    final accent = Color(ref.watch(settingsProvider.select((s) => s.accent)));
    void setAccent(Color c) => ref.read(settingsProvider.notifier).change((s) => s.copyWith(accent: c.toARGB32()));
    return Scaffold(
      appBar: AppBar(titleSpacing: 0, title: const Text('Оформление', style: OrbitText.sheetTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          const SectionLabel('Цвет'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 14,
            children: [
              for (final (color, name) in accentPresets)
                _Swatch(color: color, name: name, selected: color == accent, onTap: () => setAccent(color)),
            ],
          ),
          const SizedBox(height: 18),
          Text('Свой оттенок', style: OrbitText.caption),
          const SizedBox(height: 6),
          _HueSlider(
            hue: HSLColor.fromColor(accent).hue,
            custom: !accentPresets.any((p) => p.$1 == accent),
            onChanged: (h) => setAccent(accentOfHue(h)),
          ),
          const SectionLabel('Кнопка включения'),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final (i, style) in PowerButtonStyle.values.indexed) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                  child: _StyleCard(
                    style: style,
                    selected: style == current,
                    onTap: () => ref.read(settingsProvider.notifier).change((s) => s.copyWith(buttonStyle: style)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// A live preview of one button style, shown connected so its animation plays.
class _StyleCard extends StatelessWidget {
  const _StyleCard({required this.style, required this.selected, required this.onTap});

  final PowerButtonStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: OrbitColors.surface,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? OrbitColors.accent : OrbitColors.divider, width: selected ? 1.6 : 1),
        ),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: IgnorePointer(
                child: FittedBox(
                  child: PowerButton(style: style, state: OrbitButtonState.on, onTap: null),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  style.label,
                  style: OrbitText.bodyStrong.copyWith(color: selected ? OrbitColors.accent : OrbitColors.textPrimary),
                ),
                if (selected) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.check_rounded, size: 18, color: OrbitColors.accent),
                ],
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.name, required this.selected, required this.onTap});

  final Color color;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: name,
    child: InkResponse(
      onTap: onTap,
      radius: 28,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 44,
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: selected ? color : Colors.transparent, width: 2),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: selected
              ? Icon(Icons.check_rounded, size: 20, color: HSLColor.fromColor(color).withLightness(.12).toColor())
              : null,
        ),
      ),
    ),
  );
}

/// Any hue, on a rainbow track.
class _HueSlider extends StatelessWidget {
  const _HueSlider({required this.hue, required this.custom, required this.onChanged});

  final double hue;

  /// Whether the current accent came from here rather than a swatch, which shows the thumb.
  final bool custom;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      void pick(Offset local) => onChanged((local.dx / width).clamp(0, 1) * 359);
      return GestureDetector(
        onTapDown: (d) => pick(d.localPosition),
        onHorizontalDragUpdate: (d) => pick(d.localPosition),
        child: SizedBox(
          height: 36,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 14,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  gradient: LinearGradient(colors: [for (var h = 0; h <= 360; h += 30) accentOfHue(h % 360.0)]),
                ),
              ),
              if (custom)
                Positioned(
                  left: (hue / 359 * width - 13).clamp(0, width - 26),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: accentOfHue(hue),
                      shape: BoxShape.circle,
                      border: Border.all(color: OrbitColors.textPrimary, width: 3),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
