import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/rc/create_rc_screen.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/src/rust/api/dto.dart';
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

/// One shed row (the screen looks the target up by name inside the overview).
BridgeShed _shed(String name, BridgeShedStatus status) => BridgeShed(
  host: 'h',
  name: name,
  status: status,
  activeNamespaces: const [],
);

/// An [OverviewData] carrying a single shed with the given status + caps. The
/// shed defaults to the screen's target (`proj`, running) so tests only vary
/// what they care about; pass [shedName] `'other'` to model a missing target.
OverviewResult _data({
  String shedName = 'proj',
  BridgeShedStatus status = BridgeShedStatus.running,
  BridgeRcCapabilities? caps,
}) => OverviewData(
  BridgeOverview(
    server: const BridgeOverviewServer(version: '1', features: []),
    sheds: [
      BridgeOverviewShed(
        shed: _shed(shedName, status),
        sessions: const [],
        capabilities: caps,
      ),
    ],
    warnings: const [],
  ),
);

/// Present caps that offer claude-rc + codex + shell (all installed).
BridgeRcCapabilities _codexCaps() => _caps(
  kinds: ['claude-rc', 'codex', 'shell'],
  installed: {'claude': true, 'codex': true},
);

/// Present caps that offer only the base pair (claude-rc + shell).
BridgeRcCapabilities _baseCaps() =>
    _caps(kinds: ['claude-rc', 'shell'], installed: {'claude': true});

/// Pump [CreateRcScreen] with `overviewProvider('h')` driven by [build] — a
/// value → data, a thrown error → `AsyncError`, a never-completing future →
/// `AsyncLoading`. [build] re-runs on every (re)compute so a captured counter
/// can prove a Retry actually re-probes. Bounded pumps (never `pumpAndSettle`)
/// so a loading/error case can't hang; `retry:(_,_)=>null` stops Riverpod from
/// auto-retrying a thrown provider error.
Future<void> _pump(
  WidgetTester tester,
  FutureOr<OverviewResult> Function() build,
) async {
  await tester.binding.setSurfaceSize(const Size(500, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [overviewProvider.overrideWith((ref, name) async => build())],
      child: MaterialApp(
        theme: shedLightTheme,
        home: const CreateRcScreen(serverName: 'h', shedName: 'proj'),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Finder _kindChip(String wire) => find.byKey(ValueKey('createrc-kind-$wire'));

bool _submitEnabled(WidgetTester tester) {
  final button = tester.widget<FilledButton>(
    find.descendant(
      of: find.byKey(const ValueKey('createrc-submit')),
      matching: find.byType(FilledButton),
    ),
  );
  return button.onPressed != null;
}

void main() {
  testWidgets('loading → spinner, no kind chips, submit disabled', (
    tester,
  ) async {
    // A future that never completes → the screen stays in AsyncLoading.
    await _pump(tester, () => Completer<OverviewResult>().future);
    expect(find.byKey(const ValueKey('createrc-caps-loading')), findsOneWidget);
    // No premature base chips while we still don't know the offering.
    expect(_kindChip('claude-rc'), findsNothing);
    expect(_kindChip('shell'), findsNothing);
    expect(find.byKey(const ValueKey('createrc-caps-note')), findsNothing);
    expect(find.byKey(const ValueKey('createrc-caps-retry')), findsNothing);
    expect(_submitEnabled(tester), isFalse);
  });

  testWidgets(
    'error → Retry (no silent base chips); tapping it re-probes → present',
    (tester) async {
      var calls = 0;
      var present = false;
      await _pump(tester, () {
        calls++;
        if (!present) throw StateError('probe boom');
        return _data(caps: _codexCaps());
      });
      // Errored: NOT the silent claude+shell downgrade — a Retry instead.
      expect(calls, 1);
      expect(find.byKey(const ValueKey('createrc-caps-retry')), findsOneWidget);
      expect(_kindChip('claude-rc'), findsNothing);
      expect(_kindChip('shell'), findsNothing);
      expect(_kindChip('codex'), findsNothing);

      // Flip the source to a served overview, then Retry → the provider MUST
      // re-run (counter proves it) and the screen transitions to present.
      present = true;
      await tester.tap(find.byKey(const ValueKey('createrc-caps-retry')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(calls, 2);
      expect(_kindChip('codex'), findsOneWidget);
      expect(find.byKey(const ValueKey('createrc-caps-retry')), findsNothing);
    },
  );

  testWidgets('OverviewUnsupported → quiet base + non-retry note (no Retry)', (
    tester,
  ) async {
    await _pump(tester, () => const OverviewUnsupported());
    // Base kinds are correct here (an old server has no /api/overview).
    expect(_kindChip('claude-rc'), findsOneWidget);
    expect(_kindChip('shell'), findsOneWidget);
    expect(find.byKey(const ValueKey('createrc-caps-note')), findsOneWidget);
    // A Retry would just re-404 forever — it must NOT be offered.
    expect(find.byKey(const ValueKey('createrc-caps-retry')), findsNothing);
    expect(find.textContaining('too old'), findsOneWidget);
  });

  testWidgets('running shed + null caps → base chips + note + Retry', (
    tester,
  ) async {
    await _pump(
      tester,
      () => _data(status: BridgeShedStatus.running, caps: null),
    );
    expect(_kindChip('claude-rc'), findsOneWidget);
    expect(_kindChip('shell'), findsOneWidget);
    expect(find.byKey(const ValueKey('createrc-caps-note')), findsOneWidget);
    // A running shed's caps CAN self-heal on re-probe → Retry is offered.
    expect(find.byKey(const ValueKey('createrc-caps-retry')), findsOneWidget);
    expect(find.textContaining('unavailable'), findsOneWidget);
  });

  testWidgets('stopped shed → base chips + "start the shed" note, NOT Retry', (
    tester,
  ) async {
    await _pump(tester, () => _data(status: BridgeShedStatus.stopped));
    expect(_kindChip('claude-rc'), findsOneWidget);
    expect(_kindChip('shell'), findsOneWidget);
    final note = find.byKey(const ValueKey('createrc-caps-note'));
    expect(note, findsOneWidget);
    expect(tester.widget<Text>(note).data, contains('Start the shed'));
    // A stopped shed is not a failure — no "unreadable"/"couldn't" framing.
    expect(find.textContaining('unreadable'), findsNothing);
    expect(find.textContaining("Couldn't"), findsNothing);
    // Nothing to re-probe until it's running.
    expect(find.byKey(const ValueKey('createrc-caps-retry')), findsNothing);
  });

  testWidgets('missing shed → base chips + neutral note (no false failure)', (
    tester,
  ) async {
    // Target `proj`, but the overview only knows `other` → not found.
    await _pump(tester, () => _data(shedName: 'other'));
    expect(_kindChip('claude-rc'), findsOneWidget);
    expect(_kindChip('shell'), findsOneWidget);
    expect(find.byKey(const ValueKey('createrc-caps-note')), findsOneWidget);
    expect(find.textContaining('unreadable'), findsNothing);
    expect(find.byKey(const ValueKey('createrc-caps-retry')), findsNothing);
  });

  testWidgets('present caps with codex installed → codex chip appears', (
    tester,
  ) async {
    await _pump(tester, () => _data(caps: _codexCaps()));
    expect(_kindChip('claude-rc'), findsOneWidget);
    expect(_kindChip('codex'), findsOneWidget);
    expect(_kindChip('shell'), findsOneWidget);
    // No status note / retry when the real offering is known.
    expect(find.byKey(const ValueKey('createrc-caps-note')), findsNothing);
    expect(find.byKey(const ValueKey('createrc-caps-retry')), findsNothing);
    expect(_submitEnabled(tester), isTrue);
  });

  testWidgets('present-but-empty caps → no-kinds message, submit disabled', (
    tester,
  ) async {
    await _pump(tester, () => _data(caps: _caps(kinds: const [])));
    expect(find.byKey(const ValueKey('createrc-no-kinds')), findsOneWidget);
    expect(_kindChip('claude-rc'), findsNothing);
    expect(_submitEnabled(tester), isFalse);
  });

  testWidgets(
    'present caps offer the generic "skip"; a base state excludes it',
    (tester) async {
      // Present caps: the claude dropdown includes the NEW generic `skip`.
      await _pump(tester, () => _data(caps: _baseCaps()));
      await tester.tap(find.byKey(const ValueKey('createrc-permission-mode')));
      await tester.pumpAndSettle();
      expect(find.text('skip'), findsOneWidget);
      expect(find.text('bypassPermissions'), findsOneWidget);
    },
  );

  testWidgets(
    'a base state (unsupported) keeps the historical claude set but drops "skip"',
    (tester) async {
      // caps absent → an old binary would reject the generic `skip`.
      await _pump(tester, () => const OverviewUnsupported());
      await tester.tap(find.byKey(const ValueKey('createrc-permission-mode')));
      await tester.pumpAndSettle();
      expect(find.text('skip'), findsNothing);
      expect(find.text('bypassPermissions'), findsOneWidget);
      expect(find.text('plan'), findsOneWidget);
    },
  );

  testWidgets(
    'selecting codex then losing it (caps change) falls back sanely',
    (tester) async {
      var offerCodex = true;
      await _pump(
        tester,
        () => _data(caps: offerCodex ? _codexCaps() : _baseCaps()),
      );
      // Pick codex → the claude-only permission dropdown hides.
      await tester.tap(_kindChip('codex'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('createrc-permission-mode')),
        findsNothing,
      );

      // Caps change so codex is no longer offered; re-probe the overview.
      offerCodex = false;
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CreateRcScreen)),
      );
      container.invalidate(overviewProvider('h'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The vanished selection falls back to a still-offered kind (claude-rc):
      // codex gone, submit still enabled, no crash, dropdown back.
      expect(_kindChip('codex'), findsNothing);
      expect(_kindChip('claude-rc'), findsOneWidget);
      expect(_submitEnabled(tester), isTrue);
      expect(
        find.byKey(const ValueKey('createrc-permission-mode')),
        findsOneWidget,
      );
    },
  );
}
