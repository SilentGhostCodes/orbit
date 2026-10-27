import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbit/data/settings.dart';
import 'package:orbit/state/providers.dart';
import 'package:orbit/theme/orbit_theme.dart';
import 'package:orbit/widgets/orbit_button.dart';
import 'package:orbit/widgets/orbit_widgets.dart';
import 'package:orbit/widgets/power_button.dart';

/// Оформление: how the connect button looks.
class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(settingsProvider.select((s) => s.buttonStyle));
    return Scaffold(
      appBar: AppBar(titleSpacing: 0, title: const Text('Оформление', style: OrbitText.sheetTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
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
                  const Icon(Icons.check_rounded, size: 18, color: OrbitColors.accent),
                ],
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
