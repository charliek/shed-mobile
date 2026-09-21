import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/create/create_rc_target.dart';
import 'package:shed_mobile/features/rc/create_rc_screen.dart';
import 'package:shed_mobile/machines/machine_feed.dart';
import 'package:shed_mobile/machines/machine_record.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

/// **The shed create form is a ROOST LAUNCH FORM now** (plan 022 S6, shed#328).
///
/// It used to read `rc_capabilities` off `GET /api/overview` and offer a name, a
/// kickoff prompt and a permission mode. The RC hub is gone: what a shed can run
/// is what roost can launch there, the offering comes off the shed's feed, and
/// `tab.open` carries a kind and a directory and nothing else. So every branch
/// below is a branch of the FEED.
const _origin = 'shed:h/proj';

/// Build a bridge capabilities block from wire kind strings + installed tools.
BridgeRcCapabilities _caps({
  required List<String> kinds,
  Map<String, bool> installed = const {},
}) => BridgeRcCapabilities(
  rcVersion: 2,
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

/// Present caps that offer claude-rc + codex + shell (all installed).
BridgeRcCapabilities _codexCaps() => _caps(
  kinds: ['claude-rc', 'codex', 'shell'],
  installed: {'claude': true, 'codex': true},
);

/// Present caps that offer only the base pair (claude-rc + shell).
BridgeRcCapabilities _baseCaps() =>
    _caps(kinds: ['claude-rc', 'shell'], installed: {'claude': true});

MachineFeedState _state({
  bool reachable = true,
  BridgeRcCapabilities? caps,
  String? detail,
}) => MachineFeedState(
  machine: const MachineRecord(name: _origin, host: 'h', user: 'proj'),
  reachable: reachable,
  connectedOnce: true,
  detail: detail,
  capabilities: caps,
);

/// Pump [CreateRcScreen] with the shed's feed driven by [build] — a state →
/// data, a thrown error → `AsyncError`, a never-emitting stream →
/// `AsyncLoading`. [build] re-runs on every (re)compute so a captured counter
/// can prove a Retry actually re-probes. Bounded pumps (never `pumpAndSettle`)
/// so a loading/error case can't hang; `retry:(_,_)=>null` stops Riverpod from
/// auto-retrying a thrown provider error.
Future<void> _pump(
  WidgetTester tester,
  Stream<MachineFeedState> Function() build,
) async {
  await tester.binding.setSurfaceSize(const Size(500, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        identitiesProvider.overrideWith((ref) async => <SSHKeyPair>[]),
        machineFeedProvider.overrideWith((ref, origin) => build()),
      ],
      child: MaterialApp(
        theme: shedLightTheme,
        home: const CreateRcScreen(
          target: ShedRcTarget(serverName: 'h', shedName: 'proj'),
        ),
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
    // A stream that never emits → the screen stays in AsyncLoading.
    await _pump(tester, () => const Stream<MachineFeedState>.empty());
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
        if (!present) return Stream.error(StateError('probe boom'));
        return Stream.value(_state(caps: _codexCaps()));
      });
      // Errored: NOT the silent claude+shell downgrade — a Retry instead.
      expect(calls, 1);
      expect(find.byKey(const ValueKey('createrc-caps-retry')), findsOneWidget);
      expect(_kindChip('claude-rc'), findsNothing);
      expect(_kindChip('shell'), findsNothing);
      expect(_kindChip('codex'), findsNothing);

      // Flip the source to a served feed, then Retry → the provider MUST
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

  testWidgets(
    'unreachable shed → no chips, Retry, and the feed\'s OWN reason',
    (tester) async {
      await _pump(
        tester,
        () => Stream.value(
          _state(reachable: false, detail: 'no roost session on this shed'),
        ),
      );
      // Launching into a shed the phone cannot reach would only fail — offer
      // nothing rather than chips that cannot work.
      expect(_kindChip('claude-rc'), findsNothing);
      expect(_kindChip('shell'), findsNothing);
      final note = find.byKey(const ValueKey('createrc-caps-note'));
      expect(note, findsOneWidget);
      // The verbatim reason, not a flattened "unreachable": "no roost session"
      // and "this device's key is not authorized" have different fixes.
      expect(
        tester.widget<Text>(note).data,
        contains('no roost session on this shed'),
      );
      expect(find.byKey(const ValueKey('createrc-caps-retry')), findsOneWidget);
      expect(_submitEnabled(tester), isFalse);
    },
  );

  testWidgets('reachable shed + null caps → base chips + note + Retry', (
    tester,
  ) async {
    await _pump(tester, () => Stream.value(_state()));
    expect(_kindChip('claude-rc'), findsOneWidget);
    expect(_kindChip('shell'), findsOneWidget);
    expect(find.byKey(const ValueKey('createrc-caps-note')), findsOneWidget);
    expect(find.byKey(const ValueKey('createrc-caps-retry')), findsOneWidget);
    expect(find.textContaining('unavailable'), findsOneWidget);
  });

  testWidgets('present caps with codex installed → codex chip appears', (
    tester,
  ) async {
    await _pump(tester, () => Stream.value(_state(caps: _codexCaps())));
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
    await _pump(
      tester,
      () => Stream.value(_state(caps: _caps(kinds: const []))),
    );
    expect(find.byKey(const ValueKey('createrc-no-kinds')), findsOneWidget);
    expect(_kindChip('claude-rc'), findsNothing);
    expect(_submitEnabled(tester), isFalse);
  });

  testWidgets('a shed launch offers NO name, prompt or permission mode — '
      '`tab.open` carries none of them', (tester) async {
    // The S6 behaviour change, pinned: a field whose contents would be dropped
    // on the floor is worse than no field at all, so the form hides all three
    // for a roost target. `acceptsKickoff` is the one flag that does it.
    await _pump(tester, () => Stream.value(_state(caps: _baseCaps())));
    expect(_kindChip('claude-rc'), findsOneWidget); // the form DID render
    expect(find.byKey(const ValueKey('createrc-name')), findsNothing);
    expect(find.byKey(const ValueKey('createrc-prompt')), findsNothing);
    expect(
      find.byKey(const ValueKey('createrc-permission-mode')),
      findsNothing,
    );
    // The workdir survives: `tab.open` takes a cwd.
    expect(find.byKey(const ValueKey('createrc-workdir')), findsOneWidget);
  });

  testWidgets(
    'selecting codex then losing it (caps change) falls back sanely',
    (tester) async {
      var offerCodex = true;
      await _pump(
        tester,
        () =>
            Stream.value(_state(caps: offerCodex ? _codexCaps() : _baseCaps())),
      );
      await tester.tap(_kindChip('codex'));
      await tester.pumpAndSettle();
      expect(_kindChip('codex'), findsOneWidget);

      // Caps change so codex is no longer offered; re-probe the feed.
      offerCodex = false;
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CreateRcScreen)),
      );
      container.invalidate(machineFeedProvider(_origin));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The vanished selection falls back to a still-offered kind (claude-rc):
      // codex gone, submit still enabled, no crash.
      expect(_kindChip('codex'), findsNothing);
      expect(_kindChip('claude-rc'), findsOneWidget);
      expect(_submitEnabled(tester), isTrue);
    },
  );
}
