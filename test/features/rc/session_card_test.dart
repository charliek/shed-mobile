import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/rc/session_card.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/rc/activity_overlay.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';
import 'package:shed_mobile/src/rust/api/watcher.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

const _session = BridgeRcSession(
  host: 'h',
  shed: 'web',
  slug: 'abc123',
  tmuxSession: 'rc-abc123',
  displayName: 'frontend',
  kind: BridgeRcKind.claudeRc(),
  state: BridgeRcState.ready,
  managed: true,
);

BridgeRcCapabilities _capsWithCodexWatch() => const BridgeRcCapabilities(
  rcVersion: 3,
  kinds: [],
  agents: {},
  features: [],
  kindFeatures: {
    'codex': BridgeRcKindFeatures(
      postInput: true,
      approvals: 'tui',
      watch: true,
      input: 'gated',
    ),
  },
);

Future<void> _pump(
  WidgetTester tester,
  double width, {
  BridgeRcSession session = _session,
  bool live = false,
  BridgeRcCapabilities? caps,
  ActivityOverlay? overlay,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        shedCapabilitiesProvider.overrideWith((ref, key) async => caps),
        if (overlay != null)
          liveActivityProvider.overrideWith(
            (ref, name) => Stream.value(overlay),
          ),
      ],
      child: MaterialApp(
        theme: shedLightTheme,
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: Scaffold(
            body: SessionCard(
              serverName: 'h',
              shedName: 'web',
              session: session,
              live: live,
            ),
          ),
        ),
      ),
    ),
  );
  // Bounded pumps settle the async caps/overlay providers; a plain pumpAndSettle
  // would hang on a pulsing "working" activity dot (a repeating animation).
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// A one-entry overlay for `(shed, slug)` — the bridge already folded it, so the
/// test hands the delivered [BridgeOverlayEntry] snapshot straight in.
ActivityOverlay _overlay({
  String shed = 'web',
  String slug = 'abc123',
  BridgeRcActivity? activity,
  BridgeRcState? state,
  String? lastMessage,
}) => ActivityOverlay([
  BridgeOverlayEntry(
    shed: shed,
    slug: slug,
    activity: activity,
    state: state,
    lastMessage: lastMessage,
  ),
]);

void main() {
  testWidgets('desktop: open/delete actions, name, kind chip, status badge', (
    tester,
  ) async {
    await _pump(tester, 1100);
    expect(
      find.byKey(const ValueKey('all-session-open-h-web-abc123')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('all-session-delete-h-web-abc123')),
      findsOneWidget,
    );
    expect(find.text('frontend'), findsOneWidget); // displayName
    expect(find.text('claude-rc'), findsOneWidget); // kind chip (kind.wire)
    expect(find.text('ready'), findsOneWidget); // status badge (state.wire)
  });

  testWidgets('mobile: still has open + delete (both layouts carry them)', (
    tester,
  ) async {
    await _pump(tester, 400);
    expect(
      find.byKey(const ValueKey('all-session-open-h-web-abc123')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('all-session-delete-h-web-abc123')),
      findsOneWidget,
    );
  });

  testWidgets('activity badge + last-message render for a ready session', (
    tester,
  ) async {
    await _pump(
      tester,
      400,
      session: const BridgeRcSession(
        host: 'h',
        shed: 'web',
        slug: 'abc123',
        tmuxSession: 'rc-abc123',
        displayName: 'frontend',
        kind: BridgeRcKind.codex(),
        state: BridgeRcState.ready,
        managed: true,
        activity: BridgeRcActivity.working,
        lastMessage: 'Running the test suite now.',
      ),
    );
    expect(
      find.byKey(const ValueKey('all-session-activity-h-web-abc123')),
      findsOneWidget,
    );
    expect(find.text('working'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('all-session-lastmsg-h-web-abc123')),
      findsOneWidget,
    );
    expect(find.text('Running the test suite now.'), findsOneWidget);
  });

  testWidgets('lifecycle trumps activity: needs-auth hides the activity badge '
      'AND the last-message line (whole-dimension suppression)', (
    tester,
  ) async {
    await _pump(
      tester,
      400,
      session: const BridgeRcSession(
        host: 'h',
        shed: 'web',
        slug: 'abc123',
        tmuxSession: 'rc-abc123',
        displayName: 'frontend',
        kind: BridgeRcKind.codex(),
        state: BridgeRcState.needsAuth,
        managed: true,
        activity: BridgeRcActivity.working, // present but must be suppressed
        lastMessage: 'stale pre-gate context', // suppressed alongside it
      ),
    );
    expect(
      find.byKey(const ValueKey('all-session-activity-h-web-abc123')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('all-session-lastmsg-h-web-abc123')),
      findsNothing,
    );
    // The lifecycle badge still shows (needs auth).
    expect(find.text('needs auth'), findsOneWidget);
  });

  const codex = BridgeRcSession(
    host: 'h',
    shed: 'web',
    slug: 'abc123',
    tmuxSession: 'rc-abc123',
    displayName: 'frontend',
    kind: BridgeRcKind.codex(),
    state: BridgeRcState.ready,
    managed: true,
  );

  testWidgets('no watch button when caps do not advertise the feed', (
    tester,
  ) async {
    await _pump(tester, 400, session: codex); // caps null
    expect(
      find.byKey(const ValueKey('all-session-watch-h-web-abc123')),
      findsNothing,
    );
  });

  testWidgets('watch button appears when caps advertise the codex feed', (
    tester,
  ) async {
    await _pump(tester, 400, session: codex, caps: _capsWithCodexWatch());
    expect(
      find.byKey(const ValueKey('all-session-watch-h-web-abc123')),
      findsOneWidget,
    );
  });

  testWidgets('live overlay supersedes the base snapshot activity AND the '
      'last-message subtitle', (tester) async {
    // Base says idle + an old preview; the folded overlay says needs_input with
    // a fresh preview → the badge AND the subtitle show the live values.
    await _pump(
      tester,
      400,
      live: true,
      overlay: _overlay(
        activity: BridgeRcActivity.needsInput,
        state: BridgeRcState.ready,
        lastMessage: 'fresh live preview',
      ),
      session: const BridgeRcSession(
        host: 'h',
        shed: 'web',
        slug: 'abc123',
        tmuxSession: 'rc-abc123',
        displayName: 'frontend',
        kind: BridgeRcKind.codex(),
        state: BridgeRcState.ready,
        managed: true,
        activity: BridgeRcActivity.idle,
        lastMessage: 'stale overview preview',
      ),
    );
    expect(find.text('needs input'), findsOneWidget);
    expect(find.text('idle'), findsNothing);
    expect(find.text('fresh live preview'), findsOneWidget);
    expect(find.text('stale overview preview'), findsNothing);
  });
}
