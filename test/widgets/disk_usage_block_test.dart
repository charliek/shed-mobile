import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/src/rust/api/dto.dart';
import 'package:shed_mobile/theme/shed_theme.dart';
import 'package:shed_mobile/widgets/disk_usage_block.dart';

const _totals = BridgeDiskTotals(
  images: BridgeDiskSize(logicalBytes: 0, physicalBytes: 1323184128), // 1.23 GB
  sheds: BridgeDiskSize(logicalBytes: 0, physicalBytes: 6615306240), // 6.16 GB
  snapshots: BridgeDiskSize(logicalBytes: 0, physicalBytes: 0),
  orphans: BridgeDiskSize(logicalBytes: 0, physicalBytes: 0),
  all: BridgeDiskSize(logicalBytes: 0, physicalBytes: 14506430464),
);

Future<void> _pump(WidgetTester tester, BridgeDiskTotals totals) =>
    tester.pumpWidget(
      MaterialApp(
        theme: shedLightTheme,
        home: Scaffold(body: DiskUsageBlock(totals)),
      ),
    );

void main() {
  testWidgets('renders the four labelled buckets with physical sizes', (
    tester,
  ) async {
    await _pump(tester, _totals);
    // Labels (uppercased).
    expect(find.text('IMAGES'), findsOneWidget);
    expect(find.text('SHEDS'), findsOneWidget);
    expect(find.text('SNAPSHOTS'), findsOneWidget);
    expect(find.text('ORPHANS'), findsOneWidget);
    // Sizes (formatBytes).
    expect(find.text('1.23 GB'), findsOneWidget); // images
    expect(find.text('6.16 GB'), findsOneWidget); // sheds
    expect(find.text('Zero KB'), findsWidgets); // snapshots + orphans (0)
  });
}
