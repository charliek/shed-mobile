import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/lanes/lane_controller.dart';
import 'package:shed_mobile/lanes/lane_source.dart';
import 'package:shed_mobile/machines/machine_feed.dart';
import 'package:shed_mobile/machines/machine_record.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/src/rust/api/craze.dart';
import 'package:shed_mobile/src/rust/api/dto_lane.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';
import 'package:shed_mobile/src/rust/api/lane.dart';

/// **The Riverpod half of §3.11** — the "one lane per row" guarantee, and the
/// feed→stamp derivation the controller reconciles against.
///
/// Every lane is a craze row's (plan 038 retired the opencode lane): a roost
/// tab — an opencode one included — never resolves a lane, and the cells
/// below that say so are the provider half of the passive-opencode rule.
///
/// The guarantee lives at the PROVIDER level and nowhere else, which is why the
/// test does too: the bridge has no registry (two `lane_open` calls are two
/// lanes, two subscriptions and two adapters against one agent), so
/// `autoDispose.family` is the whole mechanism that stops two screens on one
/// row from opening two lanes.
///
/// No native library is loaded: `laneSourceProvider` and
/// `machineFeedControllerProvider` are overridden, and `MachineFeed` itself is
/// faked (its real constructor calls the FRB-sync `roostCapabilities()`).
void main() {
  group('laneControllerProvider', () {
    test('two watchers on one row share ONE controller', () async {
      final feed = _FakeFeed();
      final container = _container(feed);
      addTearDown(container.dispose);

      final first = container.listen(
        laneControllerProvider(_seven),
        (_, _) {},
        fireImmediately: true,
      );
      final second = container.listen(
        laneControllerProvider(_seven),
        (_, _) {},
        fireImmediately: true,
      );

      expect(first.read(), same(second.read()));
      // The control: a DIFFERENT row is a different lane. Without it the
      // assertion above would also pass for a provider that returned one
      // controller for the whole app.
      final other = container.read(laneControllerProvider(_eight));
      expect(other, isNot(same(first.read())));
      expect(other.slug, _hostEight);
    });

    test('the last watcher leaving closes the controller', () async {
      final feed = _FakeFeed();
      final container = _container(feed);
      addTearDown(container.dispose);

      final first = container.listen(
        laneControllerProvider(_seven),
        (_, _) {},
        fireImmediately: true,
      );
      final second = container.listen(
        laneControllerProvider(_seven),
        (_, _) {},
        fireImmediately: true,
      );
      final controller = first.read();

      first.close();
      await pumpEventQueue();
      // One watcher left: still alive, and still the same instance.
      expect(container.read(laneControllerProvider(_seven)), same(controller));

      second.close();
      await pumpEventQueue();

      // `onDispose → close()`: the state stream is ended, which is what tells a
      // screen its lane is gone rather than merely idle.
      await expectLater(controller.updates, emitsDone);
    });

    test('a row with no lane is an honest error, not a silent no-op — a '
        'roost opencode tab among them', () {
      final feed = _FakeFeed();
      final container = _container(feed);
      addTearDown(container.dispose);

      for (final ref in [_opencodeTab, _stampedOpencodeTab]) {
        expect(
          () => container.read(laneControllerProvider(ref)),
          // Riverpod wraps a build failure, so the assertion is on the
          // sentence rather than the type.
          throwsA(
            isA<Object>().having(
              (e) => '$e',
              'message',
              contains('no agent lane on mini3/${ref.slug}'),
            ),
          ),
          reason: ref.slug,
        );
      }
    });

    test('the missing-lane refusal is recognised through Riverpod\'s '
        'ProviderException wrapper, and said by its cause', () {
      final feed = _FakeFeed();
      final container = _container(feed);
      addTearDown(container.dispose);

      Object? thrown;
      try {
        container.read(laneControllerProvider(_opencodeTab));
      } catch (e) {
        thrown = e;
      }
      expect(
        thrown,
        isNot(isA<StateError>()),
        reason: 'wrapped — why a bare `on StateError` caught nothing',
      );
      expect(laneMissing(thrown!), isTrue);
      expect(laneFailureText(thrown), 'no agent lane on mini3/9 (opencode)');

      // The controls: another failure is not a missing lane, and says itself.
      expect(laneMissing(Exception('boom')), isFalse);
      expect(laneMissing(ArgumentError('x')), isFalse);
      expect(laneFailureText(Exception('boom')), 'Exception: boom');
    });
  });

  group('laneStateProvider', () {
    test('opens the lane through the craze source and streams its '
        'state', () async {
      final feed = _FakeFeed();
      final source = _FakeSource();
      final container = _container(feed, source: source);
      addTearDown(container.dispose);

      final sub = container.listen(
        laneStateProvider(_seven),
        (_, _) {},
        fireImmediately: true,
      );
      await pumpEventQueue();

      // End to end through the real wiring: the lane opened on the row's
      // hostId, through the feed's own craze opener.
      expect(source.crazeOpened, [_hostSeven]);
      // A tear-off of the same method on the same feed: equal, not identical.
      expect(source.openers.single, equals(feed.openCrazeLane));
      expect(sub.read().value?.capabilities?.kind, 'craze');
      expect(sub.read().value?.rows.single.text, 'hello');
    });
  });

  group('laneStampFor', () {
    test('finds a craze row\'s stamp by hostId, and answers null for a roost '
        'tab — stamped or not — and for no such row', () {
      final state = _state();
      expect(laneStampFor(state, crazeLaneKind, _hostSeven), _stampSeven);
      expect(laneStampFor(state, crazeLaneKind, _hostSeven)?.kind, 'craze');
      expect(
        laneStampFor(state, 'opencode', '9'),
        isNull,
        reason: 'a passive opencode tab has no lane',
      );
      expect(
        laneStampFor(state, 'opencode', '10'),
        isNull,
        reason: 'a roost tab\'s own stamp is never read (plan 038)',
      );
      expect(
        laneStampFor(state, crazeLaneKind, '9'),
        isNull,
        reason: 'a tab id is not a craze row\'s key',
      );
      expect(
        laneStampFor(state, crazeLaneKind, 'nope'),
        isNull,
        reason: 'no such row',
      );
    });
  });

  group('laneStamps', () {
    test('ignores a feed that has never connected', () async {
      // THE TRAP. A cold feed carries no rows at all, and mapping that to "the
      // row is gone" would abandon every lane in the first second of a start.
      final cold = MachineFeedState(machine: _mini3);
      final stamps = laneStamps(
        Stream<MachineFeedState>.fromIterable([cold, _state()]),
        crazeLaneKind,
        _hostSeven,
      );

      expect(
        await stamps.toList(),
        [_stampSeven],
        reason: 'only the authoritative state produced a stamp',
      );
    });

    test('emits null once the row is really gone, and dedupes repeats', () async {
      final present = _state();
      final gone = _state(hub: const []);
      final stamps = laneStamps(
        Stream<MachineFeedState>.fromIterable([
          present,
          present,
          gone,
          gone,
          present,
        ]),
        crazeLaneKind,
        _hostSeven,
      );

      final seen = await stamps.toList();
      // Three transitions, not five events: the feed re-emits its rows on every
      // poll, and a lane that reconciled on each would churn.
      expect(seen, hasLength(3));
      expect(seen[0], isNotNull);
      expect(seen[1], isNull);
      expect(seen[2], isNotNull);
    });
  });

  group('a craze row (plan 025 §3.7.2)', () {
    test('laneStampFor answers a craze row its own stamp, by hostId — and an '
        'absorbed tab\'s old key nothing', () {
      final state = _crazeState(live: true);
      expect(laneStampFor(state, crazeLaneKind, _host), crazeLaneStamp(_host));
      expect(laneStampFor(state, crazeLaneKind, _host)?.kind, crazeLaneKind);
      expect(
        laneStampFor(state, 'craze', '7'),
        isNull,
        reason: 'tab 7 is the craze row now, not a row of its own',
      );
      expect(
        laneStampFor(state, 'opencode', '8'),
        isNull,
        reason: 'the opencode tab beside it is passive',
      );
    });

    test('a craze hostId spelled like a roost tab id opens ITS OWN lane, and '
        'the tab none', () async {
      // A hostId is twelve hex digits and may well be all decimal — the very
      // spelling of a roost tab id. The kind in the lane's key keeps them
      // apart: the craze row resolves its own stamp and opens its own lane,
      // and the opencode tab spelled alike — even one carrying a stamp of its
      // own — resolves none.
      const id = '123456789012';
      final tab = _row(id, 'sess-oc', tabId: 123456789012);
      const hub = BridgeLaneSession(
        id: id,
        title: 'craze',
        cwd: '/w',
        activity: BridgeRcActivity.idle,
        pendingApprovals: 0,
        approximate: false,
      );
      final state = MachineFeedState(
        machine: _mini3,
        connectedOnce: true,
        reachable: true,
        sessions: [tab],
        craze: const BridgeCrazeSnapshot(
          rows: [hub],
          live: true,
          truncated: false,
        ),
        foldedRows: [
          MachineRow.roost(tab),
          const MachineRow.craze(session: hub, stale: false),
        ],
      );
      expect(laneStampFor(state, 'opencode', id), isNull);
      expect(laneStampFor(state, crazeLaneKind, id), crazeLaneStamp(id));

      final feed = _FakeFeed(stateOverride: state);
      final source = _FakeSource();
      final container = _container(feed, source: source);
      addTearDown(container.dispose);
      const ocRef = (machine: 'mini3', kind: 'opencode', slug: id);
      const crazeRef = (machine: 'mini3', kind: crazeLaneKind, slug: id);
      container.listen(laneStateProvider(crazeRef), (_, _) {});
      await pumpEventQueue();

      expect(
        () => container.read(laneControllerProvider(ocRef)),
        throwsA(
          isA<Object>().having((e) => laneMissing(e), 'laneMissing', isTrue),
        ),
        reason: 'the roost row has no lane',
      );
      expect(
        source.crazeOpened,
        [id],
        reason: 'and the craze row its craze lane, through the source',
      );
    });

    test('a craze lane reconciles only against a LIVE craze feed', () async {
      // A source that has not seeded yet (a restarted tunnel's) lists nothing,
      // and an offline one keeps its rows: neither is evidence the session
      // left. Only a live roster without the row is.
      final stamps = laneStamps(
        Stream<MachineFeedState>.fromIterable([
          _crazeState(live: false, rows: false),
          _crazeState(live: true),
          _crazeState(live: false),
          _crazeState(live: false, rows: false),
          _crazeState(live: true, rows: false),
        ]),
        crazeLaneKind,
        _host,
      );
      expect(await stamps.toList(), [crazeLaneStamp(_host), null]);
    });
  });
}

const _hostSeven = 'aaaaaaaaaaa7';
const _hostEight = 'aaaaaaaaaaa8';
final _stampSeven = crazeLaneStamp(_hostSeven);
const _seven = (machine: 'mini3', kind: crazeLaneKind, slug: _hostSeven);
const _eight = (machine: 'mini3', kind: crazeLaneKind, slug: _hostEight);

/// A roost opencode tab with no stamp — what every roost row is since plan
/// 038 — and one still carrying one (as a Rust core from before it would have
/// stamped): neither has a lane.
const _opencodeTab = (machine: 'mini3', kind: 'opencode', slug: '9');
const _stampedOpencodeTab = (machine: 'mini3', kind: 'opencode', slug: '10');
const _mini3 = MachineRecord(name: 'mini3', host: 'mini3');

ProviderContainer _container(_FakeFeed feed, {_FakeSource? source}) =>
    ProviderContainer(
      overrides: [
        machinesProvider.overrideWith((ref) async => const [_mini3]),
        identitiesProvider.overrideWith((ref) async => []),
        machineFeedControllerProvider('mini3').overrideWith((ref) => feed),
        machineFeedProvider(
          'mini3',
        ).overrideWith((ref) => Stream.value(feed.state)),
        if (source != null) laneSourceProvider.overrideWithValue(source),
      ],
    );

BridgeLaneSession _hubRow(String id) => BridgeLaneSession(
  id: id,
  title: 'craze $id',
  cwd: '/w',
  activity: BridgeRcActivity.idle,
  pendingApprovals: 0,
  approximate: false,
);

/// A machine with two craze sessions on a live craze feed, beside two roost
/// opencode tabs — one bare (`9`), one carrying a stamp (`10`) — that the
/// provider must never open a lane for. [hub] overrides the craze roster.
MachineFeedState _state({List<BridgeLaneSession>? hub}) {
  final rows = hub ?? [_hubRow(_hostSeven), _hubRow(_hostEight)];
  final tabs = [_row('9', null), _row('10', 'sess-10')];
  return MachineFeedState(
    machine: _mini3,
    connectedOnce: true,
    reachable: true,
    sessions: tabs,
    craze: BridgeCrazeSnapshot(rows: rows, live: true, truncated: false),
    foldedRows: [
      for (final t in tabs) MachineRow.roost(t),
      for (final r in rows) MachineRow.craze(session: r, stale: false),
    ],
  );
}

const _host = 'cccccccccccc';

/// A machine running one craze session inside roost tab 7 (owned `(craze,
/// ses-x)`) beside an opencode tab 8 — as the feed folds it: with the craze
/// feed live, tab 7 is absorbed into the hub row. [rows] false is a source
/// whose roster does not list the session (yet, or any more).
MachineFeedState _crazeState({required bool live, bool rows = true}) {
  const hub = BridgeLaneSession(
    id: _host,
    title: 'craze work',
    cwd: '/w',
    activity: BridgeRcActivity.idle,
    pendingApprovals: 0,
    approximate: false,
    providerSessionId: 'ses-x',
  );
  final tab7 = BridgeRcSession(
    host: '',
    shed: '',
    slug: '7',
    displayName: 'tui',
    kind: const BridgeRcKind.craze(),
    state: BridgeRcState.ready,
    managed: true,
    attention: false,
    tabId: 7,
    rcId: 'ses-x',
  );
  final tab8 = _row('8', null);
  return MachineFeedState(
    machine: _mini3,
    connectedOnce: true,
    reachable: true,
    sessions: [tab7, tab8],
    craze: BridgeCrazeSnapshot(
      rows: rows ? const [hub] : const [],
      live: live,
      truncated: false,
    ),
    foldedRows: [
      MachineRow.roost(tab8),
      if (rows)
        MachineRow.craze(session: hub, tabId: live ? 7 : null, stale: !live),
      if (!live) MachineRow.roost(tab7),
    ],
  );
}

/// A roost opencode tab; [sessionId] non-null gives it the `agentLane` stamp
/// an opencode tab carried before plan 038.
BridgeRcSession _row(String slug, String? sessionId, {int? tabId}) =>
    BridgeRcSession(
      host: '',
      shed: '',
      slug: slug,
      displayName: 'row$slug',
      kind: const BridgeRcKind.opencode(),
      state: BridgeRcState.ready,
      managed: true,
      attention: false,
      tabId: tabId ?? int.tryParse(slug),
      agentLane: sessionId == null
          ? null
          : BridgeAgentLaneStamp(
              kind: 'opencode',
              sessionId: sessionId,
              serverUrl: 'http://127.0.0.1:2421',
            ),
    );

/// A [MachineFeed] the provider can be handed: the real one dials SSH and calls
/// the FRB-sync `roostCapabilities()` in its constructor, so it cannot exist in
/// a unit test at all. `noSuchMethod` guards every member this fake does not
/// know about.
class _FakeFeed implements MachineFeed {
  _FakeFeed({this.stateOverride});

  /// What [state] answers when a test needs more than the default rows.
  final MachineFeedState? stateOverride;

  @override
  final MachineRecord machine = _mini3;

  @override
  MachineFeedState get state => stateOverride ?? _state();

  @override
  Stream<MachineFeedState> get updates =>
      const Stream<MachineFeedState>.empty();

  /// The feed's craze opener — handed to the bridge, never called by the fake
  /// source (a `BridgeLane` needs the native library).
  @override
  Future<BridgeLane> openCrazeLane(String hostId) =>
      throw StateError('the fake source never opens a real lane');

  /// A seeded craze source, steady: what a craze lane follows.
  @override
  int? get crazeLiveEpoch => 1;

  @override
  Stream<int?> get crazeSources => const Stream<int?>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSource implements LaneSource {
  /// Every craze open, by hostId, and the opener it was handed.
  final List<String> crazeOpened = [];
  final List<CrazeLaneOpen> openers = [];

  @override
  Future<LaneHandle> openCraze(CrazeLaneOpen open, String hostId) async {
    crazeOpened.add(hostId);
    openers.add(open);
    return _FakeHandle();
  }

  @override
  Stream<bool> nudges(LaneHandle handle) => const Stream<bool>.empty();

  /// A seeded craze lane: its capabilities ride the snapshot (plan 025
  /// §3.2.1).
  @override
  BridgeLaneSnapshot snapshot(LaneHandle handle, BigInt? sinceSeq) =>
      BridgeLaneSnapshot(
        messages: [
          BridgeRcFeedMessage(
            seq: BigInt.one,
            role: 'assistant',
            msgType: 'text',
            text: 'hello',
          ),
        ],
        full: true,
        activity: BridgeRcActivity.idle,
        generation: BigInt.one,
        ended: false,
        capabilities: const BridgeLaneCapabilities(
          kind: 'craze',
          interject: false,
          cancel: true,
          approvals: true,
          historyCursor: false,
          settings: false,
          stop: false,
          slash: false,
          setTitle: false,
        ),
        settingsFrames: BigInt.zero,
        approvals: const [],
        slashMenu: null,
      );

  /// Nothing here renames a session.
  @override
  Future<String?> setTitle(LaneHandle handle, String title) =>
      throw StateError('the provider cells never rename');

  @override
  void close(LaneHandle handle) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHandle implements LaneHandle {}
