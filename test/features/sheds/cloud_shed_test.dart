import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/sheds/shed_list_screen.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/shed/cloud.dart';
import 'package:shed_mobile/src/rust/api/dto.dart';
import 'package:shed_mobile/theme/shed_colors.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

import 'fake_shed_client.dart';

const _h = Duration(hours: 1);

/// The fake clock's start: every lease below is measured from it.
final _t0 = DateTime.utc(2026, 11, 26, 9);

/// The cards' clock, moved by the test instead of by a timer.
class _FakeClock extends CloudClock {
  @override
  DateTime build() => _t0;

  void set(DateTime t) => state = t;
}

/// A cloud shed whose lease ends [left] after [_t0], with presets already clipped
/// by the bridge to [presets] and [maxH] hours to the cap.
BridgeShed _cloud({
  String name = 'web',
  BridgeShedStatus status = BridgeShedStatus.running,
  Duration left = const Duration(hours: 5, minutes: 10, seconds: 30),
  List<int> presets = const [6, 12, 20],
  int maxH = 20,
  bool lease = true,
  int? unknownHours,
}) {
  final end = _t0.add(left).millisecondsSinceEpoch;
  return BridgeShed(
    host: 'h',
    name: name,
    status: status,
    backend: 'remote',
    activeNamespaces: const [],
    extendUnknownHours: unknownHours,
    cloud: BridgeShedCloud(
      provider: 'gce',
      sizeName: 'standard',
      cpus: 2,
      memoryMb: 8192,
      diskGb: 50,
      image: 'shed-full',
      createdAt: '2026-11-26T06:00:00Z',
      lease: lease
          ? BridgeShedLease(
              expiresAt: '',
              expiresAtMs: end,
              maxExpiresAt: '',
              maxExpiresAtMs: end + maxH * _h.inMilliseconds,
              extendable: maxH > 0,
              warnS: 7200,
              extendMaxH: maxH,
              extendPresetsH: Uint32List.fromList(presets),
            )
          : null,
    ),
  );
}

const _local = BridgeShed(
  host: 'h',
  name: 'db',
  status: BridgeShedStatus.running,
  backend: 'vz',
  cpus: 2,
  memoryMb: 4096,
  activeNamespaces: [],
);

const _usage = BridgeCloudUsage(
  person: BridgeCloudCounts(machines: 2, running: 1, stopped: 1, max: 4),
  org: BridgeCloudCounts(machines: 7, running: 5, stopped: 2, max: 10),
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeShedClient client, {
  bool watchOverview = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = ProviderContainer(
    overrides: [
      shedClientProvider('h').overrideWith((ref) async => client),
      cloudNowProvider.overrideWith(_FakeClock.new),
    ],
  );
  addTearDown(container.dispose);
  // The Hosts view's overview, kept alive as that view keeps it, so a test can
  // see an extend refresh it too.
  if (watchOverview) container.listen(overviewProvider('h'), (_, _) {});
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: shedLightTheme,
        home: const MediaQuery(
          data: MediaQueryData(size: Size(400, 900)),
          child: ShedListScreen(serverName: 'h'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Move the cards' clock to [t].
void _setClock(ProviderContainer c, DateTime t) =>
    (c.read(cloudNowProvider.notifier) as _FakeClock).set(t);

Finder _k(String key) => find.byKey(ValueKey(key));

/// The colour the meta line gives its lease words.
Color? _leaseColor(WidgetTester tester, String base, String words) {
  final rich = tester.widget<Text>(_k('all-shed-meta-$base')).textSpan!;
  Color? found;
  rich.visitChildren((span) {
    if (span is TextSpan && span.text == words) found = span.style?.color;
    return true;
  });
  return found;
}

void main() {
  group('the cloud row', () {
    testWidgets('a cloud shed wears the Cloud badge; a local one does not', (
      tester,
    ) async {
      await _pump(tester, FakeShedClient(sheds: [_cloud(), _local]));
      expect(_k('all-shed-cloud-h-web'), findsOneWidget);
      expect(
        find.descendant(
          of: _k('all-shed-cloud-h-web'),
          matching: find.text('Cloud'),
        ),
        findsOneWidget,
      );
      expect(_k('all-shed-cloud-h-db'), findsNothing);
    });

    testWidgets('the meta line has the size and the time left', (tester) async {
      await _pump(tester, FakeShedClient(sheds: [_cloud()]));
      final meta = tester.widget<Text>(_k('all-shed-meta-h-web'));
      expect(meta.textSpan!.toPlainText(), '2 vCPU · 8 GB · deleted in 5h 10m');
      expect(
        _leaseColor(tester, 'h-web', 'deleted in 5h 10m'),
        ShedColors.light.fg3,
      );
    });

    testWidgets('amber under the warning time, red once ended', (tester) async {
      await _pump(
        tester,
        FakeShedClient(
          sheds: [
            _cloud(left: const Duration(hours: 1, minutes: 30, seconds: 30)),
            _cloud(name: 'old', left: const Duration(minutes: -1)),
          ],
        ),
      );
      expect(
        _leaseColor(tester, 'h-web', 'deleted in 1h 30m'),
        ShedColors.light.warnFg,
      );
      expect(
        _leaseColor(tester, 'h-old', 'lease ended'),
        ShedColors.light.errFg,
      );
      // An ended lease offers neither extend nor stop.
      expect(_k('all-shed-extend-h-old'), findsNothing);
      expect(_k('all-shed-stop-h-old'), findsNothing);
    });

    testWidgets('a cloud shed has no restart; delete only once stopped', (
      tester,
    ) async {
      await _pump(
        tester,
        FakeShedClient(
          sheds: [
            _cloud(),
            _cloud(name: 'off', status: BridgeShedStatus.stopped),
          ],
        ),
      );
      expect(_k('all-shed-restart-h-web'), findsNothing);
      expect(_k('all-shed-stop-h-web'), findsOneWidget);
      expect(_k('all-shed-delete-h-web'), findsNothing);
      expect(_k('all-shed-extend-h-web'), findsOneWidget);
      expect(_k('all-shed-start-h-off'), findsOneWidget);
      expect(_k('all-shed-delete-h-off'), findsOneWidget);
      expect(_k('all-shed-extend-h-off'), findsOneWidget);
    });

    testWidgets('no extend without a known lease or with no hour to the cap', (
      tester,
    ) async {
      await _pump(
        tester,
        FakeShedClient(
          sheds: [
            _cloud(lease: false),
            _cloud(name: 'capped', maxH: 0, presets: const []),
          ],
        ),
      );
      expect(_k('all-shed-extend-h-web'), findsNothing);
      expect(_k('all-shed-extend-h-capped'), findsNothing);
      final meta = tester.widget<Text>(_k('all-shed-meta-h-web'));
      expect(meta.textSpan!.toPlainText(), contains('lease unknown'));
    });

    testWidgets('an extend with an unknown outcome holds Extend and says so', (
      tester,
    ) async {
      await _pump(tester, FakeShedClient(sheds: [_cloud(unknownHours: 6)]));
      expect(_k('all-shed-extend-h-web'), findsNothing);
      expect(find.text(unresolvedExtendWords(6)), findsOneWidget);
    });
  });

  testWidgets('the clock moves the countdown, its colour and the actions on', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      FakeShedClient(
        sheds: [_cloud(left: const Duration(hours: 2, seconds: 30))],
      ),
    );
    expect(_leaseColor(tester, 'h-web', 'deleted in 2h 0m'), isNotNull);
    expect(
      _leaseColor(tester, 'h-web', 'deleted in 2h 0m'),
      ShedColors.light.fg3,
    );

    // A minute on: under the two-hour warning, amber.
    _setClock(container, _t0.add(const Duration(minutes: 1)));
    await tester.pump();
    expect(
      _leaseColor(tester, 'h-web', 'deleted in 1h 59m'),
      ShedColors.light.warnFg,
    );
    expect(_k('all-shed-extend-h-web'), findsOneWidget);
    expect(_k('all-shed-stop-h-web'), findsOneWidget);

    // Past the end: red, and neither Extend nor Stop is offered.
    _setClock(container, _t0.add(const Duration(hours: 2, minutes: 1)));
    await tester.pump();
    expect(_leaseColor(tester, 'h-web', 'lease ended'), ShedColors.light.errFg);
    expect(_k('all-shed-extend-h-web'), findsNothing);
    expect(_k('all-shed-stop-h-web'), findsNothing);
  });

  group('the Extend sheet', () {
    testWidgets('offers the clipped presets and sends the one chosen, then '
        'refreshes the shed views', (tester) async {
      final client = FakeShedClient(sheds: [_cloud()]);
      await _pump(tester, client, watchOverview: true);
      final fetches = client.listShedsCalls;
      final overviews = client.overviewCalls;
      expect(overviews, 1);

      await tester.tap(_k('all-shed-extend-h-web'));
      await tester.pumpAndSettle();
      expect(_k('extend-sheet'), findsOneWidget);
      for (final h in const [6, 12, 20]) {
        expect(_k('extend-preset-$h'), findsOneWidget);
      }
      expect(_k('extend-preset-24'), findsNothing);
      expect(find.textContaining('up to 20 h'), findsOneWidget);

      await tester.tap(_k('extend-preset-12'));
      await tester.pumpAndSettle();
      await tester.tap(_k('extend-submit'));
      await tester.pumpAndSettle();

      expect(client.calls, ['extend:web:12']);
      expect(find.text('Extended web'), findsOneWidget);
      // Both views: the shed list and the overview the Hosts view renders.
      expect(client.listShedsCalls, greaterThan(fetches));
      expect(client.overviewCalls, greaterThan(overviews));
    });

    testWidgets('both views refresh even when the card unmounts during the '
        'extend', (tester) async {
      final gate = Completer<void>();
      final client = FakeShedClient(sheds: [_cloud()], extendGate: gate);
      final container = await _pump(tester, client, watchOverview: true);
      // The cross-host Sheds view's list, kept alive as that view keeps it.
      container.listen(shedsProvider('h'), (_, _) {});
      await tester.tap(_k('all-shed-extend-h-web'));
      await tester.pumpAndSettle();
      await tester.tap(_k('extend-preset-6'));
      await tester.pumpAndSettle();
      await tester.tap(_k('extend-submit'));
      await tester.pump();
      await tester.pump();
      expect(client.calls, ['extend:web:6']);
      final fetches = client.listShedsCalls;
      final overviews = client.overviewCalls;

      // The card goes away while the extend is out.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: shedLightTheme,
            home: const Scaffold(body: SizedBox()),
          ),
        ),
      );
      expect(_k('all-shed-h-web'), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();

      expect(client.listShedsCalls, greaterThan(fetches));
      expect(client.overviewCalls, greaterThan(overviews));
    });

    testWidgets('custom hours past the cap cannot be sent', (tester) async {
      final client = FakeShedClient(sheds: [_cloud()]);
      await _pump(tester, client);
      await tester.tap(_k('all-shed-extend-h-web'));
      await tester.pumpAndSettle();

      await tester.enterText(_k('extend-hours'), '21');
      await tester.pumpAndSettle();
      expect(find.text('A whole number of hours from 1 to 20'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(_k('extend-submit')).onPressed,
        isNull,
      );

      await tester.enterText(_k('extend-hours'), '3');
      await tester.pumpAndSettle();
      await tester.tap(_k('extend-submit'));
      await tester.pumpAndSettle();
      expect(client.calls, ['extend:web:3']);
    });

    testWidgets('a refusal shows its fixed words', (tester) async {
      const words =
          'the extend would take the lease past its cap; '
          'extend by fewer hours';
      final client = FakeShedClient(
        sheds: [_cloud()],
        extendOutcome: const BridgeExtendOutcome.refused(
          code: 'LEASE_AT_CAP',
          reason: '',
          status: 409,
          words: words,
        ),
      );
      await _pump(tester, client);
      await tester.tap(_k('all-shed-extend-h-web'));
      await tester.pumpAndSettle();
      await tester.tap(_k('extend-preset-6'));
      await tester.pumpAndSettle();
      await tester.tap(_k('extend-submit'));
      await tester.pumpAndSettle();
      expect(find.text('Extend refused: $words'), findsOneWidget);
    });

    testWidgets('an unknown outcome says Extend stays unavailable', (
      tester,
    ) async {
      final client = FakeShedClient(
        sheds: [_cloud()],
        extendOutcome: const BridgeExtendOutcome.unknown(
          hours: 6,
          words:
              'not known whether it was applied; Extend stays unavailable '
              'until that is known',
        ),
      );
      await _pump(tester, client);
      await tester.tap(_k('all-shed-extend-h-web'));
      await tester.pumpAndSettle();
      await tester.tap(_k('extend-preset-6'));
      await tester.pumpAndSettle();
      await tester.tap(_k('extend-submit'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Extend stays unavailable until that is known'),
        findsOneWidget,
      );
    });
  });

  group('the usage line', () {
    testWidgets('a person: their machines and the organization', (
      tester,
    ) async {
      await _pump(
        tester,
        FakeShedClient(sheds: [_cloud()], cloudUsage: _usage),
      );
      expect(
        tester.widget<Text>(_k('sheds-cloud-usage-h')).data,
        '2 of 4 machines (1 running, 1 stopped) · organization 7 of 10',
      );
    });

    testWidgets('not a person: the organization only', (tester) async {
      await _pump(
        tester,
        FakeShedClient(
          sheds: [_cloud()],
          cloudUsage: const BridgeCloudUsage(
            org: BridgeCloudCounts(
              machines: 7,
              running: 5,
              stopped: 2,
              max: 10,
            ),
          ),
        ),
      );
      expect(
        tester.widget<Text>(_k('sheds-cloud-usage-h')).data,
        'organization 7 of 10',
      );
    });

    testWidgets('a server with no cloud usage shows no line', (tester) async {
      await _pump(tester, FakeShedClient(sheds: [_local]));
      expect(_k('sheds-cloud-usage-h'), findsNothing);
    });
  });

  group('the pure rules', () {
    test('formatLeft', () {
      expect(
        formatLeft(const Duration(days: 1, hours: 2, minutes: 5)),
        '1d 2h',
      );
      expect(formatLeft(const Duration(hours: 1, minutes: 20)), '1h 20m');
      expect(formatLeft(const Duration(minutes: 20, seconds: 59)), '20m');
      expect(formatLeft(const Duration(minutes: -5)), '0m');
    });

    test('size words', () {
      BridgeShedCloud c(int cpus, int mem) => BridgeShedCloud(
        sizeName: 'standard',
        cpus: cpus,
        memoryMb: mem,
        diskGb: 0,
        image: '',
        createdAt: '',
      );
      expect(cloudSizeWords(c(2, 8192)), '2 vCPU · 8 GB');
      expect(cloudSizeWords(c(1, 1536)), '1 vCPU · 1.5 GB');
      expect(cloudSizeWords(c(0, 0)), 'standard');
    });
  });
}
