import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shed_mobile/machines/machine_record.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/src/rust/api/roost.dart';
import 'package:shed_mobile/src/rust/api/roost_bootstrap.dart';
import 'package:shed_mobile/src/rust/frb_generated.dart';
import 'package:shed_mobile/ssh/roost_bootstrap_runner.dart';

/// **The card's bootstrap goes through the machine's own feed** (plan 020 §3.8,
/// commit C-M4).
///
/// `roostBootstrapFlowProvider` hands the UI a `drive`, and the whole of this
/// file is the assertion that the drive is `MachineFeed.runBootstrap` and not a
/// `RoostBootstrapRunner` assembled somewhere convenient.
///
/// **Why it is worth a file.** Both would install the same `roost-session` on
/// the same host and answer the same terminal step. Exactly one of them also
/// records that this app run bootstrapped the machine and re-spawns its watcher
/// to honour the claim — and without that, the one machine that just earned the
/// entitlement is the one machine whose agent hooks are never re-sent. That is
/// plan 019's defect one level up: a seam built, unit-tested, and then
/// constructed by no production caller, with every gate green either way.
///
/// The entitlement registry is the only observable that tells the two apart
/// from outside, because `runBootstrap` is the only thing that writes to it.
/// So that is what this asserts, and it asserts it against the REAL provider
/// graph rather than a hand-built flow.
///
/// ## Why it lives here and not in `test/`
///
/// `machineFeedControllerProvider` builds a real `MachineFeed`, whose
/// constructor calls the FRB-sync `roostCapabilities()`. That needs the native
/// library, which only the integration harness loads — a `flutter test` cell
/// cannot construct one at all. Nothing here opens a socket: the feed is never
/// started, so `runBootstrap` records the claim and finds no watcher to
/// re-spawn (the re-spawn itself is pinned in `roost_entitlement_test.dart`).

const _mini3 = MachineRecord(name: 'mini3', host: '127.0.0.1', sshPort: 1);

/// A [BootstrapHandle] that answers one terminal step and needs no far side.
///
/// `begin` is the only verb a terminal drive reaches: there is no `Step::Exec`,
/// so nothing is ever run on a machine. (The same shape as the one in
/// `roost_entitlement_test.dart`, kept local so neither file's story has to be
/// read to follow this one.)
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

BridgeBootstrapStep _installed() => BridgeBootstrapStep.installed(
  installed: const BridgeBootstrapInstalled(
    target: 'mini3',
    plan: BridgeBootstrapPlan.install(),
  ),
);

BridgeBootstrapStep _failed() => BridgeBootstrapStep.failed(
  failure: const BridgeBootstrapFailure(
    stage: BridgeBootstrapStage.stream,
    message: 'the transfer stopped',
    stageCode: 'stream',
  ),
);

ProviderContainer _container() => ProviderContainer(
  retry: (_, _) => null,
  overrides: [
    machinesProvider.overrideWith((ref) async => const [_mini3]),
    // The feed reads these synchronously and falls back to empty; overriding
    // keeps the harness off the developer's own `~/.ssh`.
    identitiesProvider.overrideWith((ref) async => <SSHKeyPair>[]),
  ],
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());

  testWidgets('the flow is built against the machine it names', (_) async {
    final container = _container();
    addTearDown(container.dispose);
    await container.read(machinesProvider.future);
    final sub = container.listen(
      roostBootstrapFlowProvider('mini3'),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);
    final flow = sub.read();

    expect(flow.target, 'mini3');
    // The tunnel is down on an unstarted feed, and the flow reports that
    // rather than a stale port: the port is read at call time.
    expect(flow.localPort(), isNull);
  });

  testWidgets(
    'a completed install through the flow RECORDS the entitlement — so the '
    'drive is the feed\'s',
    (_) async {
      final container = _container();
      addTearDown(container.dispose);
      await container.read(machinesProvider.future);
      final sub = container.listen(
        roostBootstrapFlowProvider('mini3'),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      final flow = sub.read();
      // The app-scoped registry the feed writes to — read from the SAME
      // container, so this is the registry the app would use and not a copy.
      final entitlements = container.read(roostEntitlementsProvider);
      expect(entitlements.holds('mini3'), isFalse, reason: 'precondition');

      final step = await flow.drive(_TerminalHandle(_installed()));

      expect(step, isA<BridgeBootstrapStep_Installed>());
      expect(
        entitlements.holds('mini3'),
        isTrue,
        reason:
            'the flow\'s drive did not go through MachineFeed.runBootstrap — a '
            'runner assembled in the UI installs the same thing and silently '
            'loses the hook re-send on the machine that just earned it',
      );
      expect(entitlements.targets, {'mini3'});
    },
  );

  testWidgets('a bootstrap that changed nothing records nothing', (_) async {
    // The negative control for the cell above: without it, a `drive` that
    // recorded unconditionally — or a registry that answered true for
    // everything — would pass it.
    final container = _container();
    addTearDown(container.dispose);
    await container.read(machinesProvider.future);
    final sub = container.listen(
      roostBootstrapFlowProvider('mini3'),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);

    final step = await sub.read().drive(_TerminalHandle(_failed()));

    expect(step, isA<BridgeBootstrapStep_Failed>());
    expect(container.read(roostEntitlementsProvider).targets, isEmpty);
  });

  testWidgets('the claim is the app run\'s, not the flow\'s', (_) async {
    // Both readers are `autoDispose`, so a claim held anywhere nearer the
    // screen would be forgotten on the next background — and the install would
    // never be honoured again. This pins that a SECOND flow for the same
    // machine, built after the first was let go, still sees it.
    final container = _container();
    addTearDown(container.dispose);
    await container.read(machinesProvider.future);

    final first = container.listen(
      roostBootstrapFlowProvider('mini3'),
      (_, _) {},
      fireImmediately: true,
    );
    await first.read().drive(_TerminalHandle(_installed()));
    first.close();
    await pumpEventQueue();

    final second = container.listen(
      roostBootstrapFlowProvider('mini3'),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(second.close);
    expect(second.read().target, 'mini3');
    expect(container.read(roostEntitlementsProvider).holds('mini3'), isTrue);
  });
}
