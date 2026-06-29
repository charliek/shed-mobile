import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/system/system_card.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/shed/shed_dtos.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

const _usage = SystemDiskUsage(
  serverName: 'h',
  backend: 'vz',
  totals: DiskTotals(
    images: DiskSize(physicalBytes: 1323184128), // 1.23 GB
    sheds: DiskSize(physicalBytes: 6615306240), // 6.16 GB
    snapshots: DiskSize(),
    orphans: DiskSize(),
    all: DiskSize(physicalBytes: 14506430464), // 13.51 GB
  ),
);

Future<void> _pump(
  WidgetTester tester,
  Future<SystemDiskUsage> Function(Ref ref, String name) df,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [hostSystemDfProvider.overrideWith(df)],
      child: MaterialApp(
        theme: shedLightTheme,
        home: const Scaffold(body: SystemCard(serverName: 'h')),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('renders total + the four-bucket breakdown with the badge', (
    tester,
  ) async {
    await _pump(tester, (ref, name) async => _usage);
    expect(find.byKey(const ValueKey('system-host-h')), findsOneWidget);
    expect(find.text('vz'), findsOneWidget); // runtime badge
    expect(find.text('13.51 GB'), findsOneWidget); // total
    expect(find.text('1.23 GB'), findsOneWidget); // images
    expect(find.text('IMAGES'), findsOneWidget);
    expect(find.text('SNAPSHOTS'), findsOneWidget);
    expect(find.text('Zero KB'), findsWidgets); // snapshots + orphans
  });

  testWidgets('an old/unreachable agent shows the unavailable state', (
    tester,
  ) async {
    await _pump(tester, (ref, name) async => throw StateError('no df'));
    expect(find.byKey(const ValueKey('system-host-error-h')), findsOneWidget);
    expect(find.text('unavailable'), findsOneWidget);
  });
}
