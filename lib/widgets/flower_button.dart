import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:orbit/theme/orbit_theme.dart';

enum FlowerState { off, busy, on }

/// The connect button: a dark disc while off that opens into a white eight-petal flower with a
/// green glow once connected. While connecting it is a grey flower turning slowly.
class FlowerButton extends StatefulWidget {
  const FlowerButton({super.key, required this.state, required this.onTap, this.size = 156, this.dimmed = false});

  final FlowerState state;
  final VoidCallback? onTap;
  final double size;

  /// Drawn greyed out, as behind an open bottom sheet.
  final bool dimmed;

  @override
  State<FlowerButton> createState() => _FlowerButtonState();
}

class _FlowerButtonState extends State<FlowerButton> with SingleTickerProviderStateMixin {
  static const _petalDepth = .12;

  late final AnimationController spin = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void initState() {
    super.initState();
    _spinFor(widget.state);
  }

  @override
  void didUpdateWidget(FlowerButton old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _spinFor(widget.state);
  }

  void _spinFor(FlowerState state) {
    switch (state) {
      case FlowerState.busy:
        spin.duration = const Duration(seconds: 3);
        spin.repeat();
      case FlowerState.on:
        spin.duration = const Duration(seconds: 60);
        spin.repeat();
      case FlowerState.off:
        spin.stop();
    }
  }

  @override
  void dispose() {
    spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final dimmed = widget.dimmed;
    final size = widget.size;
    final onTap = widget.onTap;

    final target = switch (state) {
      FlowerState.off => (depth: 0.0, fill: OrbitColors.surfaceHigh, icon: OrbitColors.textPrimary, glow: 0.0),
      FlowerState.busy => (depth: _petalDepth, fill: const Color(0xFF55565B), icon: OrbitColors.accent, glow: .25),
      FlowerState.on => (depth: _petalDepth, fill: OrbitColors.flowerLight, icon: OrbitColors.accent, glow: 1.0),
    };

    return Semantics(
      button: true,
      label: switch (state) {
        FlowerState.off => 'Подключить',
        FlowerState.busy => 'Подключение',
        FlowerState.on => 'Отключить',
      },
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: target.depth),
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeOutBack,
          builder: (context, depth, _) => TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: dimmed ? const Color(0xFF5A5B5F) : target.fill),
            duration: const Duration(milliseconds: 360),
            builder: (context, fill, _) => TweenAnimationBuilder<double>(
              tween: Tween(end: dimmed ? 0 : target.glow),
              duration: const Duration(milliseconds: 600),
              builder: (context, glow, _) => AnimatedBuilder(
                animation: spin,
                builder: (context, _) => SizedBox.square(
                  dimension: size * 1.9,
                  child: CustomPaint(
                    painter: _FlowerPainter(
                      depth: depth.clamp(0, .2),
                      fill: fill!,
                      glow: glow,
                      rotation: spin.value * 2 * math.pi,
                      radius: size / 2,
                    ),
                    child: Center(
                      child: Icon(
                        Icons.power_settings_new_rounded,
                        size: size * .27,
                        color: dimmed ? OrbitColors.accent.withValues(alpha: .6) : target.icon,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FlowerPainter extends CustomPainter {
  _FlowerPainter({
    required this.depth,
    required this.fill,
    required this.glow,
    required this.rotation,
    required this.radius,
  });

  final double depth;
  final Color fill;
  final double glow;
  final double rotation;
  final double radius;

  static const _petals = 8;

  Path _shape(Offset c) {
    final path = Path();
    const steps = 240;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps * 2 * math.pi;
      // a raised cosine, flattened a little: round petals and soft, still smooth notches
      final wave = math.pow((1 + math.cos(_petals * t)) / 2, .7).toDouble();
      final r = radius * (1 - depth * (1 - wave));
      final p = c + Offset.fromDirection(t + rotation, r);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    if (glow > 0) {
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            OrbitColors.accent.withValues(alpha: .38 * glow),
            OrbitColors.accent.withValues(alpha: .12 * glow),
            OrbitColors.accent.withValues(alpha: 0),
          ],
          stops: const [.45, .7, 1],
        ).createShader(Rect.fromCircle(center: c, radius: size.width / 2));
      canvas.drawCircle(c, size.width / 2, glowPaint);
    }
    final shape = _shape(c);
    canvas.drawShadow(shape, Colors.black, 8, false);
    canvas.drawPath(shape, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_FlowerPainter old) =>
      old.depth != depth || old.fill != fill || old.glow != glow || old.rotation != rotation;
}
