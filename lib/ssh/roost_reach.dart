/// **Why a machine's `roost-session` is not answering, classified on this side
/// of the bridge** (plan 020 §3.8, amendment A2).
///
/// ## Why Dart classifies at all
///
/// On the desktop the transport is shed's own — `SystemSshTunnels::open` execs
/// `ssh`, reads its stderr, and hands the answer up as
/// `RoostReach::last_error`, so every client above it gets a typed
/// `ReachKind` for free. **On the phone Dart owns the transport**: the exec
/// runs on a dartssh2 channel this app opened, and the reach Rust is handed is
/// a `LabelledPort` — a loopback port somebody else owns, which takes the
/// trait's `last_error: None` default. So nothing on the Rust side can ever see
/// the far end's `exit 127` or its `client-bridge: no session`, and every
/// `Down` the phone's watcher publishes carries `kind: Other` until Dart says
/// otherwise.
///
/// That is what this file is: the one place Dart turns a transport observation
/// into a [BridgeReachKind]. Two consumers read it — the machine card's
/// affordance, through `MachineFeedState.downKind`, and the bootstrap probe's
/// `Step::Call`, through `roostBootstrapNoteReach`.
///
/// ## The table is roost's, not a second one
///
/// [classifySshFailure] is a **port** of `roost_ipc::ssh::classify_ssh_failure`,
/// as the Go provider's `ClassifySSHFailure` is
/// (`internal/roostprovider/classify.go`), and [reachKindFor] is a port of
/// `shed_app::roost::ReachError::from_ssh_failure`. Both halves are pinned
/// against the shared golden `crates/fixtures/roost-vectors/stderr-classes.json`
/// — `classes` and `reach_kinds` — from `integration_test/roost_goldens_test.dart`,
/// beside the Rust and Go legs that read the same file. A third language reading
/// the same bytes the same way is the only thing that makes three
/// implementations provably the same rather than the same today.
///
/// **Never a substring search over a user-facing sentence.** The input here is
/// the far side's own stderr — roost's own bytes, written by the exec chain
/// roost composed. A `Down`'s `reason`, by contrast, is copy: it is translated,
/// rewritten and shortened, and branching on it is a bug waiting for a
/// rewording (§3.8 forbids it).
library;

import '../src/rust/api/roost.dart';

// ---------------------------------------------------------------------------
// the classifier
// ---------------------------------------------------------------------------

/// roost's own classification of a failed remote exec — a port of
/// `roost_ipc::ssh::SshFailure` at the rev `rust/Cargo.toml` pins.
///
/// The six names are the golden's, in the classifier's own precedence order
/// (see [classifySshFailure] — the order is load-bearing, not alphabetical).
enum SshFailureClass {
  /// `REMOTE HOST IDENTIFICATION HAS CHANGED`. First, and first for a reason:
  /// this is what a machine-in-the-middle looks like from here, and the rule
  /// below it would also match the same blob (ssh prints "Host key
  /// verification failed." right after it).
  changedHostKey('changed-host-key'),

  /// `Host key verification failed`, with no prior pin to contradict.
  hostKeyUnknown('host-key-unknown'),

  /// `Permission denied`.
  auth('auth'),

  /// `client-bridge: no session`: a `roost-session` is INSTALLED on the far
  /// side and is not serving. Ahead of [notFound] because the bridge's own
  /// refusal is more specific than the generic "command not found" / 127 pair
  /// below it.
  noSession('no-session'),

  /// `command not found` in stderr, or exit 127 — falling off the end of
  /// roost's candidate ladder.
  notFound('not-found'),

  /// None of the above. Carries the last non-empty trimmed stderr line as its
  /// detail.
  ///
  /// roost does **not** special-case exit 255 (ssh's own "something went
  /// wrong" code): 255 with an unrecognized stderr lands here.
  transport('transport');

  const SshFailureClass(this.wire);

  /// The stable kebab name the golden uses.
  final String wire;
}

/// One classified exec failure: the class, and the one line worth quoting back
/// when the class itself is not the diagnosis.
class SshFailureVerdict {
  const SshFailureVerdict(this.failureClass, this.detail);

  final SshFailureClass failureClass;

  /// Only ever non-empty for [SshFailureClass.transport] — the other five
  /// classes ARE the diagnosis, so quoting a line back beside them would be
  /// noise.
  final String detail;
}

/// Port of `roost_ipc::ssh::classify_ssh_failure`.
///
/// [exitCode] is null when the far side never reported one — a channel that
/// closed without an `exit-status`, or an observation (the tunnel's stderr
/// band) that has no status to read at all.
///
/// **The rule order below is roost's, byte for byte.** Reordering it would
/// change the answer for every blob that matches two rules — a changed host key
/// also says "Host key verification failed"; a bridge that answers "no session"
/// can still exit 127 — and those overlaps are exactly what the golden's
/// `precedence-*` cases pin.
SshFailureVerdict classifySshFailure(int? exitCode, String stderrTail) {
  if (stderrTail.contains('REMOTE HOST IDENTIFICATION HAS CHANGED')) {
    return const SshFailureVerdict(SshFailureClass.changedHostKey, '');
  }
  if (stderrTail.contains('Host key verification failed')) {
    return const SshFailureVerdict(SshFailureClass.hostKeyUnknown, '');
  }
  if (stderrTail.contains('Permission denied')) {
    return const SshFailureVerdict(SshFailureClass.auth, '');
  }
  if (stderrTail.contains('client-bridge: no session')) {
    return const SshFailureVerdict(SshFailureClass.noSession, '');
  }
  if (stderrTail.contains('command not found') || exitCode == 127) {
    return const SshFailureVerdict(SshFailureClass.notFound, '');
  }
  return SshFailureVerdict(
    SshFailureClass.transport,
    lastNonEmptyLine(stderrTail),
  );
}

/// Port of `roost_ipc::ssh::last_line`: the last non-empty line of a stderr
/// tail, trimmed — the one thing worth quoting out of a blob that is mostly
/// login banner.
String lastNonEmptyLine(String text) {
  final lines = text.split('\n');
  for (var i = lines.length - 1; i >= 0; i--) {
    final trimmed = lines[i].trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return '';
}

/// Port of `shed_app::roost::ReachError::from_ssh_failure`'s mapping — which
/// kind a class becomes for a CLIENT.
///
/// Deliberately coarser than the classifier: the three "shed could not get onto
/// that box" families and roost's fallthrough all collapse into
/// [BridgeReachKind.unreachable], because a client's move is the same for each
/// — show the sentence and offer nothing. The two that are different are the
/// two the bootstrap turns on.
///
/// **No class maps to [BridgeReachKind.other]**, which is the property the
/// golden's `reach_kinds` section pins: `other` is what a failure that never
/// ran an exec at all reports.
BridgeReachKind reachKindFor(SshFailureClass failureClass) =>
    switch (failureClass) {
      SshFailureClass.notFound => BridgeReachKind.notInstalled,
      SshFailureClass.noSession => BridgeReachKind.noSession,
      SshFailureClass.changedHostKey ||
      SshFailureClass.hostKeyUnknown ||
      SshFailureClass.auth ||
      SshFailureClass.transport => BridgeReachKind.unreachable,
    };

/// **What one chunk of a roost exec's stderr is worth recording, if
/// anything.**
///
/// **Only a classification roost actually named is recorded.** The classifier's
/// fallback is [SshFailureClass.transport], which means "nothing here is
/// recognizable" — and on this band that is not evidence of anything: the
/// stderr belongs to the far side's own process, not to an `ssh` client, so an
/// unrecognized line is a remote program being chatty rather than a machine
/// being unreachable. The desktop can read its own fallback as `Unreachable`
/// because there it IS ssh's stderr; doing the same here would put a guess
/// where the honest answer is "unclassified, offer nothing".
///
/// No exit code is passed because this band has none to read — an exec's status
/// is not on it. It costs nothing: both actionable classes are named in the
/// text roost writes (`roost-session: command not found` from the candidate
/// ladder's last line, `client-bridge: no session` from the bridge itself), and
/// the exit-127 rule is only ever a second route to the first.
RoostReachNote? noteForExecStderr(String text) {
  final verdict = classifySshFailure(null, text);
  if (verdict.failureClass == SshFailureClass.transport) return null;
  return RoostReachNote(reachKindFor(verdict.failureClass), text.trim());
}

// ---------------------------------------------------------------------------
// what Dart observed, and who reads it
// ---------------------------------------------------------------------------

/// One thing Dart's own transport learned about a machine's roost reach: the
/// branch a caller acts on, and the sentence it shows.
class RoostReachNote {
  const RoostReachNote(this.kind, this.message);

  final BridgeReachKind kind;

  /// The far side's own words where there are any — the stderr line roost
  /// wrote — and this side's sentence where the failure never got that far.
  final String message;
}

/// **The one place Dart's transport observations are recorded**, and the seam
/// the two readers share.
///
/// A machine's feed records here (its tunnel's exec stderr, and its own failed
/// dials); `MachineFeedState.downKind` and the bootstrap probe both read it.
/// One observer rather than two because the two readings must never disagree:
/// a card that offers an install and a probe that reports "not installed" have
/// to be looking at the same observation.
///
/// **A listener exists because of an ordering.** The probe's `session.identify`
/// is performed inside Rust, during a `roostBootstrapFeedExec` call — and the
/// exec that classifies it runs *while that call is in flight*, because Rust
/// dialling the loopback port is what makes the tunnel exec at all. So a
/// bootstrap runner both (a) notes whatever is already known before it feeds,
/// and (b) subscribes, so an observation that lands mid-call still reaches the
/// handle before the call it explains fails. See
/// `RoostBootstrapRunner`.
class RoostReachObserver {
  RoostReachNote? _last;
  final List<void Function(RoostReachNote)> _listeners =
      <void Function(RoostReachNote)>[];

  /// The last classification, or null when nothing has been observed.
  ///
  /// Null is **unclassified**, not "reachable": it is the honest "offer
  /// nothing".
  RoostReachNote? get last => _last;

  /// Record what the transport just said, and tell every listener.
  void record(RoostReachNote note) {
    _last = note;
    // A copy, so a listener that cancels itself from inside its own callback
    // does not mutate the list being walked.
    for (final listener in List.of(_listeners)) {
      listener(note);
    }
  }

  /// Forget it — what a machine that came back deserves. Only evidence that the
  /// far side is answering should call this, for the same reason
  /// `MachineFeedState.downKind` is cleared by a `Snapshot` and by nothing
  /// else: a dropped connection is not evidence about the far side, and
  /// clearing on one would drop a still-true "roost is not installed here".
  void clear() => _last = null;

  /// Subscribe. The returned function cancels.
  void Function() listen(void Function(RoostReachNote) onNote) {
    _listeners.add(onNote);
    return () => _listeners.remove(onNote);
  }
}
