/// Client-side defense for guest-controlled display text (feed messages,
/// last-message previews). The rc hub strips ANSI escapes and C0/C1 control
/// characters, but NOT Unicode format characters (category Cf): a bidi
/// override like U+202E can visually reverse rendered text and spoof what a
/// message appears to say, and zero-widths/BOM can hide content. Strip the
/// whole Cf category before render.
final RegExp _formatCharsRe = RegExp(r'\p{Cf}', unicode: true);

/// Remove every Unicode format character (category Cf — bidi overrides,
/// zero-width chars, BOM, soft hyphen, …) from [s].
String stripFormatChars(String s) => s.replaceAll(_formatCharsRe, '');
