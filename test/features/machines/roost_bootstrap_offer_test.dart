import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/machines/machines_section.dart';
import 'package:shed_mobile/features/machines/roost_bootstrap_offer.dart';
import 'package:shed_mobile/machines/machine_feed.dart';
import 'package:shed_mobile/machines/machine_record.dart';
import 'package:shed_mobile/machines/roost_bootstrap_flow.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/src/rust/api/roost.dart';
import 'package:shed_mobile/src/rust/api/roost_bootstrap.dart';
import 'package:shed_mobile/ssh/roost_bootstrap_runner.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

/// **What a machine card offers about its roost reach, and what the consent
/// sheet asks before anything is written** (plan 020 §3.8, commit C-M4;
/// shed-mobile AC 2 and AC 5).
///
/// The kind → affordance decision itself is a pure function and is tested as
/// one (`test/machines/machine_feed_test.dart`). What is pinned HERE is
/// everything that only exists once it is wired to a screen:
///
/// * that the two actionable kinds actually render a control, and the other two
///   render none;
/// * that a probe runs before anything is offered to be changed, and that
///   **dismissing the sheet performs nothing** — the AC 5 property, and the one
///   that would be a remote mutation nobody asked for if it broke;
/// * that the drive goes through the flow — i.e. that this widget does NOT
///   assemble a `RoostBootstrapRunner` of its own, which is how the hook
///   entitlement gets silently lost;
/// * the progress states, which are the whole of what a person sees during a
///   drive that takes tens of seconds.
const _mini3 = MachineRecord(name: 'mini3', host: 'mini3.example');

/// A handle nothing drives. The rig's `drive` records that it was CALLED and
/// answers a canned step; the machines behind a real handle are Rust's, and
/// their own tests live there.
class _InertHandle implements BootstrapHandle {
  @override
  Future<BridgeBootstrapStep> begin() =>
      throw StateError('the rig answers instead of driving');

  @override
  Future<BridgeBootstrapStep> feedExec({
    required int? exit,
    required Uint8List stdout,
    required String stderrTail,
  }) => throw StateError('the rig answers instead of driving');

  @override
  void noteReach(BridgeReachKind kind, String message) {}

  @override
  Stream<Uint8List> source(int chunk) =>
      throw StateError('the rig answers instead of driving');
}

class _FakeSession implements BootstrapSession {
  _FakeSession(this.label, this._closed);

  final String label;
  final List<String> _closed;

  @override
  final BootstrapHandle handle = _InertHandle();

  @override
  void close() => _closed.add(label);
}

/// The seams a [RoostBootstrapFlow] is built from, recorded.
///
/// The REAL flow is exercised — only the bridge under it is faked — so a cell
/// that says "the install was opened with the probe's fingerprint" is saying it
/// about the code that ships.
class _Rig {
  _Rig({required List<BridgeBootstrapStep> steps}) : _steps = [...steps];

  final List<BridgeBootstrapStep> _steps;

  /// Which verb each `open` was, in order — `probe` then `install`.
  final List<String> opens = <String>[];

  /// Which sessions were closed, in order. A drive that leaks a machine leaves
  /// this short.
  final List<String> closed = <String>[];

  /// Every handle the flow handed to the drive. **Empty means the UI ran a
  /// bootstrap some other way**, which is the failure this rig exists to catch.
  final List<BootstrapHandle> driven = <BootstrapHandle>[];

  /// What each install was opened with.
  final List<({String fingerprint, String arch, bool needsSource})> installs =
      <({String fingerprint, String arch, bool needsSource})>[];

  final List<RoostHostTarget> hosts = <RoostHostTarget>[];

  int? port = 41111;
  BridgeBootstrapSourcePreview preview = _source();

  /// Parks the next drive, so a progress state can be observed mid-flight.
  Completer<void>? gate;

  Future<BridgeBootstrapStep> drive(BootstrapHandle handle) async {
    driven.add(handle);
    final gate = this.gate;
    if (gate != null) await gate.future;
    return _steps.removeAt(0);
  }

  RoostBootstrapFlow get flow => RoostBootstrapFlow(
    target: 'mini3',
    localPort: () => port,
    drive: drive,
    openProbe: (host) async {
      opens.add('probe');
      hosts.add(host);
      return _FakeSession('probe', closed);
    },
    openInstall:
        (
          host, {
          required fingerprint,
          required arch,
          required needsSource,
          required scratchDir,
        }) async {
          opens.add('install');
          hosts.add(host);
          installs.add((
            fingerprint: fingerprint,
            arch: arch,
            needsSource: needsSource,
          ));
          return _FakeSession('install', closed);
        },
    sourcePreview: (_, _) => preview,
    scratchDir: '/tmp/shed-mobile-consent-test',
  );
}

BridgeBootstrapProbe _probe({
  BridgeBootstrapPlan plan = const BridgeBootstrapPlan.install(
    dest: '/home/dev/.local/bin/roost-session',
  ),
  bool actionable = true,
  bool needsSource = true,
}) => BridgeBootstrapProbe(
  target: 'mini3',
  outcome: const BridgeBootstrapProbeOutcome.missing(),
  arch: 'arm64',
  home: '/home/dev',
  session: const BridgeBootstrapSessionState.notInstalled(),
  candidates: const [],
  fingerprint: 'fp-1',
  installDest: '/home/dev/.local/bin/roost-session',
  plan: plan,
  needsSource: needsSource,
  actionable: actionable,
);

BridgeBootstrapSourcePreview _source({
  bool available = true,
  String describe = 'From ROOST_SESSION_INSTALL_BIN (/opt/roost-session).',
}) => BridgeBootstrapSourcePreview(
  source: const BridgeBootstrapSource.override(path: '/opt/roost-session'),
  skipped: const [],
  available: available,
  describe: describe,
);

BridgeBootstrapStep _probed(BridgeBootstrapProbe probe) =>
    BridgeBootstrapStep.probed(probe: probe);

BridgeBootstrapStep _installed() => BridgeBootstrapStep.installed(
  installed: const BridgeBootstrapInstalled(
    target: 'mini3',
    plan: BridgeBootstrapPlan.install(),
    verdict: 'roost-session ready',
  ),
);

BridgeBootstrapStep _failed(String message, String code) =>
    BridgeBootstrapStep.failed(
      failure: BridgeBootstrapFailure(
        stage: BridgeBootstrapStage.probe,
        message: message,
        stageCode: code,
      ),
    );

MachineFeedState _down(BridgeReachKind? kind) => MachineFeedState(
  machine: _mini3,
  reachable: false,
  connectedOnce: true,
  detail: 'connection refused',
  downKind: kind,
);

/// [tag] keys the scope, so a cell that pumps the SAME widget with a different
/// feed state gets a genuinely fresh container rather than an element Riverpod
/// updates in place — which would leave the previous state on screen and let an
/// absence assertion pass for the wrong reason.
Widget _app(
  MachineFeedState state, {
  RoostBootstrapFlow? flow,
  Object tag = 'a',
}) => ProviderScope(
  key: ValueKey('scope-$tag'),
  retry: (_, _) => null,
  overrides: [
    machinesProvider.overrideWith((ref) async => const [_mini3]),
    machineFeedProvider('mini3').overrideWith((ref) => Stream.value(state)),
    if (flow != null)
      roostBootstrapFlowProvider('mini3').overrideWith((ref) => flow),
  ],
  child: MaterialApp(
    theme: shedLightTheme,
    home: const Scaffold(body: SingleChildScrollView(child: MachinesSection())),
  ),
);

Finder _install() => find.byKey(const ValueKey('machine-roost-install-mini3'));
Finder _start() => find.byKey(const ValueKey('machine-roost-start-mini3'));
Finder _sheet() => find.byKey(const ValueKey('roost-consent-sheet'));

String _textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

void main() {
  group('the affordance on the card', () {
    testWidgets('not-installed offers an install and no-session a start', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(_down(BridgeReachKind.notInstalled), tag: 'not-installed'),
      );
      await tester.pumpAndSettle();
      expect(_install(), findsOneWidget);
      expect(_start(), findsNothing);
      expect(find.text('Install roost-session'), findsOneWidget);

      await tester.pumpWidget(
        _app(_down(BridgeReachKind.noSession), tag: 'no-session'),
      );
      await tester.pumpAndSettle();
      expect(_start(), findsOneWidget);
      expect(_install(), findsNothing);
      expect(find.text('Start roost-session'), findsOneWidget);
    });

    testWidgets('unreachable, other and unclassified offer nothing', (
      tester,
    ) async {
      for (final kind in [
        BridgeReachKind.unreachable,
        BridgeReachKind.other,
        null,
      ]) {
        await tester.pumpWidget(_app(_down(kind), tag: '$kind'));
        await tester.pumpAndSettle();

        expect(_install(), findsNothing, reason: 'kind $kind offered install');
        expect(_start(), findsNothing, reason: 'kind $kind offered start');
        // Not merely a hidden button: the whole affordance is absent, so no
        // probe can be started from this card at all.
        expect(
          find.byType(RoostBootstrapOffer),
          findsNothing,
          reason: 'kind $kind built an offer widget',
        );
        // The negative control: the CARD rendered, so the absences above are
        // about the affordance and not about an empty screen.
        expect(
          find.byKey(const ValueKey('machine-card-status-mini3')),
          findsOneWidget,
        );
      }
    });

    testWidgets('a machine that is answering offers nothing', (tester) async {
      // A `Snapshot` clears the kind, so the card stops offering without
      // deciding anything itself. The regression this guards is an install
      // button sitting on a working machine.
      await tester.pumpWidget(
        _app(
          const MachineFeedState(
            machine: _mini3,
            reachable: true,
            connectedOnce: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RoostBootstrapOffer), findsNothing);
      expect(_install(), findsNothing);
      expect(_start(), findsNothing);
      expect(
        find.byKey(const ValueKey('machine-card-status-mini3')),
        findsOneWidget,
      );
    });
  });

  group('the consent sheet', () {
    testWidgets('a probe runs first, and the sheet says target, plan and what '
        'will be written', (tester) async {
      final rig = _Rig(steps: [_probed(_probe())]);
      await tester.pumpWidget(
        _app(_down(BridgeReachKind.notInstalled), flow: rig.flow),
      );
      await tester.pumpAndSettle();

      await tester.tap(_install());
      await tester.pumpAndSettle();

      // The probe ran, over the feed's own tunnel port, and NOTHING was
      // installed on the way to asking.
      expect(rig.opens, ['probe']);
      expect(rig.hosts.single.target, 'mini3');
      expect(rig.hosts.single.localPort, 41111);
      expect(
        rig.hosts.single.jailFsRoot,
        isFalse,
        reason: 'the hermetic lane knob must never steer a shipped app',
      );

      expect(_sheet(), findsOneWidget);
      // THE TARGET.
      expect(_textOf(tester, 'roost-consent-target'), 'mini3');
      // THE PLAN.
      expect(
        _textOf(tester, 'roost-consent-plan'),
        'Install roost-session on mini3.',
      );
      // WHAT WILL BE WRITTEN: where it lands, where the bytes come from, and
      // what else the host will wire.
      expect(
        _textOf(tester, 'roost-consent-where'),
        'mini3, at /home/dev/.local/bin/roost-session',
      );
      expect(
        _textOf(tester, 'roost-consent-from'),
        'From ROOST_SESSION_INSTALL_BIN (/opt/roost-session).',
      );
      expect(_textOf(tester, 'roost-consent-hooks'), kRoostHooksSentence);
      // An install replaces nothing, so there is no backup line to show.
      expect(find.byKey(const ValueKey('roost-consent-backup')), findsNothing);
      expect(
        find.byKey(const ValueKey('roost-consent-confirm')),
        findsOneWidget,
      );
    });

    testWidgets('an update names the backup, and both answers stay on screen', (
      tester,
    ) async {
      final update = _Rig(
        steps: [
          _probed(
            _probe(
              plan: const BridgeBootstrapPlan.update(
                path: '/usr/bin/roost-session',
                replacesNewer: false,
                dest: '/home/dev/.local/bin/roost-session',
              ),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        _app(
          _down(BridgeReachKind.notInstalled),
          flow: update.flow,
          tag: 'update',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(_install());
      await tester.pumpAndSettle();

      expect(_textOf(tester, 'roost-consent-title'), 'Update roost-session');
      expect(
        _textOf(tester, 'roost-consent-backup'),
        'The file currently at /home/dev/.local/bin/roost-session will be '
        'backed up before it\'s replaced.',
      );
      // **Cancel is reachable**, which on the tallest of the three sheets it
      // was not: an Update carries a sixth line and the buttons went off the
      // bottom of the viewport, leaving a consent sheet whose only visible
      // answer was yes. The lines scroll; the answer does not.
      final cancel = find.byKey(const ValueKey('roost-consent-cancel'));
      expect(
        tester.getCenter(cancel).dy,
        lessThan(
          tester.view.physicalSize.height / tester.view.devicePixelRatio,
        ),
      );
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(_sheet(), findsNothing);
      expect(update.installs, isEmpty);
    });

    testWidgets('a start names no bytes, because none are sent', (
      tester,
    ) async {
      final start = _Rig(
        steps: [
          _probed(
            _probe(
              plan: const BridgeBootstrapPlan.start(
                path: '/home/dev/.local/bin/roost-session',
              ),
              needsSource: false,
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        _app(_down(BridgeReachKind.noSession), flow: start.flow, tag: 'start'),
      );
      await tester.pumpAndSettle();
      await tester.tap(_start());
      await tester.pumpAndSettle();

      expect(_textOf(tester, 'roost-consent-title'), 'Start roost-session');
      expect(
        _textOf(tester, 'roost-consent-plan'),
        'Start the roost-session already on mini3.',
      );
      expect(
        _textOf(tester, 'roost-consent-from'),
        'Nothing is sent — the binary is already there.',
      );
      expect(find.byKey(const ValueKey('roost-consent-backup')), findsNothing);
    });

    testWidgets('DISMISSING IT PERFORMS NOTHING — Cancel, and the barrier', (
      tester,
    ) async {
      // AC 5, and the one that would be a remote mutation nobody asked for.
      // Both ways out are tested: Cancel answers false, the barrier answers
      // null, and only `true` is an install.
      for (final dismiss in ['cancel', 'barrier']) {
        final rig = _Rig(steps: [_probed(_probe()), _installed()]);
        await tester.pumpWidget(
          _app(
            _down(BridgeReachKind.notInstalled),
            flow: rig.flow,
            tag: dismiss,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(_install());
        await tester.pumpAndSettle();
        expect(_sheet(), findsOneWidget, reason: 'precondition ($dismiss)');

        if (dismiss == 'cancel') {
          await tester.tap(find.byKey(const ValueKey('roost-consent-cancel')));
        } else {
          // Above the sheet: the modal barrier.
          await tester.tapAt(const Offset(20, 20));
        }
        await tester.pumpAndSettle();

        expect(
          _sheet(),
          findsNothing,
          reason: 'the sheet stayed up ($dismiss)',
        );
        expect(rig.opens, [
          'probe',
        ], reason: '$dismiss opened an install machine on the bridge');
        expect(rig.installs, isEmpty, reason: '$dismiss wrote to the far side');
        expect(
          rig.driven,
          hasLength(1),
          reason: '$dismiss drove a second bootstrap',
        );
        // The probe's machine was closed either way — a dismissed sheet must
        // not leave one open.
        expect(rig.closed, ['probe']);
        // And the offer is back, not stuck mid-flight.
        expect(find.text('Install roost-session'), findsOneWidget);
      }
    });

    testWidgets('confirming drives the install THROUGH THE FLOW', (
      tester,
    ) async {
      // **The test that matters.** A widget that assembled its own
      // `RoostBootstrapRunner` would install exactly the same thing and record
      // no entitlement — plan 019's defect one level up. `rig.driven` is the
      // only thing that can tell the two apart from here: it is the flow's
      // `drive`, which in production is `MachineFeed.runBootstrap`.
      final rig = _Rig(steps: [_probed(_probe()), _installed()]);
      await tester.pumpWidget(
        _app(_down(BridgeReachKind.notInstalled), flow: rig.flow),
      );
      await tester.pumpAndSettle();
      await tester.tap(_install());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('roost-consent-confirm')));
      await tester.pumpAndSettle();

      expect(rig.opens, ['probe', 'install']);
      expect(
        rig.driven,
        hasLength(2),
        reason:
            'both bootstraps must go through the flow\'s drive — the install '
            'is what entitles this app run to keep the hooks wired',
      );
      // Each drive got the handle from the session that was opened for it.
      expect(identical(rig.driven[0], rig.driven[1]), isFalse);
      // The install re-checks the host against the consented probe's own
      // answers; a client that passed its own would consent to one thing and
      // install another.
      expect(rig.installs.single.fingerprint, 'fp-1');
      expect(rig.installs.single.arch, 'arm64');
      expect(rig.installs.single.needsSource, isTrue);
      // Both machines were ended.
      expect(rig.closed, ['probe', 'install']);
      expect(
        _textOf(tester, 'machine-roost-note-mini3'),
        'roost-session ready',
      );
    });
  });

  group('progress and the rows that offer no button', () {
    testWidgets('the control says what is happening at every step', (
      tester,
    ) async {
      final rig = _Rig(steps: [_probed(_probe()), _installed()]);
      rig.gate = Completer<void>();
      await tester.pumpWidget(
        _app(_down(BridgeReachKind.notInstalled), flow: rig.flow),
      );
      await tester.pumpAndSettle();

      await tester.tap(_install());
      await tester.pump();
      expect(find.text('Checking…'), findsOneWidget);
      expect(
        tester.widget<TextButton>(_install()).onPressed,
        isNull,
        reason: 'a second tap mid-probe would open a second bootstrap',
      );

      rig.gate!.complete();
      await tester.pumpAndSettle();
      // The sheet is up and the user has not answered: the card says so rather
      // than looking idle behind it.
      expect(find.text('Waiting for you…'), findsOneWidget);

      rig.gate = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('roost-consent-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Installing…'), findsOneWidget);

      rig.gate!.complete();
      await tester.pumpAndSettle();
      expect(
        find.text('Install roost-session'),
        findsOneWidget,
        reason: 'the control must come back, whatever the drive answered',
      );
    });

    testWidgets('an up-to-date probe shows a status line and no sheet', (
      tester,
    ) async {
      final rig = _Rig(
        steps: [
          _probed(
            _probe(
              plan: const BridgeBootstrapPlan.upToDate(
                identity: BridgeBootstrapSessionIdentity(
                  appVersion: '0.4.1',
                  sessionProtocol: 5,
                  libghosttyBuild: 'b',
                  sessionId: 's',
                  startedAt: 't',
                ),
              ),
              actionable: false,
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        _app(_down(BridgeReachKind.notInstalled), flow: rig.flow),
      );
      await tester.pumpAndSettle();
      await tester.tap(_install());
      await tester.pumpAndSettle();

      expect(_sheet(), findsNothing);
      expect(
        _textOf(tester, 'machine-roost-note-mini3'),
        'roost-session 0.4.1 running (protocol 5)',
      );
      expect(rig.installs, isEmpty);
    });

    testWidgets(
      'the plan matrix\'s `actionable` is the gate, not the plan\'s shape',
      (tester) async {
        // The two rows that carry no button today are `up-to-date` and
        // `report`, and the copy function answers null for both — so the cell
        // above cannot tell that gate apart from this one. This can: an Install
        // plan that roost has marked unactionable. `actionable` travels on the
        // probe and is roost's own answer to "does acting on this do anything
        // at all"; a client that re-derived it from the plan's shape would open
        // a sheet here and then ask a host to do nothing.
        final rig = _Rig(steps: [_probed(_probe(actionable: false))]);
        await tester.pumpWidget(
          _app(_down(BridgeReachKind.notInstalled), flow: rig.flow),
        );
        await tester.pumpAndSettle();
        await tester.tap(_install());
        await tester.pumpAndSettle();

        expect(_sheet(), findsNothing);
        expect(rig.installs, isEmpty);
        expect(
          _textOf(tester, 'machine-roost-note-mini3'),
          'roost-session not found',
        );
      },
    );

    testWidgets(
      'pin P6\'s report row renders roost\'s own sentence, verbatim',
      (tester) async {
        // Somebody is using that session. The client offers no button, and the
        // sentence naming the command *they* would run is roost's, not ours.
        const message =
            'roost-session on mini3 speaks protocol 9; run '
            '`roost-session restart` there.';
        final rig = _Rig(
          steps: [
            _probed(
              _probe(
                plan: const BridgeBootstrapPlan.report(
                  protocol: 9,
                  message: message,
                ),
                actionable: false,
              ),
            ),
          ],
        );
        await tester.pumpWidget(
          _app(_down(BridgeReachKind.notInstalled), flow: rig.flow),
        );
        await tester.pumpAndSettle();
        await tester.tap(_install());
        await tester.pumpAndSettle();

        expect(_sheet(), findsNothing);
        expect(_textOf(tester, 'machine-roost-note-mini3'), message);
      },
    );

    testWidgets('with no bytes to send, the sentence replaces the sheet', (
      tester,
    ) async {
      final rig = _Rig(steps: [_probed(_probe())]);
      rig.preview = _source(
        available: false,
        describe: 'No roost-session to install from on this device.',
      );
      await tester.pumpWidget(
        _app(_down(BridgeReachKind.notInstalled), flow: rig.flow),
      );
      await tester.pumpAndSettle();
      await tester.tap(_install());
      await tester.pumpAndSettle();

      expect(_sheet(), findsNothing);
      expect(
        _textOf(tester, 'machine-roost-note-mini3'),
        'No roost-session to install from on this device.',
      );
      expect(rig.installs, isEmpty);
    });

    testWidgets('a failed probe says why, and asks for nothing', (
      tester,
    ) async {
      final rig = _Rig(
        steps: [_failed('mini3 is not reachable over SSH', 'probe')],
      );
      await tester.pumpWidget(
        _app(_down(BridgeReachKind.notInstalled), flow: rig.flow),
      );
      await tester.pumpAndSettle();
      await tester.tap(_install());
      await tester.pumpAndSettle();

      expect(_sheet(), findsNothing);
      expect(
        _textOf(tester, 'machine-roost-note-mini3'),
        'mini3 is not reachable over SSH',
      );
      expect(rig.closed, ['probe'], reason: 'the machine was still ended');
    });

    testWidgets('a machine with no tunnel refuses rather than dialling one', (
      tester,
    ) async {
      final rig = _Rig(steps: [_probed(_probe())]);
      rig.port = null;
      await tester.pumpWidget(
        _app(_down(BridgeReachKind.notInstalled), flow: rig.flow),
      );
      await tester.pumpAndSettle();
      await tester.tap(_install());
      await tester.pumpAndSettle();

      expect(rig.opens, isEmpty);
      expect(
        _textOf(tester, 'machine-roost-note-mini3'),
        contains('the machine is not connected'),
      );
      expect(find.text('Install roost-session'), findsOneWidget);
    });
  });
}
