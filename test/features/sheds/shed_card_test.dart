import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/sheds/shed_card.dart';
import 'package:shed_mobile/src/rust/api/dto.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

Future<void> _pump(
  WidgetTester tester, {
  required BridgeShed shed,
  required double width,
}) async {
  // Real estate to avoid overflow, plus an explicit MediaQuery so the card's
  // `MediaQuery.sizeOf` desktop check sees this width.
  await tester.binding.setSurfaceSize(Size(width, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: shedLightTheme,
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: Scaffold(
            body: ShedCard(
              key: ValueKey('all-shed-h-${shed.name}'),
              serverName: 'h',
              shed: shed,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

const _running = BridgeShed(
  host: 'h',
  name: 'web',
  status: BridgeShedStatus.running,
  backend: 'vz',
  image: 'img:v1',
  cpus: 2,
  memoryMb: 4096,
  activeNamespaces: [],
);
const _stopped = BridgeShed(
  host: 'h',
  name: 'db',
  status: BridgeShedStatus.stopped,
  activeNamespaces: [],
);

void main() {
  testWidgets('desktop: a running shed shows open/restart/stop, not start', (
    tester,
  ) async {
    await _pump(tester, shed: _running, width: 1100);
    expect(find.byKey(const ValueKey('all-shed-open-h-web')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('all-shed-restart-h-web')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('all-shed-stop-h-web')), findsOneWidget);
    expect(find.byKey(const ValueKey('all-shed-start-h-web')), findsNothing);
    expect(find.text('vz'), findsOneWidget); // runtime badge
  });

  testWidgets('desktop: a stopped shed shows start, not restart/stop', (
    tester,
  ) async {
    await _pump(tester, shed: _stopped, width: 1100);
    expect(find.byKey(const ValueKey('all-shed-start-h-db')), findsOneWidget);
    expect(find.byKey(const ValueKey('all-shed-restart-h-db')), findsNothing);
    expect(find.byKey(const ValueKey('all-shed-stop-h-db')), findsNothing);
  });

  testWidgets('mobile: a tappable card with no inline action buttons', (
    tester,
  ) async {
    await _pump(tester, shed: _running, width: 400);
    expect(find.byKey(const ValueKey('all-shed-h-web')), findsOneWidget);
    // Inline actions are desktop-only; mobile drills via the card tap.
    expect(find.byKey(const ValueKey('all-shed-restart-h-web')), findsNothing);
    expect(find.byKey(const ValueKey('all-shed-open-h-web')), findsNothing);
  });
}
