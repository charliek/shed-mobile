import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/create/create_rc_target.dart';
import 'package:shed_mobile/features/create/target_picker.dart';
import 'package:shed_mobile/features/rc/create_rc_screen.dart';
import 'package:shed_mobile/machines/machine_feed.dart';
import 'package:shed_mobile/machines/machine_record.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/servers/server_record.dart';
import 'package:shed_mobile/src/rust/api/dto.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

/// **Starting an agent on a machine is the same act as starting one in a shed.**
///
/// Not a parallel flow, not a second button — the same "New session" the
/// Sessions tab has always had, with one more kind of place to run it. So the
/// picker offers both, and the create screen reads the chosen target's real
/// capabilities: a machine whose `sx` is old offers the base kinds and says so,
/// exactly as an old shed does, and a machine the phone cannot reach offers
/// nothing rather than a form whose submit can only fail.
const _mini3 = MachineRecord(name: 'mini3', host: 'mini3.example');

ServerRecord _host(String name) => ServerRecord(
  name: name,
  host: name,
  sshPort: 2222,
  apiUrl: 'https://$name:8443',
  tlsCertFingerprint: 'sha256:x',
  hostKeyPin: 'pin',
);

BridgeRcCapabilities _caps(List<BridgeRcKind> kinds) => BridgeRcCapabilities(
  rcVersion: 4,
  kinds: kinds,
  // A kind is only offered when its backing tool is INSTALLED — advertising
  // `codex` on a machine with no codex binary is exactly the case the gate
  // exists for.
  agents: const {
    'codex': BridgeRcAgentInfo(installed: true),
    'opencode': BridgeRcAgentInfo(installed: true),
  },
  features: const ['contract-v2'],
  kindFeatures: const {},
);

MachineFeedState _state({BridgeRcCapabilities? caps, bool reachable = true}) =>
    MachineFeedState(
      machine: _mini3,
      sessions: const [],
      reachable: reachable,
      connectedOnce: true,
      capabilities: caps,
    );

/// A [MachineRcTarget] that records what it was called with instead of
/// touching the real [MachineFeed] — the seam the "never send a permission
/// mode" test below needs. `MachineRcTarget` is a concrete, non-`final`
/// subclass of the sealed `CreateRcTarget`, so extending it from outside
/// `create_rc_target.dart` is fine; only extending the sealed class itself
/// would not be.
class _RecordingMachineTarget extends MachineRcTarget {
  _RecordingMachineTarget({required super.machineName});

  BridgeRcKind? lastKind;
  String? lastPermissionMode;

  @override
  Future<RcCreated> create(
    WidgetRef ref, {
    required BridgeRcKind kind,
    String? displayName,
    String? workdir,
    String? prompt,
    String? permissionMode,
  }) async {
    lastKind = kind;
    lastPermissionMode = permissionMode;
    return (slug: 'rec', state: 'created', url: null, result: 'rec');
  }
}

/// Pump a screen for [target], with the machine feed overridden to [state].
Future<void> _pumpCreate(
  WidgetTester tester,
  CreateRcTarget target, {
  MachineFeedState? state,
}) async {
  await tester.binding.setSurfaceSize(const Size(500, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        machinesProvider.overrideWith((ref) async => const [_mini3]),
        if (state != null)
          machineFeedProvider(
            'mini3',
          ).overrideWith((ref) => Stream.value(state)),
      ],
      child: MaterialApp(
        theme: shedLightTheme,
        home: CreateRcScreen(target: target),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the picker offers machines beside running sheds', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    CreateRcTarget? picked;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serversProvider.overrideWith((ref) => [_host('h1')]),
          machinesProvider.overrideWith((ref) async => const [_mini3]),
          shedsProvider.overrideWith(
            (ref, name) async => const [
              BridgeShed(
                host: 'h1',
                name: 'proj',
                status: BridgeShedStatus.running,
                activeNamespaces: [],
              ),
            ],
          ),
        ],
        child: MaterialApp(
          theme: shedLightTheme,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const ValueKey('go'),
                  onPressed: () async =>
                      picked = await pickRunTarget(context, ref),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('go')));
    await tester.pumpAndSettle();

    // Both kinds of place, in one list — and only then are the headers worth
    // showing.
    expect(find.byKey(const ValueKey('pick-shed-h1-proj')), findsOneWidget);
    expect(find.byKey(const ValueKey('pick-machine-mini3')), findsOneWidget);
    expect(find.text('SHEDS'), findsOneWidget);
    expect(find.text('MACHINES'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pick-machine-mini3')));
    await tester.pumpAndSettle();
    expect(picked, isA<MachineRcTarget>());
    expect((picked! as MachineRcTarget).machineName, 'mini3');
  });

  testWidgets('a machine offers exactly the kinds its probe found', (
    tester,
  ) async {
    await _pumpCreate(
      tester,
      const MachineRcTarget(machineName: 'mini3'),
      state: _state(
        caps: _caps(const [
          BridgeRcKind.opencode(),
          BridgeRcKind.codex(),
          BridgeRcKind.shell(),
        ]),
      ),
    );
    expect(find.text('New session · mini3'), findsOneWidget);
    expect(find.text('opencode'), findsOneWidget);
    expect(find.text('codex'), findsOneWidget);
  });

  testWidgets('an unreachable machine offers no kinds, and says why', (
    tester,
  ) async {
    // Failing OPEN here would render a full form whose submit could only fail
    // against a host the phone cannot dial.
    await _pumpCreate(
      tester,
      const MachineRcTarget(machineName: 'mini3'),
      state: _state(reachable: false),
    );
    expect(find.textContaining('unreachable'), findsOneWidget);
  });

  testWidgets('a machine with no capabilities falls back to the base kinds', (
    tester,
  ) async {
    // An old `sx` cannot advertise. claude + shell have always existed, so the
    // base set is honest — and a retry can genuinely self-heal a probe miss.
    await _pumpCreate(
      tester,
      const MachineRcTarget(machineName: 'mini3'),
      state: _state(),
    );
    expect(find.textContaining('unavailable on mini3'), findsOneWidget);
    expect(find.text('claude-rc'), findsOneWidget);
    expect(find.text('shell'), findsOneWidget);
  });

  testWidgets(
    'a machine target never sends a permission mode, even for a kind that '
    'has one',
    (tester) async {
      // `_permissionMode` starts non-null (`auto`) regardless of the target,
      // and opencode `hasPermissionMode` (it isn't shell) while NOT being
      // claude — exactly the kind `_modeFor` used to leak `auto` through for
      // on a machine target (acceptsKickoff == false), which has no posture
      // to carry at all.
      final target = _RecordingMachineTarget(machineName: 'mini3');
      await tester.binding.setSurfaceSize(const Size(500, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            machinesProvider.overrideWith((ref) async => const [_mini3]),
            machineFeedProvider('mini3').overrideWith(
              (ref) => Stream.value(
                _state(
                  caps: _caps(const [
                    BridgeRcKind.opencode(),
                    BridgeRcKind.shell(),
                  ]),
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: shedLightTheme,
            // A real pushed route (not `home:` directly) so the screen's own
            // `Navigator.pop()` on a successful create has something below it
            // to land on.
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    key: const ValueKey('go'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CreateRcScreen(target: target),
                      ),
                    ),
                    child: const Text('go'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('go')));
      await tester.pumpAndSettle();

      // No claude-rc offered → the fallback selection lands on opencode, the
      // offered kind list's first entry.
      expect(find.text('opencode'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('createrc-submit')));
      await tester.pumpAndSettle();

      expect(
        target.lastKind,
        const BridgeRcKind.opencode(),
        reason: 'the negative control — create really was called',
      );
      expect(
        target.lastPermissionMode,
        isNull,
        reason:
            'MachineRcTarget.acceptsKickoff is false — a permission mode '
            'must never reach create(), even for a kind that has one',
      );
    },
  );
}
