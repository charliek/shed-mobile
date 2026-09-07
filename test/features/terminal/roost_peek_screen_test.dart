import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/terminal/roost_peek_screen.dart';
import 'package:shed_mobile/src/rust/api/roost.dart';

/// A [PeekSource] double whose `open`/`dump` outcomes the test drives
/// directly, so the screen's open → poll → refresh → dispose lifecycle is
/// exercisable with no bridge underneath it at all.
///
/// `dump()` outcomes are consumed strictly in the order they were queued —
/// one queued outcome per call — so a test can line up exactly what each poll
/// tick returns. Once the queue drains, the last outcome repeats (a steady
/// state, matching a real poll that keeps reporting the same frame).
class _FakePeekSource implements PeekSource {
  /// When set, the NEXT `open()` throws this and clears itself — so a retry
  /// after the condition is fixed succeeds.
  Object? openError;

  /// When set, `open()` awaits this before resolving (or throwing
  /// [openError]) instead of returning on the same microtask — lets a test
  /// hold `open()` pending across a `dispose()` to exercise the
  /// dispose-races-open leak.
  Future<void>? openFuture;

  final List<Object> _dumpOutcomes = [];
  Object? _lastOutcome;

  int openCalls = 0;
  int closeCalls = 0;

  void pushDump(BridgeTabDump d) => _dumpOutcomes.add(d);
  void pushError([Object? e]) =>
      _dumpOutcomes.add(e ?? StateError('dump failed'));

  @override
  Future<void> open() async {
    openCalls += 1;
    final future = openFuture;
    if (future != null) await future;
    final err = openError;
    if (err != null) {
      openError = null;
      throw err;
    }
  }

  @override
  Future<BridgeTabDump> dump() async {
    final outcome = _dumpOutcomes.isNotEmpty
        ? _dumpOutcomes.removeAt(0)
        : (_lastOutcome ?? StateError('no dump queued'));
    _lastOutcome = outcome;
    if (outcome is BridgeTabDump) return outcome;
    throw outcome;
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
  }
}

BridgeTabDump _dump(
  List<String> rows, {
  int? cursorRow,
  bool cursorVisible = false,
}) => BridgeTabDump(
  cols: 80,
  rows: rows.length,
  cursorRow: cursorRow,
  cursorCol: 0,
  cursorVisible: cursorVisible,
  rowsText: rows,
);

Widget _app(PeekSource source) => ProviderScope(
  child: MaterialApp(
    home: RoostPeekScreen(
      machineName: 'mini3',
      tabId: 7,
      title: 'row7',
      peekSource: source,
    ),
  ),
);

/// Flush the microtask chain an open()/refresh() cycle runs through — no real
/// Timer or IO is involved, so a couple of zero-advance pumps is enough; it
/// is NOT a [tester.pump] with a 2s duration, which is reserved for
/// deliberately firing the periodic poll.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('renders rows from the first dump and highlights the cursor', (
    tester,
  ) async {
    final source = _FakePeekSource()
      ..pushDump(
        _dump(['\$ ls', 'file.txt'], cursorRow: 1, cursorVisible: true),
      );

    await tester.pumpWidget(_app(source));
    await _settle(tester);

    expect(find.text('row7'), findsOneWidget); // app-bar title
    expect(find.text('\$ ls'), findsOneWidget);
    expect(find.text('file.txt'), findsOneWidget);
    expect(find.byKey(const ValueKey('roost-peek-cursor')), findsOneWidget);
    expect(source.openCalls, 1);
  });

  testWidgets(
    'no highlight when the cursor is not visible (negative control)',
    (tester) async {
      final source = _FakePeekSource()
        ..pushDump(_dump(['\$ ls', 'file.txt'], cursorRow: 1));

      await tester.pumpWidget(_app(source));
      await _settle(tester);

      // The rows DID render — the absent highlight is about `cursorVisible`,
      // not an empty screen.
      expect(find.text('file.txt'), findsOneWidget);
      expect(find.byKey(const ValueKey('roost-peek-cursor')), findsNothing);
    },
  );

  testWidgets('a later dump with new rows refreshes the view', (tester) async {
    final source = _FakePeekSource()
      ..pushDump(_dump(['first']))
      ..pushDump(_dump(['second', 'third']));

    await tester.pumpWidget(_app(source));
    await _settle(tester);
    expect(find.text('first'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('second'), findsOneWidget);
    expect(find.text('third'), findsOneWidget);
    expect(find.text('first'), findsNothing);
  });

  testWidgets(
    'a dump error shows the error line and a following good dump clears it',
    (tester) async {
      final source = _FakePeekSource()..pushDump(_dump(['ok']));
      await tester.pumpWidget(_app(source));
      await _settle(tester);
      expect(find.text('ok'), findsOneWidget);
      expect(find.byKey(const ValueKey('roost-peek-error')), findsNothing);

      source.pushError();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.byKey(const ValueKey('roost-peek-error')), findsOneWidget);
      // The last-good frame stays on screen underneath the error line, and
      // polling keeps the same 2s cadence (no error-driven backoff).
      expect(find.text('ok'), findsOneWidget);

      source.pushDump(_dump(['recovered']));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.byKey(const ValueKey('roost-peek-error')), findsNothing);
      expect(find.text('recovered'), findsOneWidget);
    },
  );

  testWidgets('dispose calls close exactly once', (tester) async {
    final source = _FakePeekSource()..pushDump(_dump(['x']));
    await tester.pumpWidget(_app(source));
    await _settle(tester);
    expect(source.closeCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(source.closeCalls, 1);
  });

  testWidgets('an open failure shows retry, and retry re-opens', (
    tester,
  ) async {
    final source = _FakePeekSource()
      ..openError = StateError('the machine is not connected')
      ..pushDump(_dump(['back online']));

    await tester.pumpWidget(_app(source));
    await _settle(tester);

    expect(find.byKey(const ValueKey('roost-peek-retry')), findsOneWidget);
    expect(find.byKey(const ValueKey('roost-peek-open-error')), findsOneWidget);
    expect(source.openCalls, 1);

    await tester.tap(find.byKey(const ValueKey('roost-peek-retry')));
    await _settle(tester);

    expect(source.openCalls, 2);
    expect(source.closeCalls, 1); // retry closes the failed attempt first
    expect(find.byKey(const ValueKey('roost-peek-retry')), findsNothing);
    expect(find.text('back online'), findsOneWidget);
  });

  testWidgets(
    'disposing while open() is still in flight closes the handle once it '
    'lands, exactly once',
    (tester) async {
      // `open()` never resolves on its own here — the test drives it — so the
      // widget is torn down mid-open on purpose: that is the race where
      // `dispose()` runs before `_open()`'s `await source.open()` returns,
      // and the freshly-opened handle used to have nothing left to close it.
      final opened = Completer<void>();
      final source = _FakePeekSource()
        ..openFuture = opened.future
        ..pushDump(_dump(['x']));

      await tester.pumpWidget(_app(source));
      await tester.pump(); // let _open() reach the pending open() await
      expect(source.closeCalls, 0);

      // Dispose the screen before open() completes.
      await tester.pumpWidget(const SizedBox.shrink());
      expect(
        source.closeCalls,
        0,
        reason:
            'dispose must not close a source whose open() has not '
            'settled yet — the pending _open() call owns that',
      );

      // Now let open() land, after the widget is gone.
      opened.complete();
      await tester.pump();
      await tester.pump();

      expect(source.closeCalls, 1);
    },
  );

  testWidgets(
    'a source that throws building/opening leaves nothing dangling when '
    'disposed unmounted',
    (tester) async {
      // Mirrors the same race, but on the failure path: `open()` still
      // throws after the widget is gone, and any partially-acquired
      // resource must still be released exactly once.
      final opened = Completer<void>();
      final source = _FakePeekSource()..openFuture = opened.future;

      await tester.pumpWidget(_app(source));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(source.closeCalls, 0);

      opened.completeError(StateError('boom'));
      await tester.pump();
      await tester.pump();

      expect(source.closeCalls, 1);
    },
  );

  testWidgets(
    'a source-build failure (e.g. no tunnel port) renders the open error, '
    'not an unhandled exception',
    (tester) async {
      // `_buildProductionSource()` (real signature: reads the machine feed's
      // tunnel port and throws when it is null — no tunnel yet) used to run
      // OUTSIDE `_open()`'s try block, so that failure never reached the
      // error-rendering path at all. `peekSourceBuilder` stands in for it
      // here so the same failure-during-build case is exercisable with no
      // real machine feed (and no Rust bridge) behind it — see its doc on
      // [RoostPeekScreen].
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: RoostPeekScreen(
              machineName: 'mini3',
              tabId: 7,
              title: 'row7',
              peekSourceBuilder: () =>
                  throw StateError('mini3 is not connected'),
            ),
          ),
        ),
      );
      await _settle(tester);

      expect(
        find.byKey(const ValueKey('roost-peek-open-error')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('roost-peek-retry')), findsOneWidget);
      expect(
        find.text('Bad state: mini3 is not connected'),
        findsOneWidget,
        reason:
            'the build failure must reach the SAME error line an open() '
            'failure does, not an unhandled exception',
      );
    },
  );
}
