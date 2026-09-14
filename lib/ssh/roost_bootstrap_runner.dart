/// **Driving a roost bootstrap from the phone** (plan 020 §3.8, commit C-M3).
///
/// The choreography is not here and must never be re-implemented here. It is
/// `shed_core::roost::bootstrap`'s two sans-IO machines, driven from
/// `rust/src/api/roost_bootstrap.rs`: they yield a step and consume an outcome,
/// and the caller owns every socket and every timer. §3.8 splits that ownership
/// down one line — **Rust performs `Step::Call` and `Step::Hooks` over the
/// loopback `Conn`, Dart performs `Step::Exec` over dartssh2** — so the only
/// step that ever reaches this file is the one that needs an SSH exec, and the
/// only thing this file does is perform it and hand the answer back.
///
/// ```text
///   begin ─────────────▶ Exec │ Probed │ Installed │ Failed
///   Exec ── execBytesOn ──▶ outcome ── feedExec ──▶ the next step
/// ```
///
/// ## Three rules this file exists to obey
///
/// 1. **After a cancelled call, RE-READ with `begin` — never re-send the
///    outcome.** Both machines compute their step from their current state
///    rather than stash one, so `begin` doubles as "re-read the step I am
///    owed". `feedExec` does one thing more: it CONSUMES the outcome and
///    advances. A cancellation that lands after the machine advanced but before
///    Dart saw the answer leaves a machine already past that step, so feeding
///    the same outcome again would advance it twice on one exec — a probe that
///    skips a rung, or an install that takes a later stage's branch. An outcome
///    carries no identity, so nothing can tell the two apart. [RoostBootstrapRunner.run]
///    therefore always starts at `begin` and **never retries a `feedExec` of
///    its own accord**.
/// 2. **The caps are the step's.** `budget_ms`, `stdout_cap`, `capture_stdout`
///    and `stderr_cap` all arrive on the step. Nothing here invents one.
/// 3. **The command is opaque and is never quoted.** See `exec_bytes.dart`.
///
/// ## `exit: None` follows shed-core, not either Dart precedent
///
/// See [resolveBootstrapExit]. `SshRunner._resolveCode` and `MachineFeed.probe`
/// keep their own rules for their own callers; this seam adopts neither.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../src/rust/api/roost.dart';
import '../src/rust/api/roost_bootstrap.dart';
import 'exec_bytes.dart';
import 'roost_reach.dart';

/// How many bytes a source read asks for at a time — 64 KiB, roughly an SSH
/// channel window's worth, so the write that follows is one the transport can
/// actually take.
///
/// It bounds what this side holds at once, and nothing more: the descriptor is
/// Rust's, and every chunk is written and dropped before the next is pulled.
const int kSourceChunkBytes = 64 * 1024;

/// Performing one `Step::Exec` on the far side. `MachineFeed.bootstrapExec` is
/// the production one — it rides the feed's ONE `SSHClient`, like `probe()` and
/// `acquireForward()` do, and never opens a second link.
typedef BootstrapExec =
    Future<ExecBytesOutcome> Function(
      String command,
      Stream<Uint8List> stdin, {
      required Duration budget,
      required int stdoutCap,
      required bool captureStdout,
      required int stderrCap,
    });

/// **The four bridge verbs a drive uses**, behind a seam.
///
/// The seam exists for the reason every other one in this directory does:
/// `BridgeRoostBootstrap` is an FRB opaque handle that only the native library
/// can produce, so without this interface not one rule above could be tested
/// without a machine, a host and a `roost-session` on it. [LiveBootstrapHandle]
/// is the production implementation and is the whole of the difference.
abstract class BootstrapHandle {
  /// The first step — and the way to re-read the one you are owed.
  Future<BridgeBootstrapStep> begin();

  /// Report what the far side did with an exec, and get the next step.
  Future<BridgeBootstrapStep> feedExec({
    required int? exit,
    required Uint8List stdout,
    required String stderrTail,
  });

  /// Tell Rust why the loopback reach is not answering, from the layer that
  /// knows. Synchronous, like the bridge verb under it.
  void noteReach(BridgeReachKind kind, String message);

  /// The verified descriptor's bytes, pulled [chunk] at a time until EOF.
  Stream<Uint8List> source(int chunk);
}

/// [BootstrapHandle] over the real bridge.
class LiveBootstrapHandle implements BootstrapHandle {
  const LiveBootstrapHandle(this.handle);

  final BridgeRoostBootstrap handle;

  @override
  Future<BridgeBootstrapStep> begin() => roostBootstrapBegin(handle: handle);

  @override
  Future<BridgeBootstrapStep> feedExec({
    required int? exit,
    required Uint8List stdout,
    required String stderrTail,
  }) => roostBootstrapFeedExec(
    handle: handle,
    exit: exit,
    stdout: stdout,
    stderrTail: stderrTail,
  );

  @override
  void noteReach(BridgeReachKind kind, String message) =>
      roostBootstrapNoteReach(handle: handle, kind: kind, message: message);

  /// **Pulled, never buffered.** `async*` suspends at its `yield` until the
  /// consumer asks for more, so a stalled write stops the next
  /// `bootstrapSourceRead` rather than reading a whole binary into the phone.
  ///
  /// An empty answer is this stream's EOF — which is also why the bridge
  /// refuses a zero-byte read rather than serving one.
  @override
  Stream<Uint8List> source(int chunk) async* {
    while (true) {
      final bytes = await bootstrapSourceRead(handle: handle, max: chunk);
      if (bytes.isEmpty) return;
      yield bytes;
    }
  }
}

/// **shed-core's `exit` rule, plus the one concession that belongs to a
/// runner.**
///
/// The machines' rule is the simple one: `exit: None` is a **failure**, because
/// three real things produce no status — a budget that expired, a transport
/// that died, and dartssh2 closing a channel without an `exit-status` message —
/// and only the runner can tell them apart.
///
/// **A step whose stdin did not finish is a failure whatever the far side
/// reported**, and that guard comes first because it is the only one that can
/// override an explicit status. `tee` is the case that makes it matter: a
/// source read that errors after 3 of 9 bytes still leaves the far side reading
/// to a clean EOF, so it writes what it got and exits **0**. That 0 is the
/// remote's honest verdict on the bytes it received, and those are not the
/// bytes this step was sending — a truncated `roost-session` binary would be
/// reported installed. The install's staged verify on the far side would very
/// likely catch it too; defence in depth is the point, and this seam must not
/// hand the machine a success it did not earn. A non-zero status is not passed
/// through either: it is a verdict on a different input, so it is no verdict at
/// all, and the reason travels in the stderr tail
/// (`… sending stdin failed: …`).
///
/// The concession (`bootstrap/mod.rs`'s own wording) is that a runner whose
/// transport reported a *clean* EOF, for a step whose stdout it read to the
/// end, may pass `Some(0)`. Note what it is NOT: it is not "stdout parsed
/// completely", because Dart cannot know that — Rust does the parsing
/// afterwards.
///
/// **And it requires stdout to be non-empty.** Otherwise a step that produced
/// nothing at all — a channel that opened, said nothing and closed — would
/// report `exit: Some(0)`, and a silent failure would read as success. That
/// also settles the `capture_stdout: false` case without a second branch: a
/// stream step's stdout is discarded, so there is no evidence to concede on and
/// a stream step that ends without a status is a failure. It is the
/// conservative direction, and the one the install's staged verify is built to
/// back up.
@visibleForTesting
int? resolveBootstrapExit(ExecBytesOutcome outcome) {
  if (!outcome.stdinDelivered) return null;
  final code = outcome.exitCode;
  if (code != null) return code;
  if (outcome.cleanEof && outcome.stdout.isNotEmpty) return 0;
  return null;
}

/// **One bootstrap of one host, driven to its answer.**
class RoostBootstrapRunner {
  RoostBootstrapRunner({
    required this.handle,
    required this.exec,
    this.reach,
    this.chunkBytes = kSourceChunkBytes,
  });

  final BootstrapHandle handle;
  final BootstrapExec exec;

  /// What Dart's own transport has learned about this machine's roost reach.
  ///
  /// The probe's single `Step::Call` is what separates *session answered* from
  /// *installed but not running* from *not installed at all*, and on the phone
  /// nothing on the Rust side can ever see the far end's `exit 127` or its
  /// `client-bridge: no session` — the reach Rust holds is a loopback port Dart
  /// owns. So the classification is handed over from here.
  ///
  /// **Both before and during, and each exactly once.** What Dart already knew
  /// is handed over before the machine is asked for anything; after that the
  /// drive is SUBSCRIBED, so a classification that lands mid-flight reaches the
  /// handle too. That second half is not a belt-and-braces: Rust dialling the
  /// loopback port is what makes the tunnel exec at all, so the stderr that
  /// classifies a probe's `session.identify` arrives *while that call is in
  /// flight*, and a runner that only noted up front would note nothing at all
  /// on the first probe of a cold machine.
  ///
  /// A note already spent is deliberately not re-sent: the bridge consumes one
  /// by the failure it explains, and handing the same observation over again
  /// would let it explain a second, different failure.
  ///
  /// A runner with no observer simply does not note, and the machine reports a
  /// *failed* probe rather than guessing — roost's own rule, kept.
  final RoostReachObserver? reach;

  final int chunkBytes;

  /// Drive to a terminal step: `Probed`, `Installed` or `Failed`.
  ///
  /// **Always starts at `begin`**, which is what makes it the correct thing to
  /// call again after a cancelled drive — see this file's rule 1. It never
  /// retries a `feedExec` itself: a failed bridge call is thrown to the caller,
  /// whose only correct recovery is to call this again.
  Future<BridgeBootstrapStep> run() async {
    final cancel = reach?.listen(_note);
    try {
      final known = reach?.last;
      if (known != null) _note(known);
      var step = await handle.begin();
      while (step is BridgeBootstrapStep_Exec) {
        final outcome = await exec(
          step.command,
          _stdinFor(step.stdin),
          budget: Duration(milliseconds: step.budgetMs),
          stdoutCap: step.stdoutCap,
          captureStdout: step.captureStdout,
          stderrCap: step.stderrCap,
        );
        step = await handle.feedExec(
          exit: resolveBootstrapExit(outcome),
          stdout: outcome.stdout,
          stderrTail: outcome.stderrTail,
        );
      }
      return step;
    } finally {
      cancel?.call();
    }
  }

  void _note(RoostReachNote note) => handle.noteReach(note.kind, note.message);

  Stream<Uint8List> _stdinFor(BridgeBootstrapStdin stdin) => switch (stdin) {
    // The child must see an immediate EOF. An empty stream still closes the
    // sink, which is what sends it.
    BridgeBootstrapStdin_Empty() => const Stream<Uint8List>.empty(),
    // Data, never re-parsed by anything, however many apostrophes a path on the
    // far side has — the whole reason roost composes scripts this way instead
    // of quoting them onto a command line.
    BridgeBootstrapStdin_Bytes(:final bytes) => Stream<Uint8List>.value(bytes),
    // Never a path, and there is none to hand over: the bytes shed hashed and
    // the bytes shed sends have to be the same bytes.
    BridgeBootstrapStdin_Source() => handle.source(chunkBytes),
  };
}
