import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/rc/create_rc_screen.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

/// Build a bridge capabilities block from wire kind strings + installed tools.
BridgeRcCapabilities _caps({
  required List<String> kinds,
  Map<String, bool> installed = const {},
}) => BridgeRcCapabilities(
  rcVersion: 3,
  kinds: [
    for (final k in kinds)
      switch (k) {
        'claude-rc' => const BridgeRcKind.claudeRc(),
        'codex' => const BridgeRcKind.codex(),
        'opencode' => const BridgeRcKind.opencode(),
        'cursor' => const BridgeRcKind.cursor(),
        'shell' => const BridgeRcKind.shell(),
        _ => BridgeRcKind.other(raw: k),
      },
  ],
  agents: {
    for (final e in installed.entries)
      e.key: BridgeRcAgentInfo(installed: e.value),
  },
  features: const [],
  kindFeatures: const {},
);

Future<void> _pump(
  WidgetTester tester,
  Future<BridgeRcCapabilities?> Function() caps,
) async {
  await tester.binding.setSurfaceSize(const Size(500, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        shedCapabilitiesProvider.overrideWith((ref, key) async => caps()),
      ],
      child: MaterialApp(
        theme: shedLightTheme,
        home: const CreateRcScreen(serverName: 'h', shedName: 'proj'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('absent capabilities → claude + shell only (the safe base)', (
    tester,
  ) async {
    await _pump(tester, () async => null);
    expect(
      find.byKey(const ValueKey('createrc-kind-claude-rc')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('createrc-kind-shell')), findsOneWidget);
    // No new-agent chips and no claude-broker chip when caps are absent.
    expect(find.byKey(const ValueKey('createrc-kind-codex')), findsNothing);
    expect(
      find.byKey(const ValueKey('createrc-kind-claude-broker')),
      findsNothing,
    );
    // The old "codex-rc · soon" placeholder is gone.
    expect(find.textContaining('soon'), findsNothing);
  });

  testWidgets('capabilities with installed agents → their chips appear', (
    tester,
  ) async {
    await _pump(
      tester,
      () async => _caps(
        kinds: ['claude-rc', 'codex', 'opencode', 'cursor', 'shell'],
        installed: {
          'claude': true,
          'codex': true,
          'cursor': true,
          'opencode': false,
        },
      ),
    );
    expect(
      find.byKey(const ValueKey('createrc-kind-claude-rc')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('createrc-kind-codex')), findsOneWidget);
    expect(find.byKey(const ValueKey('createrc-kind-cursor')), findsOneWidget);
    expect(find.byKey(const ValueKey('createrc-kind-shell')), findsOneWidget);
    // opencode advertised but NOT installed → gated out.
    expect(find.byKey(const ValueKey('createrc-kind-opencode')), findsNothing);
  });

  testWidgets('selecting codex hides the claude-only permission dropdown', (
    tester,
  ) async {
    await _pump(
      tester,
      () async => _caps(
        kinds: ['claude-rc', 'codex', 'shell'],
        installed: {'claude': true, 'codex': true},
      ),
    );
    // claude-rc is the default selection → the permission dropdown shows.
    expect(
      find.byKey(const ValueKey('createrc-permission-mode')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('createrc-kind-codex')));
    await tester.pumpAndSettle();
    // codex is not a claude kind → no permission dropdown.
    expect(
      find.byKey(const ValueKey('createrc-permission-mode')),
      findsNothing,
    );
    // codex accepts a prompt.
    expect(find.byKey(const ValueKey('createrc-prompt')), findsOneWidget);
  });

  testWidgets(
    'absent capabilities: the permission dropdown excludes the NEW generic '
    '"skip" (an old binary rejects it) but keeps the historical claude set',
    (tester) async {
      await _pump(tester, () async => null);
      await tester.tap(find.byKey(const ValueKey('createrc-permission-mode')));
      await tester.pumpAndSettle();
      expect(find.text('skip'), findsNothing);
      // Historical modes stay offered (parity with the shipped app).
      expect(find.text('bypassPermissions'), findsOneWidget);
      expect(find.text('plan'), findsOneWidget);
    },
  );

  testWidgets(
    'present capabilities: the full permission set including "skip" is offered',
    (tester) async {
      await _pump(
        tester,
        () async =>
            _caps(kinds: ['claude-rc', 'shell'], installed: {'claude': true}),
      );
      await tester.tap(find.byKey(const ValueKey('createrc-permission-mode')));
      await tester.pumpAndSettle();
      expect(find.text('skip'), findsOneWidget);
      expect(find.text('bypassPermissions'), findsOneWidget);
    },
  );

  testWidgets('present-but-empty capabilities → no kinds, create disabled', (
    tester,
  ) async {
    await _pump(tester, () async => _caps(kinds: const []));
    expect(find.byKey(const ValueKey('createrc-no-kinds')), findsOneWidget);
    expect(find.byKey(const ValueKey('createrc-kind-claude-rc')), findsNothing);
    // Create is disabled when there is nothing to create.
    final button = tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const ValueKey('createrc-submit')),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
  });
}
