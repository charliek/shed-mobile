import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/machines/machine_feed.dart';
import 'package:shed_mobile/machines/machine_record.dart';
import 'package:shed_mobile/src/rust/api/craze.dart';
import 'package:shed_mobile/src/rust/api/dto_lane.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';

/// **A machine's merged rows, applied** (plan 025 §3.7.2).
///
/// The RULE — which roost tab is a craze session — is shed's own
/// (`shed_app::craze_rows::fold_plan`) and is never re-derived here: the
/// integration harness runs it over the bridge (`integration_test/
/// craze_test.dart`'s fold cells). What this file pins is the application of a
/// plan to a machine's rows, with a recording planner standing in for the
/// bridge: which tabs are handed to it and how, that a feed which is not live
/// hands it no hub at all, and that every tab it folds leaves the roost rows.
const _mini3 = MachineRecord(name: 'mini3', host: 'mini3.example');

const _host = 'cccccccccccc';

BridgeRcSession _tab(
  int tabId, {
  BridgeRcKind kind = const BridgeRcKind.opencode(),
  String? rcId,
}) => BridgeRcSession(
  host: '',
  shed: '',
  slug: '$tabId',
  displayName: 'tab$tabId',
  kind: kind,
  state: BridgeRcState.ready,
  managed: true,
  attention: false,
  tabId: tabId,
  rcId: rcId,
);

BridgeLaneSession _hubRow(String id, {String? providerSessionId}) =>
    BridgeLaneSession(
      id: id,
      title: 'craze $id',
      cwd: '/w/$id',
      activity: BridgeRcActivity.working,
      pendingApprovals: 0,
      approximate: false,
      provider: 'grok',
      providerSessionId: providerSessionId,
    );

BridgeCrazeSnapshot _craze(List<BridgeLaneSession> rows, {bool live = true}) =>
    BridgeCrazeSnapshot(rows: rows, live: live, truncated: false);

/// A planner that records what it was asked and answers [answer].
class _Planner {
  _Planner([this.answer = const []]);

  final List<BridgeFoldedTab> answer;
  final List<({List<BridgeRoostTabRef> roost, List<BridgeLaneSession>? hub})>
  calls = [];

  BridgeFoldPlan call(
    List<BridgeRoostTabRef> roost,
    List<BridgeLaneSession>? hub,
  ) {
    calls.add((roost: roost, hub: hub));
    return BridgeFoldPlan(folded: answer);
  }
}

void main() {
  group('roostTabRefs', () {
    test('names an owner ONLY for a tab roost reports as craze\'s', () {
      final refs = roostTabRefs([
        _tab(4, kind: const BridgeRcKind.craze(), rcId: 'ses-a'),
        // An opencode tab whose session id equals a craze session's provider
        // id: never craze's, so never absorbed.
        _tab(5, rcId: 'ses-a'),
        // A craze tab with no ownership id is still craze's.
        _tab(6, kind: const BridgeRcKind.craze()),
      ]);
      expect(refs, const [
        BridgeRoostTabRef(tabId: 4, crazeOwner: 'ses-a'),
        BridgeRoostTabRef(tabId: 5),
        BridgeRoostTabRef(tabId: 6, crazeOwner: ''),
      ]);
    });

    test('a row with no tab id is no roost tab at all', () {
      final hubRow = BridgeRcSession(
        host: 'h',
        shed: 's',
        slug: 'x',
        displayName: 'x',
        kind: const BridgeRcKind.craze(),
        state: BridgeRcState.ready,
        managed: true,
        attention: false,
      );
      expect(roostTabRefs([hubRow]), isEmpty);
    });
  });

  group('machineRows', () {
    test('a LIVE feed hands the plan its hub rows, and a folded tab leaves the '
        'roost rows for the hub row it names', () {
      final planner = _Planner(const [
        BridgeFoldedTab(tabId: 4, hostId: _host),
        BridgeFoldedTab(tabId: 6),
      ]);
      final rows = machineRows(
        sessions: [
          _tab(4, kind: const BridgeRcKind.craze(), rcId: 'ses-a'),
          _tab(5),
          _tab(6, kind: const BridgeRcKind.craze(), rcId: 'ses-gone'),
        ],
        craze: _craze([_hubRow(_host, providerSessionId: 'ses-a')]),
        plan: planner.call,
      );

      expect(planner.calls.single.hub?.single.id, _host);
      expect(planner.calls.single.roost.map((r) => r.tabId), [4, 5, 6]);
      // Roost's rows first, then craze's — and only the tab the plan did not
      // fold is still a roost row.
      expect(rows.map((r) => r.key), ['5', _host]);
      final craze = rows.last as CrazeMachineRow;
      expect(craze.tabId, 4, reason: 'the absorbed tab is the row\'s tab');
      expect(craze.stale, isFalse);
    });

    test('a feed that is NOT live hands the plan no hub, and its rows are '
        'stale', () {
      final planner = _Planner();
      final rows = machineRows(
        sessions: [_tab(4, kind: const BridgeRcKind.craze(), rcId: 'ses-a')],
        craze: _craze([
          _hubRow(_host, providerSessionId: 'ses-a'),
        ], live: false),
        plan: planner.call,
      );

      expect(
        planner.calls.single.hub,
        isNull,
        reason: 'a feed that is down absorbs nothing (D4)',
      );
      expect(rows.map((r) => r.key), ['4', _host]);
      final craze = rows.last as CrazeMachineRow;
      expect(craze.stale, isTrue, reason: 'retained rows render stale');
      expect(craze.tabId, isNull);
    });

    test('no craze source at all: roost\'s rows, untouched', () {
      final planner = _Planner();
      final rows = machineRows(
        sessions: [_tab(4), _tab(5)],
        craze: null,
        plan: planner.call,
      );
      expect(planner.calls.single.hub, isNull);
      expect(rows.map((r) => r.key), ['4', '5']);
      expect(rows.every((r) => r is RoostMachineRow), isTrue);
    });
  });

  group('MachineFeedState.rows', () {
    test('a hand-built state folds nothing; a folded one says what the fold '
        'said', () {
      final state = MachineFeedState(
        machine: _mini3,
        sessions: [_tab(4, kind: const BridgeRcKind.craze(), rcId: 'ses-a')],
        craze: _craze([_hubRow(_host, providerSessionId: 'ses-a')]),
      );
      expect(state.rows.map((r) => r.key), ['4', _host]);

      final folded = state.copyWith(
        rows: [
          MachineRow.craze(
            session: _hubRow(_host, providerSessionId: 'ses-a'),
            tabId: 4,
            stale: false,
          ),
        ],
      );
      expect(folded.rows.map((r) => r.key), [_host]);
      // A change that cannot move the rows keeps them …
      expect(folded.copyWith(reachable: true).rows.map((r) => r.key), [_host]);
      // … and a new roost list voids them until the feed folds again.
      expect(folded.copyWith(sessions: [_tab(9)]).rows.map((r) => r.key), [
        '9',
        _host,
      ]);
    });
  });

  group('crazeNoteFor', () {
    MachineFeedState offline(BridgeSourceOffline cause) => MachineFeedState(
      machine: _mini3,
      craze: BridgeCrazeSnapshot(
        rows: const [],
        live: false,
        offline: BridgeCrazeOffline(cause: cause, reason: 'whatever it said'),
        truncated: false,
      ),
    );

    test('too old asks for an update; every other state is quiet', () {
      expect(
        crazeNoteFor(offline(const BridgeSourceOffline.tooOld())),
        'craze on this machine is too old for shed; update it',
      );
      expect(
        crazeNoteFor(offline(const BridgeSourceOffline.notInstalled())),
        isNull,
        reason: 'not installed is quiet: the machine simply has no craze',
      );
      expect(
        crazeNoteFor(offline(const BridgeSourceOffline.unreachable())),
        isNull,
      );
      expect(crazeNoteFor(MachineFeedState(machine: _mini3)), isNull);
    });

    test('a live hub that cannot create asks for an update; one that can is '
        'quiet', () {
      MachineFeedState live({required bool create, required bool options}) =>
          MachineFeedState(
            machine: _mini3,
            craze: BridgeCrazeSnapshot(
              rows: const [],
              live: true,
              caps: BridgeSourceCapabilities(
                kind: 'craze',
                create: create,
                createOptions: options,
              ),
              truncated: false,
            ),
          );
      const update = 'update craze on this machine to create sessions here';
      expect(crazeNoteFor(live(create: true, options: false)), update);
      expect(crazeNoteFor(live(create: false, options: true)), update);
      expect(crazeNoteFor(live(create: true, options: true)), isNull);
      expect(
        crazeCreateOffered(live(create: true, options: true).craze),
        isTrue,
      );
      expect(
        crazeCreateOffered(live(create: true, options: false).craze),
        isFalse,
      );
    });
  });

  group('staleCraze', () {
    test('keeps the rows and the cause, and is no longer live', () {
      final live = _craze([_hubRow(_host)]);
      final stale = staleCraze(live)!;
      expect(stale.live, isFalse);
      expect(stale.rows.single.id, _host);
      expect(staleCraze(null), isNull);
      expect(staleCraze(stale), same(stale));
    });
  });
}
