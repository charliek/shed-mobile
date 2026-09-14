import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shed_mobile/machines/machine_feed.dart';
import 'package:shed_mobile/machines/machine_record.dart';
import 'package:shed_mobile/src/rust/api/roost.dart';
import 'package:shed_mobile/src/rust/api/roost_bootstrap.dart';
import 'package:shed_mobile/src/rust/frb_generated.dart';
import 'package:shed_mobile/ssh/host_key_store.dart';
import 'package:shed_mobile/ssh/roost_bootstrap_runner.dart';
import 'package:shed_mobile/ssh/roost_entitlement.dart';

/// **The phone keeps a bootstrapped machine's agent hooks wired** (plan 020
/// §3.3, amendment A8, commit C-M3b).
///
/// A watcher for a machine this app run bootstrapped re-sends
/// `session.set_agent_hooks` at the head of every cycle it connects; one for
/// any other machine sends nothing. The WIRE half of that is pinned in Rust
/// against a fake roost (`rust/src/api/roost.rs`). What is pinned here is the
/// half only Dart can answer: **that a feed asks for the claim it holds, at
/// every spawn** — including the two spawns a phone actually lives on, the
/// re-spawn after an install and the fresh feed after a background.
///
/// ## Why these cells live here and not in `test/`
///
/// A `MachineFeed` cannot be built under `flutter test` at all: its constructor
/// calls `roostCapabilities()`, and `start()` creates an FRB opaque watcher —
/// both need the native library, which only the integration harness loads. The
/// pure half of the same subject (the claim's own lifetime) is unit-tested in
/// `test/ssh/roost_entitlement_test.dart`.
///
/// ## Hermetic, with real sockets and no sshd
///
/// `start()` binds a loopback tunnel port and spawns a real watcher against it;
/// the SSH dial underneath it goes to a port nothing serves, which
/// `PortListener` reports as a refused connection and the watcher reads as an
/// ordinary `Down`. Nothing here waits on that: every assertion is about what
/// `start()` ASKED FOR, which it has already asked by the time it returns.

/// A machine nothing serves — the dial fails fast and stays inside the feed.
MachineRecord get _machine =>
    MachineRecord(name: 'mini3', host: '127.0.0.1', sshPort: 1);

/// Records what each `start()` asked the bridge for, then makes the real call
/// so the feed behaves exactly as it does in production.
class _RecordingSpawn {
  final List<({String machine, bool bootstrapped})> asked =
      <({String machine, bool bootstrapped})>[];

  Future<BridgeRoostWatcher> call({
    required String machine,
    required int localPort,
    required bool bootstrapped,
  }) {
    asked.add((machine: machine, bootstrapped: bootstrapped));
    return createRoostWatcher(
      machine: machine,
      localPort: localPort,
      bootstrapped: bootstrapped,
    );
  }
}

/// A [BootstrapHandle] that answers one terminal step and needs no far side.
///
/// `begin` is the only verb a terminal drive reaches: there is no `Step::Exec`,
/// so nothing is ever run on a machine. The bridge's own half — the machines,
/// the wire calls, the reach note — is tested in Rust.
class _TerminalHandle implements BootstrapHandle {
  _TerminalHandle(this.step);

  final BridgeBootstrapStep step;

  @override
  Future<BridgeBootstrapStep> begin() async => step;

  @override
  Future<BridgeBootstrapStep> feedExec({
    required int? exit,
    required Uint8List stdout,
    required String stderrTail,
  }) async => throw StateError('a terminal drive execs nothing');

  @override
  void noteReach(BridgeReachKind kind, String message) {}

  @override
  Stream<Uint8List> source(int chunk) =>
      throw StateError('a terminal drive reads no source');
}

/// The install finished. The two required fields and nothing else — no cell
/// here is about what an install reports, only about what it entitles.
BridgeBootstrapStep _installed(String target) => BridgeBootstrapStep.installed(
  installed: BridgeBootstrapInstalled(
    target: target,
    plan: const BridgeBootstrapPlan.install(),
  ),
);

/// The probe finished. Nothing was changed on the far side, so nothing is
/// earned.
BridgeBootstrapStep _failed() => BridgeBootstrapStep.failed(
  failure: const BridgeBootstrapFailure(
    stage: BridgeBootstrapStage.stream,
    message: 'the transfer stopped',
    stageCode: 'stream',
  ),
);

MachineFeed _feed(
  RoostBootstrapEntitlements entitlements,
  _RecordingSpawn spawn,
) => MachineFeed(
  machine: _machine,
  identities: const [],
  hostKeys: HostKeyStore(tofu: true),
  entitlements: entitlements,
  spawnWatcher: spawn.call,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());

  testWidgets('a machine nobody bootstrapped spawns an unentitled watcher', (
    _,
  ) async {
    final spawn = _RecordingSpawn();
    final feed = _feed(RoostBootstrapEntitlements(), spawn);

    await feed.start();
    await feed.dispose();

    expect(spawn.asked, hasLength(1));
    expect(
      spawn.asked.single.bootstrapped,
      isFalse,
      reason:
          'shed wires a session it started and nothing else — at session '
          'protocol 5 this bool is the only thing enforcing that',
    );
    expect(spawn.asked.single.machine, 'mini3');
  });

  testWidgets(
    'a completed install entitles the machine AND re-spawns its watcher '
    'entitled, in the same app run',
    (_) async {
      final entitlements = RoostBootstrapEntitlements();
      final spawn = _RecordingSpawn();
      final feed = _feed(entitlements, spawn);

      // The state every install starts from: a watcher has been running since
      // the screen opened, reporting the machine as unreachable because nothing
      // is serving there yet.
      await feed.start();
      expect(spawn.asked.single.bootstrapped, isFalse);

      final step = await feed.runBootstrap(
        _TerminalHandle(_installed('mini3')),
      );

      expect(step, isA<BridgeBootstrapStep_Installed>());
      expect(
        entitlements.holds('mini3'),
        isTrue,
        reason: 'the drive records the claim; the UI is not asked to remember',
      );
      // **The re-spawn, which is the whole point.** A watcher decides at spawn,
      // so the one already running would otherwise stay unentitled for the rest
      // of the run — the one machine that just earned the entitlement would be
      // the one machine that never exercises it.
      expect(spawn.asked, hasLength(2));
      expect(
        spawn.asked.last.bootstrapped,
        isTrue,
        reason: 'the install did not re-arm the machine it just bootstrapped',
      );

      await feed.dispose();
    },
  );

  testWidgets(
    'the claim outlives the feed that earned it — the background/foreground '
    'respawn',
    (_) async {
      final entitlements = RoostBootstrapEntitlements();
      final first = _RecordingSpawn();
      final feed = _feed(entitlements, first);
      await feed.start();
      await feed.runBootstrap(_TerminalHandle(_installed('mini3')));
      // Backgrounding: the feed is `autoDispose` and goes with the screen.
      await feed.dispose();

      // Foregrounding: a WHOLE NEW feed for the same machine, from the same
      // app-scoped registry. This is the case §3.3 names — "the agent I set up
      // yesterday never reports" is what the phone does without it, because a
      // phone rebuilds this object constantly and a desktop almost never does.
      final second = _RecordingSpawn();
      final next = _feed(entitlements, second);
      await next.start();
      await next.dispose();

      expect(second.asked, hasLength(1));
      expect(
        second.asked.single.bootstrapped,
        isTrue,
        reason: 'the respawned watcher forgot what this app run bootstrapped',
      );
    },
  );

  testWidgets('a relaunch spawns an unentitled watcher for the same machine', (
    _,
  ) async {
    final thisRun = RoostBootstrapEntitlements();
    final feed = _feed(thisRun, _RecordingSpawn());
    await feed.start();
    await feed.runBootstrap(_TerminalHandle(_installed('mini3')));
    await feed.dispose();

    // The app was killed and launched again: `roostEntitlementsProvider` builds
    // a fresh registry, because the claim was never written anywhere.
    final spawn = _RecordingSpawn();
    final relaunched = _feed(RoostBootstrapEntitlements(), spawn);
    await relaunched.start();
    await relaunched.dispose();

    expect(spawn.asked.single.bootstrapped, isFalse);
    expect(
      thisRun.holds('mini3'),
      isTrue,
      reason: 'and the run that DID bootstrap it still holds its claim',
    );
  });

  testWidgets('a bootstrap that did not install entitles nothing', (_) async {
    final entitlements = RoostBootstrapEntitlements();
    final spawn = _RecordingSpawn();
    final feed = _feed(entitlements, spawn);
    await feed.start();

    final step = await feed.runBootstrap(_TerminalHandle(_failed()));

    expect(step, isA<BridgeBootstrapStep_Failed>());
    expect(
      entitlements.holds('mini3'),
      isFalse,
      reason: 'a bootstrap that changed nothing on the far side earns nothing',
    );
    expect(
      spawn.asked,
      hasLength(1),
      reason: 'and nothing was re-spawned over a failure',
    );

    await feed.dispose();
  });
}
