import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/machines/machines_section.dart';
import 'package:shed_mobile/features/servers/server_list_screen.dart';
import 'package:shed_mobile/machines/machine_feed.dart';
import 'package:shed_mobile/machines/machine_record.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/servers/server_record.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

const _mini2 = MachineRecord(name: 'mini2', host: 'mini2.example');
const _mini3 = MachineRecord(name: 'mini3', host: 'mini3.example');
const _sleepy = MachineRecord(name: 'sleepy', host: 'sleepy.example');

const _host = ServerRecord(
  name: 'h',
  host: 'h.example',
  sshPort: 2222,
  apiUrl: 'https://h.example:8443',
  tlsCertFingerprint: 'sha256:x',
  hostKeyPin: 'pin',
);

/// A feed state with no live parts — enough to render and rank a row.
MachineFeedState _state(
  MachineRecord m, {
  bool reachable = false,
  bool connectedOnce = false,
  String? detail,
}) => MachineFeedState(
  machine: m,
  reachable: reachable,
  connectedOnce: connectedOnce,
  detail: detail,
);

Widget _app(
  List<MachineRecord> machines,
  Map<String, MachineFeedState> states, {
  List<ServerRecord> hosts = const [],
}) => ProviderScope(
  // Riverpod 3 auto-retry off: an errored overview must SETTLE to an error the
  // host card renders, rather than being retried into perpetual loading (which
  // is a `pumpAndSettle` timeout, not a test result).
  retry: (_, _) => null,
  overrides: [
    serversProvider.overrideWith((ref) => hosts),
    // These tests are about the tab's SECTION STRUCTURE, not the host card's
    // internals; an unreachable host is the cheapest state that settles.
    overviewProvider.overrideWith((ref, name) => throw StateError('offline')),
    machinesProvider.overrideWith((ref) async => machines),
    for (final m in machines)
      machineFeedProvider(m.name).overrideWith(
        (ref) => Stream.value(states[m.name] ?? _state(m)),
      ),
  ],
  child: MaterialApp(
    theme: shedLightTheme,
    home: const ServerListScreen(),
  ),
);

void main() {
  testWidgets(
    'the Hosts tab renders shed servers and machines as two sibling sections',
    (tester) async {
      await tester.pumpWidget(
        _app(
          const [_mini3],
          {'mini3': _state(_mini3, reachable: true, connectedOnce: true)},
          hosts: const [_host],
        ),
      );
      await tester.pumpAndSettle();

      // Both headers, in order — the user's model is "sheds first, machines
      // second", and a machine section that renders above the hosts would read
      // as the primary thing.
      expect(find.text('SHED SERVERS'), findsOneWidget);
      expect(find.text('MACHINES (1)'), findsOneWidget);
      final servers = tester.getTopLeft(find.text('SHED SERVERS')).dy;
      final machines = tester.getTopLeft(find.text('MACHINES (1)')).dy;
      expect(servers, lessThan(machines), reason: 'machines must come second');
    },
  );

  testWidgets('machines still render when there are no hosts at all', (
    tester,
  ) async {
    // The regression this guards: a page-sized "No hosts yet" empty state took
    // the whole body, so a user with zero hosts and two machines saw NO
    // machines — and no way to add one.
    await tester.pumpWidget(
      _app(const [_mini2, _mini3], {
        'mini2': _state(_mini2, reachable: true, connectedOnce: true),
        'mini3': _state(_mini3, reachable: true, connectedOnce: true),
      }),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('hosts-empty')), findsOneWidget);
    expect(find.text('MACHINES (2)'), findsOneWidget);
    expect(find.text('mini2'), findsOneWidget);
    expect(find.text('mini3'), findsOneWidget);
    // …including the affordance to add one.
    expect(find.byKey(const ValueKey('machines-add')), findsOneWidget);
  });

  testWidgets('healthy machines sort above connecting, and connecting above '
      'offline', (tester) async {
    await tester.pumpWidget(
      _app(
        // Deliberately supplied worst-first, so passing means the sort ran and
        // not that the input order happened to be right.
        const [_sleepy, _mini2, _mini3],
        {
          // Reached once, gone now → offline, the bottom band.
          'sleepy': _state(_sleepy, connectedOnce: true, detail: 'no route'),
          // Never reached → still connecting, the middle band.
          'mini2': _state(_mini2),
          'mini3': _state(_mini3, reachable: true, connectedOnce: true),
        },
      ),
    );
    await tester.pumpAndSettle();

    double y(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(y('mini3'), lessThan(y('mini2')), reason: 'reachable sorts first');
    expect(y('mini2'), lessThan(y('sleepy')), reason: 'offline sorts last');
  });

  testWidgets('an offline machine shows a word, with the reason beside it', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const [_sleepy], {
        'sleepy': _state(
          _sleepy,
          connectedOnce: true,
          detail: 'nothing is listening on 1029',
        ),
      }),
    );
    await tester.pumpAndSettle();

    // The badge is a clean word; the raw reason is available but never the
    // headline — "unreachable" is what you scan, the detail is what you read.
    expect(
      find.byKey(const ValueKey('machine-card-status-sleepy')),
      findsOneWidget,
    );
    expect(find.text('unreachable'), findsOneWidget);
    expect(
      find.textContaining('nothing is listening on 1029'),
      findsOneWidget,
      reason: 'the reason must survive to the card',
    );
  });

  testWidgets('with no machines the section is a quiet line, not a page', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const [], const {}, hosts: const [_host]));
    await tester.pumpAndSettle();

    expect(find.text('MACHINES'), findsOneWidget);
    expect(find.byKey(const ValueKey('machines-empty')), findsOneWidget);
    // No count suffix when there is nothing to count.
    expect(find.text('MACHINES (0)'), findsNothing);
    expect(find.byType(MachinesSection), findsOneWidget);
  });
}
