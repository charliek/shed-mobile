import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/rc/all_sessions_view.dart';
import 'package:shed_mobile/machines/machine_feed.dart';
import 'package:shed_mobile/machines/machine_record.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/servers/server_record.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

/// **Render off `kind_features`, never off the kind.**
///
/// This is the block's load-bearing correctness rule, and the reason the wire
/// carries capabilities at all. Offering a control a kind does not support
/// produces a `409 not_supported` the user cannot act on — a button that lies.
/// The three kinds below are the three shapes the real contract has:
///
/// | kind     | approvals | input   | interrupt | offered here      |
/// |----------|-----------|---------|-----------|-------------------|
/// | opencode | remote    | turn    | yes       | Steer, Interrupt  |
/// | codex    | tui       | gated   | no        | neither           |
/// | shell    | (absent)  | —       | —         | neither           |
///
/// `shell` has no `kind_features` entry AT ALL, which is a different case from
/// "an entry that says no" and must degrade the same way.
const _mini3 = MachineRecord(name: 'mini3', host: 'mini3.example');

BridgeRcKindFeatures _features({
  required String approvals,
  required String input,
  required bool interrupt,
}) => BridgeRcKindFeatures(
  postInput: true,
  approvals: approvals,
  watch: true,
  input: input,
  feed: 'messages',
  interrupt: interrupt,
  attach: 'tmux',
);

/// mini3's real capabilities, trimmed to the kinds under test.
final _caps = BridgeRcCapabilities(
  rcVersion: BigInt.from(4).toInt(),
  kinds: const [
    BridgeRcKind.opencode(),
    BridgeRcKind.codex(),
    BridgeRcKind.shell(),
  ],
  agents: const {},
  features: const ['contract-v2'],
  kindFeatures: {
    'opencode': _features(approvals: 'remote', input: 'turn', interrupt: true),
    'codex': _features(approvals: 'tui', input: 'gated', interrupt: false),
    // `shell` is deliberately ABSENT.
  },
);

BridgeRcSession _session(String slug, BridgeRcKind kind) => BridgeRcSession(
  // A hub read directly reports an EMPTY shed and host on every session.
  host: '',
  shed: '',
  slug: slug,
  tmuxSession: 'rc-$slug',
  displayName: slug,
  kind: kind,
  state: BridgeRcState.ready,
  managed: true,
);

Widget _app(MachineFeedState state) => ProviderScope(
  retry: (_, _) => null,
  overrides: [
    serversProvider.overrideWith((ref) => <ServerRecord>[]),
    machinesProvider.overrideWith((ref) async => const [_mini3]),
    machineFeedProvider('mini3').overrideWith((ref) => Stream.value(state)),
  ],
  child: MaterialApp(
    theme: shedLightTheme,
    home: const Scaffold(body: AllSessionsView()),
  ),
);

MachineFeedState _live(List<BridgeRcSession> sessions, {BridgeRcCapabilities? caps}) =>
    MachineFeedState(
      machine: _mini3,
      sessions: sessions,
      reachable: true,
      connectedOnce: true,
      capabilities: caps,
    );

void main() {
  testWidgets('a kind with remote approvals and turn input is steerable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_live([_session('oc1', const BridgeRcKind.opencode())], caps: _caps)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('machine-steer-oc1')), findsOneWidget);
    expect(find.byKey(const ValueKey('machine-interrupt-oc1')), findsOneWidget);
    expect(find.byKey(const ValueKey('machine-kill-oc1')), findsOneWidget);
  });

  testWidgets('a TUI-approvals kind is offered NO remote controls', (
    tester,
  ) async {
    // codex reports `approvals: "tui"`, `input: "gated"`, `interrupt: false`.
    // Its approvals are informational — they are answered in its terminal —
    // and it accepts keystrokes, not a structured turn. Offering Steer or
    // Interrupt here would produce a 409 the user cannot act on.
    await tester.pumpWidget(
      _app(_live([_session('cx1', const BridgeRcKind.codex())], caps: _caps)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('machine-steer-cx1')), findsNothing);
    expect(find.byKey(const ValueKey('machine-interrupt-cx1')), findsNothing);
    // Ending it is not a hub verb and is always available.
    expect(find.byKey(const ValueKey('machine-kill-cx1')), findsOneWidget);
  });

  testWidgets('a kind with no kind_features entry gets no controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_live([_session('sh1', const BridgeRcKind.shell())], caps: _caps)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('machine-steer-sh1')), findsNothing);
    expect(find.byKey(const ValueKey('machine-interrupt-sh1')), findsNothing);
    expect(find.byKey(const ValueKey('machine-kill-sh1')), findsOneWidget);
  });

  testWidgets('with capabilities UNKNOWN, even a steerable kind is observe-only', (
    tester,
  ) async {
    // Capabilities are fetched over a second SSH exec that can fail (an old
    // `sx`, a slow link). Failing OPEN — assuming a kind is steerable because
    // its name is usually steerable — is exactly the kind-not-features mistake.
    await tester.pumpWidget(
      _app(_live([_session('oc1', const BridgeRcKind.opencode())])),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('machine-steer-oc1')), findsNothing);
    expect(find.byKey(const ValueKey('machine-interrupt-oc1')), findsNothing);
    expect(find.byKey(const ValueKey('machine-kill-oc1')), findsOneWidget);
  });

  testWidgets('the steer dialog survives being dismissed', (tester) async {
    // A crash, live, on the first real steer: the controller was created by the
    // caller and disposed when `showDialog` returned — but that future completes
    // when the route is POPPED, while it is still animating out with the
    // TextField mounted and listening. Disposing under it trips
    // `_dependents.isEmpty` and takes the app down.
    //
    // `pumpAndSettle` runs the exit animation to completion, which is exactly
    // the window the bug lived in — so this cell only passes if the dialog owns
    // its controller.
    await tester.pumpWidget(
      _app(_live([_session('oc1', const BridgeRcKind.opencode())], caps: _caps)),
    );
    await tester.pumpAndSettle();

    for (final action in ['Cancel', 'Send']) {
      await tester.tap(find.byKey(const ValueKey('machine-steer-oc1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('machine-steer-text')), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('machine-steer-text')),
        // Blank for Send, so dismissal is what is under test and no turn is
        // attempted against a machine this test has no connection to.
        action == 'Send' ? '   ' : 'ignored',
      );
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '$action crashed the app');
      expect(find.byKey(const ValueKey('machine-steer-text')), findsNothing);
    }
  });

  testWidgets('two kinds side by side get different controls on one machine', (
    tester,
  ) async {
    // The end state of the rule: the SAME machine, the same capabilities, and
    // the rows differ — which can only be true if the gate reads the session's
    // kind features rather than anything about the machine.
    await tester.pumpWidget(
      _app(
        _live([
          _session('oc1', const BridgeRcKind.opencode()),
          _session('cx1', const BridgeRcKind.codex()),
        ], caps: _caps),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('machine-steer-oc1')), findsOneWidget);
    expect(find.byKey(const ValueKey('machine-steer-cx1')), findsNothing);
  });
}
