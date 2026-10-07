/// **Why a machine's craze hub is not answering, classified on this side of
/// the bridge** (plan 025 §3.7.2, §3.3.2) — the craze twin of
/// `roost_reach.dart`, and for the same reason.
///
/// ## Why Dart classifies at all
///
/// A machine's craze hub is reached through the feed's second tunnel: Dart
/// owns the SSH exec of `craze bridge --hub`, and Rust is handed a loopback
/// PORT (`crazeSourceOpen`). Over that port Rust sees no exit status and no
/// stderr, so a machine with no craze and one with craze v0.0.1 both reach it
/// as the same thing — a connection that ended before `hello` — and it can only
/// call either `Unreachable`. The exec's stderr band is where the difference
/// is written, and Dart is the only layer that reads it. So **Dart is
/// authoritative for a failure before `hello`**: it hands its class to the
/// source handle (`crazeSourceNoteReach`), and the snapshot's `offline` carries
/// it until a seed proves the far side answers. Rust stays authoritative after
/// `hello` — a hub too old by its capabilities or codecs is Rust's own
/// `TooOld`.
///
/// ## The two markers, and nothing else
///
/// * **Not installed** — craze's ladder ran out of rungs: it prints
///   `craze: command not found` on its last line and exits 127 (shed-core's
///   composer, craze's published ladder). The text is what the band carries; an
///   exit status, when a caller has one, says the same thing.
/// * **Too old** — craze v0.0.1 has no `--hub`, and cobra refuses it with
///   `unknown flag: --hub` (plan 025 Amendment A2: v0.0.1 refuses the find-only
///   probe the same way). The only signal v0.0.1 gives, and pinned against the
///   REAL v0.0.1 binary by the integration harness — never a hand-written stub.
///
/// Anything else is **unclassified**, not "unreachable": the band belongs to a
/// remote program (a login profile can be chatty — shed#231's class), and an
/// unrecognized line is not evidence of anything. `roost_reach.dart` declines
/// to guess for the same reason.
///
/// **Never a substring of a user-facing sentence.** The input is craze's own
/// bytes on its own band; a snapshot's `reason` is copy, and a branch on it is a
/// bug waiting for a rewording.
library;

import '../src/rust/api/dto_lane.dart';
import 'roost_reach.dart' show lastNonEmptyLine;

/// The ladder's own last line when no rung held a craze (shed-core's composer
/// prints it before `exit 127`).
const crazeNotFoundMarker = 'craze: command not found';

/// cobra's refusal of the flag craze v0.0.1 does not have.
const crazeTooOldMarker = 'unknown flag: --hub';

/// What Dart's transport learned about a machine's craze reach: the class the
/// source handle is told, and the far side's own line.
class CrazeReachNote {
  const CrazeReachNote(this.cause, this.message);

  /// [BridgeSourceOffline.notInstalled] or [BridgeSourceOffline.tooOld] —
  /// never anything else: those are the only two classes the band can prove.
  final BridgeSourceOffline cause;

  /// The band's own line that proved it — the one worth quoting out of a tail
  /// that may open with a login banner and close with cobra's usage text.
  final String message;
}

/// The trimmed line of [text] that carries [marker], or null.
String? _lineWith(String text, String marker) {
  for (final line in text.split('\n')) {
    if (line.contains(marker)) return line.trim();
  }
  return null;
}

/// **The pre-`hello` classifier.** `exitCode` 127 is not installed (the
/// ladder's own status); `craze: command not found` in the tail is the same
/// fact as the band writes it; `unknown flag: --hub` is too old. Null for
/// anything else — unclassified, which is the honest "offer nothing".
///
/// `exitCode` is null on the tunnel's stderr band, which has no status to read
/// (`roost_reach.dart`'s `noteForExecStderr` has the same shape); the text
/// rule covers it, because the ladder prints its marker before it exits.
CrazeReachNote? crazeNoteForExec({int? exitCode, required String stderr}) {
  final notFound = _lineWith(stderr, crazeNotFoundMarker);
  if (exitCode == 127 || notFound != null) {
    final line = notFound ?? lastNonEmptyLine(stderr);
    return CrazeReachNote(
      const BridgeSourceOffline.notInstalled(),
      line.isEmpty ? 'exit 127' : line,
    );
  }
  final tooOld = _lineWith(stderr, crazeTooOldMarker);
  if (tooOld != null) {
    return CrazeReachNote(const BridgeSourceOffline.tooOld(), tooOld);
  }
  return null;
}
