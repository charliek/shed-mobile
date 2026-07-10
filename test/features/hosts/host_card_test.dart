import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/hosts/host_card.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/servers/server_record.dart';
import 'package:shed_mobile/servers/server_store.dart';
import 'package:shed_mobile/shed/shed_dtos.dart';
import 'package:shed_mobile/storage/secret_store.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

const _rec = ServerRecord(
  name: 'h',
  host: 'h.example',
  sshPort: 2222,
  apiUrl: 'https://h.example:8443',
  tlsCertFingerprint: 'sha256:x',
  hostKeyPin: 'pin',
);

const _usage = SystemDiskUsage(
  serverName: 'h',
  backend: 'vz',
  totals: DiskTotals(
    images: DiskSize(physicalBytes: 1323184128), // 1.23 GB
    sheds: DiskSize(physicalBytes: 6615306240),
    snapshots: DiskSize(),
    orphans: DiskSize(),
    all: DiskSize(physicalBytes: 14506430464), // 13.51 GB
  ),
);

const _twoSheds = [
  OverviewShed(
    shed: Shed(name: 'a', status: 'running', backend: 'vz'),
    sessions: [],
  ),
  OverviewShed(
    shed: Shed(name: 'b', status: 'stopped'),
    sessions: [],
  ),
];

/// A whole-host overview with a df block + two sheds, as the served result.
OverviewResult _overview({SystemDiskUsage? df = _usage}) => OverviewData(
  Overview(
    server: const OverviewServer(version: '1', features: []),
    df: df,
    sheds: _twoSheds,
    warnings: const [],
  ),
);

Future<void> _pump(
  WidgetTester tester, {
  required bool mobile,
  required Future<OverviewResult> Function(Ref, String) overview,
  VoidCallback? onOpen,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      // Disable Riverpod 3 auto-retry so an errored overview settles to a stable
      // error the card renders (rather than being retried into perpetual loading).
      retry: (_, _) => null,
      overrides: [overviewProvider.overrideWith(overview)],
      child: MaterialApp(
        theme: shedLightTheme,
        home: Scaffold(
          body: HostCard(record: _rec, mobile: mobile, onOpen: onOpen),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('overview data: total, badge, breakdown, running summary', (
    tester,
  ) async {
    await _pump(tester, mobile: true, overview: (_, _) async => _overview());
    expect(find.byKey(const ValueKey('host-card-h')), findsOneWidget);
    expect(find.text('h'), findsOneWidget);
    expect(find.text('vz'), findsOneWidget); // runtime badge
    expect(find.text('13.51 GB'), findsOneWidget); // total
    expect(find.text('1.23 GB'), findsOneWidget); // images
    expect(find.text('IMAGES'), findsOneWidget);
    expect(find.text('2 sheds · 1 running'), findsOneWidget);
    expect(find.byKey(const ValueKey('server-remove-h')), findsOneWidget);
  });

  testWidgets('df block degraded but sheds ok: reachable, disk unavailable, '
      'badge falls back to a shed backend', (tester) async {
    await _pump(
      tester,
      mobile: true,
      overview: (_, _) async => _overview(df: null),
    );
    // Reachable (not the error key) — a missing df block alone isn't unreachable.
    expect(find.byKey(const ValueKey('host-card-h')), findsOneWidget);
    expect(find.text('unavailable'), findsOneWidget);
    expect(find.text('vz'), findsOneWidget); // fell back to shed 'a' backend
    expect(find.text('2 sheds · 1 running'), findsOneWidget);
  });

  testWidgets('overview error: unreachable, and delete is still available', (
    tester,
  ) async {
    await _pump(
      tester,
      mobile: true,
      overview: (_, _) async => throw StateError('offline'),
    );
    expect(find.byKey(const ValueKey('host-card-error-h')), findsOneWidget);
    expect(find.text('Unreachable'), findsOneWidget);
    // Removal must survive an offline host.
    expect(find.byKey(const ValueKey('server-remove-h')), findsOneWidget);
  });

  testWidgets('an old server (the terminal OverviewUnsupported value) shows '
      '"Needs upgrade"', (tester) async {
    await _pump(
      tester,
      mobile: true,
      overview: (_, _) async => const OverviewUnsupported(),
    );
    expect(find.byKey(const ValueKey('host-card-error-h')), findsOneWidget);
    expect(find.text('Needs upgrade'), findsOneWidget);
    expect(find.byKey(const ValueKey('server-remove-h')), findsOneWidget);
  });

  testWidgets('overview loading: shows Loading…', (tester) async {
    await _pump(
      tester,
      mobile: true,
      overview: (_, _) => Completer<OverviewResult>().future, // never resolves
    );
    expect(find.text('Loading…'), findsOneWidget);
  });

  testWidgets('mobile card taps through to onOpen', (tester) async {
    var opened = false;
    await _pump(
      tester,
      mobile: true,
      overview: (_, _) async => _overview(),
      onOpen: () => opened = true,
    );
    await tester.tap(find.text('h'));
    expect(opened, isTrue);
  });

  testWidgets('desktop variant: own delete key, no drill-in', (tester) async {
    await _pump(tester, mobile: false, overview: (_, _) async => _overview());
    expect(
      find.byKey(const ValueKey('desktop-server-remove-h')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('server-remove-h')), findsNothing);
  });

  testWidgets('tapping delete removes the host without a disposed-Ref crash', (
    tester,
  ) async {
    final store = ServerStore(InMemorySecretStore());
    await store.add(_rec);
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          serverStoreProvider.overrideWithValue(store),
          overviewProvider.overrideWith((_, _) async => _overview()),
        ],
        child: MaterialApp(
          theme: shedLightTheme,
          home: const Scaffold(body: HostCard(record: _rec, mobile: true)),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('server-remove-h')));
    await tester.pumpAndSettle();
    expect(await store.list(), isEmpty); // the host is gone
    expect(tester.takeException(), isNull); // no disposed-Ref throw
  });
}
