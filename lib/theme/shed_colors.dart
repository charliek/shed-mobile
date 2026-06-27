import 'package:flutter/material.dart';

/// Semantic status tone for a shed/session indicator. Maps the design's four
/// status families (ok / warn / idle / err) to a background, a foreground, and a
/// saturated dot color.
enum ShedStatusTone { ok, warn, idle, err }

/// The design's full semantic color palette, ported verbatim from
/// `Shed App.dc.html` (`:root` light vars + `themeVars()` dark vars). This is the
/// single source of truth for the app's colors: `buildShedTheme` projects the
/// Material-mapped subset (accent→primary, bg→surface, fg→onSurface, errFg→error,
/// …) onto the [ColorScheme] *from these same fields*, so the two can't drift.
/// Tokens with no clean Material slot — the secondary text tiers, hairlines, the
/// soft surface, the status quad, the dark "open" button, the agent-kind accents —
/// live only here. Read it all via `context.shed` (see [ShedColorsX]).
@immutable
class ShedColors extends ThemeExtension<ShedColors> {
  const ShedColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.field,
    required this.fg,
    required this.fg2,
    required this.fg3,
    required this.accent,
    required this.accentSoft,
    required this.okBg,
    required this.okFg,
    required this.warnBg,
    required this.warnFg,
    required this.idleBg,
    required this.idleFg,
    required this.errBg,
    required this.errFg,
    required this.dotOk,
    required this.dotWarn,
    required this.dotIdle,
    required this.dotErr,
    required this.btnDark,
    required this.btnDarkFg,
    required this.kindClaude,
    required this.kindCodex,
    required this.kindShell,
  });

  final Color bg; // app background (scaffold)
  final Color surface; // raised surface (cards/sheets)
  final Color surface2; // soft fill (chips, tiles, toggles)
  final Color line; // hairline divider/border
  final Color field; // input field fill
  final Color fg; // primary text
  final Color fg2; // secondary text
  final Color fg3; // tertiary / placeholder text
  final Color accent; // brand orange
  final Color accentSoft; // 10% accent wash (selected segment)

  // Status quad — a background + a foreground per family.
  final Color okBg;
  final Color okFg;
  final Color warnBg;
  final Color warnFg;
  final Color idleBg;
  final Color idleFg;
  final Color errBg;
  final Color errFg;

  // Saturated status dots (constant across themes — they read on both).
  final Color dotOk;
  final Color dotWarn;
  final Color dotIdle;
  final Color dotErr;

  // The dark pill button ("> open").
  final Color btnDark;
  final Color btnDarkFg;

  // Agent-kind accents (left border on the kind chip, terminal `[kind]`).
  final Color kindClaude;
  final Color kindCodex;
  final Color kindShell;

  Color toneBg(ShedStatusTone t) => switch (t) {
    ShedStatusTone.ok => okBg,
    ShedStatusTone.warn => warnBg,
    ShedStatusTone.idle => idleBg,
    ShedStatusTone.err => errBg,
  };

  Color toneFg(ShedStatusTone t) => switch (t) {
    ShedStatusTone.ok => okFg,
    ShedStatusTone.warn => warnFg,
    ShedStatusTone.idle => idleFg,
    ShedStatusTone.err => errFg,
  };

  Color toneDot(ShedStatusTone t) => switch (t) {
    ShedStatusTone.ok => dotOk,
    ShedStatusTone.warn => dotWarn,
    ShedStatusTone.idle => dotIdle,
    ShedStatusTone.err => dotErr,
  };

  // Tokens identical in both themes — defined once so the "constant across
  // themes" invariant is enforced by the code, not by matching copy-paste.
  static const _accent = Color(0xFFF2541B);
  static const _accentSoft = Color(0x1AF2541B);
  static const _dotOk = Color(0xFF1FB87A);
  static const _dotWarn = Color(0xFFE0A300);
  static const _dotIdle = Color(0xFFA0A4AC);
  static const _dotErr = Color(0xFFE5484D);
  static const _kindClaude = Color(0xFFF2541B);
  static const _kindCodex = Color(0xFF10A37F);
  static const _kindShell = Color(0xFF7A828C);

  static const light = ShedColors(
    bg: Color(0xFFFAFAF8),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF0EEE9),
    line: Color(0xFFECEAE5),
    field: Color(0xFFFFFFFF),
    fg: Color(0xFF15181E),
    fg2: Color(0xFF6B6F77),
    fg3: Color(0xFF9AA0A8),
    accent: _accent,
    accentSoft: _accentSoft,
    okBg: Color(0xFFDEF5EB),
    okFg: Color(0xFF117B52),
    warnBg: Color(0xFFFBF1D2),
    warnFg: Color(0xFF8A6D0F),
    idleBg: Color(0xFFEEECE7),
    idleFg: Color(0xFF71757E),
    errBg: Color(0xFFFBE3E3),
    errFg: Color(0xFFC0392B),
    dotOk: _dotOk,
    dotWarn: _dotWarn,
    dotIdle: _dotIdle,
    dotErr: _dotErr,
    btnDark: Color(0xFF15181E),
    btnDarkFg: Color(0xFFFFFFFF),
    kindClaude: _kindClaude,
    kindCodex: _kindCodex,
    kindShell: _kindShell,
  );

  static const dark = ShedColors(
    bg: Color(0xFF15181E),
    surface: Color(0xFF1A1E26),
    surface2: Color(0xFF23272F),
    line: Color(0xFF262B33),
    field: Color(0xFF1A1E26),
    fg: Color(0xFFECEEF2),
    fg2: Color(0xFF9AA0A8),
    fg3: Color(0xFF7E848D),
    accent: _accent,
    accentSoft: _accentSoft,
    okBg: Color(0xFF10342A),
    okFg: Color(0xFF3FD99A),
    warnBg: Color(0xFF33290F),
    warnFg: Color(0xFFE0B23C),
    idleBg: Color(0xFF23272F),
    idleFg: Color(0xFF9AA0A8),
    errBg: Color(0xFF3A1E1E),
    errFg: Color(0xFFF08C8C),
    dotOk: _dotOk,
    dotWarn: _dotWarn,
    dotIdle: _dotIdle,
    dotErr: _dotErr,
    btnDark: Color(0xFF000000),
    btnDarkFg: Color(0xFFECEEF2),
    kindClaude: _kindClaude,
    kindCodex: _kindCodex,
    kindShell: _kindShell,
  );

  @override
  ShedColors copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? line,
    Color? field,
    Color? fg,
    Color? fg2,
    Color? fg3,
    Color? accent,
    Color? accentSoft,
    Color? okBg,
    Color? okFg,
    Color? warnBg,
    Color? warnFg,
    Color? idleBg,
    Color? idleFg,
    Color? errBg,
    Color? errFg,
    Color? dotOk,
    Color? dotWarn,
    Color? dotIdle,
    Color? dotErr,
    Color? btnDark,
    Color? btnDarkFg,
    Color? kindClaude,
    Color? kindCodex,
    Color? kindShell,
  }) {
    return ShedColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      line: line ?? this.line,
      field: field ?? this.field,
      fg: fg ?? this.fg,
      fg2: fg2 ?? this.fg2,
      fg3: fg3 ?? this.fg3,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      okBg: okBg ?? this.okBg,
      okFg: okFg ?? this.okFg,
      warnBg: warnBg ?? this.warnBg,
      warnFg: warnFg ?? this.warnFg,
      idleBg: idleBg ?? this.idleBg,
      idleFg: idleFg ?? this.idleFg,
      errBg: errBg ?? this.errBg,
      errFg: errFg ?? this.errFg,
      dotOk: dotOk ?? this.dotOk,
      dotWarn: dotWarn ?? this.dotWarn,
      dotIdle: dotIdle ?? this.dotIdle,
      dotErr: dotErr ?? this.dotErr,
      btnDark: btnDark ?? this.btnDark,
      btnDarkFg: btnDarkFg ?? this.btnDarkFg,
      kindClaude: kindClaude ?? this.kindClaude,
      kindCodex: kindCodex ?? this.kindCodex,
      kindShell: kindShell ?? this.kindShell,
    );
  }

  @override
  ShedColors lerp(ThemeExtension<ShedColors>? other, double t) {
    if (other is! ShedColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return ShedColors(
      bg: c(bg, other.bg),
      surface: c(surface, other.surface),
      surface2: c(surface2, other.surface2),
      line: c(line, other.line),
      field: c(field, other.field),
      fg: c(fg, other.fg),
      fg2: c(fg2, other.fg2),
      fg3: c(fg3, other.fg3),
      accent: c(accent, other.accent),
      accentSoft: c(accentSoft, other.accentSoft),
      okBg: c(okBg, other.okBg),
      okFg: c(okFg, other.okFg),
      warnBg: c(warnBg, other.warnBg),
      warnFg: c(warnFg, other.warnFg),
      idleBg: c(idleBg, other.idleBg),
      idleFg: c(idleFg, other.idleFg),
      errBg: c(errBg, other.errBg),
      errFg: c(errFg, other.errFg),
      dotOk: c(dotOk, other.dotOk),
      dotWarn: c(dotWarn, other.dotWarn),
      dotIdle: c(dotIdle, other.dotIdle),
      dotErr: c(dotErr, other.dotErr),
      btnDark: c(btnDark, other.btnDark),
      btnDarkFg: c(btnDarkFg, other.btnDarkFg),
      kindClaude: c(kindClaude, other.kindClaude),
      kindCodex: c(kindCodex, other.kindCodex),
      kindShell: c(kindShell, other.kindShell),
    );
  }
}

/// `context.shed` → the active [ShedColors]. The extension is always installed by
/// `buildShedTheme`; the fallback only fires on misconfiguration (e.g. a test
/// pumping a bare `MaterialApp`), and then matches the context's brightness so a
/// dark subtree never renders light tokens.
extension ShedColorsX on BuildContext {
  ShedColors get shed {
    final theme = Theme.of(this);
    final ext = theme.extension<ShedColors>();
    assert(
      ext != null,
      'ShedColors missing from the theme — build it with buildShedTheme().',
    );
    return ext ??
        (theme.brightness == Brightness.dark
            ? ShedColors.dark
            : ShedColors.light);
  }
}
