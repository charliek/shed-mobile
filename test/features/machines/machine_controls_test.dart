import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/rc/all_sessions_view.dart';
import 'package:shed_mobile/machines/machine_feed.dart';
import 'package:shed_mobile/widgets/card_shell.dart';
import 'package:shed_mobile/machines/machine_record.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/servers/server_record.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';
import 'package:shed_mobile/theme/shed_theme.dart';
import 'package:shed_mobile/widgets/open_pill.dart';

/// **What a machine's session LIST offers, and what it deliberately does not.**
///
/// A machine's sessions are roost tabs now (plan 013 S3m), and roost reports
/// status without serving a transcript, accepting a turn, or resolving an
/// approval. So the list offers the terminal and End, and nothing else — not
/// because the UI decided to hide things, but because the capabilities say no
/// and every control here renders off the capabilities.
///
/// That is the rule this file exists to pin: **controls render off
/// `kind_features`, never off the kind.** It used to catch a machine offering
/// Watch where the same kind in a shed did not; it now catches the opposite
/// mistake — a control surviving the transport swap on a session that cannot
/// answer it, which would produce an error the user has no way to act on.
const _mini3 = MachineRecord(name: 'mini3', host: 'mini3.example');

/// One kind's entry in [_roostCaps], mirroring `shed_app::roost::
/// roost_capabilities()` field for field.
///
/// A hand-written copy, on purpose: `roostCapabilities()` is a bridge call and
/// this is a pure widget test, so the values are transcribed here and the Rust
/// side pins its own copy (`roost_capabilities_advertise_a_native_remote_
/// attach_and_no_steering`). If the two ever disagree, the app's gates are
/// being tested against a contract nothing ships.
const _roostFeatures = BridgeRcKindFeatures(
  postInput: false,
  approvals: 'none',
  watch: false,
  input: '',
  feed: '',
  interrupt: false,
  // The terminal belongs to roost: the phone's affordance is a read-only
  // `tab.dump` peek, never a tmux attach.
  attach: 'native-remote',
);

/// What a roost-backed machine advertises — synthesized, never probed.
final _roostCaps = BridgeRcCapabilities(
  rcVersion: 2,
  kinds: const [
    BridgeRcKind.claudeRc(),
    BridgeRcKind.codex(),
    BridgeRcKind.opencode(),
    BridgeRcKind.cursor(),
  ],
  agents: const {},
  features: const ['contract-v2'],
  kindFeatures: const {
    'claude-rc': _roostFeatures,
    'codex': _roostFeatures,
    'opencode': _roostFeatures,
    'cursor': _roostFeatures,
    // `shell` is deliberately ABSENT — a plain shell tab is not a session at
    // all on the roost path, and an entry that says no must behave exactly as
    // no entry does.
  },
);

/// A `tmux`-attach entry — never actually advertised for a roost row, but
/// exactly what an old shed row's capabilities looked like pre-plan-013, and
/// what a `kindFeatures` entry with no `attach` field falls back to
/// (`attachKind`'s `null`/empty → `'tmux'` fallback). Used to pin the OTHER
/// half of the attach gate: a machine row is never offered an in-app attach
/// unless it is specifically `native-remote`.
const _tmuxFeatures = BridgeRcKindFeatures(
  postInput: false,
  approvals: 'none',
  watch: false,
  input: '',
  feed: '',
  interrupt: false,
  attach: 'tmux',
);

final _tmuxCaps = BridgeRcCapabilities(
  rcVersion: 2,
  kinds: const [BridgeRcKind.opencode()],
  agents: const {},
  features: const [],
  kindFeatures: const {'opencode': _tmuxFeatures},
);

BridgeRcSession _session(
  String slug,
  BridgeRcKind kind, {
  String? url,
  bool attention = false,
}) => BridgeRcSession(
  url: url,
  // A machine's rows carry no shed and no host: they are keyed and
  // labelled by the MACHINE (`machine:<name>`).
  host: '',
  shed: '',
  slug: slug,
  displayName: 'row$slug',
  kind: kind,
  state: BridgeRcState.ready,
  managed: true,
  attention: attention,
  // The slug IS roost's tab id; the typed id travels beside it so nothing
  // has to parse one back out to close a tab.
  tabId: int.tryParse(slug),
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
  testWidgets('a roost machine offers no Watch on any kind', (tester) async {
    // The hub could serve a message feed for a machine session; roost cannot,
    // so `watch` is false for every kind and the eye must be gone everywhere —
    // not hidden for some kinds and offered for others.
    await tester.pumpWidget(
      _app(
        _live([
          _session('1', const BridgeRcKind.opencode()),
          _session('2', const BridgeRcKind.codex()),
          _session('3', const BridgeRcKind.claudeRc()),
        ], caps: _roostCaps),
      ),
    );
    await tester.pumpAndSettle();

    for (final slug in ['1', '2', '3']) {
      expect(find.byKey(ValueKey('machine-watch-$slug')), findsNothing);
      // The negative control: the rows DID render, so the absences above are
      // about the affordance and not about an empty screen.
      expect(find.byKey(ValueKey('machine-kill-mini3-$slug')), findsOneWidget);
    }
    expect(find.text('Watch'), findsNothing);
  });

  testWidgets(
    'attach != native-remote offers no peek button (negative control)',
    (tester) async {
      // Plan 013 M3: the peek button is gated on `attachKind`, not on the
      // session's kind or on reachability alone. `_tmuxCaps` advertises
      // `attach: 'tmux'` for opencode — a shape a machine row never actually
      // ships, but exactly what proves the OTHER half of the gate: a machine
      // session offers no in-app attach at all unless it is specifically
      // `native-remote`.
      await tester.pumpWidget(
        _app(
          _live([
            _session('1', const BridgeRcKind.opencode()),
          ], caps: _tmuxCaps),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('machine-open-mini3-1')), findsNothing);
      // The negative control: the row DID render (End is still there), so the
      // absence above is about the attach gate and not an empty screen.
      expect(
        find.byKey(const ValueKey('machine-kill-mini3-1')),
        findsOneWidget,
      );
    },
  );

  testWidgets('with capabilities unknown, nothing is watchable either', (
    tester,
  ) async {
    // Capabilities are synthesized now, so this state should not arise in the
    // app — but failing OPEN on an absent capability is the mistake the whole
    // render-off-features rule exists to prevent, and it stays pinned.
    await tester.pumpWidget(
      _app(_live([_session('1', const BridgeRcKind.opencode())])),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('machine-watch-1')), findsNothing);
    expect(find.byKey(const ValueKey('machine-kill-mini3-1')), findsOneWidget);
  });

  testWidgets('the action row weights the terminal over delete', (
    tester,
  ) async {
    // The shipped row drifted from the reviewed design once already: a
    // terminal pill EXPANDED to fill the row (which reads as the primary
    // action) and a filled red delete box (the loudest thing on a card you are
    // usually only reading). This pins the intended weighting.
    await tester.pumpWidget(
      _app(
        _live([_session('1', const BridgeRcKind.opencode())], caps: _roostCaps),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('machine-open-mini3-1')), findsOneWidget);

    final open = tester.getRect(
      find.byKey(const ValueKey('machine-open-mini3-1')),
    );
    final del = tester.getRect(
      find.byKey(const ValueKey('machine-kill-mini3-1')),
    );

    // Reading order: the terminal, then delete at the far edge.
    expect(open.right, lessThan(del.left));
    // The terminal does NOT fill the row.
    final card = tester.getRect(find.byType(CardShell).first);
    expect(
      open.width,
      lessThan(card.width * 0.5),
      reason: 'the terminal pill expanded to fill the row again',
    );
    // Delete is a bare glyph: no wider than a tap target.
    expect(del.width, lessThanOrEqualTo(48));
  });

  testWidgets(
    'a claude session on a machine offers its link, like a shed one',
    (tester) async {
      // The shipped machine row dropped the copy/open pair entirely, so the ONE
      // kind whose session is also reachable from a browser had no way to get
      // there — the same session in a shed offered both.
      await tester.pumpWidget(
        _app(
          _live([
            _session(
              '1',
              const BridgeRcKind.claudeRc(),
              url: 'https://claude.ai/code/session_x',
            ),
            // A second, real row with no URL — the case the assertion below
            // is actually about. Asserting its absence against a slug that was
            // never rendered at all would pass regardless of whether a
            // URL-less row correctly withholds the buttons.
            _session('2', const BridgeRcKind.claudeRc()),
          ], caps: _roostCaps),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('machine-url-copy-mini3-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('machine-url-open-mini3-1')),
        findsOneWidget,
      );
      // And a kind with no URL is not given empty buttons.
      expect(
        find.byKey(const ValueKey('machine-url-copy-mini3-2')),
        findsNothing,
      );
      // The negative control: row 2 DID render, so the absence above is about
      // the missing URL and not about an empty screen.
      expect(
        find.byKey(const ValueKey('machine-kill-mini3-2')),
        findsOneWidget,
      );
    },
  );

  testWidgets('the list offers nothing that steers a session', (tester) async {
    // Two regressions in one assertion. The first is the shipped-then-reverted
    // design, where Steer and Interrupt sat on the card so the only way to use
    // them was blind. The second is the one plan 013 introduces the chance of:
    // roost answers `input: ""`, `interrupt: false`, `approvals: "none"`, so a
    // control that survived the swap would post a verb the far side has never
    // heard of.
    await tester.pumpWidget(
      _app(
        _live([_session('1', const BridgeRcKind.opencode())], caps: _roostCaps),
      ),
    );
    await tester.pumpAndSettle();

    for (final control in ['steer', 'interrupt', 'approve', 'watch']) {
      expect(find.byKey(ValueKey('machine-$control-1')), findsNothing);
    }
    for (final label in ['Steer', 'Interrupt', 'Approve', 'Watch']) {
      expect(find.text(label), findsNothing);
    }
    // The negative control again: End is still there, so this is a card with
    // controls on it and not a card that failed to build.
    expect(find.byKey(const ValueKey('machine-kill-mini3-1')), findsOneWidget);
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
          [_session('1', const BridgeRcKind.opencode())],
          caps: _roostCaps,
          reachable: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('row1'),
      findsOneWidget,
      reason: 'the row is still listed',
    );
    expect(find.byKey(const ValueKey('machine-open-mini3-1')), findsNothing);
    expect(find.byKey(const ValueKey('machine-kill-mini3-1')), findsNothing);
  });

  testWidgets('attention dot present when a machine session carries it', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _live([
          _session('1', const BridgeRcKind.opencode(), attention: true),
        ], caps: _roostCaps),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('machine-attention-mini3-1')),
      findsOneWidget,
    );
  });

  testWidgets('attention dot absent when a machine session carries none '
      '(negative control against the row rendering at all)', (tester) async {
    await tester.pumpWidget(
      _app(
        _live([_session('1', const BridgeRcKind.opencode())], caps: _roostCaps),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('machine-attention-mini3-1')),
      findsNothing,
    );
    // The row DID render — the absence above is about `attention`, not an
    // empty screen.
    expect(find.byKey(const ValueKey('machine-kill-mini3-1')), findsOneWidget);
  });

  testWidgets(
    'two machines with the same tab slug get distinct, non-colliding keys',
    (tester) async {
      // A slug is a roost tab id, scoped to ONE machine's daemon — two
      // different machines can both hand back a tab "4". Before this fix
      // every per-row key was `machine-<action>-4`, so the second machine's
      // row silently overwrote the first's in the widget tree instead of
      // rendering beside it.
      const machineA = MachineRecord(name: 'mini3', host: 'mini3.example');
      const machineB = MachineRecord(name: 'mini4', host: 'mini4.example');

      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            serversProvider.overrideWith((ref) => <ServerRecord>[]),
            machinesProvider.overrideWith((ref) async => [machineA, machineB]),
            machineFeedProvider('mini3').overrideWith(
              (ref) => Stream.value(
                MachineFeedState(
                  machine: machineA,
                  sessions: [_session('4', const BridgeRcKind.opencode())],
                  reachable: true,
                  connectedOnce: true,
                  capabilities: _roostCaps,
                ),
              ),
            ),
            machineFeedProvider('mini4').overrideWith(
              (ref) => Stream.value(
                MachineFeedState(
                  machine: machineB,
                  sessions: [_session('4', const BridgeRcKind.opencode())],
                  reachable: true,
                  connectedOnce: true,
                  capabilities: _roostCaps,
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: shedLightTheme,
            home: const Scaffold(body: AllSessionsView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Both rows rendered — not one clobbering the other in the tree.
      expect(find.text('row4'), findsNWidgets(2));

      final openA = find.byKey(const ValueKey('machine-open-mini3-4'));
      final openB = find.byKey(const ValueKey('machine-open-mini4-4'));
      final killA = find.byKey(const ValueKey('machine-kill-mini3-4'));
      final killB = find.byKey(const ValueKey('machine-kill-mini4-4'));

      expect(openA, findsOneWidget);
      expect(openB, findsOneWidget);
      expect(killA, findsOneWidget);
      expect(killB, findsOneWidget);
      // The two machines' keys are genuinely distinct GlobalKey-equivalent
      // identities, not the same key rendered twice.
      expect(
        tester.widget<OpenPill>(openA).key,
        isNot(equals(tester.widget<OpenPill>(openB).key)),
      );
      expect(tester.widget(killA).key, isNot(equals(tester.widget(killB).key)));
    },
  );
}
