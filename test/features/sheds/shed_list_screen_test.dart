import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/sheds/shed_list_screen.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/src/rust/api/dto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

import 'fake_shed_client.dart';

const _web = BridgeShed(
  host: 'h',
  name: 'web',
  status: BridgeShedStatus.running,
  backend: 'vz',
  activeNamespaces: [],
);
const _db = BridgeShed(
  host: 'h',
  name: 'db',
  status: BridgeShedStatus.stopped,
  activeNamespaces: [],
);

Future<void> _pump(
  WidgetTester tester, {
  required FakeShedClient client,
  double width = 400,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [shedClientProvider('h').overrideWith((ref) async => client)],
      child: MaterialApp(
        theme: shedLightTheme,
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 900)),
          child: const ShedListScreen(serverName: 'h'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _k(String key) => find.byKey(ValueKey(key));

void main() {
  testWidgets('renders one shared ShedCard per shed with all-shed-* keys', (
    tester,
  ) async {
    await _pump(tester, client: FakeShedClient(sheds: const [_web, _db]));
    // The screen shell.
    expect(_k('sheds-screen'), findsOneWidget);
    expect(_k('sheds-refresh'), findsOneWidget);
    expect(_k('sheds-create'), findsOneWidget);

    // One shared ShedCard per shed (identity keys), with its action set.
    expect(_k('all-shed-h-web'), findsOneWidget);
    expect(_k('all-shed-h-db'), findsOneWidget);
    expect(_k('all-shed-delete-h-web'), findsOneWidget);
    expect(_k('all-shed-stop-h-web'), findsOneWidget);
    expect(_k('all-shed-start-h-db'), findsOneWidget);

    // The retired per-host `_ShedTile` keys are gone.
    expect(_k('shed-web'), findsNothing);
    expect(_k('shed-stop-web'), findsNothing);
    expect(_k('shed-delete-web'), findsNothing);
  });

  testWidgets('empty server shows the empty state', (tester) async {
    await _pump(tester, client: FakeShedClient(sheds: const []));
    expect(_k('sheds-empty'), findsOneWidget);
  });

  testWidgets('delete on the per-host list confirms, deletes, and re-fetches '
      '(invalidateShedViews)', (tester) async {
    final client = FakeShedClient(sheds: const [_web]);
    await _pump(tester, client: client);
    expect(client.listShedsCalls, 1); // initial fetch

    await tester.tap(_k('all-shed-delete-h-web'));
    await tester.pumpAndSettle();
    expect(_k('shed-delete-confirm'), findsOneWidget);

    await tester.tap(_k('shed-delete-confirm'));
    await tester.pumpAndSettle();

    expect(client.deletes, 1);
    expect(client.calls, contains('delete:web'));
    // invalidateShedViews invalidated shedsProvider → the watched list
    // re-fetched over the same client.
    expect(client.listShedsCalls, greaterThan(1));
  });
}
