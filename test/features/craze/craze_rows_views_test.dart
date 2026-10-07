import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/machines/machine_sessions_view.dart';
import 'package:shed_mobile/features/rc/shed_detail_screen.dart';
import 'package:shed_mobile/features/rc/shed_session_group.dart';
import 'package:shed_mobile/machines/machine_feed.dart';
import 'package:shed_mobile/machines/machine_record.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/src/rust/api/craze.dart';
import 'package:shed_mobile/src/rust/api/dto_lane.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

/// **All three session views render a machine's MERGED rows** (plan 025
/// §3.7.2): the machine group, a shed's group in the cross-host list, and a
/// shed's own screen.
///
/// The state below is what the feed emits for a machine running one craze
/// session inside a roost tab (tab 7, owned `(craze, ses-x)`) beside an
/// opencode tab (8): the merge folded tab 7 into the hub row, so the rows are
/// tab 8 and the craze session — which carries tab 7 as its own. A view that
/// read `state.sessions` instead would show tab 7 as a roost row and no craze
/// session at all, which is exactly what each cell checks for.
const _host = 'cccccccccccc';

const _mini3 = MachineRecord(name: 'mini3', host: 'mini3.example');
const _shedOrigin = 'shed:h/web';

BridgeRcSession _tab(int tabId, BridgeRcKind kind, {String? rcId}) =>
    BridgeRcSession(
      host: '',
      shed: '',
      slug: '$tabId',
      displayName: 'tab$tabId',
      kind: kind,
      state: BridgeRcState.ready,
      managed: true,
      attention: false,
      tabId: tabId,
      rcId: rcId,
    );

const _hubRow = BridgeLaneSession(
  id: _host,
  title: 'craze work',
  cwd: '/w/proj',
  activity: BridgeRcActivity.needsApproval,
  pendingApprovals: 1,
  approximate: false,
  provider: 'grok',
  model: 'grok-4',
  doing: 'reading the tests',
  headAskSummary: 'run the suite?',
  attached: 2,
  providerSessionId: 'ses-x',
);

MachineFeedState _state(MachineRecord machine, {bool live = true}) {
  final craze = BridgeCrazeSnapshot(
    rows: const [_hubRow],
    live: live,
    truncated: false,
  );
  return MachineFeedState(
    machine: machine,
    reachable: true,
    connectedOnce: true,
    sessions: [
      _tab(7, const BridgeRcKind.craze(), rcId: 'ses-x'),
      _tab(8, const BridgeRcKind.opencode()),
    ],
    craze: craze,
    // What the feed's fold answered (live: tab 7 absorbed into the hub row).
    foldedRows: live
        ? [
            MachineRow.roost(_tab(8, const BridgeRcKind.opencode())),
            const MachineRow.craze(session: _hubRow, tabId: 7, stale: false),
          ]
        : null,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required String origin,
  required MachineFeedState state,
  required Widget home,
  List<MachineRecord> machines = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        machinesProvider.overrideWith((ref) async => machines),
        machineFeedProvider(origin).overrideWith((ref) => Stream.value(state)),
      ],
      child: MaterialApp(theme: shedLightTheme, home: home),
    ),
  );
  // Bounded pumps: a pulsing activity badge never settles.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// The craze card's facts, and its tab's terminal actions — by the TAB's id.
void _expectCrazeCard(String suffix) {
  final key = '$suffix-$_host';
  expect(find.byKey(ValueKey('craze-row-$key')), findsOneWidget);
  expect(find.text('craze work'), findsOneWidget);
  expect(find.text('reading the tests'), findsOneWidget);
  expect(find.text('needs you (1): run the suite?'), findsOneWidget);
  final meta = _textOf(find.byKey(ValueKey('craze-meta-$key')));
  expect(meta, contains('grok · grok-4'));
  expect(meta, contains('2 attached'));
  expect(find.byKey(ValueKey('craze-lane-$key')), findsOneWidget);
  expect(find.byKey(ValueKey('craze-peek-$key')), findsOneWidget);
  expect(find.byKey(ValueKey('craze-end-tab-$key')), findsOneWidget);
}

String _textOf(Finder finder) =>
    (finder.evaluate().single.widget as Text).data ?? '';

void main() {
  testWidgets('the MACHINE group renders the merged rows: one craze row, '
      'its tab folded in', (tester) async {
    await _pump(
      tester,
      origin: 'mini3',
      state: _state(_mini3),
      machines: const [_mini3],
      home: const Scaffold(
        body: SingleChildScrollView(child: MachineSessionsView()),
      ),
    );
    _expectCrazeCard('mini3');
    expect(
      find.byKey(const ValueKey('machine-meta-mini3-8')),
      findsOneWidget,
      reason: 'the opencode tab is still a roost row',
    );
    expect(
      find.byKey(const ValueKey('machine-meta-mini3-7')),
      findsNothing,
      reason: 'the craze tab is the hub row now, not a roost row of its own',
    );
  });

  testWidgets(
    'a SHED\'s group in the cross-host list renders the merged rows',
    (tester) async {
      await _pump(
        tester,
        origin: _shedOrigin,
        state: _state(
          const MachineRecord(name: _shedOrigin, host: 'h', user: 'web'),
        ),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: ShedSessionGroup(serverName: 'h', shedName: 'web'),
          ),
        ),
      );
      _expectCrazeCard('h-web');
      expect(find.byKey(const ValueKey('all-session-h-web-8')), findsOneWidget);
      expect(find.byKey(const ValueKey('all-session-h-web-7')), findsNothing);
    },
  );

  testWidgets('a shed\'s own SCREEN renders the merged rows, and counts them', (
    tester,
  ) async {
    await _pump(
      tester,
      origin: _shedOrigin,
      state: _state(
        const MachineRecord(name: _shedOrigin, host: 'h', user: 'web'),
      ),
      home: const ShedDetailScreen(serverName: 'h', shedName: 'web'),
    );
    _expectCrazeCard('h-web');
    expect(find.byKey(const ValueKey('all-session-h-web-8')), findsOneWidget);
    expect(find.byKey(const ValueKey('all-session-h-web-7')), findsNothing);
  });

  testWidgets('a feed that is not live shows the craze row LAST KNOWN, and '
      'roost\'s tab stands alone', (tester) async {
    await _pump(
      tester,
      origin: 'mini3',
      state: _state(_mini3, live: false),
      machines: const [_mini3],
      home: const Scaffold(
        body: SingleChildScrollView(child: MachineSessionsView()),
      ),
    );
    final meta = _textOf(find.byKey(const ValueKey('craze-meta-mini3-$_host')));
    expect(meta, contains('last known'));
    expect(
      find.byKey(const ValueKey('craze-end-tab-mini3-$_host')),
      findsNothing,
      reason: 'nothing is absorbed while the feed is down',
    );
    expect(find.byKey(const ValueKey('machine-meta-mini3-7')), findsOneWidget);
  });

  MachineFeedState offline(BridgeSourceOffline cause) => MachineFeedState(
    machine: _mini3,
    reachable: true,
    connectedOnce: true,
    craze: BridgeCrazeSnapshot(
      rows: const [],
      live: false,
      offline: BridgeCrazeOffline(cause: cause, reason: 'said'),
      truncated: false,
    ),
  );

  testWidgets('craze TOO OLD says so on the machine', (tester) async {
    await _pump(
      tester,
      origin: 'mini3',
      state: offline(const BridgeSourceOffline.tooOld()),
      machines: const [_mini3],
      home: const Scaffold(
        body: SingleChildScrollView(child: MachineSessionsView()),
      ),
    );
    expect(
      find.text('craze on this machine is too old for shed; update it'),
      findsOneWidget,
    );
  });

  testWidgets('craze NOT INSTALLED is quiet', (tester) async {
    await _pump(
      tester,
      origin: 'mini3',
      state: offline(const BridgeSourceOffline.notInstalled()),
      machines: const [_mini3],
      home: const Scaffold(
        body: SingleChildScrollView(child: MachineSessionsView()),
      ),
    );
    expect(
      find.byKey(const ValueKey('machine-craze-note-mini3')),
      findsNothing,
    );
  });
}
