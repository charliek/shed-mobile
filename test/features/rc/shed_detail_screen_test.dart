import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/rc/shed_detail_screen.dart';
import 'package:shed_mobile/machines/machine_feed.dart';
import 'package:shed_mobile/machines/machine_record.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

/// The screen renders one shed's ROOST TABS (plan 022 S6), read off the shed's
/// feed — so these tests hand it a [MachineFeedState] rather than stubbing an
/// SSH `shed-ext-rc list`.
const _origin = 'shed:h/web';

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
  attention: false,
  displayName: displayName,
  kind: kind,
  state: state,
  url: url,
  managed: true,
);

MachineFeedState _state({
  List<BridgeRcSession> sessions = const [],
  bool reachable = true,
  bool connectedOnce = true,
  String? detail,
}) => MachineFeedState(
  machine: const MachineRecord(name: _origin, host: 'h', user: 'web'),
  sessions: sessions,
  reachable: reachable,
  connectedOnce: connectedOnce,
  detail: detail,
  capabilities: null,
);

/// Pump [ShedDetailScreen] against a stubbed shed feed. `null` [state] leaves
/// the feed stream pending, which is the "still connecting" branch.
Future<void> _pump(
  WidgetTester tester, {
  MachineFeedState? state,
  Object? startError,
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
        machineFeedProvider(_origin).overrideWith(
          (ref) => startError != null
              ? Stream<MachineFeedState>.error(startError)
              : state == null
              ? const Stream<MachineFeedState>.empty()
              : Stream.value(state),
        ),
      ],
      child: MaterialApp(
        theme: shedLightTheme,
        home: const ShedDetailScreen(serverName: 'h', shedName: 'web'),
      ),
    ),
  );
  // Bounded pumps settle the feed stream without hanging on a pulsing activity
  // animation (a plain pumpAndSettle would spin).
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets('renders each roost tab as the shared SessionCard '
      '(identity keyed)', (tester) async {
    await _pump(
      tester,
      state: _state(
        sessions: [
          _session(slug: 'aaa'),
          _session(slug: 'bbb'),
        ],
      ),
    );
    expect(find.byKey(const ValueKey('all-session-h-web-aaa')), findsOneWidget);
    expect(find.byKey(const ValueKey('all-session-h-web-bbb')), findsOneWidget);
    // The retired per-shed keys are gone.
    expect(find.byKey(const ValueKey('rc-session-aaa')), findsNothing);
    expect(find.byKey(const ValueKey('rc-terminal-aaa')), findsNothing);
  });

  testWidgets('claude row with a url shows url-copy and url-open', (
    tester,
  ) async {
    await _pump(
      tester,
      state: _state(sessions: [_session(url: 'https://claude.ai/login/xyz')]),
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

  testWidgets('an unreachable shed keeps its last-known rows rather than '
      'blanking or erroring', (tester) async {
    await _pump(
      tester,
      state: _state(
        sessions: [_session(slug: 'aaa')],
        reachable: false,
        detail: 'no roost session on this shed',
      ),
    );
    expect(find.byKey(const ValueKey('all-session-h-web-aaa')), findsOneWidget);
    // There is no error branch on this screen at all — unreachable is a state,
    // not a failure.
    expect(find.byKey(const ValueKey('rc-error')), findsNothing);
    expect(find.byKey(const ValueKey('rc-empty')), findsNothing);
  });

  testWidgets('an unreachable shed with NO rows says why, verbatim', (
    tester,
  ) async {
    await _pump(
      tester,
      state: _state(reachable: false, detail: 'no roost session on this shed'),
    );
    expect(find.byKey(const ValueKey('rc-empty')), findsOneWidget);
    // The feed's own reason, not a flattened "unreachable": "no roost session"
    // and "this device's key is not authorized" have different fixes.
    expect(find.text('no roost session on this shed'), findsOneWidget);
  });

  testWidgets('a reachable shed with no tabs says so', (tester) async {
    await _pump(tester, state: _state());
    expect(find.byKey(const ValueKey('rc-empty')), findsOneWidget);
    expect(find.text('No sessions'), findsOneWidget);
  });

  testWidgets('a feed that could not START says why, instead of spinning '
      'forever', (tester) async {
    // The failures that land here happen BEFORE MachineFeed.start() can turn
    // them into an unreachable row — a missing SSH identity, a server store
    // that will not open. Reading only `.value` collapsed them to null, which
    // this screen renders as a spinner indistinguishable from "still loading".
    await _pump(tester, startError: 'no usable SSH identity');
    await tester.pump();
    expect(find.byKey(const ValueKey('feed-start-failure')), findsOneWidget);
    // Verbatim: the reason string is the only thing naming the actual cause.
    expect(find.textContaining('no usable SSH identity'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
