import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'shed_colors.dart';

/// The default light/dark themes, built once. [buildShedTheme] is pure and a
/// theme depends only on its brightness, so memoizing avoids re-running
/// `ColorScheme.fromSeed` + the Google-Fonts text-theme build on every theme
/// toggle (each `MaterialApp` rebuild).
final ThemeData shedLightTheme = buildShedTheme(Brightness.light);
final ThemeData shedDarkTheme = buildShedTheme(Brightness.dark);

/// IBM Plex Sans text style. Mirrors [monoStyle] for the one-off UI labels (e.g.
/// button text, the brand title) that need a specific size/weight outside the
/// [TextTheme], making the family explicit rather than relying on inheritance.
TextStyle sansStyle({
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? letterSpacing,
}) => GoogleFonts.ibmPlexSans(
  fontSize: fontSize,
  fontWeight: fontWeight,
  color: color,
  letterSpacing: letterSpacing,
);

/// IBM Plex Mono text style — the design's `.mono` class (hosts/URLs, ids, status
/// labels, helper text). Centralized so every monospace bit shares one family.
TextStyle monoStyle({double? fontSize, FontWeight? fontWeight, Color? color}) =>
    GoogleFonts.ibmPlexMono(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
    );

/// Build the Shed [ThemeData] for a brightness from the design tokens
/// ([ShedColors]). Material slots that map directly to the design live on the
/// [ColorScheme]; the rest ride along as a [ShedColors] extension. Typography is
/// IBM Plex Sans (UI) with IBM Plex Mono available via [monoStyle].
ThemeData buildShedTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? ShedColors.dark : ShedColors.light;

  final scheme =
      ColorScheme.fromSeed(
        seedColor: c.accent,
        brightness: brightness,
      ).copyWith(
        primary: c.accent,
        onPrimary: Colors.white,
        surface: c.bg,
        onSurface: c.fg,
        onSurfaceVariant: c.fg2,
        surfaceContainerLowest: c.bg,
        surfaceContainer: c.surface,
        surfaceContainerHigh: c.surface,
        surfaceContainerHighest: c.surface2,
        outline: c.fg3,
        outlineVariant: c.line,
        error: c.errFg,
        // `error` is a dark red on light but a light pink on dark, so the text
        // drawn on an error fill must flip with it to stay readable.
        onError: brightness == Brightness.dark ? c.bg : Colors.white,
        errorContainer: c.errBg,
        onErrorContainer: c.errFg,
      );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
  );
  final textTheme = GoogleFonts.ibmPlexSansTextTheme(
    base.textTheme,
  ).apply(bodyColor: c.fg, displayColor: c.fg);

  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    textTheme: textTheme,
    extensions: [c],
    dividerColor: c.line,
    iconTheme: IconThemeData(color: c.fg2),
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.fg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.ibmPlexSans(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: c.fg,
        letterSpacing: -0.01,
      ),
      iconTheme: IconThemeData(color: c.fg),
      actionsIconTheme: IconThemeData(color: c.fg2),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: c.surface2,
        disabledForegroundColor: c.fg3,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: sansStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.fg,
        side: BorderSide(color: c.line),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: sansStyle(fontSize: 14, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accent,
        textStyle: sansStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.accent,
      foregroundColor: Colors.white,
      elevation: 4,
      focusElevation: 4,
      hoverElevation: 6,
      extendedTextStyle: sansStyle(fontSize: 14, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      isDense: true,
      labelStyle: TextStyle(color: c.fg3),
      floatingLabelStyle: TextStyle(color: c.accent),
      hintStyle: TextStyle(color: c.fg3),
      helperStyle: monoStyle(fontSize: 11, color: c.fg3),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: c.line, width: 1.5),
      ),
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: c.accent, width: 1.5),
      ),
      errorStyle: TextStyle(color: c.errFg),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : c.fg3,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : c.surface2,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      iconColor: c.accent,
      collapsedIconColor: c.fg2,
      textColor: c.accent,
      collapsedTextColor: c.fg,
      tilePadding: EdgeInsets.zero,
      shape: const Border(),
      collapsedShape: const Border(),
    ),
    listTileTheme: ListTileThemeData(iconColor: c.fg2, textColor: c.fg),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.fg,
      contentTextStyle: GoogleFonts.ibmPlexSans(color: c.bg, fontSize: 13),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );
}
