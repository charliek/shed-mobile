/// Pure, dependency-free URL extraction over raw terminal output.
///
/// The in-app terminal renders TUI pixels, so a login/console URL a tool prints
/// (a cursor auth link, a claude console URL, …) is buried in ANSI-coloured,
/// control-char-laden bytes with no structure to lift it out of. [latestUrlIn]
/// strips the terminal escapes, finds the `http(s)` URLs, and returns the most
/// recent one so the screen can offer a one-tap Copy/Open banner — far easier
/// than drag-selecting on a phone.
///
/// This file is the unit-tested core: it holds ALL the heuristics (what counts
/// as an escape, where a URL ends, which trailing punctuation to shed) so they
/// can be pinned by `test/core/url_scan_test.dart` without a widget or a PTY.
library;

// ---------------------------------------------------------------------------
// Escape / control stripping
// ---------------------------------------------------------------------------

// Terminal escape sequences, matched in precedence order (OSC before CSI before
// the catch-all, because each starts with ESC and a looser alternative would
// otherwise swallow a stricter one's introducer):
//   * OSC — ESC `]` … terminated by BEL (\x07) or ST (ESC `\`). Its body excludes
//     ESC so a *missing* terminator can't run on and eat a following CSI or the
//     URL; the terminator is optional so an OSC clipped at the tail boundary is
//     still removed.
//   * CSI — ESC `[`, parameter bytes (0x30–0x3F), intermediate bytes (0x20–0x2F),
//     one final byte (0x40–0x7E): SGR colours, cursor moves, erases, …
//   * Any other escape — ESC + optional intermediates + an optional final byte:
//     charset designations (`ESC ( B`), `ESC =`, `ESC M`, and a lone trailing ESC.
final _escapes = RegExp(
  r'\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)?' // OSC ... BEL | ST
  r'|\x1B\[[\x30-\x3F]*[\x20-\x2F]*[\x40-\x7E]' // CSI ... final
  r'|\x1B[\x20-\x2F]*[\x30-\x7E]?', // other / lone ESC
);

// C0 control bytes and DEL, EXCEPT the whitespace controls (\t \n \v \f \r =
// 0x09–0x0D), which we deliberately keep so they still delimit a URL. Removing
// the rest lets an escape that was sitting flush against a URL fall away without
// leaving a stray control byte wedged into the match.
final _controls = RegExp(r'[\x00-\x08\x0E-\x1F\x7F]');

// ---------------------------------------------------------------------------
// URL matching
// ---------------------------------------------------------------------------

// `http`/`https` only (never a `file:`/`javascript:`/… scheme — those must not
// reach a launcher), then a run of non-whitespace: query strings, fragments,
// ports, and bracketed IPv6 hosts (`[::1]`) all ride along, and the match stops
// at the first whitespace/control (controls were already stripped above).
final _urlRe = RegExp(r'https?://\S+', caseSensitive: false);

// Trailing punctuation that is almost never part of a URL when it sits at the
// very end — the tail of a sentence, not the link. Note the set intentionally
// omits `#`, `&`, `=`, `/`: those carry query/fragment content, so we never trim
// them. A bare trailing `?` (an empty query) is fine to drop.
const _alwaysTrim = '.,;:!?\'">';

// Closing brackets are trimmed only when UNBALANCED within the URL, so a URL that
// legitimately ends in a bracket survives — an IPv6 host `https://[::1]` (the
// closing `]` balances the opening `[`) or a parenthesised path segment
// `…/Foo_(bar)` — while a `)` that merely hugs the link (`(see https://x)`) is
// shed.
const _closers = {')': '(', ']': '[', '}': '{'};

int _count(String s, String ch) {
  var n = 0;
  for (var i = 0; i < s.length; i++) {
    if (s[i] == ch) n++;
  }
  return n;
}

/// Strip trailing punctuation from [url] without eating a real query/fragment or
/// a balanced closing bracket. Walks in from the end: an [_alwaysTrim] char is
/// always dropped; a closing bracket is dropped only while it outnumbers its
/// opener; anything else stops the walk.
String _trimTrailing(String url) {
  var end = url.length;
  while (end > 0) {
    final ch = url[end - 1];
    if (_alwaysTrim.contains(ch)) {
      end--;
      continue;
    }
    final opener = _closers[ch];
    if (opener != null &&
        _count(url.substring(0, end), ch) >
            _count(url.substring(0, end), opener)) {
      end--;
      continue;
    }
    break;
  }
  return url.substring(0, end);
}

/// The last `http`/`https` URL in [text], or null if there is none.
///
/// [text] is raw terminal output (typically a bounded rolling tail — see
/// [appendBoundedTail]): escapes and control bytes are stripped first so a colour
/// code or title-set sequence flush against the URL doesn't break the match, then
/// the final match wins (a TUI redraw re-emits the same URL; the newest is what a
/// user is looking at). Non-`http(s)` schemes never match, so nothing else can
/// leak through to a launcher. The caller de-dups identical results.
String? latestUrlIn(String text) {
  final cleaned = text.replaceAll(_escapes, '').replaceAll(_controls, '');
  final matches = _urlRe.allMatches(cleaned);
  if (matches.isEmpty) return null;
  return _trimTrailing(matches.last.group(0)!);
}

/// Append [chunk] to [tail] and keep only the last [maxChars] characters.
///
/// The terminal already retains a 10k-line scrollback; scanning for a URL must
/// NOT re-accumulate a second copy of it. Feeding every decoded output chunk
/// through this keeps the scan buffer to a small, fixed rolling window (a URL
/// older than the window simply falls out of detection — acceptable, since a
/// login link is acted on when it appears).
String appendBoundedTail(String tail, String chunk, {int maxChars = 4096}) {
  final combined = tail + chunk;
  if (combined.length <= maxChars) return combined;
  return combined.substring(combined.length - maxChars);
}
