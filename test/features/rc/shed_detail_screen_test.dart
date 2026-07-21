import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/rc/codex_watch_screen.dart';
import 'package:shed_mobile/features/rc/shed_detail_screen.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/rc/activity_overlay.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

BridgeRcSession _session({
  String slug = 'abc123',
  String displayName = 'frontend',
  BridgeRcKind kind = const BridgeRcKind.claudeRc(),
  BridgeRcState state = BridgeRcState.ready,
  String? url,
}) => BridgeRcSession(
  host: 'h',
  shed: 'web',
  slug: slug,
  tmuxSession: 'rc-$slug',
  displayName: displayName,
  kind: kind,
  state: state,
  url: url,
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

/// Pump [ShedDetailScreen] with the SSH session list stubbed via
/// [rcSessionsProvider]. Capabilities are supplied either directly (via [caps],
/// overriding [shedCapabilitiesProvider]) or — when [overviewErrors] — by making
/// the underlying [overviewProvider] throw so the real derivation is exercised
/// (the caps then resolve to an error, i.e. `null` at the card, and the eye
/// hides).
Future<void> _pump(
  WidgetTester tester, {
  required List<BridgeRcSession> sessions,
  BridgeRcCapabilities? caps,
  bool overviewErrors = false,
  double width = 900,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      // Disable Riverpod's auto-retry so a deliberately-erroring provider
      // doesn't leave a pending backoff timer at teardown.
      retry: (_, _) => null,
      overrides: [
        rcSessionsProvider.overrideWith((ref, key) async => sessions),
        if (overviewErrors)
          overviewProvider.overrideWith(
            (ref, name) async => throw Exception('overview boom'),
          )
        else
          shedCapabilitiesProvider.overrideWith((ref, key) async => caps),
        // Keep the codex-watch screen (pushed by the eye) off the native watcher.
        liveActivityProvider.overrideWith(
          (ref, name) => Stream<ActivityOverlay>.empty(),
        ),
      ],
      child: MaterialApp(
        theme: shedLightTheme,
        home: const ShedDetailScreen(serverName: 'h', shedName: 'web'),
      ),
    ),
  );
  // Bounded pumps settle the async session/caps providers without hanging on a
  // pulsing activity animation (a plain pumpAndSettle would spin).
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets('renders each SSH session as the shared SessionCard '
      '(identity keyed)', (tester) async {
    await _pump(
      tester,
      sessions: [
        _session(slug: 'aaa'),
        _session(slug: 'bbb'),
      ],
    );
    expect(find.byKey(const ValueKey('all-session-h-web-aaa')), findsOneWidget);
    expect(find.byKey(const ValueKey('all-session-h-web-bbb')), findsOneWidget);
    // The retired per-shed keys are gone.
    expect(find.byKey(const ValueKey('rc-session-aaa')), findsNothing);
    expect(find.byKey(const ValueKey('rc-terminal-aaa')), findsNothing);
  });

  testWidgets('codex row whose caps advertise watch shows the eye and tapping '
      'it pushes CodexWatchScreen', (tester) async {
    await _pump(
      tester,
      sessions: [_session(kind: const BridgeRcKind.codex())],
      caps: _capsWithCodexWatch(),
    );
    final eye = find.byKey(const ValueKey('all-session-watch-h-web-abc123'));
    expect(eye, findsOneWidget);

    await tester.tap(eye);
    await tester.pump(); // start the route push
    await tester.pump(const Duration(milliseconds: 350)); // finish transition
    expect(find.byType(CodexWatchScreen), findsOneWidget);
  });

  testWidgets('claude row with a url shows url-copy and url-open', (
    tester,
  ) async {
    await _pump(
      tester,
      sessions: [_session(url: 'https://claude.ai/login/xyz')],
    );
    expect(
      find.byKey(const ValueKey('all-session-url-copy-h-web-abc123')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('all-session-url-open-h-web-abc123')),
      findsOneWidget,
    );
  });

  testWidgets('an overview/caps error does NOT blank the SSH session list', (
    tester,
  ) async {
    await _pump(
      tester,
      sessions: [
        _session(slug: 'aaa'),
        _session(slug: 'bbb'),
      ],
      overviewErrors: true,
    );
    // The list still renders from rcSessionsProvider…
    expect(find.byKey(const ValueKey('all-session-h-web-aaa')), findsOneWidget);
    expect(find.byKey(const ValueKey('all-session-h-web-bbb')), findsOneWidget);
    // …and there is no error/empty state.
    expect(find.byKey(const ValueKey('rc-error')), findsNothing);
    expect(find.byKey(const ValueKey('rc-empty')), findsNothing);
    // The caps error just hides the watch eye.
    expect(
      find.byKey(const ValueKey('all-session-watch-h-web-aaa')),
      findsNothing,
    );
  });
}
