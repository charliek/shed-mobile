import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/core/url_launch.dart';
import 'package:shed_mobile/features/rc/session_card.dart';
import 'package:shed_mobile/machines/machine_feed.dart';
import 'package:shed_mobile/machines/machine_record.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/src/rust/api/dto_lane.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';
import 'package:shed_mobile/theme/shed_theme.dart';
import 'package:url_launcher/url_launcher.dart';

/// The shed card renders a ROOST TAB now (plan 022 S6): everything it shows
/// comes off the shed's feed state, so these tests build one rather than
/// overriding a capabilities future and an activity stream.
const _origin = 'shed:h/web';

const _session = BridgeRcSession(
  host: 'h',
  shed: 'web',
  slug: 'abc123',
  attention: false,
  displayName: 'frontend',
  kind: BridgeRcKind.claudeRc(),
  state: BridgeRcState.ready,
  managed: true,
  // Every roost row carries roost's own tab id, so the default fixture does
  // too — the peek addresses the tab by it. `attentionSession` below is the
  // deliberate no-tab-id case.
  tabId: 4,
);

/// A capability block whose only row is `claude-rc`, with [attach] and
/// [feed]/[watch] as given — the ceiling the card reads for its attach
/// affordance (and deliberately NOT for the transcript pill).
BridgeRcCapabilities _caps(
  String kind, {
  // `native-remote`, not `tmux`: after S6 `roost_capabilities()` is the only
  // producer and every kind it publishes says `native-remote`. A `tmux`
  // default here would model a producer that no longer exists.
  String attach = 'native-remote',
  bool watch = false,
  String feed = 'activity',
}) => BridgeRcCapabilities(
  rcVersion: 2,
  kinds: const [],
  agents: const {},
  features: const [],
  kindFeatures: {
    kind: BridgeRcKindFeatures(
      postInput: false,
      approvals: 'none',
      watch: watch,
      input: '',
      feed: feed,
      interrupt: false,
      attach: attach,
    ),
  },
);

MachineFeedState _state({
  required BridgeRcSession session,
  BridgeRcCapabilities? caps,
  MachinePatch? patch,
  bool reachable = true,
}) => MachineFeedState(
  machine: const MachineRecord(name: _origin, host: 'h', user: 'web'),
  sessions: [session],
  overlay: patch == null ? const {} : {session.slug: patch},
  reachable: reachable,
  connectedOnce: true,
  capabilities: caps,
);

Future<void> _pump(
  WidgetTester tester,
  double width, {
  BridgeRcSession session = _session,
  BridgeRcCapabilities? caps,
  MachinePatch? patch,
  bool reachable = true,
  UrlLauncher? urlLauncher,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // The card only reads the feed CONTROLLER to kill a row; nothing in
        // these tests taps delete, and an unoverridden controller would try to
        // open a real SSH connection.
        identitiesProvider.overrideWith((ref) async => <SSHKeyPair>[]),
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
              state: _state(
                session: session,
                caps: caps,
                patch: patch,
                reachable: reachable,
              ),
              urlLauncher: urlLauncher,
            ),
          ),
        ),
      ),
    ),
  );
  // Bounded pumps settle the widget tree; a plain pumpAndSettle would hang on a
  // pulsing "working" activity dot (a repeating animation).
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets('desktop: peek/delete actions, name, kind chip, status badge', (
    tester,
  ) async {
    await _pump(tester, 1100, caps: _caps('claude-rc'));
    expect(
      find.byKey(const ValueKey('all-session-peek-h-web-abc123')),
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

  testWidgets('mobile: still has peek + delete (both layouts carry them)', (
    tester,
  ) async {
    await _pump(tester, 400, caps: _caps('claude-rc'));
    expect(
      find.byKey(const ValueKey('all-session-peek-h-web-abc123')),
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
        attention: false,
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
        attention: false,
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
    attention: false,
    displayName: 'frontend',
    kind: BridgeRcKind.codex(),
    state: BridgeRcState.ready,
    managed: true,
  );

  testWidgets('no transcript pill when the row carries no agent lane', (
    tester,
  ) async {
    await _pump(tester, 400, session: codex);
    expect(
      find.byKey(const ValueKey('all-session-lane-h-web-abc123')),
      findsNothing,
    );
  });

  testWidgets('the transcript pill is gated on the ROW\'s lane stamp, never on '
      'the kind ceiling', (tester) async {
    // The ceiling says this kind HAS a message feed (`feed: "messages"`,
    // `watch: true`) — which is exactly what `roost_kind_features` answers for
    // opencode/gx — and the row still carries no stamp. A card that read the
    // ceiling would offer a transcript that `laneControllerProvider` refuses.
    await _pump(
      tester,
      400,
      session: codex,
      caps: _caps('codex', watch: true, feed: 'messages'),
    );
    expect(
      find.byKey(const ValueKey('all-session-lane-h-web-abc123')),
      findsNothing,
    );
    // Negative control: the row DID render.
    expect(
      find.byKey(const ValueKey('all-session-delete-h-web-abc123')),
      findsOneWidget,
    );
  });

  testWidgets('the transcript pill appears for a row that carries a stamp', (
    tester,
  ) async {
    await _pump(
      tester,
      400,
      session: const BridgeRcSession(
        host: 'h',
        shed: 'web',
        slug: 'abc123',
        attention: false,
        displayName: 'frontend',
        kind: BridgeRcKind.opencode(),
        state: BridgeRcState.ready,
        managed: true,
        agentLane: BridgeAgentLaneStamp(
          kind: 'opencode',
          sessionId: 'ses_abc',
          serverUrl: 'http://127.0.0.1:4096',
        ),
      ),
      // The ceiling says nothing useful here on purpose: the stamp is the
      // whole condition.
      caps: _caps('opencode'),
    );
    expect(
      find.byKey(const ValueKey('all-session-lane-h-web-abc123')),
      findsOneWidget,
    );
  });

  testWidgets('a live feed patch supersedes the base snapshot activity', (
    tester,
  ) async {
    // The snapshot says idle; the feed's folded patch says needs_input → the
    // badge shows the live value.
    await _pump(
      tester,
      400,
      patch: const MachinePatch(
        activity: BridgeRcActivity.needsInput,
        state: BridgeRcState.ready,
      ),
      session: const BridgeRcSession(
        host: 'h',
        shed: 'web',
        slug: 'abc123',
        attention: false,
        displayName: 'frontend',
        kind: BridgeRcKind.codex(),
        state: BridgeRcState.ready,
        managed: true,
        activity: BridgeRcActivity.idle,
      ),
    );
    expect(find.text('needs input'), findsOneWidget);
    expect(find.text('idle'), findsNothing);
  });

  // ---- attach gating + attention dot -----------------------------------------

  const attentionSession = BridgeRcSession(
    host: 'h',
    shed: 'web',
    slug: 'abc123',
    attention: true,
    displayName: 'frontend',
    kind: BridgeRcKind.claudeRc(),
    state: BridgeRcState.ready,
    managed: true,
  );

  testWidgets('attention dot present when the session carries attention', (
    tester,
  ) async {
    await _pump(tester, 400, session: attentionSession);
    expect(
      find.byKey(const ValueKey('all-session-attention-h-web-abc123')),
      findsOneWidget,
    );
  });

  testWidgets('attention dot absent when the session carries none '
      '(negative control against the row rendering at all)', (tester) async {
    await _pump(tester, 400); // _session has attention: false
    expect(
      find.byKey(const ValueKey('all-session-attention-h-web-abc123')),
      findsNothing,
    );
    // The row DID render — the absence above is about `attention`, not an
    // empty screen. Anchored on the display name, which every row shows
    // whatever its attach affordance turns out to be.
    expect(find.text('frontend'), findsOneWidget);
  });

  testWidgets('a native-remote row offers the PEEK, not the xterm attach — '
      'this is every roost row', (tester) async {
    await _pump(
      tester,
      400,
      session: const BridgeRcSession(
        host: 'h',
        shed: 'web',
        slug: 'abc123',
        attention: false,
        displayName: 'frontend',
        kind: BridgeRcKind.claudeRc(),
        state: BridgeRcState.ready,
        managed: true,
        tabId: 4,
      ),
      caps: _caps('claude-rc', attach: 'native-remote'),
    );
    expect(
      find.byKey(const ValueKey('all-session-peek-h-web-abc123')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('all-session-open-h-web-abc123')),
      findsNothing,
    );
  });

  testWidgets('an UNKNOWN kind offers NEITHER affordance — roost\'s own '
      '`manual`/`legacy` tabs land here', (tester) async {
    // roost's `ownership.source` is an open string, so shed maps anything it
    // does not know to `RcKind::Other` and documents the policy as "renders
    // the raw kind with no affordances". Such a row misses `kindFeatures`
    // entirely, so the card reads `attachKind(null)`.
    await _pump(
      tester,
      400,
      // Capabilities that know a DIFFERENT kind: this is the real shape, not
      // a null-capability stand-in — the map exists, this row is just not in it.
      caps: _caps('codex'),
    );
    expect(
      find.byKey(const ValueKey('all-session-peek-h-web-abc123')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('all-session-open-h-web-abc123')),
      findsNothing,
    );
    // The row still rendered — the absence above is about affordances.
    expect(find.text('frontend'), findsOneWidget);
  });

  testWidgets('a native-remote row with no tab id offers NEITHER — the peek '
      'addresses the tab by roost\'s own id', (tester) async {
    await _pump(
      tester,
      400,
      session: attentionSession, // tabId: null
      caps: _caps('claude-rc', attach: 'native-remote'),
    );
    expect(
      find.byKey(const ValueKey('all-session-peek-h-web-abc123')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('all-session-open-h-web-abc123')),
      findsNothing,
    );
    // Negative control: the row still rendered — delete is still there.
    expect(
      find.byKey(const ValueKey('all-session-delete-h-web-abc123')),
      findsOneWidget,
    );
  });

  // ---- claude URL actions ----------------------------------------------------

  const sessionUrl = 'https://claude.ai/login/xyz';
  const urlSession = BridgeRcSession(
    host: 'h',
    shed: 'web',
    slug: 'abc123',
    attention: false,
    displayName: 'frontend',
    kind: BridgeRcKind.claudeRc(),
    state: BridgeRcState.ready,
    managed: true,
    url: sessionUrl,
  );

  testWidgets('url copy/open actions absent when the session has no url', (
    tester,
  ) async {
    await _pump(tester, 400); // _session has url == null
    expect(
      find.byKey(const ValueKey('all-session-url-copy-h-web-abc123')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('all-session-url-open-h-web-abc123')),
      findsNothing,
    );
  });

  testWidgets('url copy/open actions present when the session carries a url '
      '(both layouts)', (tester) async {
    for (final width in const [1100.0, 400.0]) {
      await _pump(tester, width, session: urlSession);
      expect(
        find.byKey(const ValueKey('all-session-url-copy-h-web-abc123')),
        findsOneWidget,
        reason: 'copy @ $width',
      );
      expect(
        find.byKey(const ValueKey('all-session-url-open-h-web-abc123')),
        findsOneWidget,
        reason: 'open @ $width',
      );
    }
  });

  testWidgets('tapping url-copy places the exact URL on the clipboard', (
    tester,
  ) async {
    String? copied;
    // Intercept the platform clipboard channel so the copy is observable without
    // a real platform.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _pump(tester, 400, session: urlSession);
    await tester.tap(
      find.byKey(const ValueKey('all-session-url-copy-h-web-abc123')),
    );
    await tester.pump();
    expect(copied, sessionUrl);
    // The confirmation snackbar shows.
    expect(find.text('URL copied'), findsOneWidget);
  });

  testWidgets('tapping url-open invokes the injected launcher with the URL '
      'as an http(s) Uri in external mode', (tester) async {
    Uri? launched;
    LaunchMode? launchedMode;
    Future<bool> recordingLauncher(
      Uri url, {
      LaunchMode mode = LaunchMode.platformDefault,
    }) {
      launched = url;
      launchedMode = mode;
      return Future.value(true);
    }

    await _pump(
      tester,
      400,
      session: urlSession,
      urlLauncher: recordingLauncher,
    );
    await tester.tap(
      find.byKey(const ValueKey('all-session-url-open-h-web-abc123')),
    );
    await tester.pump();
    await tester.pump();
    expect(launched, Uri.parse(sessionUrl));
    expect(launchedMode, LaunchMode.externalApplication);
  });

  testWidgets('url-open failure (launcher returns false) shows a snackbar', (
    tester,
  ) async {
    Future<bool> fake(
      Uri url, {
      LaunchMode mode = LaunchMode.platformDefault,
    }) => Future.value(false);
    await _pump(tester, 400, session: urlSession, urlLauncher: fake);
    await tester.tap(
      find.byKey(const ValueKey('all-session-url-open-h-web-abc123')),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Could not open URL'), findsOneWidget);
  });
}
