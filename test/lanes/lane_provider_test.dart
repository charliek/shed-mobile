import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/lanes/lane_controller.dart';
import 'package:shed_mobile/lanes/lane_source.dart';
import 'package:shed_mobile/machines/machine_feed.dart';
import 'package:shed_mobile/machines/machine_record.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/src/rust/api/dto_lane.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';
import 'package:shed_mobile/src/rust/api/lane.dart';
import 'package:shed_mobile/ssh/lane_forward.dart';

import 'fake_lane_lease.dart';

/// **The Riverpod half of §3.11** — the "one lane per row" guarantee, and the
/// feed→stamp derivation the controller reconciles against.
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
      expect(other.slug, '8');
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

    test('a row with no lane is an honest error, not a silent no-op', () {
      final feed = _FakeFeed();
      final container = _container(feed);
      addTearDown(container.dispose);

      expect(
        () => container.read(
          laneControllerProvider((machine: 'mini3', slug: '9')),
        ),
        // Riverpod wraps a build failure, so the assertion is on the sentence
        // rather than the type.
        throwsA(
          isA<Object>().having(
            (e) => '$e',
            'message',
            contains('no agent lane on mini3/9'),
          ),
        ),
      );
    });
  });

  group('laneStateProvider', () {
    test('opens the lane and streams its state', () async {
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

      // End to end through the real wiring: the feed's OWN probe ran (the
      // production `ProbeRunner` is `MachineFeed.probe`, i.e. `execOn` over the
      // one SSH client the feed holds), the feed's forward was reserved, and
      // the spec carried its local port.
      expect(feed.probes, [source.gxProbeCommand()]);
      expect(source.specs.single.gxProbeStdout, orderedEquals([9, 9]));
      expect(feed.acquired, [2421]);
      expect(source.specs.single.dialUrl, 'http://127.0.0.1:41000');
      expect(sub.read().value?.capabilities?.kind, 'gx');
      expect(sub.read().value?.rows.single.text, 'hello');
    });
  });

  group('laneStampFor', () {
    test('finds the row\'s stamp, and answers null for a row with none', () {
      final state = _state();
      expect(laneStampFor(state, '7')?.sessionId, 'sess-7');
      expect(laneStampFor(state, '9'), isNull, reason: 'the row carries none');
      expect(laneStampFor(state, 'nope'), isNull, reason: 'no such row');
    });
  });

  group('laneStamps', () {
    test('ignores a feed that has never connected', () async {
      // THE TRAP. A cold feed carries no rows at all, and mapping that to "the
      // row is gone" would abandon every lane in the first second of a start.
      final cold = MachineFeedState(machine: _mini3);
      final stamps = laneStamps(
        Stream<MachineFeedState>.fromIterable([cold, _state()]),
        '7',
      );

      expect(await stamps.toList(), [
        isA<BridgeAgentLaneStamp>(),
      ], reason: 'only the authoritative state produced a stamp');
    });

    test('emits null once the row is really gone, and dedupes repeats', () async {
      final present = _state();
      final gone = _state(sessions: const []);
      final stamps = laneStamps(
        Stream<MachineFeedState>.fromIterable([
          present,
          present,
          gone,
          gone,
          present,
        ]),
        '7',
      );

      final seen = await stamps.toList();
      // Three transitions, not five events: the feed re-emits its rows on every
      // roost poll, and a lane that reconciled on each would churn.
      expect(seen, hasLength(3));
      expect(seen[0], isNotNull);
      expect(seen[1], isNull);
      expect(seen[2], isNotNull);
    });
  });

  group('laneReachProvider', () {
    test('production is machine reach, unconditionally', () {
      final container = _container(_FakeFeed());
      addTearDown(container.dispose);

      expect(container.read(laneReachProvider), LaneReach.machine);
    });

    test('a lane on a LOOPBACK host still forwards', () async {
      // THE LIVE BUG, as a regression guard. This seam used to infer the reach
      // from the host and answer `local` for `localhost`/`127.0.0.1`, but a
      // shed VM is dialled at `localhost:2222` — the shed *server's* sshd,
      // which routes into a microVM whose `127.0.0.1:2421` is not this
      // device's. Registered as `localhost` the lane made no forward and sat at
      // `generation=0` forever; registered by LAN address, the same VM worked.
      // So a loopback host must change nothing here.
      final feed = _FakeFeed(
        machine: const MachineRecord(name: 'mini3', host: 'localhost'),
      );
      final source = _FakeSource();
      final container = _container(feed, source: source);
      addTearDown(container.dispose);

      final sub = container.listen(
        laneStateProvider(_seven),
        (_, _) {},
        fireImmediately: true,
      );
      await pumpEventQueue();

      expect(
        container.read(laneControllerProvider(_seven)).reach,
        LaneReach.machine,
      );
      expect(feed.acquired, [2421], reason: 'a forward, despite the host');
      expect(
        source.specs.single.dialUrl,
        'http://127.0.0.1:41000',
        reason: 'the dial goes to OUR forward, not to the reported port',
      );
      expect(sub.read().value?.capabilities?.kind, 'gx');
    });

    test('the override is the seam the hermetic harness relies on', () async {
      // `integration_test/lane_test.dart` needs a lane with no sshd and no
      // forward, and this override is the ONLY way it gets one now — which is
      // why the no-forward path stays covered here rather than only there.
      final feed = _FakeFeed();
      final source = _FakeSource();
      final container = _container(
        feed,
        source: source,
        reach: LaneReach.local,
      );
      addTearDown(container.dispose);

      final sub = container.listen(
        laneStateProvider(_seven),
        (_, _) {},
        fireImmediately: true,
      );
      await pumpEventQueue();

      expect(
        container.read(laneControllerProvider(_seven)).reach,
        LaneReach.local,
      );
      expect(feed.acquired, isEmpty, reason: 'nothing to forward');
      expect(
        source.specs.single.dialUrl,
        source.specs.single.reportedUrl,
        reason: 'the local branch dials the reported url verbatim',
      );
      expect(sub.read().value?.capabilities?.kind, 'gx');
    });
  });
}

const _seven = (machine: 'mini3', slug: '7');
const _eight = (machine: 'mini3', slug: '8');
const _mini3 = MachineRecord(name: 'mini3', host: 'mini3');

ProviderContainer _container(
  _FakeFeed feed, {
  _FakeSource? source,
  LaneReach? reach,
}) => ProviderContainer(
  overrides: [
    machinesProvider.overrideWith((ref) async => const [_mini3]),
    identitiesProvider.overrideWith((ref) async => []),
    machineFeedControllerProvider('mini3').overrideWith((ref) => feed),
    machineFeedProvider(
      'mini3',
    ).overrideWith((ref) => Stream.value(feed.state)),
    if (source != null) laneSourceProvider.overrideWithValue(source),
    // Left alone unless a test is about the reach: the default IS the
    // production value, so every other cell exercises the shipped path.
    if (reach != null) laneReachProvider.overrideWithValue(reach),
  ],
);

MachineFeedState _state({List<BridgeRcSession>? sessions}) => MachineFeedState(
  machine: _mini3,
  connectedOnce: true,
  reachable: true,
  sessions:
      sessions ??
      [
        _row('7', 'sess-7'),
        _row('8', 'sess-8'),
        // A row with no agent lane at all — the `laneStampFor` null case, and
        // the reason the controller provider has to refuse rather than open
        // something.
        _row('9', null),
      ],
);

BridgeRcSession _row(String slug, String? sessionId) => BridgeRcSession(
  host: '',
  shed: '',
  slug: slug,
  displayName: 'row$slug',
  kind: const BridgeRcKind.gx(),
  state: BridgeRcState.ready,
  managed: true,
  attention: false,
  tabId: int.tryParse(slug),
  agentLane: sessionId == null
      ? null
      : BridgeAgentLaneStamp(
          kind: 'gx',
          sessionId: sessionId,
          serverUrl: 'http://127.0.0.1:2421',
        ),
);

/// A [MachineFeed] the provider can be handed: the real one dials SSH and calls
/// the FRB-sync `roostCapabilities()` in its constructor, so it cannot exist in
/// a unit test at all. `noSuchMethod` guards every member this fake does not
/// know about.
class _FakeFeed implements MachineFeed {
  _FakeFeed({this.machine = _mini3});

  final List<String> probes = [];
  final List<int> acquired = [];

  /// Carried because [MachineFeed] declares it, and settable so one test can
  /// give the machine a LOOPBACK host and prove the reach ignores it.
  @override
  final MachineRecord machine;

  @override
  MachineFeedState get state => _state();

  @override
  Stream<MachineFeedState> get updates =>
      const Stream<MachineFeedState>.empty();

  @override
  Future<Uint8List> probe(String wireCommand) async {
    probes.add(wireCommand);
    return Uint8List.fromList([9, 9]);
  }

  @override
  Future<LaneLease> acquireForward(int remotePort) async {
    acquired.add(remotePort);
    return FakeLaneLease(41000);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSource implements LaneSource {
  final List<BridgeLaneSpec> specs = [];

  @override
  String gxProbeCommand() => "sh -c 'probe'";

  @override
  Future<LaneHandle> open(BridgeLaneSpec spec) async {
    specs.add(spec);
    return _FakeHandle();
  }

  @override
  Stream<bool> nudges(LaneHandle handle) => const Stream<bool>.empty();

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
        approvals: const [],
        needsCredentials: false,
      );

  @override
  void close(LaneHandle handle) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHandle implements LaneHandle {}
