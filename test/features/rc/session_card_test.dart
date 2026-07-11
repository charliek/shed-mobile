import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/rc/session_card.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/rc/rc_capabilities.dart';
import 'package:shed_mobile/rc/rc_events.dart';
import 'package:shed_mobile/rc/rc_models.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

const _session = RcSession(
  slug: 'abc123',
  tmuxSession: 'rc-abc123',
  displayName: 'frontend',
  kind: RcKind.claudeRc,
  state: RcState.ready,
  managed: true,
);

RcCapabilities _capsWithCodexWatch() => RcCapabilities.fromJson(const {
  'rc_version': 3,
  'kind_features': {
    'codex': {
      'post_input': true,
      'approvals': 'tui',
      'watch': true,
      'input': 'gated',
    },
  },
});

Future<void> _pump(
  WidgetTester tester,
  double width, {
  RcSession session = _session,
  bool live = false,
  RcCapabilities? caps,
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
      session: const RcSession(
        slug: 'abc123',
        tmuxSession: 'rc-abc123',
        displayName: 'frontend',
        kind: RcKind.codex,
        state: RcState.ready,
        managed: true,
        activity: RcActivity.working,
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
      session: const RcSession(
        slug: 'abc123',
        tmuxSession: 'rc-abc123',
        displayName: 'frontend',
        kind: RcKind.codex,
        state: RcState.needsAuth,
        managed: true,
        activity: RcActivity.working, // present but must be suppressed
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

  const codex = RcSession(
    slug: 'abc123',
    tmuxSession: 'rc-abc123',
    displayName: 'frontend',
    kind: RcKind.codex,
    state: RcState.ready,
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

  testWidgets('live overlay supersedes the base snapshot activity', (
    tester,
  ) async {
    // Base says idle; the SSE overlay says needs_input → the badge shows the
    // live value.
    final overlay = ActivityOverlay.empty.apply(
      const RcActivityChanged(
        shed: 'web',
        slug: 'abc123',
        activity: RcActivity.needsInput,
        state: RcState.ready,
      ),
    );
    await _pump(
      tester,
      400,
      live: true,
      overlay: overlay,
      session: const RcSession(
        slug: 'abc123',
        tmuxSession: 'rc-abc123',
        displayName: 'frontend',
        kind: RcKind.codex,
        state: RcState.ready,
        managed: true,
        activity: RcActivity.idle,
      ),
    );
    expect(find.text('needs input'), findsOneWidget);
    expect(find.text('idle'), findsNothing);
  });
}
