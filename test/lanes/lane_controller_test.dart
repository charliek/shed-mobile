import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/lanes/lane_controller.dart';
import 'package:shed_mobile/lanes/lane_source.dart';
import 'package:shed_mobile/src/rust/api/dto_lane.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';
import 'package:shed_mobile/src/rust/api/lane.dart';
import 'package:shed_mobile/ssh/lane_forward.dart';

import 'fake_lane_lease.dart';

/// **[LaneController] — the phone's lane logic** (plan 018 §3.11).
///
/// Everything here runs through the two seams that exist so it can: a
/// [LaneSource] standing in for the FRB bridge, and a [ProbeRunner] standing in
/// for `execOn` over the machine's SSH client. No native library is loaded and
/// no sshd is dialled.
///
/// The load-bearing claims, each of which fails silently in production if it
/// regresses:
///
/// 1. **The open ORDER** — probe, then forward, then `lane_open`. The probe's
///    bytes are an argument to the open (Rust parses them into the discovery it
///    pins the epoch with) and the forward's local port IS the dial url, so
///    either one out of place means opening a lane that cannot authenticate or
///    cannot dial, and finding out a round trip later.
/// 2. **The probe bytes never come back to Dart.** They are one `cat` away from
///    a bearer token: they cross verbatim, and nothing decodes, logs or
///    interpolates them — asserted with a sentinel plus invalid UTF-8.
/// 3. **`needsCredentials` causes NO re-open.** The pin resumes in place; a
///    re-open would throw away the generation the screen is showing.
/// 4. **The generation fence** — a nudge from a superseded handle is dropped,
///    not folded into the live view.
/// 5. **`unknown_session` and a vanished row end the retries.** Both are
///    answers that cannot change, and retrying them is a battery bill.
void main() {
  group('open', () {
    test('runs probe, then forward, then lane_open — in that order', () async {
      final rig = _Rig();
      await rig.controller.open();

      expect(rig.log.take(3).toList(), ['probe', 'forward:2421', 'open']);
      final spec = rig.bridge.specs.single;
      // The reported url is what a gx discovery record is matched against; the
      // dial url is where THIS phone reaches it. Never conflated.
      expect(spec.reportedUrl, 'http://127.0.0.1:2421');
      expect(spec.dialUrl, 'http://127.0.0.1:40001');
      expect(spec.kind, 'gx');
      expect(spec.sessionId, 'sess-1');
      expect(rig.controller.state.capabilities?.kind, 'gx');
      // The roster row was already folded before the pump started, so there is
      // something to read without waiting for a nudge.
      expect(rig.bridge.snapshots, 1);
    });

    test(
      'a LOCAL reach opens with no forward and dials the reported url',
      () async {
        // The negative control on the forward: reach decides it, and the
        // hermetic harness (§3.13) runs entirely on this leg.
        final rig = _Rig(reach: LaneReach.local);
        await rig.controller.open();

        expect(rig.log.contains('forward:2421'), isFalse);
        expect(rig.acquired, isEmpty);
        final spec = rig.bridge.specs.single;
        expect(spec.dialUrl, spec.reportedUrl);
      },
    );

    test('an opencode lane runs no probe at all', () async {
      // The negative control on the probe: it is gx's credential mechanism,
      // and opencode needs none. A probe here would be an SSH round trip
      // spent on nothing, and `lane_refresh_credentials` would refuse it.
      final rig = _Rig(kind: 'opencode');
      await rig.controller.open();

      expect(rig.probes, isEmpty);
      expect(rig.bridge.specs.single.gxProbeStdout, isNull);
      expect(rig.log.take(2).toList(), ['forward:2421', 'open']);
    });

    test('is idempotent — a second call opens nothing', () async {
      final rig = _Rig();
      await Future.wait([rig.controller.open(), rig.controller.open()]);
      await rig.controller.open();

      expect(rig.bridge.opens, 1);
      expect(rig.acquired, [2421]);
      expect(rig.probes.length, 1);
    });
  });

  group('the probe bytes', () {
    test('cross verbatim and reach no log, no error and no decode', () async {
      // A sentinel the way the harness greps for one, plus two bytes that are
      // not valid UTF-8: anything that decoded this would leave replacement
      // characters behind, and anything that logged it would leave the
      // sentinel.
      final sentinel = Uint8List.fromList([
        ...utf8.encode('SENTINEL_TOKEN_deadbeefcafe'),
        0xff,
        0xfe,
      ]);
      final rig = _Rig(probeStdout: sentinel);
      // The refusal Rust composes when no record matches — it names the
      // reported url and nothing from the stdout.
      rig.bridge.openFailure = const BridgeLaneError.unavailable(
        msg: 'no gx discovery record for http://127.0.0.1:2421',
      );

      final captured = <String>[];
      final previous = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) captured.add(message);
      };
      await runZoned(
        rig.controller.open,
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => captured.add(line),
        ),
      );
      debugPrint = previous;

      // Wired: the bytes DID reach the bridge, unaltered. Without this the
      // assertions below would pass against a probe that never ran.
      expect(rig.bridge.specs.single.gxProbeStdout, orderedEquals(sentinel));

      final error = rig.controller.state.error!;
      expect(error.code, 'LANE_UNAVAILABLE');
      final everythingDartSaid = [
        ...captured,
        error.code,
        error.message,
        error.toString(),
      ].join('\n');
      expect(everythingDartSaid, isNot(contains('SENTINEL')));
      expect(everythingDartSaid, isNot(contains('deadbeef')));
      // The replacement character a `utf8.decode(allowMalformed: true)` would
      // have left on those trailing bytes.
      expect(everythingDartSaid, isNot(contains('\u{FFFD}')));
    });
  });

  group('needsCredentials', () {
    test('re-probes and refreshes IN PLACE — no re-open', () async {
      final rig = _Rig();
      rig.bridge.onSnapshot = (_) => _snap(needsCredentials: true);
      await rig.controller.open();
      await pumpEventQueue();

      expect(rig.probes.length, 2, reason: 'one at open, one for the refresh');
      expect(rig.bridge.refreshed.single, orderedEquals(rig.probeStdout));
      // THE CLAIM: the lane is not re-opened, the handle is not closed, and the
      // generation the screen is showing is untouched.
      expect(rig.bridge.opens, 1);
      expect(rig.bridge.closes, 0);
      expect(rig.bridge.handles.single.closed, isFalse);
      expect(rig.delays, isEmpty);
      expect(rig.controller.state.needsCredentials, isTrue);
    });

    test('a snapshot that does not ask for one re-probes nothing', () async {
      final rig = _Rig();
      rig.bridge.onSnapshot = (_) => _snap();
      await rig.controller.open();
      await pumpEventQueue();

      expect(rig.probes.length, 1);
      expect(rig.bridge.refreshed, isEmpty);
    });
  });

  group('stale — the one re-open Dart owns', () {
    test(
      're-opens on the 1s → 30s ladder, with a fresh probe, keeping the lease',
      () async {
        final rig = _Rig();
        rig.bridge.onSnapshot = (_) => _snap(stale: 'transport closed');
        await rig.controller.open();
        await pumpEventQueue();

        expect(rig.delays, [const Duration(seconds: 1)]);
        expect(rig.controller.state.retrying, isTrue);
        expect(rig.controller.state.stale, 'transport closed');
        expect(rig.bridge.handles.single.closed, isTrue);
        // The lease is KEPT: the local port is fixed for the forward's life and
        // the forward re-dials the channel underneath it, so giving it back would
        // close a forward the next open needs.
        expect(rig.leases.single.releases, 0);

        rig.releaseDelay();
        await pumpEventQueue();
        expect(rig.bridge.opens, 2);
        expect(rig.probes.length, 2, reason: 'a fresh probe on every re-open');
        expect(rig.acquired, [2421], reason: 'and no second forward');

        // The ladder DOUBLES across consecutive failures — an agent that accepts
        // a connection and dies inside it must not be retried every second. (The
        // re-opened lane goes stale on its own first pull, which is exactly that
        // shape.)
        expect(rig.delays, [
          const Duration(seconds: 1),
          const Duration(seconds: 2),
        ]);
        rig.releaseDelay();
        await pumpEventQueue();
        expect(rig.delays.last, const Duration(seconds: 4));
        expect(rig.leases.single.releases, 0, reason: 'still the one forward');
      },
    );

    test('a healthy snapshot re-opens nothing', () async {
      final rig = _Rig();
      await rig.controller.open();
      await pumpEventQueue();

      expect(rig.delays, isEmpty);
      expect(rig.bridge.opens, 1);
      expect(rig.controller.state.stale, isNull);
      expect(rig.controller.state.retrying, isFalse);
    });

    test('unknown_session in the reason ENDS the retries', () async {
      final rig = _Rig();
      rig.bridge.onSnapshot = (_) =>
          _snap(stale: 'the agent reported unknown_session');
      await rig.controller.open();
      await pumpEventQueue();

      expect(rig.delays, isEmpty, reason: 'no ladder at all');
      expect(rig.controller.state.abandoned, isTrue);
      expect(rig.bridge.handles.single.closed, isTrue);
      expect(rig.leases.single.releases, 1);

      // And it stays ended: a later open() is a no-op.
      await rig.controller.open();
      expect(rig.bridge.opens, 1);
    });
  });

  group('the generation fence', () {
    test(
      'a nudge from a superseded handle is dropped; the live one pulls',
      () async {
        final rig = _Rig();
        // Stale once, then healthy: the re-open has to land on a LIVE lane, or
        // the second half of this test would be fenced for the wrong reason.
        var down = true;
        rig.bridge.onSnapshot = (_) {
          final stale = down ? 'transport closed' : null;
          down = false;
          return _snap(stale: stale);
        };
        await rig.controller.open();
        await pumpEventQueue();
        rig.releaseDelay();
        await pumpEventQueue();
        expect(rig.bridge.handles.length, 2, reason: 'the lane re-opened');
        expect(rig.controller.isOpen, isTrue);

        // The nudge stream a controller cancels would normally deliver nothing;
        // `_StubbornNudges` ignores the cancel precisely so the FENCE is what is
        // being tested here rather than the cancel that usually gets there first.
        final before = rig.bridge.snapshots;
        rig.bridge.handles.first.nudges.deliver();
        rig.pumpFrame();
        expect(
          rig.bridge.snapshots,
          before,
          reason: 'the old generation asked for nothing',
        );

        // The control: the CURRENT handle's nudge does pull.
        rig.bridge.handles.last.nudges.deliver();
        rig.pumpFrame();
        expect(rig.bridge.snapshots, before + 1);
      },
    );

    test('a nudge after close() is dropped', () async {
      final rig = _Rig();
      await rig.controller.open();
      await rig.controller.close();
      final before = rig.bridge.snapshots;

      rig.bridge.handles.single.nudges.deliver();
      rig.pumpFrame();

      expect(rig.bridge.snapshots, before);
    });
  });

  group('snapshot batching and the cursor', () {
    test('two nudges in one frame are one pull', () async {
      final rig = _Rig();
      await rig.controller.open();
      final before = rig.bridge.snapshots;

      rig.bridge.handles.single.nudges.deliver();
      rig.bridge.handles.single.nudges.deliver();
      rig.bridge.handles.single.nudges.deliver();
      rig.pumpFrame();

      expect(rig.bridge.snapshots, before + 1);

      // The control: one per frame, not one forever.
      rig.bridge.handles.single.nudges.deliver();
      rig.pumpFrame();
      expect(rig.bridge.snapshots, before + 2);
    });

    test(
      'full replaces, a delta appends, and the cursor follows the rows',
      () async {
        final rig = _Rig();
        var stage = 0;
        rig.bridge.onSnapshot = (_) => switch (stage) {
          0 => _snap(messages: [_row(1, 'a'), _row(2, 'b')]),
          1 => _snap(messages: [_row(3, 'c')], full: false),
          _ => _snap(messages: [_row(10, 'z')], generation: 2),
        };

        await rig.controller.open();
        expect(rig.bridge.cursors, [null]);
        expect(rig.controller.state.rows.map((r) => r.text), ['a', 'b']);

        stage = 1;
        rig.bridge.handles.single.nudges.deliver();
        rig.pumpFrame();
        expect(rig.bridge.cursors.last, BigInt.two);
        expect(rig.controller.state.rows.map((r) => r.text), ['a', 'b', 'c']);

        stage = 2;
        rig.bridge.handles.single.nudges.deliver();
        rig.pumpFrame();
        expect(rig.bridge.cursors.last, BigInt.from(3));
        // A `full` answer REPLACES — which is also how a generation change, a
        // resubscription and an evicted cursor all arrive.
        expect(rig.controller.state.rows.map((r) => r.text), ['z']);
        expect(rig.controller.state.generation, BigInt.two);
      },
    );

    test('a full answer with no rows clears the cursor', () async {
      final rig = _Rig();
      var empty = false;
      rig.bridge.onSnapshot = (_) =>
          empty ? _snap() : _snap(messages: [_row(7, 'a')]);
      await rig.controller.open();
      expect(rig.controller.state.rows, hasLength(1));

      empty = true;
      rig.bridge.handles.single.nudges.deliver();
      rig.pumpFrame();
      expect(rig.bridge.cursors.last, BigInt.from(7));

      rig.bridge.handles.single.nudges.deliver();
      rig.pumpFrame();
      // The seq Dart held names a window that no longer exists, so the next
      // ask is for the whole generation rather than a delta with a hole in it.
      expect(rig.bridge.cursors.last, isNull);
      expect(rig.controller.state.rows, isEmpty);
    });
  });

  group('full-stamp reconciliation', () {
    test('a vanished row closes the lane and ends the retries', () async {
      final rig = _Rig();
      await rig.controller.open();

      rig.stamps.add(null);
      await pumpEventQueue();

      expect(rig.controller.state.abandoned, isTrue);
      expect(rig.bridge.handles.single.closed, isTrue);
      expect(rig.leases.single.releases, 1);
      expect(rig.delays, isEmpty);

      await rig.controller.open();
      expect(rig.bridge.opens, 1, reason: 'gone is gone');
    });

    test('the SAME stamp again changes nothing', () async {
      // The negative control on reconciliation: the feed re-emits its rows on
      // every roost poll, and a lane that re-opened on each of those would
      // reconnect every two seconds forever.
      final rig = _Rig();
      await rig.controller.open();

      rig.stamps.add(rig.controller.stamp);
      await pumpEventQueue();

      expect(rig.bridge.opens, 1);
      expect(rig.bridge.closes, 0);
      expect(rig.leases.single.releases, 0);
    });

    test('a changed stamp re-opens against the new one, immediately', () async {
      final rig = _Rig();
      await rig.controller.open();

      // A restarted tab: the same session on a new port. Row-presence alone
      // would have missed this and kept talking to a dead forward.
      rig.stamps.add(
        const BridgeAgentLaneStamp(
          kind: 'gx',
          sessionId: 'sess-1',
          serverUrl: 'http://127.0.0.1:2500',
        ),
      );
      await pumpEventQueue();

      expect(rig.bridge.opens, 2);
      expect(rig.bridge.specs.last.reportedUrl, 'http://127.0.0.1:2500');
      expect(rig.acquired, [2421, 2500], reason: 'the port moved');
      expect(rig.leases.first.releases, 1, reason: 'the old forward went back');
      expect(rig.leases.last.releases, 0);
      expect(rig.delays, isEmpty, reason: 'a new stamp is news, not a failure');
      expect(rig.bridge.specs.last.dialUrl, 'http://127.0.0.1:40002');
    });

    test('a new stamp revives a lane that had been given up on', () async {
      final rig = _Rig();
      rig.bridge.onSnapshot = (_) => _snap(stale: 'gone: unknown_session');
      await rig.controller.open();
      await pumpEventQueue();
      expect(rig.controller.state.abandoned, isTrue);

      rig.bridge.onSnapshot = (_) => _snap();
      rig.stamps.add(
        const BridgeAgentLaneStamp(
          kind: 'gx',
          sessionId: 'sess-2',
          serverUrl: 'http://127.0.0.1:2421',
        ),
      );
      await pumpEventQueue();

      expect(rig.bridge.opens, 2);
      expect(rig.controller.state.abandoned, isFalse);
      expect(rig.bridge.specs.last.sessionId, 'sess-2');
    });
  });

  group('open failures', () {
    test('a transient refusal retries on the ladder', () async {
      final rig = _Rig();
      rig.bridge.openFailure = const BridgeLaneError.unavailable(
        msg: 'connection refused',
      );
      await rig.controller.open();
      await pumpEventQueue();

      expect(rig.controller.state.error?.code, 'LANE_UNAVAILABLE');
      expect(rig.controller.state.retrying, isTrue);
      expect(rig.controller.state.abandoned, isFalse);
      expect(rig.delays, [const Duration(seconds: 1)]);
    });

    test('an unsupported kind is permanent — no ladder', () async {
      final rig = _Rig(kind: 'codex');
      rig.bridge.openFailure = const BridgeLaneError.unsupportedLane(
        kind: 'codex',
      );
      await rig.controller.open();
      await pumpEventQueue();

      expect(rig.controller.state.error?.code, 'LANE_UNSUPPORTED_KIND');
      expect(rig.controller.state.abandoned, isTrue);
      expect(rig.controller.state.retrying, isFalse);
      expect(rig.delays, isEmpty);
    });

    test('a failed probe gives the lease back to nobody and retries', () async {
      final rig = _Rig();
      rig.probeFailure = StateError('the ssh link is down');
      await rig.controller.open();
      await pumpEventQueue();

      // The probe is first, so nothing was acquired and nothing leaked.
      expect(rig.acquired, isEmpty);
      expect(rig.bridge.opens, 0);
      expect(rig.controller.state.retrying, isTrue);
      expect(rig.delays, [const Duration(seconds: 1)]);
    });
  });

  group('the verbs', () {
    test('send and cancel reach the bridge', () async {
      final rig = _Rig();
      await rig.controller.open();

      await rig.controller.send('hello');
      await rig.controller.send('now', mode: BridgeSendMode.interject);
      await rig.controller.cancel();

      expect(rig.bridge.sent, ['hello', 'now']);
      expect(rig.bridge.modes, [
        BridgeSendMode.queue,
        BridgeSendMode.interject,
      ]);
      expect(rig.bridge.cancels, 1);
      expect(rig.controller.state.composerError, isNull);
    });

    test(
      'a refused cancel is an inline composer error, not a lane error',
      () async {
        final rig = _Rig();
        await rig.controller.open();
        rig.bridge.cancelFailure = const BridgeLaneError.notAccepting();

        await rig.controller.cancel();

        expect(rig.controller.state.composerError?.code, 'LANE_NOT_ACCEPTING');
        expect(rig.controller.state.error, isNull);
        expect(rig.controller.state.approvalErrors, isEmpty);
      },
    );

    test('a refused answer lands on the CARD that raised it', () async {
      final rig = _Rig();
      await rig.controller.open();
      rig.bridge.answerFailure = const BridgeLaneError.badRequest(
        msg: 'no option matches that decision',
      );

      await rig.controller.answer('appr-1', const BridgeLaneAnswer.reject());

      final error = rig.controller.state.approvalErrors['appr-1'];
      expect(error?.code, 'LANE_BAD_REQUEST');
      expect(error?.message, 'no option matches that decision');
      // Not a toast, and not the composer's: only this card's.
      expect(rig.controller.state.error, isNull);
      expect(rig.controller.state.composerError, isNull);
      expect(rig.controller.state.approvalErrors.keys, ['appr-1']);
    });

    test('a successful answer clears that card', () async {
      final rig = _Rig();
      await rig.controller.open();
      rig.bridge.answerFailure = const BridgeLaneError.alreadySubmitted();
      await rig.controller.answer('appr-1', const BridgeLaneAnswer.reject());
      expect(rig.controller.state.approvalErrors, isNotEmpty);

      rig.bridge.answerFailure = null;
      await rig.controller.answer('appr-1', const BridgeLaneAnswer.reject());

      expect(rig.controller.state.approvalErrors, isEmpty);
      expect(rig.bridge.answered, ['appr-1', 'appr-1']);
    });

    test(
      'a verb with no lane open is refused without touching the bridge',
      () async {
        final rig = _Rig();

        await rig.controller.send('hello');
        await rig.controller.answer('appr-1', const BridgeLaneAnswer.reject());

        expect(rig.controller.state.composerError?.code, 'LANE_NOT_OPEN');
        expect(
          rig.controller.state.approvalErrors['appr-1']?.code,
          'LANE_NOT_OPEN',
        );
        expect(rig.bridge.sent, isEmpty);
        expect(rig.bridge.answered, isEmpty);
      },
    );
  });

  group('close', () {
    test('releases the lease exactly once and is idempotent', () async {
      final rig = _Rig();
      await rig.controller.open();

      await rig.controller.close();
      await rig.controller.close();

      expect(rig.leases.single.releases, 1);
      expect(rig.bridge.closes, 1);
      expect(rig.bridge.handles.single.closed, isTrue);
      expect(rig.controller.isOpen, isFalse);
      // And it cannot be re-opened behind the caller's back.
      await rig.controller.open();
      expect(rig.bridge.opens, 1);
    });

    test('a close during the probe builds nothing at all', () async {
      final rig = _Rig();
      final gate = Completer<void>();
      rig.holdProbe = gate;
      final opening = rig.controller.open();

      await rig.controller.close();
      gate.complete();
      await opening;

      // The fence right after the probe: no forward is reserved and no lane is
      // opened, so there is nothing to leak.
      expect(rig.acquired, isEmpty);
      expect(rig.bridge.opens, 0);
      expect(rig.controller.isOpen, isFalse);
    });

    test('a lane that lands after a close is closed, not installed', () async {
      final rig = _Rig();
      final gate = Completer<void>();
      rig.bridge.holdOpen = gate;
      final opening = rig.controller.open();
      await pumpEventQueue();
      expect(rig.acquired, [2421], reason: 'the forward is already reserved');

      await rig.controller.close();
      gate.complete();
      await opening;

      // An abandoned open still runs to completion, so the handle it built is
      // closed HERE — otherwise it would sit there holding a pump, an adapter
      // and the HTTP connections the adapter opened, with nobody to end them.
      expect(rig.bridge.handles.single.closed, isTrue);
      expect(rig.controller.isOpen, isFalse);
      expect(rig.leases.single.releases, 1);
    });
  });

  group('the pure url helpers', () {
    test('laneRemotePort reads the port a forward must reach', () {
      expect(laneRemotePort('http://127.0.0.1:2421'), 2421);
      expect(laneRemotePort('http://127.0.0.1'), 80);
      expect(laneRemotePort('https://127.0.0.1'), 443);
      expect(
        () => laneRemotePort('not a url at all'),
        throwsA(
          isA<Object>().having(
            (e) => '$e',
            'message',
            contains('LANE_BAD_SERVER_URL'),
          ),
        ),
      );
    });

    test('laneDialUrl re-points the authority and keeps everything else', () {
      expect(
        laneDialUrl('http://127.0.0.1:2421', 40001),
        'http://127.0.0.1:40001',
      );
      expect(
        laneDialUrl('http://127.0.0.1:2421/v1', 40001),
        'http://127.0.0.1:40001/v1',
      );
    });
  });
}

// ---------------------------------------------------------------------------
// The rig
// ---------------------------------------------------------------------------

/// Everything a [LaneController] needs, faked, plus the levers each test pulls.
class _Rig {
  _Rig({
    String kind = 'gx',
    this.reach = LaneReach.machine,
    Uint8List? probeStdout,
  }) : probeStdout = probeStdout ?? Uint8List.fromList([1, 2, 3]) {
    bridge = _FakeLaneBridge(log);
    stamps = StreamController<BridgeAgentLaneStamp?>();
    controller = LaneController(
      machine: 'mini3',
      slug: '7',
      stamp: BridgeAgentLaneStamp(
        kind: kind,
        sessionId: 'sess-1',
        serverUrl: 'http://127.0.0.1:2421',
      ),
      source: bridge,
      probe: _probe,
      reach: reach,
      acquireForward: _acquire,
      stamps: stamps.stream,
      schedulePull: _frames.add,
      delay: _delay,
    );
    addTearDown(() async {
      await stamps.close();
      await controller.close();
    });
  }

  final LaneReach reach;
  final Uint8List probeStdout;

  /// The ORDERED record of what the open path did. The order is the claim.
  final List<String> log = [];

  late final _FakeLaneBridge bridge;
  late final StreamController<BridgeAgentLaneStamp?> stamps;
  late final LaneController controller;

  final List<String> probes = [];
  final List<int> acquired = [];
  final List<FakeLaneLease> leases = [];
  final List<Duration> delays = [];
  final List<void Function()> _frames = [];

  Object? probeFailure;
  Completer<void>? holdProbe;

  /// Every delay parks until [releaseDelay]. Deliberately not "completes
  /// immediately": a ladder that ran on its own would spin a failing open into
  /// an infinite loop inside a test.
  Completer<void> _delayGate = Completer<void>();

  void releaseDelay() {
    final gate = _delayGate;
    _delayGate = Completer<void>();
    gate.complete();
  }

  /// Run the pulls a nudge queued — the test's animation frame.
  void pumpFrame() {
    final pending = [..._frames];
    _frames.clear();
    for (final pull in pending) {
      pull();
    }
  }

  Future<void> _delay(Duration wait) {
    delays.add(wait);
    return _delayGate.future;
  }

  Future<Uint8List> _probe(String wireCommand) async {
    log.add('probe');
    probes.add(wireCommand);
    final gate = holdProbe;
    if (gate != null) await gate.future;
    final failure = probeFailure;
    if (failure != null) throw failure;
    return probeStdout;
  }

  Future<LaneLease> _acquire(int remotePort) async {
    log.add('forward:$remotePort');
    acquired.add(remotePort);
    final lease = FakeLaneLease(40000 + acquired.length);
    leases.add(lease);
    return lease;
  }
}

/// A [LaneSource] that records everything and invents nothing — the
/// `FakeShedClient` `noSuchMethod` pattern, so a call this fake does not know
/// about is a loud failure rather than a null.
class _FakeLaneBridge implements LaneSource {
  _FakeLaneBridge(this.log);

  final List<String> log;

  final List<BridgeLaneSpec> specs = [];
  final List<_FakeHandle> handles = [];
  final List<BigInt?> cursors = [];
  final List<Uint8List> refreshed = [];
  final List<String> sent = [];
  final List<BridgeSendMode> modes = [];
  final List<String> answered = [];

  int cancels = 0;
  int closes = 0;
  int snapshots = 0;

  int get opens => specs.length;

  Object? openFailure;
  Object? sendFailure;
  Object? cancelFailure;
  Object? answerFailure;

  /// Parks `lane_open` after the spec has been recorded, so a test can land a
  /// handle into a controller that has already torn down.
  Completer<void>? holdOpen;

  BridgeLaneSnapshot Function(BigInt? cursor) onSnapshot = (_) => _snap();

  @override
  String gxProbeCommand() => "sh -c 'probe'";

  @override
  Future<LaneHandle> open(BridgeLaneSpec spec) async {
    log.add('open');
    specs.add(spec);
    final gate = holdOpen;
    if (gate != null) await gate.future;
    final failure = openFailure;
    if (failure != null) throw failure;
    final handle = _FakeHandle();
    handles.add(handle);
    return handle;
  }

  @override
  Stream<bool> nudges(LaneHandle handle) => (handle as _FakeHandle).nudges;

  @override
  BridgeLaneCapabilities capabilities(LaneHandle handle) =>
      const BridgeLaneCapabilities(
        kind: 'gx',
        interject: true,
        create: true,
        cancel: true,
        approvals: true,
        historyCursor: true,
      );

  @override
  BridgeLaneSnapshot snapshot(LaneHandle handle, BigInt? sinceSeq) {
    snapshots++;
    cursors.add(sinceSeq);
    return onSnapshot(sinceSeq);
  }

  @override
  Future<void> send(
    LaneHandle handle, {
    required String text,
    required BridgeSendMode mode,
  }) async {
    final failure = sendFailure;
    if (failure != null) throw failure;
    sent.add(text);
    modes.add(mode);
  }

  @override
  Future<void> cancel(LaneHandle handle) async {
    final failure = cancelFailure;
    if (failure != null) throw failure;
    cancels++;
  }

  @override
  Future<void> answer(
    LaneHandle handle, {
    required String approvalId,
    required BridgeLaneAnswer answer,
  }) async {
    answered.add(approvalId);
    final failure = answerFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> refreshCredentials(
    LaneHandle handle,
    Uint8List gxProbeStdout,
  ) async => refreshed.add(gxProbeStdout);

  @override
  void close(LaneHandle handle) {
    closes++;
    (handle as _FakeHandle).closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHandle implements LaneHandle {
  final _StubbornNudges nudges = _StubbornNudges();
  bool closed = false;
}

/// A nudge stream whose `cancel` is a NO-OP.
///
/// The only way to test the generation fence rather than the subscription
/// cancel that usually gets there first: with a real stream a superseded
/// handle's nudge is never delivered at all, so a controller that had NO fence
/// would pass. This one delivers it anyway.
class _StubbornNudges extends Stream<bool> {
  final List<void Function(bool)> _listeners = [];

  void deliver() {
    for (final listener in [..._listeners]) {
      listener(true);
    }
  }

  @override
  StreamSubscription<bool> listen(
    void Function(bool event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    if (onData != null) _listeners.add(onData);
    return _DeafSubscription();
  }
}

class _DeafSubscription implements StreamSubscription<bool> {
  @override
  Future<void> cancel() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// DTO builders (plain Dart — no FFI is touched)
// ---------------------------------------------------------------------------

BridgeLaneSnapshot _snap({
  List<BridgeRcFeedMessage> messages = const [],
  bool full = true,
  BridgeRcActivity activity = BridgeRcActivity.idle,
  int generation = 1,
  String? stale,
  List<BridgeLaneApproval> approvals = const [],
  bool needsCredentials = false,
}) => BridgeLaneSnapshot(
  messages: messages,
  full: full,
  activity: activity,
  generation: BigInt.from(generation),
  stale: stale,
  approvals: approvals,
  needsCredentials: needsCredentials,
);

BridgeRcFeedMessage _row(int seq, String text) => BridgeRcFeedMessage(
  seq: BigInt.from(seq),
  role: 'assistant',
  msgType: 'text',
  text: text,
);
