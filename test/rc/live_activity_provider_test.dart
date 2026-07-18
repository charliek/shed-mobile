import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/rc/activity_overlay.dart';
import 'package:shed_mobile/src/rust/api/client.dart';
import 'package:shed_mobile/src/rust/api/dto.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';
import 'package:shed_mobile/src/rust/api/watcher.dart';

/// The Riverpod wiring behavior of [liveActivityProvider] — resync→invalidate,
/// Down-is-not-destructive, deterministic teardown, and the consumer-side
/// unknown-slug debounce — has no Rust home, so B4 tests it here through the
/// injectable [RcWatcherBridge] seam + a fake watcher. No native library is
/// touched: [shedClientProvider] and [overviewProvider] are overridden too.

const _server = 'srv';

/// A minimal opaque handle fake (`RustOpaqueInterface` is just dispose + isDisposed).
class _FakeHandle implements BridgeWatcherHandle {
  bool _disposed = false;
  @override
  void dispose() => _disposed = true;
  @override
  bool get isDisposed => _disposed;
}

/// A BridgeClient fake — the fake seam ignores it, so every real method is
/// unreachable (noSuchMethod guards against an accidental call).
class _FakeClient implements BridgeClient {
  @override
  void dispose() {}
  @override
  bool get isDisposed => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A StreamController-backed watcher seam recording teardown, so a test can drive
/// the update stream and assert stop/dispose discipline + no leaked listeners.
class _FakeWatcherBridge extends RcWatcherBridge {
  _FakeWatcherBridge();

  final controller = StreamController<BridgeWatcherUpdate>();
  final handle = _FakeHandle();
  int createCount = 0;
  int stopCount = 0;
  int disposeCount = 0;

  /// When set, `create` parks on this gate before returning the handle — lets a
  /// test dispose the provider WHILE create is in-flight (the "disposed between
  /// create and listen" branch).
  Completer<void>? createGate;

  void emit(BridgeWatcherUpdate u) => controller.add(u);

  @override
  Future<BridgeWatcherHandle> create({
    required BridgeClient client,
    required String serverName,
  }) async {
    createCount++;
    if (createGate != null) await createGate!.future;
    return handle;
  }

  @override
  Stream<BridgeWatcherUpdate> events(BridgeWatcherHandle handle) =>
      controller.stream;

  @override
  void stop(BridgeWatcherHandle handle) => stopCount++;

  @override
  void dispose(BridgeWatcherHandle handle) {
    disposeCount++;
    if (!handle.isDisposed) handle.dispose();
  }
}

/// A build counter for the overview override, so an invalidation is observable.
class _Counter {
  int n = 0;
}

BridgeRcEvent _activity(String shed, String slug) =>
    BridgeRcEvent.activityChanged(shed: shed, slug: slug);

BridgeWatcherUpdate _event(
  BridgeRcEvent event, {
  List<BridgeOverlayEntry> overlay = const [],
  bool resync = false,
}) => BridgeWatcherUpdate.event(event: event, overlay: overlay, resync: resync);

/// An overview holding one known session `web/known` (so an event for any other
/// slug is "unknown" and trips the debounce).
const _overviewWithKnown = OverviewData(
  BridgeOverview(
    server: BridgeOverviewServer(version: '1', features: ['rc-events']),
    sheds: [
      BridgeOverviewShed(
        shed: BridgeShed(
          host: 'h',
          name: 'web',
          status: BridgeShedStatus.running,
          activeNamespaces: [],
        ),
        sessions: [
          BridgeRcSession(
            host: 'h',
            shed: 'web',
            slug: 'known',
            tmuxSession: 't',
            displayName: 'known',
            kind: BridgeRcKind.shell(),
            state: BridgeRcState.ready,
            managed: true,
          ),
        ],
      ),
    ],
    warnings: [],
  ),
);

ProviderContainer _container(
  _FakeWatcherBridge fake,
  _Counter overviewBuilds, {
  OverviewResult overview = const OverviewUnsupported(),
}) => ProviderContainer(
  overrides: [
    rcWatcherBridgeProvider.overrideWithValue(fake),
    shedClientProvider(_server).overrideWith((ref) async => _FakeClient()),
    overviewProvider(_server).overrideWith((ref) async {
      overviewBuilds.n++;
      return overview;
    }),
  ],
);

Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('initial emission is an empty overlay', () async {
    final fake = _FakeWatcherBridge();
    final c = _container(fake, _Counter());
    addTearDown(c.dispose);
    ActivityOverlay? latest;
    final psub = c.listen(liveActivityProvider(_server), (_, next) {
      latest = next.value;
    }, fireImmediately: true);
    addTearDown(psub.close);
    await _settle();
    expect(latest, isNotNull);
    expect(latest!.lookup('web', 'anything'), isNull); // empty
    expect(fake.createCount, 1);
  });

  test('Event with resync:true invalidates the overview', () async {
    final fake = _FakeWatcherBridge();
    final builds = _Counter();
    final c = _container(fake, builds);
    addTearDown(c.dispose);
    // Keep the overview alive so an invalidation triggers an observable rebuild.
    c.listen(overviewProvider(_server), (_, _) {});
    final psub = c.listen(liveActivityProvider(_server), (_, _) {});
    addTearDown(psub.close);
    await _settle();

    final before = builds.n;
    // hub.unavailable is NOT in the debounce set, so this isolates resync.
    fake.emit(
      _event(const BridgeRcEvent.hubUnavailable(shed: 'web'), resync: true),
    );
    await _settle();
    expect(builds.n, before + 1);
  });

  test(
    'Down does NOT tear down or reconnect (stop not called; sub stays)',
    () async {
      final fake = _FakeWatcherBridge();
      final c = _container(fake, _Counter());
      addTearDown(c.dispose);
      ActivityOverlay? latest;
      final psub = c.listen(liveActivityProvider(_server), (_, next) {
        latest = next.value;
      });
      addTearDown(psub.close);
      await _settle();

      fake.emit(const BridgeWatcherUpdate.down(reason: 'blip'));
      await _settle();
      expect(fake.stopCount, 0); // Rust owns reconnect — never torn down here
      expect(fake.controller.hasListener, isTrue); // subscription stays alive

      // The still-live subscription delivers a later event's overlay.
      fake.emit(
        _event(
          _activity('web', 'known'),
          overlay: const [
            BridgeOverlayEntry(
              shed: 'web',
              slug: 'known',
              activity: BridgeRcActivity.working,
            ),
          ],
        ),
      );
      await _settle();
      expect(
        latest!.lookup('web', 'known')?.activity,
        BridgeRcActivity.working,
      );
    },
  );

  test(
    'dispose stops exactly once + disposes the handle, no leaked listeners',
    () async {
      final fake = _FakeWatcherBridge();
      final c = _container(fake, _Counter());
      addTearDown(c.dispose);
      final psub = c.listen(liveActivityProvider(_server), (_, _) {});
      await _settle();
      expect(fake.controller.hasListener, isTrue);

      // Last listener gone → autoDispose runs the provider's onDispose teardown.
      psub.close();
      await _settle();

      expect(fake.stopCount, 1);
      expect(fake.disposeCount, 1);
      expect(fake.handle.isDisposed, isTrue);
      expect(
        fake.controller.hasListener,
        isFalse,
      ); // Dart subscription cancelled
    },
  );

  test(
    'unknown-slug event triggers a debounced overview refetch (once/window)',
    () async {
      final fake = _FakeWatcherBridge();
      final builds = _Counter();
      final c = _container(fake, builds, overview: _overviewWithKnown);
      addTearDown(c.dispose);
      c.listen(overviewProvider(_server), (_, _) {});
      // Force the overview to resolve so `.value` is OverviewData for the lookup.
      await c.read(overviewProvider(_server).future);
      final psub = c.listen(liveActivityProvider(_server), (_, _) {});
      addTearDown(psub.close);
      await _settle();

      final before = builds.n;
      // `web/mystery` is absent from the overview → one refetch fires.
      fake.emit(_event(_activity('web', 'mystery')));
      await _settle();
      expect(builds.n, before + 1);

      // A second unknown-slug event within the 5s window does NOT refetch again.
      fake.emit(_event(_activity('web', 'mystery')));
      await _settle();
      expect(builds.n, before + 1);
    },
  );

  test('a known-slug event does not trigger a refetch', () async {
    final fake = _FakeWatcherBridge();
    final builds = _Counter();
    final c = _container(fake, builds, overview: _overviewWithKnown);
    addTearDown(c.dispose);
    c.listen(overviewProvider(_server), (_, _) {});
    await c.read(overviewProvider(_server).future);
    final psub = c.listen(liveActivityProvider(_server), (_, _) {});
    addTearDown(psub.close);
    await _settle();

    final before = builds.n;
    fake.emit(_event(_activity('web', 'known'))); // present → no refetch
    await _settle();
    expect(builds.n, before);
  });

  // F7(a): disposed before the client future resolves → the watcher is NEVER
  // created (the provider body's `if (disposed) return` before `bridge.create`).
  test('disposed before the client resolves → watcher never created', () async {
    final fake = _FakeWatcherBridge();
    final clientGate = Completer<BridgeClient>();
    final c = ProviderContainer(
      overrides: [
        rcWatcherBridgeProvider.overrideWithValue(fake),
        shedClientProvider(_server).overrideWith((ref) => clientGate.future),
        overviewProvider(
          _server,
        ).overrideWith((ref) async => const OverviewUnsupported()),
      ],
    );
    addTearDown(c.dispose);
    final psub = c.listen(liveActivityProvider(_server), (_, _) {});
    await _settle();

    // Tear the provider down BEFORE the client future completes…
    psub.close();
    await _settle();
    // …then resolve the client: the parked `.then` must early-return on disposed.
    clientGate.complete(_FakeClient());
    await _settle();

    expect(fake.createCount, 0);
  });

  // F7(b): disposed WHILE create is in-flight → the handle is stopped+dropped
  // exactly once (the "disposed between create and listen" branch), never listened.
  test(
    'disposed while create is pending → stop+dispose once, no leak',
    () async {
      final fake = _FakeWatcherBridge();
      fake.createGate = Completer<void>();
      final c = _container(fake, _Counter());
      addTearDown(c.dispose);
      final psub = c.listen(liveActivityProvider(_server), (_, _) {});
      await _settle();
      // The client resolved and create() is parked on the gate.
      expect(fake.createCount, 1);

      // Dispose while create is still pending.
      psub.close();
      await _settle();

      // Now let create complete — the disposed-post-create branch runs.
      fake.createGate!.complete();
      await _settle();

      expect(fake.stopCount, 1);
      expect(fake.disposeCount, 1);
      expect(fake.handle.isDisposed, isTrue);
      expect(fake.controller.hasListener, isFalse); // never listened
    },
  );

  // F7(c): the debounce re-enables after its window elapses — a second unknown
  // slug (past the shrunk window) fires a fresh refetch.
  test('debounce re-enables after the window elapses', () async {
    setRcUnknownSlugDebounceForTest(const Duration(milliseconds: 80));
    addTearDown(() => setRcUnknownSlugDebounceForTest(null));
    final fake = _FakeWatcherBridge();
    final builds = _Counter();
    final c = _container(fake, builds, overview: _overviewWithKnown);
    addTearDown(c.dispose);
    c.listen(overviewProvider(_server), (_, _) {});
    await c.read(overviewProvider(_server).future);
    final psub = c.listen(liveActivityProvider(_server), (_, _) {});
    addTearDown(psub.close);
    await _settle();

    final before = builds.n;
    fake.emit(_event(_activity('web', 'mystery')));
    await _settle();
    expect(builds.n, before + 1); // first fires

    fake.emit(_event(_activity('web', 'mystery')));
    await _settle();
    expect(builds.n, before + 1); // within window → suppressed

    // Wait past the (shrunk) window, then a fresh unknown-slug event refetches.
    await Future<void>.delayed(const Duration(milliseconds: 130));
    fake.emit(_event(_activity('web', 'mystery')));
    await _settle();
    expect(builds.n, before + 2); // re-enabled
  });

  // F7(d): a single event that is BOTH resync AND for an unknown slug fires
  // exactly ONE invalidation (locks F5 — the resync branch skips the unknown check).
  test(
    'resync + unknown-slug in one event → exactly ONE invalidation',
    () async {
      final fake = _FakeWatcherBridge();
      final builds = _Counter();
      final c = _container(fake, builds, overview: _overviewWithKnown);
      addTearDown(c.dispose);
      c.listen(overviewProvider(_server), (_, _) {});
      await c.read(overviewProvider(_server).future);
      final psub = c.listen(liveActivityProvider(_server), (_, _) {});
      addTearDown(psub.close);
      await _settle();

      final before = builds.n;
      fake.emit(_event(_activity('web', 'mystery'), resync: true));
      await _settle();
      expect(builds.n, before + 1); // resync invalidates; unknown check skipped
    },
  );
}
