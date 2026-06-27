import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/main.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/storage/secret_store.dart';

void main() {
  testWidgets('home renders the (empty) servers screen', (tester) async {
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
    expect(find.byKey(const ValueKey('servers-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('servers-add')), findsOneWidget);
  });
}
