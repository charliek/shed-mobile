import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/create/target_picker.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/servers/server_record.dart';
import 'package:shed_mobile/shed/shed_dtos.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

ServerRecord _rec(String name) => ServerRecord(
  name: name,
  host: name,
  sshPort: 2222,
  apiUrl: 'https://$name:8443',
  tlsCertFingerprint: 'sha256:x',
  hostKeyPin: 'pin',
);

/// Pump a button that runs [fn] and records its result, with `serversProvider`
/// overridden to [hosts] and (optionally) `shedsProvider` to [sheds]. Overrides
/// are built inside so tests never have to name the un-exported `Override` type.
Future<Object?> _run(
  WidgetTester tester,
  Future<Object?> Function(BuildContext, WidgetRef) fn, {
  required List<ServerRecord> hosts,
  Future<List<Shed>> Function(String name)? sheds,
}) async {
  Object? result;
  await tester.binding.setSurfaceSize(const Size(500, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        serversProvider.overrideWith((ref) => hosts),
        if (sheds != null)
          shedsProvider.overrideWith((ref, name) => sheds(name)),
      ],
      child: MaterialApp(
        theme: shedLightTheme,
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const ValueKey('go'),
                onPressed: () async => result = await fn(context, ref),
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
  return result;
}

void main() {
  testWidgets('pickHost: a single host is auto-selected without a sheet', (
    tester,
  ) async {
    final result = await _run(tester, pickHost, hosts: [_rec('only')]);
    expect(result, 'only');
    expect(find.byKey(const ValueKey('pick-host-only')), findsNothing);
  });

  testWidgets('pickHost: multiple hosts open a sheet; tapping one returns it', (
    tester,
  ) async {
    // Can't use _run here (need to tap a sheet row after the picker opens).
    Object? result;
    await tester.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serversProvider.overrideWith((ref) => [_rec('a'), _rec('b')]),
        ],
        child: MaterialApp(
          theme: shedLightTheme,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const ValueKey('go'),
                  onPressed: () async => result = await pickHost(context, ref),
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
    expect(find.byKey(const ValueKey('pick-host-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('pick-host-b')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pick-host-b')));
    await tester.pumpAndSettle();
    expect(result, 'b');
  });

  testWidgets('pickShed: only running sheds are offered, grouped by host', (
    tester,
  ) async {
    await _run(
      tester,
      pickShed,
      hosts: [_rec('h1'), _rec('h2')],
      sheds: (name) async => name == 'h1'
          ? const [
              Shed(name: 'run', status: 'running'),
              Shed(name: 'stop', status: 'stopped'),
            ]
          : const [Shed(name: 'run2', status: 'running')],
    );
    expect(find.byKey(const ValueKey('pick-shed-h1-run')), findsOneWidget);
    expect(find.byKey(const ValueKey('pick-shed-h2-run2')), findsOneWidget);
    // Stopped sheds are not selectable targets.
    expect(find.byKey(const ValueKey('pick-shed-h1-stop')), findsNothing);
  });

  testWidgets('pickShed: one unreachable host does not hide the others', (
    tester,
  ) async {
    await _run(
      tester,
      pickShed,
      hosts: [_rec('down'), _rec('up')],
      sheds: (name) async {
        if (name == 'down') throw StateError('offline');
        return const [Shed(name: 'ok', status: 'running')];
      },
    );
    expect(find.byKey(const ValueKey('pick-shed-up-ok')), findsOneWidget);
  });

  testWidgets('pickShed: no running sheds shows the "start a shed" hint', (
    tester,
  ) async {
    await _run(
      tester,
      pickShed,
      hosts: [_rec('h')],
      sheds: (name) async => const [Shed(name: 'idle', status: 'stopped')],
    );
    expect(find.byKey(const ValueKey('pick-empty')), findsOneWidget);
  });
}
