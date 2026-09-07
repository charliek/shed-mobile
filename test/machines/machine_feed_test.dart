import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/machines/machine_feed.dart';
import 'package:shed_mobile/machines/machine_record.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';
import 'package:shed_mobile/src/rust/api/roost.dart';

/// **The fold: what a roost update does to a machine's rows** (plan 013 S3m).
///
/// [MachineFeed] itself owns an SSH connection and a Rust watcher, neither of
/// which exists in a unit test — so the reconciliation is a set of pure
/// functions and this file tests those. They are the whole of the contract
/// between what roost reports and what the cards show, and every rule here is
/// one that fails silently in production if it is wrong: a merged snapshot
/// resurrects closed tabs, a `Down` that clears rows blanks a machine on every
/// network blip, and an optimistic row that does not land makes a working
/// button look broken.
const _mini3 = MachineRecord(name: 'mini3', host: 'mini3.example');

BridgeRcSession _row(String slug, {String? workdir}) => BridgeRcSession(
  // A machine's rows carry no shed and no host — they are keyed by the machine.
  host: '',
  shed: '',
  slug: slug,
  displayName: 'row$slug',
  workdir: workdir,
  kind: const BridgeRcKind.opencode(),
  state: BridgeRcState.ready,
  managed: true,
  attention: false,
  // The slug IS roost's tab id, rendered as a string.
  tabId: int.parse(slug),
);

MachineFeedState _state({
  List<BridgeRcSession> sessions = const [],
  bool reachable = false,
  String? detail,
  bool connectedOnce = false,
}) => MachineFeedState(
  machine: _mini3,
  sessions: sessions,
  reachable: reachable,
  detail: detail,
  connectedOnce: connectedOnce,
);

void main() {
  group('foldRoostUpdate', () {
    test('a snapshot REPLACES the row set rather than merging into it', () {
      // roost's `tab.list` is the machine's whole agent-owned tab list as of
      // that poll. Merging would leave a closed tab on screen forever — the
      // card would simply never go away, because nothing ever says "this one
      // is gone" on this wire.
      final before = _state(
        sessions: [_row('1'), _row('2')],
        reachable: true,
        connectedOnce: true,
      );

      final after = foldRoostUpdate(
        before,
        BridgeRoostUpdate.snapshot(sessions: [_row('2'), _row('3')]),
      );

      expect(after.sessions.map((s) => s.slug), [
        '2',
        '3',
      ], reason: 'a tab roost no longer lists must not survive the snapshot');
      expect(after.reachable, isTrue);
      expect(after.connectedOnce, isTrue);
      expect(after.detail, isNull, reason: 'a snapshot clears the last reason');
    });

    test('a snapshot clears the overlay it lands on', () {
      // The snapshot already carries every dimension a patch could hold, so a
      // surviving patch could only ever be stale truth beating fresh truth.
      final before = _state(
        sessions: [_row('1')],
        reachable: true,
      ).copyWith(overlay: {'1': const MachinePatch(state: BridgeRcState.dead)});

      final after = foldRoostUpdate(
        before,
        BridgeRoostUpdate.snapshot(sessions: [_row('1')]),
      );

      expect(after.overlay, isEmpty);
      expect(after.stateOf(after.sessions.single), BridgeRcState.ready);
    });

    test('an empty snapshot is a real answer, not a missing one', () {
      // "This machine is reachable and has nothing running" and "we have never
      // reached this machine" render differently, and only `connectedOnce`
      // tells them apart.
      final after = foldRoostUpdate(
        _state(sessions: [_row('1')], reachable: true, connectedOnce: true),
        const BridgeRoostUpdate.snapshot(sessions: []),
      );

      expect(after.sessions, isEmpty);
      expect(after.connectedOnce, isTrue);
      expect(after.reachable, isTrue);
    });

    test('a Down keeps the last rows and says why', () {
      // A phone changes networks constantly. Blanking the machine each time
      // throws away the best available answer to "what is running on mini3?".
      final before = _state(
        sessions: [_row('1'), _row('2')],
        reachable: true,
        connectedOnce: true,
      );

      final after = foldRoostUpdate(
        before,
        const BridgeRoostUpdate.down(reason: 'connection refused'),
      );

      expect(after.sessions.map((s) => s.slug), ['1', '2']);
      expect(after.reachable, isFalse);
      expect(after.detail, 'connection refused');
      expect(
        after.connectedOnce,
        isTrue,
        reason: 'having been reachable once is not undone by going away',
      );
    });

    test('a recorded dial failure outranks the watcher\'s own reason', () {
      // The watcher can only ever see "the local port refused"; the SSH dial
      // underneath knows the connection was refused BECAUSE this device's key
      // is not authorized. That is the one part the user can act on, and it is
      // the part the transport swap would otherwise have thrown away.
      final after = foldRoostUpdate(
        _state(sessions: [_row('1')], reachable: true, connectedOnce: true),
        const BridgeRoostUpdate.down(reason: 'connection refused'),
        dialDetail: 'this device\'s key is not authorized on the machine',
      );

      expect(
        after.detail,
        'this device\'s key is not authorized on the machine',
      );

      // The control: with no dial failure recorded, roost's own reason is what
      // shows — so the assertion above is about precedence, not about the
      // parameter simply always winning.
      final withoutDial = foldRoostUpdate(
        _state(sessions: [_row('1')], reachable: true, connectedOnce: true),
        const BridgeRoostUpdate.down(reason: 'connection refused'),
      );
      expect(withoutDial.detail, 'connection refused');
    });
  });

  group('foldOpenedRow', () {
    test('the row a tab.open returned appears immediately', () {
      // The watcher polls every two seconds. Without this the card only shows
      // up after the next poll, which reads as "did that button do anything?".
      final after = foldOpenedRow(
        _state(sessions: [_row('1')], reachable: true),
        _row('7', workdir: '/home/shed/app'),
      );

      expect(after.sessions.map((s) => s.slug), ['1', '7']);
      expect(after.sessions.last.workdir, '/home/shed/app');
    });

    test('re-opening a slug replaces that row instead of doubling it', () {
      final after = foldOpenedRow(
        _state(sessions: [_row('1'), _row('2')], reachable: true),
        _row('2', workdir: '/tmp'),
      );

      expect(after.sessions.map((s) => s.slug), ['1', '2']);
      expect(after.sessions.last.workdir, '/tmp');
    });
  });

  group('foldClosedRow', () {
    test('a closed tab leaves, and only that one', () {
      // `tab.close` removes the tab from `tab.list` entirely, so the next poll
      // agrees — this only spares the user a poll interval of watching a
      // session they just ended sit there looking alive.
      final after = foldClosedRow(
        _state(
          sessions: [_row('1'), _row('2'), _row('3')],
          reachable: true,
        ).copyWith(overlay: {'2': const MachinePatch(lastSeq: null)}),
        '2',
      );

      expect(
        after.sessions.map((s) => s.slug),
        ['1', '3'],
        reason:
            'the neighbours are the negative control — kill removes one row',
      );
      expect(after.overlay.containsKey('2'), isFalse);
    });

    test('closing an unknown slug changes nothing', () {
      final before = _state(sessions: [_row('1')], reachable: true);
      final after = foldClosedRow(before, '9');
      expect(after.sessions.map((s) => s.slug), ['1']);
    });
  });

  group('DialDedupe', () {
    // [MachineFeed._connect] cannot be exercised directly here: it dials a
    // real SSHClient, which needs a live socket to construct. This tests the
    // generation bookkeeping it delegates to instead — the exact bug a
    // stop/start cycle used to hit (a dial from the PREVIOUS generation
    // getting adopted by the new one, which the generation check then closes,
    // rejecting the new waiter) — with a dummy dialed type so no socket is
    // needed.
    test('reuses a pending dial from the same generation', () {
      final dedupe = DialDedupe<int>();
      final completer = Completer<int>();
      dedupe.start(0, completer.future);

      expect(identical(dedupe.pendingFor(0), completer.future), isTrue);
    });

    test('does not adopt a pending dial from a stale generation', () {
      final dedupe = DialDedupe<int>();
      final completer = Completer<int>();
      dedupe.start(0, completer.future);

      expect(
        dedupe.pendingFor(1),
        isNull,
        reason:
            'generation moved on (a stop happened); the stale dial must not '
            'be adopted — the caller starts a fresh one instead of getting '
            'rejected by a dial that generation 0 is about to close',
      );
    });

    test("a stale dial's finally does not clobber the fresh dial that "
        'superseded it', () {
      final dedupe = DialDedupe<int>();
      final first = Completer<int>();
      final second = Completer<int>();
      dedupe.start(0, first.future);
      // generation 1's _connect() saw pendingFor(1) == null (the case
      // above) and started its own dial.
      dedupe.start(1, second.future);

      // generation 0's dial finally fires late.
      dedupe.clear(first.future);

      expect(identical(dedupe.pendingFor(1), second.future), isTrue);
    });

    test('clear removes the pending dial it was given', () {
      final dedupe = DialDedupe<int>();
      final completer = Completer<int>();
      dedupe.start(0, completer.future);

      dedupe.clear(completer.future);

      expect(dedupe.pendingFor(0), isNull);
    });
  });
}
