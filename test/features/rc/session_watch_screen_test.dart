import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/rc/session_watch_screen.dart';
import 'package:shed_mobile/features/rc/session_watch_source.dart';
import 'package:shed_mobile/features/terminal/terminal_target.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

/// **Render off `kind_features`, never off the kind — where it now matters.**
///
/// This is the block's load-bearing correctness rule, and the watch screen is
/// where it has teeth: this is the only place a session can be directed, so
/// this is the only place a control can lie. Offering a verb a kind does not
/// take produces a `409 not_supported` the user cannot act on.
///
/// The three shapes the real contract has, taken from mini3's own capabilities:
///
/// | kind     | approvals | input   | interrupt | send enabled when | interrupt |
/// |----------|-----------|---------|-----------|-------------------|-----------|
/// | opencode | remote    | turn    | yes       | alive             | offered   |
/// | codex    | tui       | gated   | no        | it is WAITING     | hidden    |
/// | shell    | (absent)  | —       | —         | never             | hidden    |
///
/// A source stands in for the transport, which is exactly what the seam is for:
/// the screen cannot tell a shed from a machine, so neither does this file.
class _FakeSource extends SessionWatchSource {
  _FakeSource({
    required this.features,
    this.state = BridgeRcState.ready,
    this.activity,
    this.messages_ = const [],
  });

  final BridgeRcKindFeatures? features;
  final BridgeRcState state;
  final BridgeRcActivity? activity;
  final List<BridgeRcFeedMessage> messages_;

  final sentInputs = <String>[];
  final sentTurns = <String>[];
  int interrupts = 0;
  bool interruptAnswer = true;

  @override
  String get slug => 'abc123';

  @override
  String get title => 'mini3/abc123';

  @override
  TerminalTarget get terminalTarget => const ShedTerminalTarget(
    serverName: 'h',
    shedName: 'mini3',
    slug: 'abc123',
    title: 't',
  );

  @override
  WatchedSession watch(WidgetRef ref) =>
      (state: state, activity: activity, lastSeq: null, features: features);

  @override
  Future<BridgeRcMessagesPage> messages(
    WidgetRef ref, {
    required BigInt since,
    required int limit,
  }) async => BridgeRcMessagesPage(messages: messages_, truncated: false);

  @override
  Future<void> sendInput(WidgetRef ref, String text) async =>
      sentInputs.add(text);

  @override
  Future<void> steer(WidgetRef ref, String text) async => sentTurns.add(text);

  @override
  Future<bool> interrupt(WidgetRef ref) async {
    interrupts++;
    return interruptAnswer;
  }
}

BridgeRcKindFeatures _features({
  required String approvals,
  required String input,
  required bool interrupt,
}) => BridgeRcKindFeatures(
  postInput: true,
  approvals: approvals,
  watch: true,
  input: input,
  feed: 'messages',
  interrupt: interrupt,
  attach: 'tmux',
);

final _opencode = _features(
  approvals: 'remote',
  input: 'turn',
  interrupt: true,
);
final _codex = _features(approvals: 'tui', input: 'gated', interrupt: false);

/// Bounded pumps, not `pumpAndSettle`: a session that is WORKING renders a
/// pulsing activity badge, and a repeating animation never settles. The
/// terminal screen's tests bound their pumps for the same reason (its cursor
/// blink).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _pump(WidgetTester tester, _FakeSource source) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      child: MaterialApp(
        theme: shedLightTheme,
        home: SessionWatchScreen(source: source),
      ),
    ),
  );
  await _settle(tester);
}

Finder get _sendButton => find.byKey(const ValueKey('session-watch-send'));
Finder get _input => find.byKey(const ValueKey('session-watch-input'));

bool _enabled(WidgetTester tester) =>
    tester.widget<IconButton>(_sendButton).onPressed != null;

void main() {
  testWidgets('a turn kind can be directed whenever it is alive', (
    tester,
  ) async {
    // Not only while it is "waiting": a structured turn is how you interrupt a
    // train of thought with new direction, which is the whole point of being
    // able to steer from a phone.
    final s = _FakeSource(
      features: _opencode,
      activity: BridgeRcActivity.working,
    );
    await _pump(tester, s);

    expect(_enabled(tester), isTrue);
    await tester.enterText(_input, 'describe this project');
    await tester.tap(_sendButton);
    await _settle(tester);

    expect(s.sentTurns, ['describe this project']);
    expect(
      s.sentInputs,
      isEmpty,
      reason: 'a turn kind must not get the keystroke verb',
    );
  });

  testWidgets('a gated kind is writable unless it is blocked on a decision', (
    tester,
  ) async {
    // codex and cursor are TUIs that QUEUE typing mid-turn — codex's own footer
    // offers "tab to queue message" — and the hub delivers accordingly. Closing
    // the box while the agent worked hid it during exactly the turn a person
    // most wants to correct.
    final working = _FakeSource(
      features: _codex,
      activity: BridgeRcActivity.working,
    );
    await _pump(tester, working);
    expect(
      _enabled(tester),
      isTrue,
      reason: 'mid-turn text is queued, not lost',
    );

    await tester.enterText(_input, 'actually, use the other file');
    await tester.tap(_sendButton);
    await _settle(tester);
    expect(working.sentInputs, ['actually, use the other file']);
    expect(working.sentTurns, isEmpty, reason: 'a gated kind takes keystrokes');

    final waiting = _FakeSource(
      features: _codex,
      activity: BridgeRcActivity.needsInput,
    );
    await _pump(tester, waiting);
    expect(_enabled(tester), isTrue);

    // The one activity that still closes it: under an approval a line does not
    // queue, it ANSWERS the dialog — and the hub 409s it for the same reason.
    final blocked = _FakeSource(
      features: _codex,
      activity: BridgeRcActivity.needsApproval,
    );
    await _pump(tester, blocked);
    expect(
      _enabled(tester),
      isFalse,
      reason: 'a keystroke under a dialog answers it',
    );
  });

  testWidgets('interrupt is offered only to a kind that advertises it', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeSource(features: _codex, activity: BridgeRcActivity.working),
    );
    expect(
      find.byKey(const ValueKey('session-watch-interrupt')),
      findsNothing,
      reason: 'codex reports interrupt:false — the button would 409',
    );

    final oc = _FakeSource(
      features: _opencode,
      activity: BridgeRcActivity.working,
    );
    await _pump(tester, oc);
    expect(
      find.byKey(const ValueKey('session-watch-interrupt')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('session-watch-interrupt')));
    await _settle(tester);
    expect(oc.interrupts, 1);
  });

  testWidgets('"nothing was running" is reported as information, not an error', (
    tester,
  ) async {
    // Interrupting an idle session is a no-op the user asked for. Surfacing it
    // as a failure trains people to ignore the error path.
    final s = _FakeSource(features: _opencode, activity: BridgeRcActivity.idle)
      ..interruptAnswer = false;
    await _pump(tester, s);

    await tester.tap(find.byKey(const ValueKey('session-watch-interrupt')));
    await _settle(tester);

    expect(find.text('Nothing was running'), findsOneWidget);
    expect(find.textContaining('failed'), findsNothing);
  });

  testWidgets('a kind with no capabilities at all is observe-only', (
    tester,
  ) async {
    // `shell` has no kind_features entry, and a capability probe that failed
    // yields the same null. Failing OPEN here — assuming a kind is directable
    // because its name usually is — is exactly the mistake the rule forbids.
    final s = _FakeSource(
      features: null,
      activity: BridgeRcActivity.needsInput,
    );
    await _pump(tester, s);

    expect(_enabled(tester), isFalse);
    expect(find.byKey(const ValueKey('session-watch-interrupt')), findsNothing);
  });

  testWidgets('a lifecycle the feed cannot drive hands off to the terminal', (
    tester,
  ) async {
    // needs-auth and dead are not "an error loading the feed" — the session is
    // there, and the only thing that can help is a terminal. So the screen says
    // so up front rather than rendering an empty feed and a dead input bar.
    final s = _FakeSource(features: _opencode, state: BridgeRcState.needsAuth);
    await _pump(tester, s);

    expect(
      find.byKey(const ValueKey('session-watch-open-tui-banner')),
      findsOneWidget,
    );
    expect(_enabled(tester), isFalse, reason: 'nothing typed here can help');
  });

  testWidgets('the feed renders what the source returns', (tester) async {
    // Plain Text by design — the hub sanitizes, so nothing here interprets
    // markup that an agent's output might contain.
    final s = _FakeSource(
      features: _opencode,
      messages_: [
        BridgeRcFeedMessage(
          seq: BigInt.one,
          role: 'user',
          msgType: 'text',
          text: 'describe this project',
        ),
        BridgeRcFeedMessage(
          seq: BigInt.two,
          role: 'assistant',
          msgType: 'text',
          text: 'It is a reverse proxy.',
        ),
      ],
    );
    await _pump(tester, s);

    expect(find.text('describe this project'), findsOneWidget);
    expect(find.text('It is a reverse proxy.'), findsOneWidget);
  });

  testWidgets('the status strip carries lifecycle AND activity, unsqueezed', (
    tester,
  ) async {
    // Both live on their own full-width line rather than beside three action
    // icons, where the app-bar title was truncating to `8c8…` — the one thing
    // on this screen that cannot be inferred from context.
    await _pump(
      tester,
      _FakeSource(
        features: _opencode,
        activity: BridgeRcActivity.needsApproval,
      ),
    );

    expect(find.byKey(const ValueKey('session-watch-state')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('session-watch-activity')),
      findsOneWidget,
    );
    // The slug is never elided, whatever else is on the bar.
    expect(find.text('abc123'), findsOneWidget);
    // …and the origin is readable beside it, so "which box am I on" has an
    // answer now that a shed and a machine render identically.
    expect(find.text('mini3/abc123'), findsOneWidget);
  });

  testWidgets('the terminal is always one tap away', (tester) async {
    // Every kind can fall back to the TUI, including ones with no feed — so the
    // handoff is a permanent action, not something that appears only once the
    // rendered view has already failed.
    for (final f in [_opencode, _codex, null]) {
      await _pump(tester, _FakeSource(features: f));
      expect(
        find.byKey(const ValueKey('session-watch-open-tui-action')),
        findsOneWidget,
      );
    }
  });
}
