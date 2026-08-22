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

/// **What a session LIST offers, and what it deliberately does not.**
///
/// Watch and End — and nothing that steers. Directing an agent from a list row
/// means acting without having read a word of its output, which is not how
/// anyone actually works. Steering, interrupting, and the capability gate that
/// governs them live on the watch screen, beside the output
/// (`session_watch_screen_test.dart`).
///
/// So the rule this file pins is the inverse of a gate: EVERY kind gets the
/// same two actions here, because "can I direct this?" is not a question the
/// list is allowed to answer.
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
  rcVersion: 4,
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
    // `shell` is deliberately ABSENT — no entry at all is a different case
    // from an entry that says no, and both must behave the same here.
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

MachineFeedState _live(
  List<BridgeRcSession> sessions, {
  BridgeRcCapabilities? caps,
  bool reachable = true,
}) => MachineFeedState(
  machine: _mini3,
  sessions: sessions,
  reachable: reachable,
  connectedOnce: true,
  capabilities: caps,
);

void main() {
  testWidgets('every kind gets the same two list actions: Watch and End', (
    tester,
  ) async {
    // opencode is fully steerable, codex takes keystrokes only, shell takes
    // nothing — and on the LIST that difference is invisible, by design.
    await tester.pumpWidget(
      _app(
        _live([
          _session('oc1', const BridgeRcKind.opencode()),
          _session('cx1', const BridgeRcKind.codex()),
          _session('sh1', const BridgeRcKind.shell()),
        ], caps: _caps),
      ),
    );
    await tester.pumpAndSettle();

    for (final slug in ['oc1', 'cx1', 'sh1']) {
      expect(
        find.byKey(ValueKey('machine-watch-$slug')),
        findsOneWidget,
        reason: '$slug must be watchable',
      );
      expect(find.byKey(ValueKey('machine-kill-$slug')), findsOneWidget);
    }
  });

  testWidgets('the list offers nothing that steers a session', (tester) async {
    // The regression this guards is the shipped-then-reverted design: Steer and
    // Interrupt sat on the card, so the only way to use them was blind.
    await tester.pumpWidget(
      _app(_live([_session('oc1', const BridgeRcKind.opencode())], caps: _caps)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('machine-steer-oc1')), findsNothing);
    expect(find.byKey(const ValueKey('machine-interrupt-oc1')), findsNothing);
    expect(find.text('Steer'), findsNothing);
    expect(find.text('Interrupt'), findsNothing);
  });

  testWidgets('an unreachable machine offers no actions on its stale rows', (
    tester,
  ) async {
    // The last snapshot stays on screen so "mini3 is asleep and these were its
    // sessions" is still readable — but acting on a row the app cannot reach
    // would only produce an error, so nothing is offered.
    await tester.pumpWidget(
      _app(
        _live(
          [_session('oc1', const BridgeRcKind.opencode())],
          caps: _caps,
          reachable: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('oc1'), findsOneWidget, reason: 'the row is still listed');
    expect(find.byKey(const ValueKey('machine-watch-oc1')), findsNothing);
    expect(find.byKey(const ValueKey('machine-kill-oc1')), findsNothing);
  });
}
