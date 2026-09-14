import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/ssh/exec_bytes.dart';

import 'support/fake_exec_channel.dart';

/// **The bootstrap exec seam** (plan 020 §3.8, commit C-M3).
///
/// Every cell here is about one clause of `Step::Exec`'s contract, because the
/// three obvious fields are not the contract: `budget`, `stdout_cap`,
/// `capture_stdout` and the stderr tail all decide whether an install reports
/// what actually happened, and all four fail silently when they are wrong.
///
/// The seam is [execBytesWith] over a [FakeExecChannel], for the reason every
/// other seam in this directory exists: dartssh2's `SSHSession` is handed out by
/// a live `SSHClient` and by nothing else, so the alternative to a fake is an
/// sshd. The wire-level proof that a remote command is composed and delivered
/// correctly is shed's `tests/machine-transport` differential, not here.

/// A budget nothing in these cells is meant to hit.
const Duration _generous = Duration(seconds: 30);

/// The script a `/bin/sh -s` step feeds, standing in for one roost composed.
const String _script = 'set -e\nprintf "%s\\0" "Linux"\n';

/// One exec over [channel], with the four step-supplied knobs defaulted to
/// something harmless. Every cell overrides exactly the one it is about.
Future<ExecBytesOutcome> run(
  FakeExecChannel channel,
  Stream<Uint8List> stdin, {
  String command = '/bin/sh -s',
  Duration budget = _generous,
  int stdoutCap = 64 * 1024,
  bool captureStdout = true,
  int stderrCap = 4 * 1024,
  void Function(String)? onCommand,
}) => execBytesWith(
  (c) async {
    onCommand?.call(c);
    return channel;
  },
  command,
  stdin,
  budget: budget,
  stdoutCap: stdoutCap,
  captureStdout: captureStdout,
  stderrCap: stderrCap,
  label: 'mini3',
);

Stream<Uint8List> bytes(List<int> data) =>
    Stream<Uint8List>.value(Uint8List.fromList(data));

void main() {
  test('a `/bin/sh -s` step delivers its script and CLOSES stdin', () async {
    final channel = FakeExecChannel();
    var seen = '';
    final outcome = run(
      channel,
      bytes(utf8.encode(_script)),
      onCommand: (c) => seen = c,
    );
    await pumpEventQueue();

    // The EOF is the whole point: `sh -s` reads its program until stdin
    // closes, so a runner that never closes it hangs the step until its
    // budget expires. The tunnel's rule is the opposite one, which is why
    // this is a second seam and not a widened `execOn`.
    expect(channel.stdinClosed, isTrue);
    expect(channel.receivedText, _script);

    channel.emitStdout(utf8.encode('Linux\x00'));
    channel.finish(exit: 0);
    final result = await outcome;

    expect(result.exitCode, 0);
    expect(result.cleanEof, isTrue);
    expect(result.stdinDelivered, isTrue);
    expect(utf8.decode(result.stdout), 'Linux\x00');
    // Opaque, and handed over verbatim: every `Step::Exec.command` is roost's
    // own composition and never goes through a quoter of Dart's.
    expect(seen, '/bin/sh -s');
  });

  test('a self-contained one-line command runs with an EMPTY stdin, and '
      'nothing on the way back is skipped or re-read', () async {
    // roost's `start_script`/`path_check_command` shape: one `sh -c '…'` word
    // the far side's login shell parses itself, with nothing on stdin. The
    // child must still see an immediate EOF — a step that waits for one it
    // never gets burns its whole budget.
    //
    // Dart skips NOTHING on the way back. The interleaved-event skipping roost
    // needs is a property of its IPC framing, and §3.8 pins every `Step::Call`
    // in Rust over the loopback `Conn`; what crosses this seam is a process's
    // stdout, handed over whole for Rust to parse.
    final channel = FakeExecChannel();
    final outcome = run(
      channel,
      const Stream<Uint8List>.empty(),
      command: "sh -c 'roost-session start'",
    );
    await pumpEventQueue();
    expect(channel.stdinClosed, isTrue);
    expect(channel.received, isEmpty);

    channel.emitStdout(utf8.encode('ready pid=4242\n'));
    channel.emitStdout(utf8.encode('a second line nothing here reads\n'));
    channel.finish(exit: 0);
    final result = await outcome;

    expect(
      utf8.decode(result.stdout),
      'ready pid=4242\na second line nothing here reads\n',
    );
  });

  test('a chunked binary crosses byte-exact, NULs and invalid UTF-8 '
      'included', () async {
    // A `roost-session` is not text. A seam that decoded anywhere would turn
    // an 0x80 into a replacement character and put a corrupt binary on the far
    // side that only the staged verify would catch.
    final blob = Uint8List.fromList(<int>[
      0x7f,
      0x45,
      0x4c,
      0x46,
      0x00,
      0x00,
      0xff,
      0xfe,
      0x80,
      0xc3,
      0x28,
      0x00,
    ]);
    final channel = FakeExecChannel();
    final outcome = run(
      channel,
      Stream<Uint8List>.fromIterable(<Uint8List>[
        Uint8List.sublistView(blob, 0, 5),
        Uint8List.sublistView(blob, 5, 9),
        Uint8List.sublistView(blob, 9),
      ]),
    );
    await pumpEventQueue();
    channel.finish(exit: 0);
    await outcome;

    expect(channel.received, blob);
    expect(channel.stdinClosed, isTrue);
  });

  test('a stream step DISCARDS stdout rather than capping it', () async {
    // `capture_stdout: false` is the `tee` echo: every byte of the binary
    // comes back. Buffering 10 MiB to look at output nothing reads would be
    // absurd — and a cap alone would still hold `stdout_cap` of it for no
    // reason. The band is still DRAINED, or the far side blocks forever.
    final channel = FakeExecChannel();
    final outcome = run(
      channel,
      bytes(<int>[1, 2, 3]),
      captureStdout: false,
      stdoutCap: 64 * 1024,
    );
    await pumpEventQueue();
    for (var i = 0; i < 64; i++) {
      channel.emitStdout(Uint8List(1024));
    }
    channel.finish(exit: 0);
    final result = await outcome;

    expect(result.stdout, isEmpty);
    expect(result.exitCode, 0);
  });

  test('stdout is capped from the HEAD and stderr from the TAIL', () async {
    // Opposite ends, and neither is arbitrary: roost's answers are
    // NUL-delimited records at the START of stdout, while the useful line of
    // stderr is the LAST one — a login banner comes first.
    final channel = FakeExecChannel();
    final outcome = run(
      channel,
      const Stream<Uint8List>.empty(),
      stdoutCap: 8,
      stderrCap: 15,
    );
    await pumpEventQueue();
    channel.emitStdout(utf8.encode('HEADhead-tail-and-more'));
    channel.emitStderr('a very long login banner nobody wants\n');
    channel.emitStderr('the real error\n');
    channel.finish(exit: 1);
    final result = await outcome;

    // The head: a cap that kept the TAIL would keep 'and-more'.
    expect(utf8.decode(result.stdout), 'HEADhead');
    // The tail: a cap that kept the HEAD would keep 'a very long lin'.
    expect(result.stderrTail, 'the real error\n');
  });

  test('a clean EOF, a budget that expired and a transport failure are three '
      'different answers', () async {
    // The whole of shed-core's `exit: None` rule turns on telling these apart,
    // and the runner is the only layer that can.
    final clean = FakeExecChannel();
    final cleanRun = run(clean, const Stream<Uint8List>.empty());
    await pumpEventQueue();
    clean.emitStdout(utf8.encode('answer\x00'));
    clean.finish();
    final cleanResult = await cleanRun;
    expect(cleanResult.exitCode, isNull, reason: 'dartssh2 dropped the status');
    expect(cleanResult.cleanEof, isTrue);
    expect(cleanResult.stdout, isNotEmpty);

    // A channel that never ends. The budget is what stops it, and the step is
    // KILLED — one left running on the far side hands its output to the next.
    final wedged = FakeExecChannel();
    final expired = await run(
      wedged,
      const Stream<Uint8List>.empty(),
      budget: const Duration(milliseconds: 30),
    );
    expect(expired.exitCode, isNull);
    expect(expired.cleanEof, isFalse);
    expect(expired.stdout, isEmpty);
    expect(expired.stderrTail, contains('did not finish within 30ms'));
    expect(expired.stderrTail, contains('mini3'));
    // FORCIBLY, not politely. A graceful close sends EOF and asks — which is
    // exactly what a command wedged past its budget ignores — and dartssh2
    // then leaves the channel open on the SHARED client.
    expect(wedged.destroyCalled, isTrue);

    // A band that ERRORS is not an EOF at all, however much it had delivered.
    final broken = FakeExecChannel();
    final brokenRun = run(broken, const Stream<Uint8List>.empty());
    await pumpEventQueue();
    broken.emitStdout(utf8.encode('half an answer'));
    broken.failStdout(const SocketException('connection reset'));
    final brokenResult = await brokenRun;
    expect(brokenResult.cleanEof, isFalse);
    expect(
      broken.destroyCalled,
      isTrue,
      reason: 'a leaked channel is a leak for the whole app',
    );
  });

  test('an open that lands AFTER the budget is destroyed, not left '
      'running', () async {
    // dartssh2 has no cancel, so a `client.execute` that outran the budget is
    // merely ABANDONED — and it can still complete with a live exec a moment
    // later. Nothing would own that one: an undrained remote channel on the
    // SHARED client, for the rest of the app's life.
    final lateSession = FakeExecChannel();
    final gate = Completer<BootstrapExecSession>();
    final result = await execBytesWith(
      (_) => gate.future,
      'sh -c slow',
      const Stream<Uint8List>.empty(),
      budget: const Duration(milliseconds: 20),
      stdoutCap: 1024,
      captureStdout: true,
      stderrCap: 1024,
      label: 'mini3',
    );

    expect(result.stderrTail, contains('did not finish within 20ms'));
    expect(lateSession.destroyCalled, isFalse, reason: 'it has not opened yet');

    gate.complete(lateSession);
    await pumpEventQueue();

    expect(
      lateSession.destroyCalled,
      isTrue,
      reason: 'the abandoned open is still owned by someone',
    );
  });

  test('a channel whose `done` fails is not a clean EOF either', () async {
    final channel = FakeExecChannel();
    final outcome = run(channel, const Stream<Uint8List>.empty());
    await pumpEventQueue();
    channel.emitStdout(utf8.encode('answer\x00'));
    channel.failDone(StateError('the transport died'));
    final result = await outcome;

    expect(result.cleanEof, isFalse);
    expect(result.stdout, isNotEmpty, reason: 'what arrived still arrived');
  });

  test('an exec that cannot be opened is an OUTCOME, never a throw', () async {
    // The machine has to hear about it, or the step it was owed is lost and
    // the drive stalls with no answer at all.
    final result = await execBytesWith(
      (_) => Future<BootstrapExecSession>.error(StateError('no channel')),
      'sh -c true',
      const Stream<Uint8List>.empty(),
      budget: _generous,
      stdoutCap: 1024,
      captureStdout: true,
      stderrCap: 1024,
      label: 'mini3',
    );

    expect(result.exitCode, isNull);
    expect(result.cleanEof, isFalse);
    expect(result.stderrTail, contains('could not open the remote step'));
  });

  test('an early remote close mid-write reports the send failure, but only '
      'when the far side said nothing itself', () async {
    // A broken pipe is the ORDINARY way a failing step ends — the far side
    // exited while this side was still feeding it — so it is never a verdict
    // of its own, and never worth overwriting a reason the far side gave.
    final quiet = FakeExecChannel();
    final quietRun = run(quiet, _failing());
    await pumpEventQueue();
    quiet.finish(exit: 1);
    final quietResult = await quietRun;
    expect(quietResult.cleanEof, isFalse);
    expect(quietResult.stderrTail, contains('sending stdin failed'));
    expect(quietResult.stdinDelivered, isFalse);

    final loud = FakeExecChannel();
    final loudRun = run(loud, _failing());
    await pumpEventQueue();
    loud.emitStderr('roost-session: command not found\n');
    loud.finish(exit: 127);
    final loudResult = await loudRun;
    expect(loudResult.exitCode, 127);
    expect(loudResult.stderrTail, 'roost-session: command not found\n');
    // The far side's status is reported as observed — this type records what
    // the transport saw and judges nothing. That the send failed is carried
    // ALONGSIDE it, one field over, for `resolveBootstrapExit` to rule on.
    expect(loudResult.stdinDelivered, isFalse);
  });

  test('a far side that exits 0 on a TRUNCATED send says so in the '
      'outcome', () async {
    // The exact `tee` shape, and the reason `stdinDelivered` is a field rather
    // than a corollary of `cleanEof`: the source dies after 3 of 9 bytes, the
    // far side reads to a clean EOF, writes what it got and exits 0. Every
    // other signal here says success. Only this one does not.
    final channel = FakeExecChannel();
    final outcome = run(channel, _failing(), captureStdout: false);
    await pumpEventQueue();
    channel.finish(exit: 0);
    final result = await outcome;

    expect(result.exitCode, 0, reason: 'the far side really did report one');
    expect(result.stdinDelivered, isFalse);
    expect(channel.received, Uint8List.fromList(<int>[1, 2, 3]));
  });

  test('the writer WAITS on a stalled drain instead of buffering the '
      'binary', () async {
    // The property the whole stream step rests on. The source is pulled out of
    // Rust one chunk at a time (`bootstrapSourceRead`), so a writer with no
    // backpressure reads a whole `roost-session` into the phone's memory
    // before the first byte reaches the wire — on a device that will be killed
    // for it.
    const chunks = 200;
    var pulled = 0;
    Stream<Uint8List> source() async* {
      for (var i = 0; i < chunks; i++) {
        pulled++;
        yield Uint8List(64)..fillRange(0, 64, i % 256);
      }
    }

    final channel = FakeExecChannel(stalled: true);
    final outcome = run(channel, source());
    await pumpEventQueue();

    expect(channel.writes, 0, reason: 'the drain is stalled');
    expect(
      pulled,
      lessThanOrEqualTo(1),
      reason: 'a writer with no backpressure would have pulled all $chunks',
    );

    channel.release();
    await pumpEventQueue();
    channel.finish(exit: 0);
    await outcome;

    expect(pulled, chunks);
    expect(channel.writes, chunks);
    expect(channel.received.length, chunks * 64);
    expect(channel.stdinClosed, isTrue);
  });
}

/// A stdin stream that dies part-way through — a source read that failed, or a
/// far side that went away mid-send.
Stream<Uint8List> _failing() async* {
  yield Uint8List.fromList(<int>[1, 2, 3]);
  throw StateError('reading the roost-session source: no such file');
}
