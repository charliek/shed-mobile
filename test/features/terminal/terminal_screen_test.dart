import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/terminal/terminal_screen.dart';
import 'package:shed_mobile/ssh/host_key_store.dart';
import 'package:shed_mobile/ssh/pty_session.dart';
import 'package:xterm/xterm.dart';

/// A [PtySession]-shaped double whose output stream, `done` future, and start
/// outcome the test drives directly — so the terminal's connect / reconnect /
/// dispose lifecycle is exercisable without a real SSH PTY. It extends the
/// concrete [PtySession] (the injection seam is typed to it) and overrides only
/// the surface the screen touches.
class _FakePty extends PtySession {
  _FakePty()
    : super(
        host: 'h',
        port: 22,
        user: 'web',
        identities: const [],
        hostKeys: _hostKeys,
        slug: 'abc123',
      );

  static final _hostKeys = HostKeyStore();

  final _out = StreamController<Uint8List>.broadcast();
  final _doneC = Completer<int?>();

  /// When set, [start] throws it (models a connect that fails after the pty is
  /// assigned) — driving the screen's error/reconnect path.
  Object? startError;
  bool closed = false;

  @override
  Stream<Uint8List> get output => _out.stream;

  @override
  Future<int?> get done => _doneC.future;

  @override
  Future<void> start({required int cols, required int rows}) async {
    final err = startError;
    if (err != null) throw err;
  }

  @override
  void write(List<int> data) {}

  @override
  void resize(int cols, int rows) {}

  @override
  void close() => closed = true;

  // ---- test drivers ----
  void emit(String s) {
    if (!_out.isClosed) _out.add(Uint8List.fromList(utf8.encode(s)));
  }

  void finish(int? code) {
    if (!_doneC.isCompleted) _doneC.complete(code);
  }
}

/// A [PtyBuilder] that hands out [ptys] in order — one per `_connect()` — so a
/// reconnect gets a distinct pty from the original connection.
PtyBuilder _queue(List<_FakePty> ptys) {
  var i = 0;
  return (
    WidgetRef ref, {
    required String serverName,
    required String shedName,
    required String slug,
  }) async {
    final pty = ptys[i];
    i++;
    return pty;
  };
}

Future<void> _settle(WidgetTester tester) async {
  // Bounded pumps drain the async connect chain; a plain pumpAndSettle would
  // hang on the terminal's repeating cursor-blink timer.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _pump(WidgetTester tester, {required PtyBuilder builder}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: TerminalScreen(
          serverName: 'srv',
          shedName: 'web',
          slug: 'abc123',
          title: 'frontend',
          ptyBuilder: builder,
        ),
      ),
    ),
  );
  await _settle(tester);
}

IconButton _copyButton(WidgetTester tester) =>
    tester.widget<IconButton>(find.byKey(const ValueKey('terminal-copy')));

void main() {
  testWidgets('Copy is disabled with no selection, enabled once a selection is '
      'set, and copies the exact selected buffer text', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _pump(tester, builder: _queue([_FakePty()]));

    // Connected: the Copy action is present but disabled (no selection yet).
    expect(_copyButton(tester).onPressed, isNull);

    final dynamic state = tester.state(find.byType(TerminalScreen));
    final Terminal term = state.terminal as Terminal;
    final TerminalController controller =
        state.terminalController as TerminalController;

    term.write('hello world');
    await tester.pump();

    // Select the first five columns ("hello") of row 0.
    controller.setSelection(
      term.buffer.createAnchor(0, 0),
      term.buffer.createAnchor(5, 0),
    );
    await tester.pump();

    expect(_copyButton(tester).onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('terminal-copy')));
    await tester.pump();
    await tester.pump();

    expect(copied, 'hello');
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('stale connection: after a reconnect supersedes it, the old pty '
      'can neither write to the terminal nor set the exit code', (
    tester,
  ) async {
    final pty1 = _FakePty()..startError = Exception('boom');
    final pty2 = _FakePty();
    await _pump(tester, builder: _queue([pty1, pty2]));

    // gen 1 failed to start -> error screen + reconnect affordance.
    expect(find.byKey(const ValueKey('terminal-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('terminal-reconnect')), findsOneWidget);

    // Reconnect -> gen 2 (pty2), which starts cleanly and goes live.
    await tester.tap(find.byKey(const ValueKey('terminal-reconnect')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('terminal-view')), findsOneWidget);
    expect(pty1.closed, isTrue); // reconnect tore the old pty down

    final dynamic state = tester.state(find.byType(TerminalScreen));
    final Terminal term = state.terminal as Terminal;

    // Late traffic from the superseded gen-1 pty: an output chunk and an exit.
    pty1.emit('STALE-OUTPUT');
    pty1.finish(137);
    await _settle(tester);

    // The generation guard drops both: nothing was written, and the exit code
    // banner never appears (no stale setState).
    expect(term.buffer.getText().contains('STALE-OUTPUT'), isFalse);
    expect(find.byKey(const ValueKey('terminal-ended')), findsNothing);
    // Still the live gen-2 terminal (Copy action present == active session).
    expect(find.byKey(const ValueKey('terminal-copy')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'narrow phone (320px): font-/font+/paste/copy fit the AppBar with '
    'no overflow (no popup menu needed)',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pump(tester, builder: _queue([_FakePty()]));

      for (final key in const [
        'terminal-font-dec',
        'terminal-font-inc',
        'terminal-paste',
        'terminal-copy',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
      // A RenderFlex overflow would surface here.
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dispose cancels the output subscription: a late emit/done from '
      'the detached pty raises no setState-after-dispose error', (
    tester,
  ) async {
    final pty = _FakePty();
    await _pump(tester, builder: _queue([pty]));
    expect(find.byKey(const ValueKey('terminal-view')), findsOneWidget);

    // Tear the screen down.
    await tester.pumpWidget(const SizedBox());
    expect(pty.closed, isTrue); // dispose closed the pty

    // Traffic arriving after dispose must be inert (subscription cancelled,
    // done guarded by !mounted) — no disposed-controller/setState exception.
    pty.emit('after dispose');
    pty.finish(0);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
