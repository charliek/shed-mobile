import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/app/mobile_scaffold.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/servers/server_record.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

void main() {
  testWidgets('bottom bar has Hosts/Sheds/Sessions and no System tab', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        // No saved hosts → the Hosts tab renders its empty state, no network.
        overrides: [serversProvider.overrideWith((ref) => <ServerRecord>[])],
        child: MaterialApp(theme: shedLightTheme, home: const MobileScaffold()),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('nav-hosts')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-sheds')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-sessions')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-system')), findsNothing);
  });
}
