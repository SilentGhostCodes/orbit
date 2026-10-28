import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:orbit/theme/orbit_theme.dart';
import 'package:orbit/util/server_meta.dart';

/// The Orbit mark: a ring with a planet in the middle and a moon on the ring.
class OrbitLogo extends StatelessWidget {
  const OrbitLogo({super.key, this.size = 18, this.color});

  final double size;

  /// The accent when null.
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _OrbitLogoPainter(color ?? OrbitColors.accent));
}

class _OrbitLogoPainter extends CustomPainter {
  _OrbitLogoPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * .16;
    canvas.drawCircle(c, r * .84, stroke);
    final fill = Paint()..color = color;
    canvas.drawCircle(c, r * .4, fill);
    // the moon sits on the ring, up and to the right, with a gap cut round it
    final moon = c + Offset.fromDirection(-math.pi / 4, r * .84);
    canvas.drawCircle(moon, r * .26, Paint()..color = OrbitColors.background);
    canvas.drawCircle(moon, r * .17, fill);
  }

  @override
  bool shouldRepaint(_OrbitLogoPainter old) => old.color != color;
}

/// A rectangular flag for a server, or a neutral globe when the country is unknown.
class FlagBadge extends StatelessWidget {
  const FlagBadge({super.key, this.countryCode, this.size = 28});

  final String? countryCode;
  final double size;

  @override
  Widget build(BuildContext context) {
    final emoji = countryCode == null ? '' : flagEmoji(countryCode!);
    final height = size * .72;
    return SizedBox(
      width: size,
      height: height,
      child: emoji.isEmpty
          ? DecoratedBox(
              decoration: BoxDecoration(color: OrbitColors.surfaceHighest, borderRadius: BorderRadius.circular(4)),
              child: Icon(Icons.public_rounded, size: height * .75, color: OrbitColors.textSecondary),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: Text(emoji, style: const TextStyle(fontSize: 40, height: 1.05)),
              ),
            ),
    );
  }
}

/// The little bar on top of a bottom sheet.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.only(top: 10, bottom: 14),
      width: 32,
      height: 3,
      decoration: BoxDecoration(color: OrbitColors.textTertiary, borderRadius: BorderRadius.circular(2)),
    ),
  );
}

class OrbitPrimaryButton extends StatelessWidget {
  const OrbitPrimaryButton({super.key, required this.label, required this.onPressed, this.loading = false});

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 52,
    child: FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: OrbitColors.accent,
        foregroundColor: OrbitColors.onAccent,
        disabledBackgroundColor: OrbitColors.accent.withValues(alpha: .4),
        disabledForegroundColor: OrbitColors.onAccent.withValues(alpha: .6),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: OrbitFonts.sans, fontSize: 15, fontWeight: FontWeight.w700),
      ),
      onPressed: loading ? null : onPressed,
      child: loading
          ? SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: OrbitColors.onAccent),
            )
          : Text(label),
    ),
  );
}

class OrbitOutlinedButton extends StatelessWidget {
  const OrbitOutlinedButton({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 50,
    child: OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: OrbitColors.textPrimary,
        side: const BorderSide(color: OrbitColors.surfaceHighest),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: OrbitFonts.sans, fontSize: 14, fontWeight: FontWeight.w700),
      ),
      onPressed: onPressed,
      icon: icon == null ? null : Icon(icon, size: 18),
      label: Text(label),
    ),
  );
}

/// A small dark button with an icon, like "Вставить" and "QR-код" on the new subscription sheet.
class OrbitTonalButton extends StatelessWidget {
  const OrbitTonalButton({super.key, required this.label, required this.icon, required this.onPressed});

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: TextButton.icon(
      style: TextButton.styleFrom(
        backgroundColor: OrbitColors.surfaceHigh,
        foregroundColor: OrbitColors.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontFamily: OrbitFonts.sans, fontSize: 13, fontWeight: FontWeight.w700),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: Text(label),
    ),
  );
}

/// The round icon button in page headers ("+", the lightning bolt).
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({super.key, required this.icon, required this.onPressed, this.tooltip, this.color});

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 22, color: color ?? OrbitColors.textPrimary),
  );
}

/// Ping in milliseconds as the design colours it: plain when fine, amber when slow, a red dash when
/// the server did not answer.
class PingLabel extends StatelessWidget {
  const PingLabel({super.key, required this.delay, this.unit = false, this.highlight = false});

  final int? delay;
  final bool unit;

  /// Tints a good ping with the accent, as on the home screen while connected.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final d = delay;
    if (d == null) return const SizedBox.shrink();
    if (d > 65000 || d < 0) {
      return Text('—', style: OrbitText.mono.copyWith(color: OrbitColors.danger, fontSize: 13));
    }
    final color = d >= 100 ? OrbitColors.warning : (highlight ? OrbitColors.accent : OrbitColors.textSecondary);
    return Text(unit ? '$d мс' : '$d', style: OrbitText.mono.copyWith(color: color));
  }
}

/// A section caption in settings ("Подключение", "Сеть").
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 4),
    child: Text(text, style: OrbitText.section),
  );
}

/// A settings row: a title on the left and a value, a switch or a chevron on the right.
class OrbitTile extends StatelessWidget {
  const OrbitTile({
    super.key,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.divider = true,
  });

  final String title;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 48),
      decoration: BoxDecoration(
        border: divider ? const Border(bottom: BorderSide(color: OrbitColors.divider)) : null,
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: OrbitText.body),
                if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: OrbitText.caption)],
              ],
            ),
          ),
          if (value != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  value!,
                  style: OrbitText.body.copyWith(color: OrbitColors.textSecondary, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ),
            ),
          ?trailing,
        ],
      ),
    ),
  );
}

class OrbitSwitchTile extends StatelessWidget {
  const OrbitSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.divider = true,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool divider;

  @override
  Widget build(BuildContext context) => OrbitTile(
    title: title,
    subtitle: subtitle,
    divider: divider,
    onTap: onChanged == null ? null : () => onChanged!(!value),
    trailing: SizedBox(
      height: 28,
      child: FittedBox(child: Switch(value: value, onChanged: onChanged)),
    ),
  );
}

/// Stands in for a flag on "Авто".
class AutoBadge extends StatelessWidget {
  const AutoBadge({super.key, this.size = 26});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size * .72,
    decoration: BoxDecoration(color: OrbitColors.surfaceHighest, borderRadius: BorderRadius.circular(4)),
    child: Icon(Icons.bolt_rounded, size: size * .54, color: OrbitColors.accent),
  );
}
