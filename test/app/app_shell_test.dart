import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/app/app_shell.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/servers/server_record.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

Future<void> _pumpAtWidth(WidgetTester tester, double width) async {
  // Size the real test surface so AppShell's root LayoutBuilder sees this width
  // (a SizedBox would be clamped to the default 800px surface).
  await tester.binding.setSurfaceSize(Size(width, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      // No saved servers → the shell renders empty states with no network.
      overrides: [serversProvider.overrideWith((ref) => <ServerRecord>[])],
      child: MaterialApp(theme: shedLightTheme, home: const AppShell()),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('renders the mobile shell just below the 900px breakpoint', (
    tester,
  ) async {
    await _pumpAtWidth(tester, 899);
    expect(find.byKey(const ValueKey('shell-mobile')), findsOneWidget);
    expect(find.byKey(const ValueKey('shell-desktop')), findsNothing);
  });

  testWidgets('renders the desktop shell at the 900px breakpoint', (
    tester,
  ) async {
    await _pumpAtWidth(tester, 900);
    expect(find.byKey(const ValueKey('shell-desktop')), findsOneWidget);
    expect(find.byKey(const ValueKey('shell-mobile')), findsNothing);
  });
}
