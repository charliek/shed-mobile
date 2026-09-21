import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/rc/all_sessions_view.dart';
import 'package:shed_mobile/machines/machine_feed.dart';
import 'package:shed_mobile/machines/machine_record.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/servers/server_record.dart';
import 'package:shed_mobile/src/rust/api/dto.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

/// The gap between the two "your server is too old" thresholds.
///
/// A server with no `/api/overview` at all already gets a terminal upgrade
/// banner (`all-sessions-needs-upgrade-*`). A 0.8.x server HAS the route, so it
/// returns `OverviewData` and lands on the normal path — but its agent sessions
/// came from the RC hub, which plan 022/S6 deleted on this side. Without this
/// wiring the shed group renders "no roost session on this shed", which names a
/// repair that cannot work.
const _server = ServerRecord(
  name: 'h',
  host: 'h',
  sshPort: 22,
  apiUrl: 'https://h:8080',
  tlsCertFingerprint: '',
  hostKeyPin: '',
);

const _shed = BridgeShed(
  host: 'h',
  name: 'web',
  status: BridgeShedStatus.running,
  activeNamespaces: [],
);

const _legacySession = BridgeRcSession(
  host: 'h',
  shed: 'web',
  slug: 'abc123',
  attention: false,
  displayName: 'frontend',
  kind: BridgeRcKind.claudeRc(),
  state: BridgeRcState.ready,
  managed: true,
);

BridgeOverview _overview({required bool withLegacySessions}) => BridgeOverview(
  server: const BridgeOverviewServer(version: '0.8.2', features: []),
  sheds: [
    BridgeOverviewShed(
      shed: _shed,
      sessions: withLegacySessions ? const [_legacySession] : const [],
    ),
  ],
  warnings: const [],
);

Future<void> _pump(
  WidgetTester tester, {
  required bool withLegacySessions,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        serversProvider.overrideWith((ref) => const <ServerRecord>[_server]),
        machinesProvider.overrideWith((ref) async => const <MachineRecord>[]),
        overviewProvider('h').overrideWith(
          (ref) async =>
              OverviewData(_overview(withLegacySessions: withLegacySessions)),
        ),
        // The shed's own roost feed: reachable, and genuinely empty. Against a
        // 0.9.0 server this is the ordinary "no sessions" case.
        machineFeedProvider('shed:h/web').overrideWith(
          (ref) => Stream.value(
            const MachineFeedState(
              machine: MachineRecord(name: 'shed:h/web', host: 'h'),
              sessions: [],
              overlay: {},
              reachable: false,
              connectedOnce: true,
              detail: 'no roost session on this shed',
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
}

void main() {
  testWidgets('a 0.8.x server is named as the cause, not the shed', (
    tester,
  ) async {
    await _pump(tester, withLegacySessions: true);
    expect(find.textContaining('predates 0.9.0'), findsOneWidget);
    expect(
      find.textContaining('no roost session'),
      findsNothing,
      reason: 'that is the 0.9.0 advice; this server cannot act on it',
    );
  });

  testWidgets('a 0.9.0 server still gets the ordinary roost reason', (
    tester,
  ) async {
    // The other half of the wiring: an empty `sessions` list must NOT be read
    // as "old server", or every modern shed would claim to need an upgrade.
    await _pump(tester, withLegacySessions: false);
    expect(find.textContaining('no roost session'), findsOneWidget);
    expect(find.textContaining('predates 0.9.0'), findsNothing);
  });
}
