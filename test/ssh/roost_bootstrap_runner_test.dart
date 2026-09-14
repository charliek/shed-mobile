import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/src/rust/api/roost.dart';
import 'package:shed_mobile/src/rust/api/roost_bootstrap.dart';
import 'package:shed_mobile/ssh/exec_bytes.dart';
import 'package:shed_mobile/ssh/roost_bootstrap_runner.dart';
import 'package:shed_mobile/ssh/roost_reach.dart';

import 'support/fake_exec_channel.dart';

/// **The drive loop** (plan 020 §3.8, commit C-M3): what Dart does with a
/// `Step::Exec`, and the three rules it exists to obey.
///
/// `BridgeRoostBootstrap` is an FRB opaque handle that only the native library
/// can produce, so the seam under test is [BootstrapHandle] — which is why it
/// exists. The bridge's own half (the machines, the wire calls, the reach note
/// being consumed by the failure it explains) is tested in Rust, in
/// `rust/src/api/roost_bootstrap.rs`'s own test module.

/// One exec step with every knob named, so a cell can move exactly one.
BridgeBootstrapStep exec({
  String command = '/bin/sh -s',
  BridgeBootstrapStdin stdin = const BridgeBootstrapStdin.empty(),
  int budgetMs = 15000,
  int stdoutCap = 65536,
  bool captureStdout = true,
  int stderrCap = 4096,
}) => BridgeBootstrapStep.exec(
  command: command,
  stdin: stdin,
  budgetMs: budgetMs,
  stdoutCap: stdoutCap,
  captureStdout: captureStdout,
  stderrCap: stderrCap,
);

/// A terminal step. `Failed` rather than `Probed` because it carries four
/// fields instead of eleven, and no cell here is about which terminal it is.
BridgeBootstrapStep done(String message) => BridgeBootstrapStep.failed(
  failure: BridgeBootstrapFailure(
    stage: BridgeBootstrapStage.probe,
    message: message,
    stageCode: 'probe',
  ),
);

/// What one exec the runner performed looked like.
class Performed {
  Performed(
    this.command,
    this.budget,
    this.stdoutCap,
    this.captureStdout,
    this.stderrCap,
  );

  final String command;
  final Duration budget;
  final int stdoutCap;
  final bool captureStdout;
  final int stderrCap;
  final BytesBuilder stdin = BytesBuilder(copy: true);
  Object? stdinError;
}

/// [BootstrapHandle] under the test's control: a scripted sequence of steps, a
/// record of everything the runner asked for, and a source it can make fail.
class FakeHandle implements BootstrapHandle {
  FakeHandle(
    this.steps, {
    this.sourceChunks = const <List<int>>[],
    this.sourceError,
  });

  /// The steps to hand back, in order: the first is `begin`'s.
  final List<BridgeBootstrapStep> steps;
  final List<List<int>> sourceChunks;
  final Object? sourceError;

  /// Every verb the runner called, in order — the whole point of cell 5.
  final List<String> calls = <String>[];
  final List<({int? exit, Uint8List stdout, String stderrTail})> fed =
      <({int? exit, Uint8List stdout, String stderrTail})>[];
  final List<RoostReachNote> notes = <RoostReachNote>[];

  /// Set to throw out of the next `feedExec` — a call that did not answer.
  Object? feedError;
  int sourceChunkAsked = 0;

  /// Which step the machine is currently owed. `begin` re-READS it and `feed`
  /// ADVANCES past it, which is the asymmetry the whole cancellation rule turns
  /// on — and the reason a fake that advanced on both would pass a test that
  /// proves nothing.
  int _at = 0;

  @override
  Future<BridgeBootstrapStep> begin() async {
    calls.add('begin');
    return steps[_at];
  }

  @override
  Future<BridgeBootstrapStep> feedExec({
    required int? exit,
    required Uint8List stdout,
    required String stderrTail,
  }) async {
    calls.add('feed');
    fed.add((exit: exit, stdout: stdout, stderrTail: stderrTail));
    // Consumed and advanced BEFORE the throw, deliberately: a cancellation that
    // lands after the machine moved and before Dart saw the answer is the
    // dangerous case, and the only one worth writing a rule for.
    if (_at < steps.length - 1) _at++;
    final error = feedError;
    if (error != null) {
      feedError = null;
      throw error;
    }
    return steps[_at];
  }

  @override
  void noteReach(BridgeReachKind kind, String message) {
    calls.add('note');
    notes.add(RoostReachNote(kind, message));
  }

  @override
  Stream<Uint8List> source(int chunk) async* {
    sourceChunkAsked = chunk;
    for (final chunk in sourceChunks) {
      yield Uint8List.fromList(chunk);
    }
    final error = sourceError;
    if (error != null) throw error;
  }
}

/// A runner over [handle] whose exec is recorded rather than performed.
({RoostBootstrapRunner runner, List<Performed> performed}) recorded(
  FakeHandle handle, {
  RoostReachObserver? reach,
  ExecBytesOutcome Function(Performed)? answer,
}) {
  final performed = <Performed>[];
  final runner = RoostBootstrapRunner(
    handle: handle,
    reach: reach,
    exec:
        (
          command,
          stdin, {
          required budget,
          required stdoutCap,
          required captureStdout,
          required stderrCap,
        }) async {
          final call = Performed(
            command,
            budget,
            stdoutCap,
            captureStdout,
            stderrCap,
          );
          performed.add(call);
          try {
            await for (final chunk in stdin) {
              call.stdin.add(chunk);
            }
          } catch (error) {
            call.stdinError = error;
          }
          return answer?.call(call) ?? ok();
        },
  );
  return (runner: runner, performed: performed);
}

ExecBytesOutcome ok({List<int> stdout = const <int>[1]}) => ExecBytesOutcome(
  exitCode: 0,
  cleanEof: true,
  stdinDelivered: true,
  stdout: Uint8List.fromList(stdout),
  stderrTail: '',
);

void main() {
  group('resolveBootstrapExit', () {
    test('a status the far side reported is the answer, whatever it says', () {
      expect(
        resolveBootstrapExit(
          ExecBytesOutcome(
            exitCode: 127,
            cleanEof: true,
            stdinDelivered: true,
            stdout: Uint8List(0),
            stderrTail: '',
          ),
        ),
        127,
      );
      expect(
        resolveBootstrapExit(
          ExecBytesOutcome(
            exitCode: 0,
            cleanEof: false,
            stdinDelivered: true,
            stdout: Uint8List(0),
            stderrTail: '',
          ),
        ),
        0,
      );
    });

    test('a clean EOF with output is the runner\'s ONE concession', () {
      // dartssh2 occasionally drops the `exit-status` request even on success.
      // This is the exception `bootstrap/mod.rs` leaves to the runner, and the
      // reason it is the runner's: a subprocess always has a status, so the
      // desktop never applies it.
      expect(
        resolveBootstrapExit(
          ExecBytesOutcome(
            exitCode: null,
            cleanEof: true,
            stdinDelivered: true,
            stdout: Uint8List.fromList(utf8.encode('Linux\x00')),
            stderrTail: '',
          ),
        ),
        0,
      );
    });

    test('a clean EOF with NOTHING on stdout is still a failure', () {
      // The guard that keeps a silent failure from reading as success: a step
      // that opened, said nothing and closed would otherwise report `Some(0)`
      // and the machine would take its success branch on no evidence at all.
      // It settles `capture_stdout: false` in the same stroke — a stream step
      // discards stdout, so there is no evidence to concede on.
      expect(
        resolveBootstrapExit(
          ExecBytesOutcome(
            exitCode: null,
            cleanEof: true,
            stdinDelivered: true,
            stdout: Uint8List(0),
            stderrTail: '',
          ),
        ),
        isNull,
      );
    });

    test('a send that did not finish is NEVER a success, whatever the far '
        'side reported', () {
      // The `tee` case, and the one guard that outranks an explicit status: a
      // source read that errors after 3 of 9 bytes still leaves the far side
      // reading to a clean EOF, so it writes what it got and exits 0. Reporting
      // that 0 would tell the machine a truncated `roost-session` binary
      // installed successfully. The remote staged verify would probably catch
      // it too — which is the point: this is the layer that must not hand over
      // a success it did not earn.
      expect(
        resolveBootstrapExit(
          ExecBytesOutcome(
            exitCode: 0,
            cleanEof: false,
            stdinDelivered: false,
            stdout: Uint8List(0),
            stderrTail: 'mini3: sending stdin failed: …',
          ),
        ),
        isNull,
      );
      // Nor is a NON-zero one passed through: a status earned on bytes this
      // step never finished sending is a verdict on a different input, so it
      // is no verdict on this step at all. The reason rides the stderr tail.
      expect(
        resolveBootstrapExit(
          ExecBytesOutcome(
            exitCode: 1,
            cleanEof: false,
            stdinDelivered: false,
            stdout: Uint8List.fromList(utf8.encode('partial\x00')),
            stderrTail: 'mini3: sending stdin failed: …',
          ),
        ),
        isNull,
      );
    });

    test('an unclean end is a failure however much it delivered', () {
      // A budget that expired and a transport that died both land here, and
      // shed-core's rule for both is the simple one.
      expect(
        resolveBootstrapExit(
          ExecBytesOutcome(
            exitCode: null,
            cleanEof: false,
            stdinDelivered: true,
            stdout: Uint8List.fromList(utf8.encode('half an answer')),
            stderrTail: 'the remote step did not finish within 60s',
          ),
        ),
        isNull,
      );
    });
  });

  group('the drive', () {
    test('runs each exec asked for and feeds its answer back', () async {
      final handle = FakeHandle(<BridgeBootstrapStep>[
        exec(command: 'sh -c discovery'),
        exec(command: 'sh -c identity'),
        done('the probe finished'),
      ]);
      final rig = recorded(handle);

      final step = await rig.runner.run();
      final commands = rig.performed.map((p) => p.command).toList();

      expect(step, isA<BridgeBootstrapStep_Failed>());
      expect(handle.calls, <String>['begin', 'feed', 'feed']);
      expect(commands, <String>['sh -c discovery', 'sh -c identity']);
      expect(handle.fed.first.exit, 0);
    });

    test('every cap is the STEP\'s — the runner invents none', () async {
      // `stderr_cap` rides out with the other two precisely so the two clients
      // do not truncate the same failure differently; a runner that picked its
      // own number would put that back.
      final handle = FakeHandle(<BridgeBootstrapStep>[
        exec(
          budgetMs: 4321,
          stdoutCap: 17,
          captureStdout: false,
          stderrCap: 99,
        ),
        done('done'),
      ]);
      final rig = recorded(handle);

      await rig.runner.run();

      final call = rig.performed.single;
      expect(call.budget, const Duration(milliseconds: 4321));
      expect(call.stdoutCap, 17);
      expect(call.captureStdout, isFalse);
      expect(call.stderrCap, 99);
    });

    test('each stdin shape becomes the bytes that shape means', () async {
      final empty = FakeHandle(<BridgeBootstrapStep>[exec(), done('done')]);
      final emptyRig = recorded(empty);
      await emptyRig.runner.run();
      expect(emptyRig.performed.single.stdin.toBytes(), isEmpty);

      final script = utf8.encode('printf "%s\\0" Linux\n');
      final bytesHandle = FakeHandle(<BridgeBootstrapStep>[
        exec(
          stdin: BridgeBootstrapStdin.bytes(bytes: Uint8List.fromList(script)),
        ),
        done('done'),
      ]);
      final bytesRig = recorded(bytesHandle);
      await bytesRig.runner.run();
      expect(bytesRig.performed.single.stdin.toBytes(), script);

      // The source carries no path and no bytes — only a length, an origin and
      // a digest — so the runner has to PULL it through the bridge.
      final sourceHandle = FakeHandle(
        <BridgeBootstrapStep>[
          exec(
            stdin: BridgeBootstrapStdin.source(
              len: BigInt.from(6),
              origin: 'the override',
              sha256: 'abc',
            ),
            captureStdout: false,
          ),
          done('done'),
        ],
        sourceChunks: <List<int>>[
          <int>[0x7f, 0x45, 0x4c],
          <int>[0x46, 0x00, 0xff],
        ],
      );
      final sourceRig = recorded(sourceHandle);
      await sourceRig.runner.run();
      expect(
        sourceRig.performed.single.stdin.toBytes(),
        Uint8List.fromList(<int>[0x7f, 0x45, 0x4c, 0x46, 0x00, 0xff]),
      );
      expect(sourceHandle.sourceChunkAsked, kSourceChunkBytes);
    });

    test('a source read that FAILS reaches the machine as a failed step, with '
        'the reason', () async {
      // The whole path, over the real exec seam: a `bootstrapSourceRead` that
      // refuses (a second reader, a closed handle, a read error) must not
      // vanish into the sink — it has to become this step's `exit: None` and
      // its stderr tail, or the install reports success on a truncated binary.
      final handle = FakeHandle(
        <BridgeBootstrapStep>[
          exec(
            stdin: BridgeBootstrapStdin.source(
              len: BigInt.from(9),
              origin: 'the override',
              sha256: null,
            ),
            captureStdout: false,
          ),
          done('done'),
        ],
        sourceChunks: <List<int>>[
          <int>[1, 2, 3],
        ],
        sourceError: StateError('a source call for mini3 is already in flight'),
      );
      final channel = FakeExecChannel();
      final runner = RoostBootstrapRunner(
        handle: handle,
        exec:
            (
              command,
              stdin, {
              required budget,
              required stdoutCap,
              required captureStdout,
              required stderrCap,
            }) {
              final outcome = execBytesWith(
                (_) async => channel,
                command,
                stdin,
                budget: budget,
                stdoutCap: stdoutCap,
                captureStdout: captureStdout,
                stderrCap: stderrCap,
                label: 'mini3',
              );
              // The far side exits cleanly having received a short file — the
              // shape that makes this worth asserting at all.
              unawaited(pumpEventQueue().then((_) => channel.finish(exit: 0)));
              return outcome;
            },
      );

      await runner.run();

      // `exit: None`, and the far side's own 0 is exactly why this cell is
      // worth writing. `tee` read 3 of the 9 bytes it was promised, saw a
      // clean EOF, wrote what it had and exited 0 — an honest status about an
      // input this step never finished sending. Reporting it would tell the
      // machine a truncated binary installed successfully.
      expect(
        handle.fed.single.exit,
        isNull,
        reason:
            'a truncated send is never a success, whatever the far side '
            'reported',
      );
      expect(
        handle.fed.single.stderrTail,
        contains('already in flight'),
        reason: 'the reason must reach the machine, not the zone',
      );
      expect(channel.received, Uint8List.fromList(<int>[1, 2, 3]));
    });
  });

  group('a cancelled call', () {
    test('is RE-READ with begin, and the outcome is never re-sent', () async {
      // The rule C-M2 created, and the one that cannot be recovered from by
      // inspection: `feed` CONSUMES the outcome and advances, so re-sending it
      // advances the machine twice on one exec — a probe that skips a rung, or
      // an install that takes a later stage's branch. An outcome carries no
      // identity, so nothing can tell the two apart.
      final handle = FakeHandle(<BridgeBootstrapStep>[
        exec(command: 'sh -c discovery'),
        exec(command: 'sh -c identity'),
        done('done'),
      ]);
      final rig = recorded(handle);
      handle.feedError = StateError('the call was cancelled');

      await expectLater(rig.runner.run(), throwsA(isA<StateError>()));
      expect(handle.calls, <String>['begin', 'feed']);
      expect(handle.fed, hasLength(1));

      // The recovery is another drive, and it starts by ASKING what step it is
      // owed rather than by repeating the answer it already gave. The machine
      // moved on under the cancellation, so what comes back is the SECOND
      // step — and feeding the first outcome again would have run the install's
      // next stage against the answer to its previous one.
      await rig.runner.run();
      final commands = rig.performed.map((p) => p.command).toList();
      expect(handle.calls, <String>['begin', 'feed', 'begin', 'feed']);
      expect(commands, <String>['sh -c discovery', 'sh -c identity']);
      expect(
        handle.fed,
        hasLength(2),
        reason: 'one feed per exec performed, never a replay of the last one',
      );
    });
  });

  group('the reach note', () {
    test(
      'hands over what Dart already knew, before the machine asks',
      () async {
        final observer = RoostReachObserver()
          ..record(
            const RoostReachNote(
              BridgeReachKind.notInstalled,
              'roost-session: command not found',
            ),
          );
        final handle = FakeHandle(<BridgeBootstrapStep>[done('done')]);
        final rig = recorded(handle, reach: observer);

        await rig.runner.run();

        expect(handle.calls.first, 'note', reason: 'noted BEFORE begin');
        expect(handle.notes.single.kind, BridgeReachKind.notInstalled);
        expect(handle.notes.single.message, 'roost-session: command not found');
      },
    );

    test('reaches the handle when it lands MID-DRIVE, which is when it '
        'lands', () async {
      // Rust dialling the loopback port is what makes the tunnel exec at all,
      // so the stderr that classifies a probe's `session.identify` arrives
      // while that very call is in flight. A runner that only noted up front
      // would note nothing on the first probe of a cold machine — and the
      // install offer would never appear.
      final observer = RoostReachObserver();
      final handle = FakeHandle(<BridgeBootstrapStep>[exec(), done('done')]);
      final performed = <Performed>[];
      final runner = RoostBootstrapRunner(
        handle: handle,
        reach: observer,
        exec:
            (
              command,
              stdin, {
              required budget,
              required stdoutCap,
              required captureStdout,
              required stderrCap,
            }) async {
              performed.add(
                Performed(command, budget, stdoutCap, captureStdout, stderrCap),
              );
              observer.record(
                const RoostReachNote(
                  BridgeReachKind.noSession,
                  'client-bridge: no session',
                ),
              );
              return ok();
            },
      );

      await runner.run();

      expect(handle.notes.single.kind, BridgeReachKind.noSession);
      expect(performed, hasLength(1));

      // And the subscription does not outlive the drive: a note recorded
      // afterwards belongs to whatever happens next, not to a finished probe.
      observer.record(
        const RoostReachNote(BridgeReachKind.unreachable, 'later'),
      );
      expect(handle.notes, hasLength(1));
    });

    test('a runner with no observer notes nothing, and the machine reports a '
        'failed probe rather than guessing', () async {
      final handle = FakeHandle(<BridgeBootstrapStep>[exec(), done('done')]);
      final rig = recorded(handle);

      await rig.runner.run();

      expect(handle.notes, isEmpty);
      expect(handle.calls, <String>['begin', 'feed']);
    });
  });
}
