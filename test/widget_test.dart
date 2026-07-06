import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/main.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/storage/secret_store.dart';

void main() {
  testWidgets('home renders the (empty) Hosts screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secretStoreProvider.overrideWithValue(InMemorySecretStore()),
        ],
        child: const ShedMobileApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('servers-screen')), findsOneWidget);
    // The merged Hosts body is HostGroups, whose empty state keys `hosts-empty`.
    expect(find.byKey(const ValueKey('hosts-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('servers-add')), findsOneWidget);
  });
}
