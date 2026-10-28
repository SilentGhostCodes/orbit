import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Orbit palette, taken from the design: dark graphite surfaces and a single accent, mint unless
/// the user picked another under Оформление.
abstract class OrbitColors {
  static const defaultAccent = Color(0xFF3DD6A0);

  /// Set by [OrbitApp] from the settings before the tree builds.
  static Color accent = defaultAccent;

  /// Text and icons on the accent: a deep shade of it.
  static Color get onAccent {
    final hsl = HSLColor.fromColor(accent);
    return hsl.withLightness(.11).withSaturation(hsl.saturation * .6).toColor();
  }

  static const background = Color(0xFF1B1C1F);
  static const surface = Color(0xFF232427);
  static const surfaceHigh = Color(0xFF2B2C30);
  static const surfaceHighest = Color(0xFF34353A);
  static const divider = Color(0xFF2C2D31);

  static const textPrimary = Color(0xFFF2F2F0);
  static const textSecondary = Color(0xFF8E8F94);
  static const textTertiary = Color(0xFF5E5F65);

  static const flowerLight = Color(0xFFF5F3EE);
  static const warning = Color(0xFFF2B84B);
  static const danger = Color(0xFFE5484D);
}

abstract class OrbitFonts {
  static const sans = 'Manrope';
  static const mono = 'JetBrainsMono';
}

abstract class OrbitText {
  static const title = TextStyle(
    fontFamily: OrbitFonts.sans,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: OrbitColors.textPrimary,
    letterSpacing: -.2,
  );
  static const sheetTitle = TextStyle(
    fontFamily: OrbitFonts.sans,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: OrbitColors.textPrimary,
  );
  static const body = TextStyle(
    fontFamily: OrbitFonts.sans,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: OrbitColors.textPrimary,
  );
  static const bodyStrong = TextStyle(
    fontFamily: OrbitFonts.sans,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: OrbitColors.textPrimary,
  );
  static const caption = TextStyle(
    fontFamily: OrbitFonts.sans,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: OrbitColors.textSecondary,
  );
  static const section = TextStyle(
    fontFamily: OrbitFonts.sans,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: OrbitColors.textTertiary,
  );
  static const mono = TextStyle(
    fontFamily: OrbitFonts.mono,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: OrbitColors.textSecondary,
  );
}

ThemeData orbitTheme() {
  final scheme = ColorScheme.dark(
    primary: OrbitColors.accent,
    onPrimary: OrbitColors.onAccent,
    primaryContainer: OrbitColors.surfaceHigh,
    onPrimaryContainer: OrbitColors.textPrimary,
    secondary: OrbitColors.accent,
    onSecondary: OrbitColors.onAccent,
    secondaryContainer: OrbitColors.surfaceHigh,
    onSecondaryContainer: OrbitColors.textPrimary,
    surface: OrbitColors.background,
    onSurface: OrbitColors.textPrimary,
    onSurfaceVariant: OrbitColors.textSecondary,
    surfaceContainerLowest: OrbitColors.background,
    surfaceContainerLow: OrbitColors.surface,
    surfaceContainer: OrbitColors.surface,
    surfaceContainerHigh: OrbitColors.surfaceHigh,
    surfaceContainerHighest: OrbitColors.surfaceHighest,
    outline: OrbitColors.textTertiary,
    outlineVariant: OrbitColors.divider,
    error: OrbitColors.danger,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: OrbitFonts.sans);
  return base.copyWith(
    scaffoldBackgroundColor: OrbitColors.background,
    canvasColor: OrbitColors.background,
    dividerColor: OrbitColors.divider,
    dividerTheme: const DividerThemeData(color: OrbitColors.divider, thickness: 1, space: 1),
    appBarTheme: const AppBarTheme(
      backgroundColor: OrbitColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: OrbitText.title,
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: OrbitColors.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: OrbitColors.surface,
      showDragHandle: false,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: OrbitColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: OrbitColors.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      textStyle: OrbitText.body,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? OrbitColors.onAccent : OrbitColors.textSecondary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? OrbitColors.accent : OrbitColors.surfaceHighest,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? OrbitColors.accent : Colors.transparent,
      ),
      checkColor: WidgetStateProperty.all(OrbitColors.onAccent),
      side: const BorderSide(color: OrbitColors.textTertiary, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: OrbitColors.surfaceHighest,
      contentTextStyle: OrbitText.body,
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: OrbitColors.accent),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: OrbitColors.accent,
      selectionHandleColor: OrbitColors.accent,
    ),
  );
}

/// The accents offered under Оформление; any other hue can be picked on a slider.
const accentPresets = [
  (OrbitColors.defaultAccent, 'Мята'),
  (Color(0xFF22D3EE), 'Бирюза'),
  (Color(0xFF4DA3FF), 'Небо'),
  (Color(0xFF9B8CFF), 'Лаванда'),
  (Color(0xFFFF5FA2), 'Фуксия'),
  (Color(0xFFFF6B6B), 'Красный'),
  (Color(0xFFFF8A4C), 'Коралл'),
  (Color(0xFFFFC145), 'Янтарь'),
  (Color(0xFFA3E635), 'Лайм'),
  (Color(0xFFE6E6E6), 'Белый'),
];

/// A bright accent of [hue], as the custom slider makes them.
Color accentOfHue(double hue) => HSLColor.fromAHSL(1, hue, .78, .62).toColor();
