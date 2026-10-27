import 'package:flutter/material.dart';
import 'package:orbit/data/settings.dart';
import 'package:orbit/widgets/flower_button.dart';
import 'package:orbit/widgets/orbit_button.dart';

/// The connect button in the style picked under Оформление.
class PowerButton extends StatelessWidget {
  const PowerButton({super.key, required this.style, required this.state, required this.onTap, this.size = 156});

  final PowerButtonStyle style;
  final OrbitButtonState state;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) => switch (style) {
    PowerButtonStyle.orbit => OrbitButton(state: state, onTap: onTap, size: size),
    PowerButtonStyle.flower => FlowerButton(
      state: switch (state) {
        OrbitButtonState.off => FlowerState.off,
        OrbitButtonState.busy => FlowerState.busy,
        OrbitButtonState.on => FlowerState.on,
      },
      onTap: onTap,
      size: size,
    ),
  };
}
