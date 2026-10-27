import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:orbit/theme/orbit_theme.dart';

enum OrbitButtonState { off, busy, on }

/// The connect button. Off, a plain round button. Connecting and connected, an orbit opens around
/// it: a ring with a moon at the head of a glowing trail, turning clockwise round the button, which
/// stays still. Connecting, the orbit runs fast; connected, it settles into a slow, steady turn.
class OrbitButton extends StatefulWidget {
  const OrbitButton({super.key, required this.state, required this.onTap, this.size = 156});

  final OrbitButtonState state;
  final VoidCallback? onTap;

  /// The button's diameter; the widget takes [size] × 1.9 for the orbit and its glow.
  final double size;

  @override
  State<OrbitButton> createState() => _OrbitButtonState();
}

class _OrbitButtonState extends State<OrbitButton> with TickerProviderStateMixin {
  /// One turn of the orbit, clockwise.
  late final AnimationController _orbit = AnimationController(vsync: this);

  /// The orbit opening (0 hidden, 1 shown).
  late final AnimationController _appear = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  @override
  void initState() {
    super.initState();
    _apply(widget.state, initial: true);
  }

  @override
  void didUpdateWidget(OrbitButton old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _apply(widget.state);
  }

  void _apply(OrbitButtonState state, {bool initial = false}) {
    switch (state) {
      case OrbitButtonState.off:
        // the orbit keeps turning while it closes, then stops
        _appear.reverse().whenCompleteOrCancel(() {
          if (mounted && widget.state == OrbitButtonState.off) _orbit.stop();
        });
      case OrbitButtonState.busy:
        _appear.forward();
        _orbit
          ..duration = const Duration(milliseconds: 1400)
          ..repeat();
      case OrbitButtonState.on:
        if (initial) _appear.value = 1;
        _appear.forward();
        _orbit
          ..duration = const Duration(seconds: 7)
          ..repeat();
    }
  }

  @override
  void dispose() {
    _orbit.dispose();
    _appear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final on = state == OrbitButtonState.on;
    final size = widget.size;

    return Semantics(
      button: true,
      label: switch (state) {
        OrbitButtonState.off => 'Подключить',
        OrbitButtonState.busy => 'Подключение',
        OrbitButtonState.on => 'Отключить',
      },
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: TweenAnimationBuilder<double>(
          // 0 off, 1 on: the button's colours and the glow follow it
          tween: Tween(end: on ? 1 : 0),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
          builder: (context, lit, _) => AnimatedBuilder(
            animation: Listenable.merge([_orbit, _appear]),
            builder: (context, _) {
              final appear = Curves.easeOutBack.transform(_appear.value).clamp(0.0, 1.2);
              return SizedBox.square(
                dimension: size * 1.9,
                child: CustomPaint(
                  painter: _OrbitPainter(
                    radius: size / 2,
                    appear: appear,
                    orbitTurn: _orbit.value,
                    lit: lit,
                    busy: state == OrbitButtonState.busy,
                  ),
                  child: Center(child: _Disc(size: size, lit: lit, busy: state == OrbitButtonState.busy)),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The button itself: a disc with a power sign.
class _Disc extends StatelessWidget {
  const _Disc({required this.size, required this.lit, required this.busy});

  final double size;
  final double lit;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final fill = Color.lerp(OrbitColors.surfaceHigh, OrbitColors.flowerLight, lit)!;
    final icon = busy || lit > .5 ? OrbitColors.accent : OrbitColors.textPrimary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: .35), blurRadius: 18, offset: const Offset(0, 6)),
          if (lit > 0)
            BoxShadow(color: OrbitColors.accent.withValues(alpha: .35 * lit), blurRadius: 40, spreadRadius: 2),
        ],
      ),
      child: Center(child: Icon(Icons.power_settings_new_rounded, size: size * .27, color: icon)),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({
    required this.radius,
    required this.appear,
    required this.orbitTurn,
    required this.lit,
    required this.busy,
  });

  /// The button's radius.
  final double radius;
  final double appear;
  final double orbitTurn;
  final double lit;
  final bool busy;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);

    // the glow behind everything, once connected
    if (lit > 0) {
      canvas.drawCircle(
        c,
        size.width / 2,
        Paint()
          ..shader = RadialGradient(
            colors: [
              OrbitColors.accent.withValues(alpha: .30 * lit),
              OrbitColors.accent.withValues(alpha: .08 * lit),
              OrbitColors.accent.withValues(alpha: 0),
            ],
            stops: const [.4, .7, 1],
          ).createShader(Rect.fromCircle(center: c, radius: size.width / 2)),
      );
    }

    if (appear <= 0.001) return;
    final opacity = appear.clamp(0.0, 1.0);
    // the orbit grows out from the button's edge as it appears
    final orbitR = radius * (1.0 + .36 * appear);
    final head = -math.pi / 2 + orbitTurn * 2 * math.pi;

    // the whole path, faint
    canvas.drawCircle(
      c,
      orbitR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = OrbitColors.accent.withValues(alpha: .18 * opacity),
    );

    // the trail behind the moon: a sweep that fades to nothing
    final trail = busy ? math.pi * 1.1 : math.pi * .75;
    final rect = Rect.fromCircle(center: c, radius: orbitR);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(head);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawArc(
      rect,
      -trail,
      trail,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          center: Alignment.center,
          startAngle: 2 * math.pi - trail,
          endAngle: 2 * math.pi,
          colors: [OrbitColors.accent.withValues(alpha: 0), OrbitColors.accent.withValues(alpha: .9 * opacity)],
        ).createShader(rect),
    );
    canvas.restore();

    // the moon at the head, with a soft halo
    final moon = c + Offset.fromDirection(head, orbitR);
    canvas.drawCircle(
      moon,
      11,
      Paint()
        ..color = OrbitColors.accent.withValues(alpha: .28 * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(moon, 5.5, Paint()..color = OrbitColors.accent.withValues(alpha: opacity));
    canvas.drawCircle(moon, 2.2, Paint()..color = Colors.white.withValues(alpha: .85 * opacity));
  }

  @override
  bool shouldRepaint(_OrbitPainter old) =>
      old.appear != appear || old.orbitTurn != orbitTurn || old.lit != lit || old.busy != busy;
}
