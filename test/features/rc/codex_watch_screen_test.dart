import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/control/control_token_provider.dart';
import 'package:shed_mobile/core/app_error.dart';
import 'package:shed_mobile/features/rc/codex_watch_screen.dart';
import 'package:shed_mobile/net/pinned_http_client.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/rc/rc_capabilities.dart';
import 'package:shed_mobile/rc/rc_events.dart';
import 'package:shed_mobile/rc/rc_feed.dart';
import 'package:shed_mobile/rc/rc_models.dart';
import 'package:shed_mobile/shed/shed_client.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

class _NoHttp extends PinnedHttpClient {
  _NoHttp() : super(host: 'x', port: 1, fingerprint: 'sha256:00');
  @override
  void close() {}
}

class _Tok implements TokenSource {
  @override
  Future<String?> get() async => null;
  @override
  void invalidate(String token) {}
}

class _FakeClient extends ShedClient {
  _FakeClient({this.page, this.pages, this.messagesError, this.onInput})
    : super(_NoHttp(), _Tok());
  final RcMessagesPage? page;

  /// Scripted per-call handler (receives the `since` cursor); wins over [page].
  final RcMessagesPage Function(int since)? pages;

  /// Thrown from every fetch (Object, not just AppError — the broad-catch
  /// tests throw a raw StateError).
  final Object? messagesError;
  final Future<void> Function()? onInput;

  /// Every fetch's `since` cursor, in order (the reload/regression tests
  /// assert on it).
  final fetches = <int>[];

  @override
  Future<RcMessagesPage> fetchRcMessages(
    String shed,
    String slug, {
    int? since,
    int? limit,
  }) async {
    fetches.add(since ?? 0);
    final err = messagesError;
    if (err != null) throw err;
    if (pages != null) return pages!(since ?? 0);
    // First page returns the fixture; a subsequent drain returns empty.
    return (since ?? 0) == 0
        ? page!
        : const RcMessagesPage(messages: [], truncated: false);
  }

  @override
  Future<void> postRcInput(String shed, String slug, String text) async {
    if (onInput != null) await onInput!();
  }
}

RcFeedMessage _msg(int seq, String role, String type, {String? text}) =>
    RcFeedMessage(seq: seq, role: role, type: type, text: text);

const _codexSession = RcSession(
  slug: 'cdx777',
  tmuxSession: 'rc-cdx777',
  displayName: 'proj/cdx777',
  kind: RcKind.codex,
  state: RcState.ready,
  managed: true,
);

RcCapabilities _gatedCaps() => RcCapabilities.fromJson(const {
  'rc_version': 3,
  'kind_features': {
    'codex': {
      'post_input': true,
      'approvals': 'tui',
      'watch': true,
      'input': 'gated',
    },
  },
});

Future<void> _pump(
  WidgetTester tester, {
  required _FakeClient client,
  RcSession session = _codexSession,
  RcCapabilities? caps,
  ActivityOverlay overlay = ActivityOverlay.empty,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        shedClientProvider.overrideWith((ref, name) async => client),
        shedCapabilitiesProvider.overrideWith((ref, key) async => caps),
        liveActivityProvider.overrideWith((ref, name) => Stream.value(overlay)),
      ],
      child: MaterialApp(
        theme: shedLightTheme,
        home: CodexWatchScreen(
          serverName: 'h',
          shedName: 'proj',
          session: session,
        ),
      ),
    ),
  );
  // Bounded pumps: run the postFrame _reload, its async fetch, and the
  // scroll-to-bottom animation. A plain pumpAndSettle would hang on a pulsing
  // "working" activity dot (a repeating animation).
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

ActivityOverlay _overlay(RcActivity activity, RcState state) =>
    ActivityOverlay.empty.apply(
      RcActivityChanged(
        shed: 'proj',
        slug: 'cdx777',
        activity: activity,
        state: state,
      ),
    );

void main() {
  testWidgets('renders the feed messages (plain text, no truncation divider)', (
    tester,
  ) async {
    await _pump(
      tester,
      client: _FakeClient(
        page: RcMessagesPage(
          messages: [
            _msg(1, 'user', 'text', text: 'do the thing'),
            _msg(2, 'assistant', 'text', text: 'on it'),
          ],
          truncated: false,
        ),
      ),
    );
    expect(find.byKey(const ValueKey('codex-watch-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('codex-watch-msg-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('codex-watch-msg-2')), findsOneWidget);
    expect(find.text('do the thing'), findsOneWidget);
    expect(find.byKey(const ValueKey('codex-watch-truncated')), findsNothing);
  });

  testWidgets('a truncated first page shows the history-truncated divider', (
    tester,
  ) async {
    await _pump(
      tester,
      client: _FakeClient(
        page: RcMessagesPage(
          messages: [_msg(50, 'assistant', 'text', text: 'mid-stream')],
          truncated: true,
        ),
      ),
    );
    expect(find.byKey(const ValueKey('codex-watch-truncated')), findsOneWidget);
  });

  testWidgets('input is gated: disabled unless needs_input + gated kind', (
    tester,
  ) async {
    // Working (not waiting) → input disabled even for the gated codex kind.
    await _pump(
      tester,
      caps: _gatedCaps(),
      overlay: _overlay(RcActivity.working, RcState.ready),
      client: _FakeClient(
        page: RcMessagesPage(
          messages: [_msg(1, 'assistant', 'text', text: 'working…')],
          truncated: false,
        ),
      ),
    );
    final disabled = tester.widget<TextField>(
      find.byKey(const ValueKey('codex-watch-input')),
    );
    expect(disabled.enabled, isFalse);
  });

  testWidgets(
    'needs_input + gated → input enabled; a 409 send surfaces a snackbar',
    (tester) async {
      await _pump(
        tester,
        caps: _gatedCaps(),
        overlay: _overlay(RcActivity.needsInput, RcState.ready),
        client: _FakeClient(
          page: RcMessagesPage(
            messages: [_msg(1, 'assistant', 'text', text: 'your turn')],
            truncated: false,
          ),
          onInput: () async =>
              throw AppError('RC_NOT_ACCEPTING', 'not waiting', 409),
        ),
      );
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('codex-watch-input')),
      );
      expect(field.enabled, isTrue);

      await tester.enterText(
        find.byKey(const ValueKey('codex-watch-input')),
        'hello',
      );
      await tester.tap(find.byKey(const ValueKey('codex-watch-send')));
      await _settle(tester);
      expect(
        find.text('Session is no longer waiting for input'),
        findsOneWidget,
      );
    },
  );

  testWidgets('needs-auth lifecycle shows the TUI handoff banner', (
    tester,
  ) async {
    await _pump(
      tester,
      session: const RcSession(
        slug: 'cdx777',
        tmuxSession: 'rc-cdx777',
        displayName: 'proj/cdx777',
        kind: RcKind.codex,
        state: RcState.needsAuth,
        managed: true,
      ),
      client: _FakeClient(
        page: RcMessagesPage(
          messages: [
            _msg(1, 'assistant', 'text', text: 'history stays readable'),
          ],
          truncated: false,
        ),
      ),
    );
    expect(find.byKey(const ValueKey('codex-watch-banner')), findsOneWidget);
    // The banner's handoff button carries the -banner suffix (the plain key
    // belongs to the error/unavailable body — the two can coexist on screen).
    expect(
      find.byKey(const ValueKey('codex-watch-open-tui-banner')),
      findsOneWidget,
    );
  });

  testWidgets('a 503 on load shows the "unavailable" state + TUI handoff', (
    tester,
  ) async {
    await _pump(
      tester,
      client: _FakeClient(
        messagesError: AppError('RC_HUB_UNAVAILABLE', 'hub down', 503),
      ),
    );
    expect(
      find.byKey(const ValueKey('codex-watch-unavailable')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('codex-watch-open-tui')), findsOneWidget);
  });

  testWidgets('a non-AppError transport failure lands in the error state '
      '(never stuck loading)', (tester) async {
    await _pump(
      tester,
      client: _FakeClient(messagesError: StateError('socket closed')),
    );
    expect(find.byKey(const ValueKey('codex-watch-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('codex-watch-loading')), findsNothing);
  });

  testWidgets('duplicate / non-positive seqs are uniquified '
      '(no duplicate-ValueKey crash)', (tester) async {
    await _pump(
      tester,
      client: _FakeClient(
        page: RcMessagesPage(
          messages: [
            _msg(0, 'assistant', 'text', text: 'zero'),
            _msg(1, 'user', 'text', text: 'one'),
            _msg(1, 'user', 'text', text: 'dup'),
            _msg(2, 'assistant', 'text', text: 'two'),
          ],
          truncated: false,
        ),
      ),
    );
    expect(find.byKey(const ValueKey('codex-watch-msg-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('codex-watch-msg-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('codex-watch-msg-0')), findsNothing);
    expect(find.text('dup'), findsNothing);
  });

  testWidgets('a truncated LATER backfill page restarts the backfill once', (
    tester,
  ) async {
    var calls = 0;
    final client = _FakeClient(
      pages: (since) {
        calls++;
        if (calls == 1) {
          // A full first page (== the 200 page limit) → pagination continues.
          return RcMessagesPage(
            messages: [
              for (var i = 1; i <= 200; i++)
                _msg(i, 'assistant', 'text', text: 'm$i'),
            ],
            truncated: false,
          );
        }
        if (calls == 2) {
          // The ring dropped/restarted mid-pagination: stale cursor.
          return const RcMessagesPage(messages: [], truncated: true);
        }
        // The restarted backfill's fresh head (drop-oldest → truncated).
        return RcMessagesPage(
          messages: [_msg(300, 'assistant', 'text', text: 'fresh')],
          truncated: true,
        );
      },
    );
    await _pump(tester, client: client);
    // Pre-restart accumulation was discarded; the fresh head renders with the
    // truncation divider.
    expect(find.byKey(const ValueKey('codex-watch-truncated')), findsOneWidget);
    expect(find.byKey(const ValueKey('codex-watch-msg-300')), findsOneWidget);
    // The restart happened exactly once: 0 → 200 → 0 again.
    expect(client.fetches, [0, 200, 0]);
  });

  testWidgets('a seq REGRESSION (hub restart) triggers a full reload, '
      'not a stalled targeted drain', (tester) async {
    final client = _FakeClient(
      page: RcMessagesPage(
        messages: [
          _msg(1, 'assistant', 'text', text: 'a'),
          _msg(2, 'assistant', 'text', text: 'b'),
        ],
        truncated: false,
      ),
    );
    final overlays = StreamController<ActivityOverlay>();
    addTearDown(overlays.close);
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shedClientProvider.overrideWith((ref, name) async => client),
          shedCapabilitiesProvider.overrideWith((ref, key) async => null),
          liveActivityProvider.overrideWith((ref, name) => overlays.stream),
        ],
        child: MaterialApp(
          theme: shedLightTheme,
          home: CodexWatchScreen(
            serverName: 'h',
            shedName: 'proj',
            session: _codexSession,
          ),
        ),
      ),
    );
    await _settle(tester); // initial load: since=0, _lastSeq settles at 2
    final before = client.fetches.length;

    // The hub restarted: seq resets to 1 (< the held cursor of 2).
    overlays.add(
      ActivityOverlay.empty.apply(
        const RcMessageAppended(shed: 'proj', slug: 'cdx777', seq: 1),
      ),
    );
    await _settle(tester);
    // A full reload (fresh since=0 fetch) — a since=2 drain would stall on
    // empty pages forever against the restarted ring.
    expect(client.fetches.length, greaterThan(before));
    expect(client.fetches.sublist(before), contains(0));
  });
}
