import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/sheds/shed_card.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/src/rust/api/dto.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

import 'fake_shed_client.dart';

/// Records route pushes so a test can assert whether a tap navigated. The initial
/// route counts as one push, so callers compare against a captured baseline.
class _PushSpy extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
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

Future<void> _pump(
  WidgetTester tester, {
  required BridgeShed shed,
  required double width,
  FakeShedClient? client,
  double textScale = 1.0,
  List<NavigatorObserver> observers = const [],
  bool overrideSessions = false,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final fake = client ?? FakeShedClient();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        shedClientProvider('h').overrideWith((ref) async => fake),
        // So a whole-card tap can push ShedDetailScreen (which watches
        // rcSessionsProvider) without a real client — it renders empty.
        if (overrideSessions)
          rcSessionsProvider((
            serverName: 'h',
            shedName: 'web',
          )).overrideWith((ref) async => <BridgeRcSession>[]),
      ],
      child: MaterialApp(
        theme: shedLightTheme,
        navigatorObservers: observers,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            textScaler: TextScaler.linear(textScale),
          ),
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

Finder _k(String key) => find.byKey(ValueKey(key));

void main() {
  // ---- action matrix (running vs stopped × desktop vs mobile) --------------

  for (final width in const [1100.0, 400.0]) {
    final surface = width >= 900 ? 'desktop' : 'mobile';

    testWidgets('$surface: a running shed shows open/restart/stop/delete', (
      tester,
    ) async {
      await _pump(tester, shed: _running, width: width);
      expect(_k('all-shed-open-h-web'), findsOneWidget);
      expect(_k('all-shed-restart-h-web'), findsOneWidget);
      expect(_k('all-shed-stop-h-web'), findsOneWidget);
      expect(_k('all-shed-delete-h-web'), findsOneWidget);
      expect(_k('all-shed-start-h-web'), findsNothing);
      // The retired per-host `_ShedTile` keys are gone.
      expect(_k('shed-web'), findsNothing);
      expect(_k('shed-start-web'), findsNothing);
      expect(_k('shed-stop-web'), findsNothing);
      expect(_k('shed-delete-web'), findsNothing);
    });

    testWidgets('$surface: a stopped shed shows open/start/delete, no '
        'restart/stop', (tester) async {
      await _pump(tester, shed: _stopped, width: width);
      expect(_k('all-shed-open-h-db'), findsOneWidget);
      expect(_k('all-shed-start-h-db'), findsOneWidget);
      expect(_k('all-shed-delete-h-db'), findsOneWidget);
      expect(_k('all-shed-restart-h-db'), findsNothing);
      expect(_k('all-shed-stop-h-db'), findsNothing);
      expect(_k('shed-start-db'), findsNothing);
      expect(_k('shed-delete-db'), findsNothing);
    });
  }

  // ---- textual status label -------------------------------------------------

  testWidgets('a textual status label is present (running)', (tester) async {
    await _pump(tester, shed: _running, width: 400);
    expect(_k('all-shed-status-h-web'), findsOneWidget);
    expect(find.text('running'), findsOneWidget);
  });

  testWidgets('a textual status label is present (stopped)', (tester) async {
    await _pump(tester, shed: _stopped, width: 400);
    expect(_k('all-shed-status-h-db'), findsOneWidget);
    expect(find.text('stopped'), findsOneWidget);
  });

  // ---- delete confirm -------------------------------------------------------

  testWidgets('delete shows a confirm dialog; Cancel does NOT delete', (
    tester,
  ) async {
    final client = FakeShedClient();
    await _pump(tester, shed: _running, width: 1100, client: client);
    await tester.tap(_k('all-shed-delete-h-web'));
    await tester.pumpAndSettle();
    expect(_k('shed-delete-confirm'), findsOneWidget);
    expect(find.text('Delete web?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(_k('shed-delete-confirm'), findsNothing);
    expect(client.deletes, 0);
  });

  testWidgets('confirming delete calls client.delete(name) exactly once', (
    tester,
  ) async {
    final client = FakeShedClient();
    await _pump(tester, shed: _running, width: 1100, client: client);
    await tester.tap(_k('all-shed-delete-h-web'));
    await tester.pumpAndSettle();
    await tester.tap(_k('shed-delete-confirm'));
    await tester.pumpAndSettle();
    expect(client.calls, ['delete:web']);
    expect(client.deletes, 1);
  });

  testWidgets('a barrier dismiss does NOT delete', (tester) async {
    final client = FakeShedClient();
    await _pump(tester, shed: _running, width: 1100, client: client);
    await tester.tap(_k('all-shed-delete-h-web'));
    await tester.pumpAndSettle();
    // Tap the modal barrier (top-left, well outside the dialog) to dismiss.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(_k('shed-delete-confirm'), findsNothing);
    expect(client.deletes, 0);
  });

  testWidgets('double-tapping delete stacks only ONE dialog / one delete', (
    tester,
  ) async {
    final client = FakeShedClient();
    await _pump(tester, shed: _running, width: 1100, client: client);
    // Two taps fired back-to-back with NO pump between (raw gestures don't pump,
    // so the first dialog's modal barrier isn't laid out yet). Only the
    // _confirming guard — set synchronously before the dialog await — can stop
    // the second tap from opening a second dialog.
    final at = tester.getCenter(_k('all-shed-delete-h-web'));
    await (await tester.startGesture(at)).up();
    await (await tester.startGesture(at)).up();
    await tester.pumpAndSettle();
    expect(_k('shed-delete-confirm'), findsOneWidget);

    await tester.tap(_k('shed-delete-confirm'));
    await tester.pumpAndSettle();
    expect(client.deletes, 1);
  });

  // ---- restart = stop then start -------------------------------------------

  testWidgets('restart calls stop then start, once each', (tester) async {
    final client = FakeShedClient();
    await _pump(tester, shed: _running, width: 1100, client: client);
    await tester.tap(_k('all-shed-restart-h-web'));
    await tester.pumpAndSettle();
    expect(client.calls, ['stop:web', 'start:web']);
    expect(client.stops, 1);
    expect(client.starts, 1);
    expect(client.deletes, 0);
  });

  // ---- mobile: card tap navigates, action tap does not ---------------------

  testWidgets('mobile: a whole-card tap pushes ShedDetailScreen', (
    tester,
  ) async {
    final spy = _PushSpy();
    await _pump(
      tester,
      shed: _running,
      width: 400,
      observers: [spy],
      overrideSessions: true,
    );
    final baseline = spy.pushes;
    // Tap the status label — inside the card's InkWell but not on a button.
    await tester.tap(_k('all-shed-status-h-web'));
    await tester.pumpAndSettle();
    expect(spy.pushes, baseline + 1);
    expect(find.byKey(const ValueKey('rc-screen')), findsOneWidget);
  });

  testWidgets('mobile: a tap on an action button does NOT navigate', (
    tester,
  ) async {
    final client = FakeShedClient();
    final spy = _PushSpy();
    await _pump(
      tester,
      shed: _running,
      width: 400,
      client: client,
      observers: [spy],
      overrideSessions: true,
    );
    final baseline = spy.pushes;
    await tester.tap(_k('all-shed-stop-h-web'));
    await tester.pumpAndSettle();
    // The button won the gesture (stop ran) and the card did not navigate.
    expect(client.stops, 1);
    expect(spy.pushes, baseline);
    expect(find.byKey(const ValueKey('rc-screen')), findsNothing);
  });

  // ---- no RenderFlex overflow ----------------------------------------------

  for (final width in const [320.0, 360.0]) {
    for (final scale in const [1.0, 1.6]) {
      testWidgets(
        'no overflow @ ${width}px scale=$scale — running (4 actions)',
        (tester) async {
          await _pump(tester, shed: _running, width: width, textScale: scale);
          expect(tester.takeException(), isNull);
          expect(_k('all-shed-delete-h-web'), findsOneWidget);
        },
      );

      testWidgets(
        'no overflow @ ${width}px scale=$scale — stopped (3 actions)',
        (tester) async {
          await _pump(tester, shed: _stopped, width: width, textScale: scale);
          expect(tester.takeException(), isNull);
          expect(_k('all-shed-delete-h-db'), findsOneWidget);
        },
      );
    }
  }
}
