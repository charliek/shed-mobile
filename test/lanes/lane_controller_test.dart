import 'dart:async';

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
/// Everything here runs through the one seam that exists so it can: a
/// [LaneSource] standing in for the FRB bridge. No native library is loaded
/// and no sshd is dialled.
///
/// The load-bearing claims, each of which fails silently in production if it
/// regresses:
///
/// 1. **The open ORDER** — forward, then `lane_open`. The forward's local
///    port IS the dial url, so opening before it exists means dialing a port
///    nothing is listening on yet.
/// 2. **The generation fence** — a nudge from a superseded handle is dropped,
///    not folded into the live view.
/// 3. **`unknown_session` and a vanished row end the retries.** Both are
///    answers that cannot change, and retrying them is a battery bill.
/// 4. **Only `ended` re-opens a lane, never `stale`** (plan 025 §3.2.4). An
///    adapter resuming from its cursor marks the view stale and clears it again
///    without the lane ending; a re-open there throws the cursor away.
void main() {
  group('open', () {
    test('runs forward, then lane_open — in that order', () async {
      final rig = _Rig();
      await rig.controller.open();

      expect(rig.log.take(2).toList(), ['forward:2421', 'open']);
      final spec = rig.bridge.specs.single;
      // The reported url is what a gx discovery record used to be matched
      // against, back when gx was one of the lane kinds; the dial url is
      // where THIS phone reaches it. Never conflated.
      expect(spec.reportedUrl, 'http://127.0.0.1:2421');
      expect(spec.dialUrl, 'http://127.0.0.1:40001');
      expect(spec.kind, 'opencode');
      expect(spec.sessionId, 'sess-1');
      // From the first SNAPSHOT — there is no capabilities call to cache at
      // open any more (plan 025 §3.2.1).
      expect(rig.controller.state.capabilities?.kind, 'opencode');
      // The roster row was already folded before the pump started, so there is
      // something to read without waiting for a nudge.
      expect(rig.bridge.snapshots, 1);
    });

    test('capabilities, settings and the live row follow the snapshot, '
        'verbatim', () async {
      // Plan 025 §3.2.1: they ride the lane's stream, so the controller takes
      // whatever each snapshot says — including "nothing yet" — rather than
      // keeping a value it saw once. A craze session's capabilities change
      // with its incarnation; a copy kept from an earlier snapshot would gate
      // the panel on a session that no longer exists.
      final rig = _Rig();
      rig.bridge.onSnapshot = (_) => _snap(capabilities: null);
      await rig.controller.open();
      expect(
        rig.controller.state.capabilities,
        isNull,
        reason: 'nothing is known until a seed carries it',
      );

      rig.bridge.onSnapshot = (_) => _snap(
        capabilities: _caps(kind: 'craze', interject: true, stop: true),
        session: _session(title: 'the live title', permissionMode: 'bypass'),
      );
      rig.bridge.handles.single.nudges.deliver();
      rig.pumpFrame();
      expect(rig.controller.state.capabilities?.kind, 'craze');
      expect(rig.controller.state.capabilities?.stop, isTrue);
      expect(rig.controller.state.session?.title, 'the live title');
      expect(rig.controller.state.session?.permissionMode, 'bypass');

      // A later snapshot that carries less — no row, different capabilities —
      // replaces what is held rather than merging into it.
      rig.bridge.onSnapshot = (_) =>
          _snap(capabilities: _caps(kind: 'craze', interject: false));
      rig.bridge.handles.single.nudges.deliver();
      rig.pumpFrame();
      expect(rig.controller.state.capabilities?.interject, isFalse);
      expect(rig.controller.state.session, isNull);
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

    test('is idempotent — a second call opens nothing', () async {
      final rig = _Rig();
      await Future.wait([rig.controller.open(), rig.controller.open()]);
      await rig.controller.open();

      expect(rig.bridge.opens, 1);
      expect(rig.acquired, [2421]);
    });
  });

  group('ended — the one re-open Dart owns', () {
    test('re-opens on the 1s → 30s ladder, keeping the lease', () async {
      final rig = _Rig();
      rig.bridge.onSnapshot = (_) =>
          _snap(stale: 'transport closed', ended: true);
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
    });

    test('a STALE lane that has not ended re-opens nothing — a silent resume '
        'is Rust\'s', () async {
      // The shape a craze lane resuming from its cursor produces: the banner
      // is up (`stale`), the lane has NOT ended. Re-opening here would tear
      // down the very handle that is resuming and throw its cursor away
      // (plan 025 §3.2.4) — the next snapshot clears the mark on its own.
      final rig = _Rig();
      rig.bridge.onSnapshot = (_) =>
          _snap(stale: 'hub connection lost', ended: false);
      await rig.controller.open();
      await pumpEventQueue();

      expect(rig.controller.state.stale, 'hub connection lost');
      expect(rig.controller.state.ended, isFalse);
      expect(rig.delays, isEmpty, reason: 'no re-open ladder for a stale mark');
      expect(rig.bridge.opens, 1);
      expect(rig.bridge.handles.single.closed, isFalse);
      expect(rig.controller.state.retrying, isFalse);

      // The resume lands: a lone same-generation Ready cleared the mark.
      rig.bridge.onSnapshot = (_) => _snap();
      rig.bridge.handles.single.nudges.deliver();
      rig.pumpFrame();
      expect(rig.controller.state.stale, isNull);
      expect(rig.bridge.opens, 1, reason: 'the same handle, start to finish');
    });

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
          _snap(stale: 'the agent reported unknown_session', ended: true);
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
        // Ended once, then healthy: the re-open has to land on a LIVE lane,
        // or the second half of this test would be fenced for the wrong
        // reason.
        var down = true;
        rig.bridge.onSnapshot = (_) {
          final stale = down ? 'transport closed' : null;
          final ended = down;
          down = false;
          return _snap(stale: stale, ended: ended);
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
          kind: 'opencode',
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
      rig.bridge.onSnapshot = (_) =>
          _snap(stale: 'gone: unknown_session', ended: true);
      await rig.controller.open();
      await pumpEventQueue();
      expect(rig.controller.state.abandoned, isTrue);

      rig.bridge.onSnapshot = (_) => _snap();
      rig.stamps.add(
        const BridgeAgentLaneStamp(
          kind: 'opencode',
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
  _Rig({String kind = 'opencode', this.reach = LaneReach.machine}) {
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

  /// The ORDERED record of what the open path did. The order is the claim.
  final List<String> log = [];

  late final _FakeLaneBridge bridge;
  late final StreamController<BridgeAgentLaneStamp?> stamps;
  late final LaneController controller;

  final List<int> acquired = [];
  final List<FakeLaneLease> leases = [];
  final List<Duration> delays = [];
  final List<void Function()> _frames = [];

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

/// opencode's own capabilities — what every opencode seed carries.
const _opencodeCaps = BridgeLaneCapabilities(
  kind: 'opencode',
  interject: false,
  cancel: true,
  approvals: true,
  historyCursor: false,
  settings: false,
  stop: false,
);

BridgeLaneCapabilities _caps({
  String kind = 'opencode',
  bool interject = false,
  bool stop = false,
}) => BridgeLaneCapabilities(
  kind: kind,
  interject: interject,
  cancel: true,
  approvals: true,
  historyCursor: false,
  settings: false,
  stop: stop,
);

BridgeLaneSession _session({String title = '', String? permissionMode}) =>
    BridgeLaneSession(
      id: 'sess-1',
      title: title,
      cwd: '/home/shed/proj',
      activity: BridgeRcActivity.idle,
      pendingApprovals: 0,
      approximate: false,
      permissionMode: permissionMode,
    );

/// A seeded snapshot: opencode's capabilities unless a test says otherwise —
/// an explicit `capabilities: null` is "no seed yet" — live and not ended.
BridgeLaneSnapshot _snap({
  List<BridgeRcFeedMessage> messages = const [],
  bool full = true,
  BridgeRcActivity activity = BridgeRcActivity.idle,
  int generation = 1,
  String? stale,
  bool ended = false,
  BridgeLaneSession? session,
  BridgeLaneCapabilities? capabilities = _opencodeCaps,
  List<BridgeLaneApproval> approvals = const [],
}) => BridgeLaneSnapshot(
  messages: messages,
  full: full,
  activity: activity,
  session: session,
  generation: BigInt.from(generation),
  stale: stale,
  ended: ended,
  capabilities: capabilities,
  approvals: approvals,
);

BridgeRcFeedMessage _row(int seq, String text) => BridgeRcFeedMessage(
  seq: BigInt.from(seq),
  role: 'assistant',
  msgType: 'text',
  text: text,
);
