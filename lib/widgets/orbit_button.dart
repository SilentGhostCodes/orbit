import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:orbit/theme/orbit_theme.dart';

enum OrbitButtonState { off, busy, on }

/// The connect button. Off, a plain round button. Connecting and connected, an orbit opens around
/// it: a ring with a moon at the head of a glowing trail, turning clockwise, while the button turns
/// the other way. Connecting spins fast; connected settles into a slow, steady turn.
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

  /// One turn of the button, counter-clockwise.
  late final AnimationController _spin = AnimationController(vsync: this);

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
        _appear.reverse();
        // the button comes to rest once the orbit has closed
        _spin.animateTo(_spin.value < .5 ? 0 : 1, duration: const Duration(milliseconds: 500), curve: Curves.easeOut)
            .whenCompleteOrCancel(() {
              if (mounted && widget.state == OrbitButtonState.off) {
                _spin.value = 0;
                _orbit.stop();
              }
            });
      case OrbitButtonState.busy:
        _appear.forward();
        _orbit
          ..duration = const Duration(milliseconds: 1400)
          ..repeat();
        _spin
          ..duration = const Duration(seconds: 4)
          ..repeat();
      case OrbitButtonState.on:
        if (initial) _appear.value = 1;
        _appear.forward();
        _orbit
          ..duration = const Duration(seconds: 7)
          ..repeat();
        _spin
          ..duration = const Duration(seconds: 14)
          ..repeat();
    }
  }

  @override
  void dispose() {
    _orbit.dispose();
    _spin.dispose();
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
            animation: Listenable.merge([_orbit, _spin, _appear]),
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
                  child: Center(
                    child: Transform.rotate(
                      angle: -_spin.value * 2 * math.pi,
                      child: _Disc(size: size, lit: lit, busy: state == OrbitButtonState.busy),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The button itself: a disc with a power sign, and a ring of ticks that shows it turning.
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
      child: CustomPaint(
        painter: _TicksPainter(
          // none while off: then it is a plain button
          color: Color.lerp(OrbitColors.textTertiary, OrbitColors.accent, lit)!.withValues(
            alpha: busy ? .55 : .6 * lit,
          ),
        ),
        child: Center(child: Icon(Icons.power_settings_new_rounded, size: size * .27, color: icon)),
      ),
    );
  }
}

class _TicksPainter extends CustomPainter {
  _TicksPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (color.a == 0) return;
    final c = size.center(Offset.zero);
    final r = size.width / 2 * .84;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round;
    const ticks = 24;
    for (var i = 0; i < ticks; i++) {
      final a = i / ticks * 2 * math.pi;
      // every sixth tick is longer, so the turn reads at a glance
      final long = i % 6 == 0;
      paint.strokeWidth = long ? 2.4 : 1.4;
      final inner = r - (long ? 7 : 4);
      canvas.drawLine(c + Offset.fromDirection(a, inner), c + Offset.fromDirection(a, r), paint);
    }
  }

  @override
  bool shouldRepaint(_TicksPainter old) => old.color != color;
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
