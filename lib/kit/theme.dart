// The ESCA look, shared by every application on the board.
//
// lib/kit/ is copied verbatim into com.esca.home.app, com.esca.app.camview,
// com.esca.app.monitor and com.esca.app.voice. Each is built by its own
// recipe, and a package shared across repositories would have to be fetched
// at build time as well; four identical copies are the cheaper trade. Change
// one, copy it to the others.

import 'package:flutter/material.dart';

/// Colour tokens. Named for what they mean, not what they look like, so a
/// screen asks for [bad] rather than for red.
abstract final class EscaColors {
  static const background = Color(0xFF0A0F14);
  static const backgroundRaised = Color(0xFF0E1620);
  static const surface = Color(0xFF121A23);
  static const surfaceHigh = Color(0xFF18222D);
  static const border = Color(0xFF223041);
  static const borderStrong = Color(0xFF2E4054);

  static const text = Color(0xFFE8EEF4);
  static const textDim = Color(0xFF8B98A8);
  static const textFaint = Color(0xFF5B6878);

  /// ESCA teal: the brand, and "this is the thing to press".
  static const accent = Color(0xFF14C8B4);
  static const accentDeep = Color(0xFF0B8F86);
  static const info = Color(0xFF4EA8FF);
  static const violet = Color(0xFFA78BFA);

  static const good = Color(0xFF34D399);
  static const warn = Color(0xFFF5B544);
  static const bad = Color(0xFFF26B6B);

  /// One colour per detected class, the same spread esca-camview used, so a
  /// person is the same colour in every build.
  static const classes = [
    Color(0xFF4FC3F7),
    Color(0xFFAED581),
    Color(0xFFFFB74D),
    Color(0xFFE57373),
    Color(0xFFBA68C8),
    Color(0xFF4DB6AC),
    Color(0xFFFFD54F),
    Color(0xFF90A4AE),
    Color(0xFFF06292),
    Color(0xFF7986CB),
  ];
}

abstract final class EscaRadius {
  static const card = 22.0;
  static const control = 14.0;
  static const pill = 999.0;
}

/// Bundled, not taken from the board's fontconfig: the image ships no font
/// with Vietnamese coverage worth looking at, and a bundled one makes the
/// board and the development host draw the same thing.
const kEscaFontFamily = 'BeVietnamPro';

ThemeData escaTheme() {
  const scheme = ColorScheme.dark(
    primary: EscaColors.accent,
    onPrimary: Color(0xFF02201D),
    secondary: EscaColors.info,
    surface: EscaColors.surface,
    onSurface: EscaColors.text,
    error: EscaColors.bad,
    outline: EscaColors.border,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: kEscaFontFamily,
    scaffoldBackgroundColor: EscaColors.background,
    splashFactory: InkSparkle.splashFactory,
  );

  final text = base.textTheme.apply(
    bodyColor: EscaColors.text,
    displayColor: EscaColors.text,
  );

  return base.copyWith(
    textTheme: text.copyWith(
      displayLarge: text.displayLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1.5),
      displayMedium: text.displayMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1.0),
      displaySmall: text.displaySmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      bodySmall: text.bodySmall?.copyWith(color: EscaColors.textDim),
      labelSmall: text.labelSmall?.copyWith(color: EscaColors.textDim, letterSpacing: 0.8),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: EscaColors.accent,
      inactiveTrackColor: EscaColors.border,
      thumbColor: EscaColors.accent,
      overlayColor: Color(0x2914C8B4),
      trackHeight: 4,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : EscaColors.textDim),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? EscaColors.accent : EscaColors.surfaceHigh),
      trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? EscaColors.accent : EscaColors.borderStrong),
    ),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(
        color: EscaColors.surfaceHigh,
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      textStyle: TextStyle(color: EscaColors.text, fontFamily: kEscaFontFamily),
    ),
  );
}
