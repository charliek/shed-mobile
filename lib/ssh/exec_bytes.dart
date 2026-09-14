/// **One bootstrap step's remote exec** (plan 020 §3.8, commit C-M3) — the
/// second exec seam on this connection, beside `execOn` and deliberately not a
/// widening of it.
///
/// ## Why this is not `execOn`, and not the tunnel
///
/// Three rules make a bootstrap step a different animal from both of the exec
/// paths this app already has:
///
/// * **stdin is CLOSED, and that is the point.** [RoostTunnel]'s rule is "never
///   half-close the exec's stdin" (`roost_tunnel.dart`), because `client-bridge`
///   is a byte pump the watcher parks on for minutes. A bootstrap step is the
///   opposite: `/bin/sh -s` reads its program until EOF and `tee` reads its
///   input until EOF, so a runner that never closes stdin hangs every step until
///   its budget expires.
/// * **The bytes are a stream, not a `String`.** A stream step feeds a whole
///   `roost-session` binary — tens of megabytes of arbitrary bytes, NULs and
///   invalid UTF-8 included — pulled chunk by chunk out of Rust. `execOn` takes
///   a `String? stdin` and encodes it; there is no string here and there must
///   never be one.
/// * **The caps are the step's, not the runner's.** `stdout_cap`,
///   `capture_stdout`, `budget_ms` and `stderr_cap` all ride out on
///   `BridgeBootstrapStep::Exec` (the last one so that the two clients do not
///   truncate the same failure differently). Nothing here invents a number.
///
/// ## The three bands, concurrently
///
/// Writing the whole of stdin before reading a byte of stdout deadlocks the
/// moment the far side says anything at all: its pipe buffer fills, it stops
/// draining ours, and both sides wait. So the writer, the stdout reader and the
/// stderr tail all run at once — the shape `shed_app::roost::SshRunner::run`
/// uses for the same reason on the desktop.
///
/// ## Backpressure is load-bearing, not a nicety
///
/// The stdin stream is written with `addStream`, which pauses its source when
/// the channel's window is full. That is what keeps a 10 MiB install out of
/// memory: the source stream is an `async*` that pulls the next chunk out of
/// Rust (`bootstrapSourceRead`) only when it is asked for one, so a stalled far
/// side stops the pull rather than filling a buffer on the phone.
///
/// ## The command is NEVER quoted
///
/// Every `command` here is roost's own composition — `/bin/sh -s` with the
/// script on stdin, or one of roost's self-contained `sh -c '…'` words the far
/// side's login shell parses itself. It travels like `roostRemoteCommand()`:
/// verbatim, never through `wireCmd`. This file deliberately does not import the
/// quoter.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'rolling_tail.dart';
import 'roost_tunnel.dart';

/// One remote exec, reduced to the five things a BOOTSTRAP step needs.
///
/// [RoostExecSession] plus one member — and that member is the whole reason
/// this is its own type. The tunnel never reads an exit status (a byte pump has
/// no verdict; the stream ending is the signal), while a bootstrap step's
/// status is most of its answer: shed-core's rule is that a missing one is a
/// failure.
///
/// **Why the seam exists** is [RoostExecSession]'s reason unchanged: dartssh2's
/// `SSHSession` can only be produced by a live `SSHClient` against a real
/// server, so without this interface every test below would need an sshd.
abstract class BootstrapExecSession implements RoostExecSession {
  /// The remote process's exit status, or null when the far side never sent
  /// one. dartssh2 occasionally drops the `exit-status` request even on
  /// success, so null is "unknown", not "failed" — see [ExecBytesOutcome].
  int? get exitCode;

  /// **Abandon the exec as forcibly as this transport can**, for a budget that
  /// expired or a band that died — never for a step that ended on its own.
  ///
  /// It exists as its own member because [RoostExecSession.close] is *polite*:
  /// it sends EOF and asks. A remote command that ignores EOF (a `tee` wedged
  /// on a full disk, a `sh` waiting on something) keeps running, and its
  /// channel stays open on the SHARED `SSHClient` that the roost tunnel and
  /// every lane forward ride — so a leak here is a leak for the whole app, and
  /// the step's output arrives during the NEXT step.
  ///
  /// See `_SshBootstrapExec.destroy` for exactly how forcible dartssh2 2.18.0
  /// lets this be, which is less than one would like.
  void destroy();
}

/// Opens one exec of [command] on the far side. See [BootstrapExecSession].
typedef BootstrapExecOpen =
    Future<BootstrapExecSession> Function(String command);

/// **How one bootstrap exec ended, before shed-core's `exit` rule is applied.**
///
/// The rule itself is not here on purpose: this type reports what the transport
/// observed, and `resolveBootstrapExit` (in `roost_bootstrap_runner.dart`)
/// turns that into the `exit` the machine is fed. Keeping the observation and
/// the judgement apart is what lets the judgement be tested as a pure function
/// against every combination the transport can produce.
class ExecBytesOutcome {
  const ExecBytesOutcome({
    required this.exitCode,
    required this.cleanEof,
    required this.stdinDelivered,
    required this.stdout,
    required this.stderrTail,
  });

  /// What the far side reported, or null when it reported nothing — a budget
  /// that expired, a transport that died, or a channel that closed without an
  /// `exit-status`.
  final int? exitCode;

  /// **Whether the transport itself ended cleanly**: every band finished with
  /// an end-of-stream rather than an error, the channel's `done` settled
  /// without one, the budget did not expire, and stdin was delivered and closed.
  ///
  /// A stdin write that failed counts against this. A broken pipe is the
  /// ordinary way a *failing* remote step ends, and a transport that could not
  /// finish handing over what it was sending has not closed cleanly, whatever
  /// the read half did.
  final bool cleanEof;

  /// **Whether every byte this step was asked to send was handed over and the
  /// write half then closed.**
  ///
  /// False when the source stream errored — a `bootstrapSourceRead` that
  /// refused part-way through a `roost-session` binary — or when the channel's
  /// own sink did.
  ///
  /// It is reported separately from [cleanEof] because it is the one
  /// observation that outranks an explicit exit status. A remote `tee` that
  /// receives 3 of 9 bytes and then sees EOF exits **0**: it did what it was
  /// asked with what it was given. That status is a verdict on a *different*
  /// input from the one the step was supposed to deliver, so it is not this
  /// step's answer at all — see `resolveBootstrapExit`. The remote-side staged
  /// verify would very likely catch the truncation too; this is the seam that
  /// must not hand the machine a success it did not earn in the first place.
  final bool stdinDelivered;

  /// Stdout, capped from the **head** at the step's `stdout_cap`, and empty for
  /// a step that asked for no capture. The answers that matter are
  /// NUL-delimited records at the start.
  final Uint8List stdout;

  /// The **tail** of stderr, at the step's `stderr_cap`: a login banner comes
  /// first and the useful line last. Decoded leniently — the cut is at a byte
  /// boundary, so it can land inside a UTF-8 sequence.
  final String stderrTail;
}

/// **Run one bootstrap step on an ALREADY-OPEN [client]**, feeding [stdin] and
/// closing it to send EOF.
///
/// The connection is neither opened nor closed here: one `SSHClient` per
/// machine is shared by the roost tunnel, every lane forward and this, and
/// closing it after a step would take the others down with it.
///
/// [label] prefixes the sentences this side has to write itself (a budget that
/// expired, a channel that would not open) — the machine's name, so a card can
/// say which host stalled.
Future<ExecBytesOutcome> execBytesOn(
  SSHClient client,
  String command,
  Stream<Uint8List> stdin, {
  required Duration budget,
  required int stdoutCap,
  required bool captureStdout,
  required int stderrCap,
  String label = 'the machine',
}) => execBytesWith(
  (c) async => _SshBootstrapExec(await client.execute(c)),
  command,
  stdin,
  budget: budget,
  stdoutCap: stdoutCap,
  captureStdout: captureStdout,
  stderrCap: stderrCap,
  label: label,
);

/// [execBytesOn] with the SSH half replaced. See [BootstrapExecSession] for why.
@visibleForTesting
Future<ExecBytesOutcome> execBytesWith(
  BootstrapExecOpen open,
  String command,
  Stream<Uint8List> stdin, {
  required Duration budget,
  required int stdoutCap,
  required bool captureStdout,
  required int stderrCap,
  String label = 'the machine',
}) async {
  final started = Stopwatch()..start();
  final BootstrapExecSession session;
  final opening = open(command);
  try {
    session = await opening.timeout(budget);
  } on TimeoutException {
    // **The open is abandoned, not cancelled** — dartssh2 has no cancel, and
    // `client.execute` may still complete with a live exec a moment later. That
    // exec would be owned by nobody: an undrained remote channel on the SHARED
    // `SSHClient`, for the rest of the app's life, quietly filling its window.
    // So whatever the abandoned future eventually yields is destroyed here.
    unawaited(
      opening.then<void>((opened) {
        try {
          opened.destroy();
        } catch (_) {
          // Already gone. Nothing to close and nothing to report.
        }
      }, onError: (Object _) {}),
    );
    return _expired(label, budget);
  } catch (error) {
    // Never thrown: the machine has to hear about this as an outcome, or the
    // step it was owed is lost and the drive stalls. A channel that would not
    // open is `exit: None` with a sentence, exactly like a budget that expired.
    return ExecBytesOutcome(
      exitCode: null,
      cleanEof: false,
      stdinDelivered: false,
      stdout: Uint8List(0),
      stderrTail: '$label: could not open the remote step: $error',
    );
  }
  final run = _ExecBytesRun(
    session,
    stdoutCap: stdoutCap,
    captureStdout: captureStdout,
    stderrCap: stderrCap,
    label: label,
  );
  // The budget covers the WHOLE step, so what is left of it after the channel
  // opened is what the body gets. A per-phase budget would let a step that
  // opened slowly still run for its full length.
  final remaining = budget - started.elapsed;
  return run.drive(
    stdin,
    remaining.isNegative ? Duration.zero : remaining,
    budget,
  );
}

ExecBytesOutcome _expired(String label, Duration budget) => ExecBytesOutcome(
  exitCode: null,
  cleanEof: false,
  // A step that ran out of budget mid-send did not finish sending, and one
  // whose channel never opened never started: neither delivered.
  stdinDelivered: false,
  stdout: Uint8List(0),
  stderrTail: '$label: the remote step did not finish within ${_spell(budget)}',
);

/// Shed's own sentence spells the budget in whole seconds; a phone's budgets
/// include sub-second ones in tests, and "within 0s" is not a diagnosis.
String _spell(Duration budget) => budget.inMilliseconds < 1000
    ? '${budget.inMilliseconds}ms'
    : '${budget.inSeconds}s';

/// One exec in flight: three concurrent bands, one deadline, and the teardown
/// that has to happen however it ends.
class _ExecBytesRun {
  _ExecBytesRun(
    this._session, {
    required this.stdoutCap,
    required this.captureStdout,
    required this.stderrCap,
    required this.label,
  });

  final BootstrapExecSession _session;
  final int stdoutCap;
  final bool captureStdout;
  final int stderrCap;
  final String label;

  final BytesBuilder _out = BytesBuilder(copy: false);
  int _kept = 0;
  late final RollingTail _err = RollingTail(stderrCap);

  final Completer<void> _outDone = Completer<void>();
  final Completer<void> _errDone = Completer<void>();
  StreamSubscription<Uint8List>? _outSub;
  StreamSubscription<Uint8List>? _errSub;

  /// The first thing that made this not a clean end: a band that errored, a
  /// `done` that threw, or a stdin write that failed.
  Object? _transportError;
  Object? _writeError;

  Future<ExecBytesOutcome> drive(
    Stream<Uint8List> stdin,
    Duration remaining,
    Duration budget,
  ) async {
    // **Registered BEFORE the first await, and that ordering is the whole
    // point** — `execOn` learned this the hard way. An error handed to a
    // `Completer` whose future has no listener YET is reported to the zone as
    // UNHANDLED at that instant, which fails the enclosing test and raises a
    // spurious crash report in the app; a handler attached afterwards cannot
    // retract it. `ignore()` suppresses only the REPORT, never the value: an
    // `await` on the same future still throws.
    _outSub = _session.stdout.listen(
      _takeStdout,
      onDone: () => _settle(_outDone),
      onError: (Object e) => _fail(_outDone, e),
    );
    _errSub = _session.stderr.listen(
      _err.add,
      onDone: () => _settle(_errDone),
      onError: (Object e) => _fail(_errDone, e),
    );
    final done = _session.done;
    _outDone.future.ignore();
    _errDone.future.ignore();
    done.ignore();

    var finished = false;
    final work = () async {
      try {
        // Awaited first, but not performed first: both read bands are ALREADY
        // draining, because their subscriptions were registered above. That is
        // what keeps a stream step from deadlocking — writing the whole of
        // stdin before reading a byte would stall the moment the far side's
        // pipe buffer filled and it stopped draining ours.
        await _write(stdin);
        await _outDone.future;
        await _errDone.future;
        await done;
      } catch (error) {
        _transportError ??= error;
      } finally {
        finished = true;
      }
    }();
    work.ignore();

    final expired = Completer<void>();
    final timer = Timer(remaining, () {
      if (!expired.isCompleted) expired.complete();
    });
    try {
      await Future.any(<Future<void>>[work, expired.future]);
    } finally {
      timer.cancel();
    }

    if (!finished) {
      // The budget expired. Stop the bands and kill the channel — a step left
      // running on the far side is a step whose output arrives during the next
      // one.
      await _abort();
      return _expired(label, budget);
    }

    final clean = _transportError == null && _writeError == null;
    if (!clean) {
      // A band that errored leaves a live channel on the SHARED client, so a
      // leak here is a leak for the whole app rather than for one call.
      await _abort();
    }
    var tail = _err.decode();
    final writeError = _writeError;
    // A broken pipe is the ordinary way a *failing* remote step ends — the far
    // side exited while this side was still feeding it — so it is never a
    // verdict of its own. It is worth one line of evidence when there is
    // nothing else, and worth nothing when the far side already said why.
    if (writeError != null && tail.trim().isEmpty) {
      tail = '$label: sending stdin failed: $writeError';
    }
    return ExecBytesOutcome(
      exitCode: _session.exitCode,
      cleanEof: clean,
      stdinDelivered: writeError == null,
      stdout: _out.takeBytes(),
      stderrTail: tail,
    );
  }

  void _settle(Completer<void> completer) {
    if (!completer.isCompleted) completer.complete();
  }

  void _fail(Completer<void> completer, Object error) {
    if (!completer.isCompleted) completer.completeError(error);
  }

  /// The head cap, applied while reading rather than afterwards: a far side
  /// that decides to `cat` something must not be able to make this side
  /// allocate without bound. A step whose answer was cut fails its own parse in
  /// Rust, which is the correct outcome — roost's parsers refuse output that
  /// does not end in its NUL.
  ///
  /// **A step that asked for no capture DISCARDS**, and does not merely cap:
  /// `tee` echoes every byte it is fed, and buffering a 10 MiB binary back into
  /// memory to look at a stdout nothing reads would be absurd. The band is
  /// still drained — an unread stdout is a channel that fills and a far side
  /// that blocks forever.
  void _takeStdout(Uint8List chunk) {
    if (!captureStdout) return;
    final room = stdoutCap - _kept;
    if (room <= 0) return;
    if (chunk.length <= room) {
      _out.add(chunk);
      _kept += chunk.length;
    } else {
      _out.add(Uint8List.sublistView(chunk, 0, room));
      _kept = stdoutCap;
    }
  }

  /// Write every chunk, then close — and the close is the EOF the far side is
  /// waiting for, not a channel close. `addStream` is what applies the
  /// backpressure: it pauses its source while the channel's window is full, so
  /// a stalled far side stops the pull instead of filling a buffer here.
  Future<void> _write(Stream<Uint8List> stdin) async {
    // **A source that FAILS must not vanish into the sink.** `addStream`
    // forwards a source's error to the SINK rather than completing its own
    // future with it, so without this a failed `bootstrapSourceRead` would land
    // in dartssh2's own stdin controller — reported to the zone as an unhandled
    // error, and invisible to the outcome this step is about to report. Caught
    // here, it ends the send (the generator is finished either way), closes
    // stdin, and costs the step its clean EOF.
    final guarded = stdin.handleError((Object error) => _writeError ??= error);
    try {
      await _session.stdin.addStream(guarded);
    } catch (error) {
      _writeError ??= error;
    }
    try {
      await _session.stdin.close();
    } catch (error) {
      _writeError ??= error;
    }
  }

  Future<void> _abort() async {
    await _outSub?.cancel();
    await _errSub?.cancel();
    _outSub = null;
    _errSub = null;
    // A cancelled subscription never fires `onDone`, so the band completers
    // would stay pending forever and the work future with them — holding the
    // session alive for a step that has already been reported. Settle them
    // here; they are already settled on every path that did not abort.
    _settle(_outDone);
    _settle(_errDone);
    try {
      // **Forcible, never the polite close.** Every caller of this is an
      // abnormal end — a budget that expired, a band that errored — and a
      // graceful EOF is exactly what a wedged remote command ignores. See
      // [BootstrapExecSession.destroy].
      _session.destroy();
    } catch (_) {
      // Already gone; there is nothing left to close and nothing to report.
    }
  }
}

/// Production [BootstrapExecSession]: dartssh2's own session, unchanged.
class _SshBootstrapExec implements BootstrapExecSession {
  _SshBootstrapExec(this._session);

  final SSHSession _session;

  @override
  StreamSink<Uint8List> get stdin => _session.stdin;

  @override
  Stream<Uint8List> get stdout => _session.stdout;

  @override
  Stream<Uint8List> get stderr => _session.stderr;

  @override
  Future<void> get done => _session.done;

  @override
  int? get exitCode => _session.exitCode;

  @override
  void close() => _session.close();

  /// **As forcible as dartssh2 2.18.0 allows, which is not very** — and the
  /// limit is the package's, so it is written down here rather than papered
  /// over.
  ///
  /// What the package offers on an exec, read off its source rather than
  /// guessed:
  ///
  /// * `SSHSession.close()` → `SSHChannelController.close()`, which cancels the
  ///   local consumer, sends `SSH_MSG_CHANNEL_EOF`, and sends
  ///   `SSH_MSG_CHANNEL_CLOSE` **only if the remote has already closed its
  ///   half**. Otherwise it returns a future that settles when the far side
  ///   closes — so on a command that ignores EOF, the channel stays open.
  /// * `SSHSession.kill(SSHSignal)` → a `signal` channel request with
  ///   `want_reply: false`. Best effort: OpenSSH's sshd does not implement
  ///   `signal` on a session channel, so against the usual far side this is a
  ///   no-op — but it costs one unanswered message, and against a server that
  ///   does implement it, it is the only thing that actually stops the process.
  /// * `SSHChannel.destroy()` is the real forced seam — it closes the remote
  ///   stream, sends EOF *and* CLOSE, and completes `done`. It is unreachable:
  ///   `SSHSession` holds its channel in a private field and
  ///   `src/ssh_channel.dart` is not exported from `package:dartssh2/dartssh2.dart`.
  ///
  /// **The consequence, stated plainly:** a remote command that ignores EOF can
  /// outlive a budget expiry on the far side until its own channel ends. What
  /// this side guarantees is narrower and is what the caller depends on — both
  /// read bands are cancelled and the outcome is already reported, so no byte
  /// of a timed-out step can be mistaken for the next step's output. If
  /// dartssh2 ever exposes a session-level destroy, this method is the one
  /// place that changes.
  @override
  void destroy() {
    // A process that already reported a status has exited — signalling it would
    // be a request against a channel the far side has finished with, on a
    // connection the whole app shares.
    if (_session.exitCode == null) {
      try {
        _session.kill(SSHSignal.KILL);
      } catch (_) {
        // The transport is already gone; the close below is still worth trying.
      }
    }
    _session.close();
  }
}
