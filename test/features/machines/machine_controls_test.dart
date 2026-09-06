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

/// **What a session LIST offers, and what it deliberately does not.**
///
/// Watch and End — and nothing that steers. Directing an agent from a list row
/// means acting without having read a word of its output, which is not how
/// anyone actually works. Steering, interrupting, and the capability gate that
/// governs them live on the watch screen, beside the output
/// (`session_watch_screen_test.dart`).
///
/// Two rules, then. "Can I direct this?" is not a question the list is allowed
/// to answer — nothing here steers. But "can I READ this?" is a capability like
/// any other, so Watch is gated on `kind_features.watch` exactly as the shed
/// card gates it: a kind with no feed must not be offered a view that can only
/// fail, and it must not be offered one on a machine that it would be denied in
/// a shed.
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

BridgeRcSession _session(String slug, BridgeRcKind kind, {String? url}) =>
    BridgeRcSession(
      url: url,
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
  testWidgets('Watch is offered exactly where the kind advertises a feed', (
    tester,
  ) async {
    // codex review: this used to offer Watch for EVERY kind, which meant a
    // `shell` session on a machine opened a watch screen that could only fail
    // against the messages endpoint — while the same kind in a SHED offered no
    // Watch at all. Same capability, two answers, decided by where it ran.
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

    // opencode and codex both report `watch: true`.
    for (final slug in ['oc1', 'cx1']) {
      expect(find.byKey(ValueKey('machine-watch-$slug')), findsOneWidget);
    }
    // `shell` has no kind_features entry at all — no feed to watch.
    expect(find.byKey(const ValueKey('machine-watch-sh1')), findsNothing);

    // Ending it is not a hub verb and needs no capability: always offered.
    for (final slug in ['oc1', 'cx1', 'sh1']) {
      expect(find.byKey(ValueKey('machine-kill-$slug')), findsOneWidget);
    }
  });

  testWidgets('with capabilities unknown, nothing is watchable', (
    tester,
  ) async {
    // The probe is a second SSH exec that can fail. Failing OPEN — assuming a
    // feed because the kind usually has one — is the mistake the whole
    // render-off-features rule exists to prevent.
    await tester.pumpWidget(
      _app(_live([_session('oc1', const BridgeRcKind.opencode())])),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('machine-watch-oc1')), findsNothing);
    expect(find.byKey(const ValueKey('machine-kill-oc1')), findsOneWidget);
  });

  testWidgets('the action row weights Watch over the terminal over delete', (
    tester,
  ) async {
    // The shipped row drifted from the reviewed design: an unlabelled eye in a
    // plain box, a terminal pill EXPANDED to fill the row (which reads as the
    // primary action), and a filled red delete box (the loudest thing on a card
    // you are usually only reading). This pins the intended weighting.
    await tester.pumpWidget(
      _app(
        _live([_session('oc1', const BridgeRcKind.opencode())], caps: _caps),
      ),
    );
    await tester.pumpAndSettle();

    // Watch is LABELLED — an unlabelled eye is a guess.
    expect(find.text('Watch'), findsOneWidget);
    expect(find.byKey(const ValueKey('machine-watch-oc1')), findsOneWidget);
    // The terminal is present on a machine card too, which is how a kind with
    // no feed has any way in at all.
    expect(find.byKey(const ValueKey('machine-open-oc1')), findsOneWidget);

    final watch = tester.getRect(
      find.byKey(const ValueKey('machine-watch-oc1')),
    );
    final open = tester.getRect(find.byKey(const ValueKey('machine-open-oc1')));
    final del = tester.getRect(find.byKey(const ValueKey('machine-kill-oc1')));

    // Reading order: Watch, then terminal, then delete at the far edge.
    expect(watch.left, lessThan(open.left));
    expect(open.right, lessThan(del.left));
    // The terminal does NOT fill the row — a full-width button reads as the
    // primary one, and Watch is.
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
              'cl1',
              const BridgeRcKind.claudeRc(),
              url: 'https://claude.ai/code/session_x',
            ),
          ], caps: _caps),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('machine-url-copy-cl1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('machine-url-open-cl1')),
        findsOneWidget,
      );
      // And a kind with no URL is not given empty buttons.
      expect(find.byKey(const ValueKey('machine-url-copy-oc1')), findsNothing);
    },
  );

  testWidgets('the list offers nothing that steers a session', (tester) async {
    // The regression this guards is the shipped-then-reverted design: Steer and
    // Interrupt sat on the card, so the only way to use them was blind.
    await tester.pumpWidget(
      _app(
        _live([_session('oc1', const BridgeRcKind.opencode())], caps: _caps),
      ),
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
