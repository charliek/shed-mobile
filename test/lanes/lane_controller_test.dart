import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/bridge/bridge_adapters.dart';
import 'package:shed_mobile/lanes/lane_controller.dart';
import 'package:shed_mobile/lanes/lane_settings.dart';
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
/// 3. **A final `Down` and a vanished row end the retries.** A session that
///    does not exist (`unknown_session`), was closed (`session_closed`, craze's
///    end after a Stop) or never started (`start_failed: <cause>`) is an
///    answer that cannot change, and retrying it is a battery bill.
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

  group('a craze lane (plan 025 §3.7.2)', () {
    // A craze row's stamp is synthesized from its hostId — no URL: the lane
    // is the machine's craze source's to open.
    _Rig crazeRig() => _Rig(kind: crazeLaneKind, serverUrl: '');

    test('opens through the craze source and acquires NO forward', () async {
      final rig = crazeRig();
      await rig.controller.open();

      expect(
        rig.acquired,
        isEmpty,
        reason:
            'a craze session has no agent port: a lease would hold an '
            'SSH channel to nothing',
      );
      expect(rig.log, ['openCraze:sess-1']);
      expect(rig.bridge.specs, isEmpty, reason: 'and no stamped lane_open');
      expect(
        rig.bridge.crazeOpeners.single,
        same(rig.controller.openCrazeLane),
        reason: 'the machine feed\'s opener is the one the bridge is handed',
      );
      expect(rig.controller.isOpen, isTrue);
      expect(rig.controller.state.capabilities?.kind, 'opencode');
    });

    test('re-opens only on ENDED, and never through a forward', () async {
      final rig = crazeRig();
      rig.bridge.onSnapshot = (_) => _snap(stale: 'reconnecting');
      await rig.controller.open();
      await pumpEventQueue();
      expect(
        rig.bridge.crazeOpened,
        ['sess-1'],
        reason: 'stale is a silent resume in progress, not a re-open',
      );
      expect(rig.delays, isEmpty);

      // An end that says nothing of the SESSION (its transport gave up): a
      // `session_closed` is final, and re-opens nothing (the group below).
      rig.bridge.onSnapshot = (_) => _snap(stale: 'unreachable', ended: true);
      rig.bridge.handles.single.nudges.deliver();
      rig.pumpFrame();
      await pumpEventQueue();
      expect(rig.delays, [const Duration(seconds: 1)]);
      rig.releaseDelay();
      await pumpEventQueue();
      expect(rig.bridge.crazeOpened, ['sess-1', 'sess-1']);
      expect(
        rig.acquired,
        isEmpty,
        reason: 'a re-open forwards nothing either',
      );
    });

    test('a retired craze source closes the lane, and its replacement '
        're-opens it AT ONCE', () async {
      // A feed restart (a roost bootstrap completing does one) closes the
      // craze tunnel and source this lane rode, and the lane's own stream
      // says nothing about it. Following the source is what keeps it from
      // redialling a closed port for minutes.
      final rig = crazeRig();
      await rig.controller.open();
      final first = rig.bridge.handles.single;

      await rig.crazeSource(null);
      expect(first.closed, isTrue, reason: 'the retired source\'s handle goes');
      expect(rig.controller.isOpen, isFalse);
      expect(rig.controller.state.retrying, isTrue);
      expect(
        rig.controller.state.abandoned,
        isFalse,
        reason: 'a source\'s retirement is not the session\'s end',
      );
      expect(rig.bridge.crazeOpened, ['sess-1'], reason: 'nothing to open yet');

      await rig.crazeSource(2);
      expect(rig.bridge.crazeOpened, ['sess-1', 'sess-1']);
      expect(rig.controller.isOpen, isTrue);
      expect(rig.delays, isEmpty, reason: 'at once — not on the ended ladder');
      expect(rig.acquired, isEmpty, reason: 'and still no forward');
    });

    test('the same source said live again re-opens nothing', () async {
      final rig = crazeRig();
      await rig.controller.open();
      await rig.crazeSource(1);
      expect(rig.bridge.crazeOpened, ['sess-1']);
      expect(rig.bridge.handles.single.closed, isFalse);
    });

    test('a source replaced while an open was in flight moves the lane once '
        'it lands', () async {
      final rig = crazeRig();
      final gate = Completer<void>();
      rig.bridge.holdOpen = gate;
      final opening = rig.controller.open();
      await pumpEventQueue();
      // The restart lands while the open (through epoch 1) is in flight.
      await rig.crazeSource(2);
      expect(rig.bridge.crazeOpened, ['sess-1'], reason: 'one open at a time');
      rig.bridge.holdOpen = null;
      gate.complete();
      await opening;
      await pumpEventQueue();
      expect(
        rig.bridge.crazeOpened,
        ['sess-1', 'sess-1'],
        reason: 'the handle through the retired source moved to epoch 2',
      );
      expect(rig.bridge.handles.first.closed, isTrue);
      expect(rig.controller.isOpen, isTrue);
    });

    test('a replacement that goes live WHILE the retired handle is being '
        'dropped is not missed', () async {
      // The drop awaits the nudge stream's cancel. A replacement that goes live
      // in that window sends its only notification while the lane has no
      // handle and has not finished leaving — so the lane must record the
      // wait before the await, and re-read the CURRENT source after it.
      final rig = crazeRig();
      await rig.controller.open();
      final first = rig.bridge.handles.single;
      first.holdCancel = Completer<void>();

      await rig.crazeSource(null);
      expect(first.closed, isTrue, reason: 'lane_close ran; the drop is held');
      await rig.crazeSource(2);
      expect(
        rig.bridge.crazeOpened,
        ['sess-1'],
        reason: 'nothing opens while the old handle is still being dropped',
      );

      first.holdCancel!.complete();
      await pumpEventQueue();
      expect(
        rig.bridge.crazeOpened,
        ['sess-1', 'sess-1'],
        reason: 'the drop landed on a live replacement: open through it now',
      );
      expect(rig.controller.isOpen, isTrue);
      expect(rig.controller.state.retrying, isFalse);
      expect(rig.delays, isEmpty);
    });

    test('an ENDED lane on its backoff is left to its own ladder by a '
        'retirement and a replacement', () async {
      final rig = crazeRig();
      await rig.controller.open();
      // An end that is not final (a `session_closed` would be given up on).
      rig.bridge.onSnapshot = (_) => _snap(stale: 'unreachable', ended: true);
      rig.bridge.handles.single.nudges.deliver();
      rig.pumpFrame();
      await pumpEventQueue();
      expect(rig.delays, [const Duration(seconds: 1)], reason: 'on its ladder');

      await rig.crazeSource(null);
      await rig.crazeSource(2);
      expect(
        rig.bridge.crazeOpened,
        ['sess-1'],
        reason:
            'a lane with no handle for its OWN reason is not the '
            'source\'s to re-open',
      );

      rig.bridge.onSnapshot = (_) => _snap();
      rig.releaseDelay();
      await pumpEventQueue();
      expect(
        rig.bridge.crazeOpened,
        ['sess-1', 'sess-1'],
        reason: 'the ended ladder re-opens it, through the live source',
      );
      expect(rig.controller.isOpen, isTrue);
    });

    test('an open that fails because its source was retired under it waits '
        'for the replacement, not the ladder', () async {
      final rig = crazeRig();
      final gate = Completer<void>();
      rig.bridge.holdOpen = gate;
      rig.bridge.openFailure = const BridgeLaneError.unavailable(
        msg: 'the craze source for mini3 was closed',
      );
      final opening = rig.controller.open();
      await pumpEventQueue();
      await rig.crazeSource(null);
      gate.complete();
      await opening;
      await pumpEventQueue();
      expect(rig.delays, isEmpty, reason: 'not the ended/transient ladder');
      expect(rig.controller.state.retrying, isTrue);

      rig.bridge.holdOpen = null;
      rig.bridge.openFailure = null;
      await rig.crazeSource(2);
      expect(rig.bridge.crazeOpened, ['sess-1', 'sess-1']);
      expect(rig.controller.isOpen, isTrue);
    });

    test('a craze stamp with no craze opener is refused at construction', () {
      expect(
        () => LaneController(
          machine: 'mini3',
          slug: 'cccccccccccc',
          stamp: BridgeAgentLaneStamp(
            kind: crazeLaneKind,
            sessionId: 'cccccccccccc',
            serverUrl: '',
          ),
          source: _FakeLaneBridge([]),
          reach: LaneReach.machine,
          acquireForward: (_) async => FakeLaneLease(1),
        ),
        throwsArgumentError,
      );
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

    test('unknown_session ENDS the retries', () async {
      final rig = _Rig();
      rig.bridge.onSnapshot = (_) =>
          _snap(stale: laneUnknownSession, ended: true);
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

  group('a final end (plan 025 §3.7.3) — never re-opened', () {
    test('laneDownIsFinal is the desktop\'s down_is_final, word for word', () {
      for (final reason in [
        'unknown_session',
        'session_closed',
        'start_failed',
        'start_failed: acp: agent exited',
      ]) {
        expect(laneDownIsFinal(reason), isTrue, reason: '$reason is final');
      }
      for (final reason in [
        'unreachable',
        're-attach bound',
        'protocol: another host answered',
        'the opencode event stream ended',
        'closed',
        'session_closed_soon',
        'down: unknown_session',
        '',
      ]) {
        expect(
          laneDownIsFinal(reason),
          isFalse,
          reason: '$reason is worth another attempt',
        );
      }
    });

    for (final reason in [
      'session_closed',
      'start_failed: KEYCHAIN LOCKED',
      'start_failed',
    ]) {
      test('a craze lane ended "$reason" is given up on, the transcript '
          'kept', () async {
        final rig = _Rig(kind: crazeLaneKind, serverUrl: '');
        rig.bridge.onSnapshot = (_) => _snap(
          messages: [_row(1, 'the last thing it said')],
          stale: reason,
          ended: true,
          capabilities: _caps(kind: 'craze', stop: true),
        );
        await rig.controller.open();
        await pumpEventQueue();

        expect(rig.delays, isEmpty, reason: 'no re-open ladder at all');
        expect(rig.controller.state.abandoned, isTrue);
        expect(rig.controller.state.retrying, isFalse);
        expect(rig.bridge.handles.single.closed, isTrue);
        expect(
          rig.controller.state.rows.single.text,
          'the last thing it said',
          reason: 'the transcript stays',
        );
        expect(rig.controller.state.stale, reason);

        // And it stays ended: a later open() is a no-op.
        await rig.controller.open();
        expect(rig.bridge.crazeOpened, ['sess-1']);
      });
    }

    test('the control: an end that is not final re-opens', () async {
      // Exact words: a reason that merely CONTAINS a final one is not one.
      final rig = _Rig(kind: crazeLaneKind, serverUrl: '');
      rig.bridge.onSnapshot = (_) =>
          _snap(stale: 'session_closed_soon', ended: true);
      await rig.controller.open();
      await pumpEventQueue();

      expect(rig.delays, [const Duration(seconds: 1)]);
      expect(rig.controller.state.abandoned, isFalse);
      rig.releaseDelay();
      await pumpEventQueue();
      expect(rig.bridge.crazeOpened, ['sess-1', 'sess-1']);
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
          _snap(stale: laneUnknownSession, ended: true);
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
      'stop reaches the bridge, and its refusal lands on the STOP',
      () async {
        final rig = _Rig(kind: crazeLaneKind, serverUrl: '');
        await rig.controller.open();

        await rig.controller.stop();
        expect(rig.bridge.stops, 1);
        expect(rig.controller.state.stopError, isNull);

        rig.bridge.stopFailure = const BridgeLaneError.failed(
          msg: 'unsupported: this host cannot stop its session',
        );
        await rig.controller.stop();
        expect(rig.controller.state.stopError?.code, 'LANE_FAILED');
        // Not the composer's, and not the lane's: Stop's own.
        expect(rig.controller.state.composerError, isNull);
        expect(rig.controller.state.error, isNull);
        expect(rig.controller.state.approvalErrors, isEmpty);

        // A stop that works clears it.
        rig.bridge.stopFailure = null;
        await rig.controller.stop();
        expect(rig.controller.state.stopError, isNull);
        expect(rig.bridge.stops, 3);
      },
    );

    test('a SEND whose answer was lost says so in the desktop\'s words; a '
        'refusal keeps its own', () async {
      final rig = _Rig(kind: crazeLaneKind, serverUrl: '');
      await rig.controller.open();
      rig.bridge.sendFailure = const BridgeLaneError.outcomeUnknown(
        msg:
            'outcome unknown: the connection dropped with session.prompt in '
            'flight',
      );

      await rig.controller.send('did this land?');
      expect(rig.controller.state.composerError?.code, laneOutcomeUnknownCode);
      expect(
        rig.controller.state.composerError?.message,
        laneSendOutcomeUnknown,
      );
      expect(
        laneSendOutcomeUnknown,
        'outcome unknown: the connection to craze dropped; check the '
        'transcript before sending again',
        reason: 'the desktop\'s SEND_OUTCOME_UNKNOWN',
      );

      // The control: a definite refusal is said as itself.
      rig.bridge.sendFailure = const BridgeLaneError.notAccepting();
      await rig.controller.send('again');
      expect(rig.controller.state.composerError?.code, 'LANE_NOT_ACCEPTING');
    });

    test(
      'a verb with no lane open is refused without touching the bridge',
      () async {
        final rig = _Rig();

        await rig.controller.send('hello');
        await rig.controller.answer('appr-1', const BridgeLaneAnswer.reject());
        await rig.controller.stop();

        expect(rig.controller.state.composerError?.code, 'LANE_NOT_OPEN');
        expect(rig.controller.state.stopError?.code, 'LANE_NOT_OPEN');
        expect(rig.bridge.stops, 0);
        expect(
          rig.controller.state.approvalErrors['appr-1']?.code,
          'LANE_NOT_OPEN',
        );
        expect(rig.bridge.sent, isEmpty);
        expect(rig.bridge.answered, isEmpty);
      },
    );
  });

  group('settings changes (plan 025 §3.10)', () {
    /// A craze lane open on a session that offers settings, at [frames]
    /// `Settings` so far.
    Future<_Rig> settingsRig({int frames = 1}) async {
      final rig = _Rig(kind: crazeLaneKind, serverUrl: '');
      rig.bridge.onSnapshot = (_) => _snap(
        capabilities: _settingsCaps,
        settings: _settings(),
        settingsFrames: frames,
      );
      await rig.controller.open();
      return rig;
    }

    /// Deliver [next] as the lane's next snapshot.
    void read(_Rig rig, BridgeLaneSnapshot next) {
      rig.bridge.onSnapshot = (_) => next;
      rig.bridge.handles.last.nudges.deliver();
      rig.pumpFrame();
    }

    test('a press is pending until craze answers — with no optimistic '
        'value — and a definite answer leaves no mark', () async {
      final rig = await settingsRig();
      final effort = _effortRow(rig.controller.state.settings!);
      rig.bridge.holdSet = Completer<void>();

      final pressed = rig.controller.setSetting(
        effort,
        'low',
        displayedModel: 'grok-4.6',
      );
      await pumpEventQueue();
      expect(rig.controller.state.settingMarks[effort.key], isA<RowPending>());
      expect(
        _effortRow(rig.controller.state.settings!).current,
        'high',
        reason: 'the row shows the SESSION\'s value, never the press',
      );

      // A second press on the pending row sends nothing.
      await rig.controller.setSetting(
        effort,
        'low',
        displayedModel: 'grok-4.6',
      );
      expect(rig.bridge.sets, hasLength(1));

      // craze's delta lands ahead of its answer: the next Settings.
      read(
        rig,
        _snap(
          capabilities: _settingsCaps,
          settings: _settings(effort: 'low'),
          settingsFrames: 2,
        ),
      );
      rig.bridge.holdSet!.complete();
      await pressed;
      expect(rig.controller.state.settingMarks, isEmpty);
      expect(_effortRow(rig.controller.state.settings!).current, 'low');
      expect(rig.bridge.sets, [
        const BridgeLaneSettingChange.config(
          id: 'effort',
          value: 'low',
          forModel: 'grok-4.6',
        ),
      ]);
    });

    test('a press of the value shown, or of one the row does not offer, '
        'sends nothing', () async {
      final rig = await settingsRig();
      final effort = _effortRow(rig.controller.state.settings!);
      await rig.controller.setSetting(
        effort,
        'high',
        displayedModel: 'grok-4.6',
      );
      await rig.controller.setSetting(
        effort,
        'max',
        displayedModel: 'grok-4.6',
      );
      expect(rig.bridge.sets, isEmpty);
      expect(rig.controller.state.settingMarks, isEmpty);
    });

    test('CONTROL (A13): an option goes out bound to the model the sheet '
        'DISPLAYED, not the one the lane holds', () async {
      // The lane's state says grok-4.6; the sheet drew composer-2.5 (a frame
      // behind, or ahead) — the press names what was SHOWN.
      final rig = await settingsRig();
      await rig.controller.setSetting(
        _effortRow(rig.controller.state.settings!),
        'low',
        displayedModel: 'composer-2.5',
      );
      expect(rig.bridge.sets, [
        const BridgeLaneSettingChange.config(
          id: 'effort',
          value: 'low',
          forModel: 'composer-2.5',
        ),
      ]);
    });

    test('CONTROL: a refusal is shown INLINE on its row, and the retry is a '
        'new press', () async {
      final rig = await settingsRig();
      final effort = _effortRow(rig.controller.state.settings!);
      rig.bridge.setFailure = const BridgeLaneError.notAccepting();

      await rig.controller.setSetting(
        effort,
        'low',
        displayedModel: 'grok-4.6',
      );
      expect(
        rig.controller.state.settingMarks,
        {effort.key: const RowRefused(staleModelText)},
        reason: 'craze\'s stale_model, on the option\'s own row',
      );
      expect(rig.controller.state.composerError, isNull);
      expect(rig.controller.state.error, isNull);

      // A refusal stays through later reads, until the row is pressed again.
      read(
        rig,
        _snap(
          capabilities: _settingsCaps,
          settings: _settings(),
          settingsFrames: 5,
        ),
      );
      expect(
        shownMark(
          rig.controller.state.settingMarks[effort.key],
          rig.controller.state.settingsSeen,
        ),
        const RowRefused(staleModelText),
      );

      rig.bridge.setFailure = null;
      await rig.controller.setSetting(
        effort,
        'low',
        displayedModel: 'grok-4.6',
      );
      expect(rig.bridge.sets, hasLength(2), reason: 'the retry was sent');
      expect(rig.controller.state.settingMarks, isEmpty);
    });

    test('a model refused not_accepting says the agent\'s words, not the '
        'stale-model ones', () async {
      final rig = await settingsRig();
      final model = sheetRows(
        rig.controller.state.settings!,
      ).firstWhere((r) => r.kind == SettingKind.model);
      rig.bridge.setFailure = const BridgeLaneError.notAccepting();
      await rig.controller.setSetting(
        model,
        'composer-2.5',
        displayedModel: 'grok-4.6',
      );
      expect(
        rig.controller.state.settingMarks[model.key],
        const RowRefused('the session is not accepting that right now'),
      );
    });

    test('CONTROL: a lost answer is "not confirmed" — never shown as applied '
        '— until the next LIVE Settings, and is never resent', () async {
      final rig = await settingsRig(frames: 3);
      final effort = _effortRow(rig.controller.state.settings!);
      expect(rig.controller.state.settingsSeen, 3);
      rig.bridge.setFailure = const BridgeLaneError.outcomeUnknown(
        msg: 'outcome unknown: the connection dropped',
      );

      await rig.controller.setSetting(
        effort,
        'low',
        displayedModel: 'grok-4.6',
      );
      RowMark? shown() => shownMark(
        rig.controller.state.settingMarks[effort.key],
        rig.controller.state.settingsSeen,
      );
      expect(shown(), const RowNotConfirmed(3));
      expect(markText(shown()), notConfirmedText);
      expect(_effortRow(rig.controller.state.settings!).current, 'high');

      // A read with no new Settings: still not confirmed.
      read(
        rig,
        _snap(
          capabilities: _settingsCaps,
          settings: _settings(),
          settingsFrames: 3,
          stale: 'reconnecting',
        ),
      );
      expect(shown(), const RowNotConfirmed(3));

      // A reseed's Settings, folded while the view is still STALE (its
      // `Ready` not yet in): the count is not taken, the mark stays.
      read(
        rig,
        _snap(
          capabilities: _settingsCaps,
          settings: _settings(),
          settingsFrames: 4,
          stale: 'reconnecting',
        ),
      );
      expect(rig.controller.state.settingsSeen, 3);
      expect(shown(), const RowNotConfirmed(3));

      // The live read that shows it: the real value replaces the mark.
      read(
        rig,
        _snap(
          capabilities: _settingsCaps,
          settings: _settings(effort: 'low'),
          settingsFrames: 4,
        ),
      );
      expect(rig.controller.state.settingsSeen, 4);
      expect(shown(), isNull);
      expect(_effortRow(rig.controller.state.settings!).current, 'low');
      expect(rig.bridge.sets, hasLength(1), reason: 'never resent');
    });

    test(
      'a lost answer whose value the row already shows is no mark',
      () async {
        final rig = await settingsRig();
        final effort = _effortRow(rig.controller.state.settings!);
        rig.bridge.holdSet = Completer<void>();
        rig.bridge.setFailure = const BridgeLaneError.outcomeUnknown(
          msg: 'outcome unknown: the connection dropped',
        );
        final pressed = rig.controller.setSetting(
          effort,
          'low',
          displayedModel: 'grok-4.6',
        );
        await pumpEventQueue();
        // The session's own Settings said it took before the loss was known.
        read(
          rig,
          _snap(
            capabilities: _settingsCaps,
            settings: _settings(effort: 'low'),
            settingsFrames: 2,
          ),
        );
        rig.bridge.holdSet!.complete();
        await pressed;
        expect(rig.controller.state.settingMarks, isEmpty);
      },
    );

    test('nothing is sent where the capabilities say no settings', () async {
      final rig = _Rig(kind: crazeLaneKind, serverUrl: '');
      rig.bridge.onSnapshot = (_) => _snap(
        capabilities: _caps(kind: 'craze'),
        settings: _settings(),
      );
      await rig.controller.open();
      await rig.controller.setSetting(
        _effortRow(_settings()),
        'low',
        displayedModel: 'grok-4.6',
      );
      expect(rig.bridge.sets, isEmpty);
      expect(rig.controller.state.settingMarks, isEmpty);
    });

    test('the settings clock carries across a re-open: each handle counts '
        'from zero', () async {
      final rig = await settingsRig(frames: 3);
      expect(rig.controller.state.settingsSeen, 3);
      read(
        rig,
        _snap(
          capabilities: _settingsCaps,
          settings: _settings(),
          settingsFrames: 3,
          stale: 'unreachable',
          ended: true,
        ),
      );
      await pumpEventQueue();
      // The re-opened handle's own seed: its first Settings.
      rig.bridge.onSnapshot = (_) => _snap(
        capabilities: _settingsCaps,
        settings: _settings(),
        settingsFrames: 1,
      );
      rig.releaseDelay();
      await pumpEventQueue();
      expect(rig.bridge.handles, hasLength(2), reason: 're-opened');
      expect(
        rig.controller.state.settingsSeen,
        4,
        reason: 'the new handle\'s seed Settings, on top of the old three',
      );
    });

    test('a new stamp clears the marks, and a change still in flight on the '
        'old session settles nothing', () async {
      final rig = await settingsRig();
      final effort = _effortRow(rig.controller.state.settings!);
      rig.bridge.holdSet = Completer<void>();
      rig.bridge.setFailure = const BridgeLaneError.notAccepting();
      final pressed = rig.controller.setSetting(
        effort,
        'low',
        displayedModel: 'grok-4.6',
      );
      await pumpEventQueue();
      expect(rig.controller.state.settingMarks, isNotEmpty);

      rig.stamps.add(
        const BridgeAgentLaneStamp(
          kind: crazeLaneKind,
          sessionId: 'sess-2',
          serverUrl: '',
        ),
      );
      await pumpEventQueue();
      expect(rig.controller.state.settingMarks, isEmpty);

      rig.bridge.holdSet!.complete();
      await pressed;
      expect(
        rig.controller.state.settingMarks,
        isEmpty,
        reason: 'the old session\'s refusal is not the new one\'s',
      );
    });
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
  _Rig({
    String kind = 'opencode',
    this.reach = LaneReach.machine,
    String serverUrl = 'http://127.0.0.1:2421',
  }) {
    bridge = _FakeLaneBridge(log);
    stamps = StreamController<BridgeAgentLaneStamp?>();
    controller = LaneController(
      machine: 'mini3',
      slug: '7',
      stamp: BridgeAgentLaneStamp(
        kind: kind,
        sessionId: 'sess-1',
        serverUrl: serverUrl,
      ),
      source: bridge,
      reach: reach,
      acquireForward: _acquire,
      openCrazeLane: openCrazeLane,
      crazeSourceEpoch: () => liveEpoch,
      crazeSources: crazeSources.stream,
      stamps: stamps.stream,
      schedulePull: _frames.add,
      delay: _delay,
    );
    addTearDown(() async {
      await stamps.close();
      await controller.close();
      await crazeSources.close();
    });
  }

  final LaneReach reach;

  /// The machine feed's craze source as a craze lane sees it: the epoch it
  /// opens through now (null while there is none), and the transitions.
  int? liveEpoch = 1;
  final StreamController<int?> crazeSources =
      StreamController<int?>.broadcast();

  /// Retire the source, or bring a new one live — the feed's two transitions.
  Future<void> crazeSource(int? epoch) async {
    liveEpoch = epoch;
    crazeSources.add(epoch);
    await pumpEventQueue();
  }

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

  /// What the controller is handed as the machine feed's craze opener — the
  /// identity a craze open must pass through to the bridge. The fake bridge
  /// never calls it (a `BridgeLane` needs the native library).
  Future<BridgeLane> openCrazeLane(String hostId) =>
      throw StateError('the fake bridge never opens a real lane');

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
  Object? stopFailure;
  int stops = 0;

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

  /// Every craze open: the hostId, and the opener it was handed.
  final List<String> crazeOpened = [];
  final List<CrazeLaneOpen> crazeOpeners = [];

  @override
  Future<LaneHandle> openCraze(CrazeLaneOpen open, String hostId) async {
    log.add('openCraze:$hostId');
    crazeOpened.add(hostId);
    crazeOpeners.add(open);
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
  Future<void> stop(LaneHandle handle) async {
    stops++;
    final failure = stopFailure;
    if (failure != null) throw failure;
  }

  /// Every settings change sent, in order.
  final List<BridgeLaneSettingChange> sets = [];
  Object? setFailure;

  /// Parks `set` after the change is recorded — a change PENDING, for as long
  /// as a cell needs one.
  Completer<void>? holdSet;

  @override
  Future<void> set(LaneHandle handle, BridgeLaneSettingChange change) async {
    sets.add(change);
    final gate = holdSet;
    if (gate != null) await gate.future;
    final failure = setFailure;
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
  late final _StubbornNudges nudges = _StubbornNudges(this);
  bool closed = false;

  /// While set, cancelling this handle's nudge stream — the await inside the
  /// controller's handle drop — parks on it, so a cell can land a source
  /// event while a drop is still in flight.
  Completer<void>? holdCancel;
}

/// A nudge stream whose `cancel` is a NO-OP.
///
/// The only way to test the generation fence rather than the subscription
/// cancel that usually gets there first: with a real stream a superseded
/// handle's nudge is never delivered at all, so a controller that had NO fence
/// would pass. This one delivers it anyway.
class _StubbornNudges extends Stream<bool> {
  _StubbornNudges(this._handle);

  final _FakeHandle _handle;
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
    return _DeafSubscription(_handle);
  }
}

class _DeafSubscription implements StreamSubscription<bool> {
  _DeafSubscription(this._handle);

  final _FakeHandle _handle;

  @override
  Future<void> cancel() => _handle.holdCancel?.future ?? Future<void>.value();

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
  bool settings = false,
}) => BridgeLaneCapabilities(
  kind: kind,
  interject: interject,
  cancel: true,
  approvals: true,
  historyCursor: false,
  settings: settings,
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
  BridgeLaneSettings? settings,
  int settingsFrames = 0,
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
  settings: settings,
  settingsFrames: BigInt.from(settingsFrames),
  approvals: approvals,
);

/// A craze session that offers settings.
final _settingsCaps = _caps(kind: 'craze', settings: true, stop: true);

/// A session on [model] with an effort option at [effort] — the shape craze's
/// permodel cursor hands over, cut down to what a press needs.
BridgeLaneSettings _settings({
  String model = 'grok-4.6',
  String effort = 'high',
}) => BridgeLaneSettings(
  model: model,
  models: const [
    BridgeLaneChoice(id: 'grok-4.6', name: 'Grok 4.6'),
    BridgeLaneChoice(id: 'composer-2.5', name: 'Composer 2.5'),
  ],
  modes: const [],
  options: [
    BridgeLaneSetting(
      id: 'effort',
      name: 'Effort',
      category: 'thought_level',
      current: effort,
      values: const [
        BridgeLaneChoice(id: 'low', name: 'Low'),
        BridgeLaneChoice(id: 'high', name: 'High'),
      ],
    ),
  ],
);

/// The effort row of [s], as the sheet draws it.
SettingsRow _effortRow(BridgeLaneSettings s) =>
    sheetRows(s).firstWhere((r) => r.id == 'effort');

BridgeRcFeedMessage _row(int seq, String text) => BridgeRcFeedMessage(
  seq: BigInt.from(seq),
  role: 'assistant',
  msgType: 'text',
  text: text,
);
