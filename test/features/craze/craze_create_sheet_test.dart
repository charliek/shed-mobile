import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/craze/craze_create.dart';
import 'package:shed_mobile/features/craze/craze_create_sheet.dart';
import 'package:shed_mobile/features/craze/craze_resume.dart';
import 'package:shed_mobile/features/create/create_rc_target.dart';
import 'package:shed_mobile/features/lanes/lane_screen.dart';
import 'package:shed_mobile/features/rc/create_rc_screen.dart';
import 'package:shed_mobile/lanes/lane_controller.dart';
import 'package:shed_mobile/lanes/lane_state.dart';
import 'package:shed_mobile/machines/machine_feed.dart';
import 'package:shed_mobile/machines/machine_record.dart';
import 'package:shed_mobile/providers.dart';
import 'package:shed_mobile/src/rust/api/craze.dart';
import 'package:shed_mobile/src/rust/api/dto_lane.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';
import 'package:shed_mobile/theme/shed_theme.dart';

/// **The create screen's craze choice** (plan 025 §3.8, CM4) — the sheet the
/// desktop's `CrazeCreateDialog` is, rendered on the phone's create screen.
///
/// Everything below the bridge is a fake feed: the options it answers, the
/// creates it records (with the request id each carried) and the states it
/// pushes — live, offline, too old. The real hub's half (craze's own
/// createOptions, a real start failure, a real lost answer) is
/// `integration_test/craze_test.dart`'s.
const _mini3 = MachineRecord(name: 'mini3', host: 'mini3.example');

/// craze's createOptions on the recipe rig: cursor missing, grok ready (the
/// default), native without a key; two recent directories.
const _recipe = BridgeLaneCreateOptions(
  providers: [
    BridgeLaneProvider(
      id: 'cursor',
      label: 'cursor',
      state: BridgeLaneProviderState.unavailable(),
      reason: 'cursor-agent not found on PATH',
      fix: 'install cursor-agent',
    ),
    BridgeLaneProvider(
      id: 'grok',
      label: 'grok',
      state: BridgeLaneProviderState.ready(),
    ),
    BridgeLaneProvider(
      id: 'native',
      label: 'native',
      state: BridgeLaneProviderState.needsSetup(),
      reason: 'no model provider has a key',
      fix: 'craze auth login',
    ),
  ],
  defaultProvider: 'grok',
  recentDirs: ['/home/u/proj', '/home/u/other'],
  reopen: false,
);

/// The recipe read again later: grok needs setup now, and native has its key.
const _grokNotReady = BridgeLaneCreateOptions(
  providers: [
    BridgeLaneProvider(
      id: 'cursor',
      label: 'cursor',
      state: BridgeLaneProviderState.unavailable(),
      reason: 'cursor-agent not found on PATH',
      fix: 'install cursor-agent',
    ),
    BridgeLaneProvider(
      id: 'grok',
      label: 'grok',
      state: BridgeLaneProviderState.needsSetup(),
      reason: 'grok has no key',
      fix: 'craze auth login grok',
    ),
    BridgeLaneProvider(
      id: 'native',
      label: 'native',
      state: BridgeLaneProviderState.ready(),
    ),
  ],
  defaultProvider: 'grok',
  recentDirs: ['/home/u/proj', '/home/u/other'],
  reopen: false,
);

const _liveTitled = BridgeCrazeSnapshot(
  rows: [],
  live: true,
  caps: BridgeSourceCapabilities(
    kind: 'craze',
    create: true,
    createOptions: true,
    createTitle: true,
    reopen: false,
  ),
  truncated: false,
);

const _live = BridgeCrazeSnapshot(
  rows: [],
  live: true,
  caps: BridgeSourceCapabilities(
    kind: 'craze',
    create: true,
    createOptions: true,
    createTitle: false,
    reopen: false,
  ),
  truncated: false,
);

BridgeCrazeSnapshot _offline(BridgeSourceOffline cause) => BridgeCrazeSnapshot(
  rows: const [],
  live: false,
  offline: BridgeCrazeOffline(cause: cause, reason: 'gone'),
  caps: _live.caps,
  truncated: false,
);

const _newHost = 'cccccccccccc';

BridgeLaneSession _session(String id, {String cwd = '/home/u/proj'}) =>
    BridgeLaneSession(
      id: id,
      title: 'grok in proj',
      cwd: cwd,
      activity: BridgeRcActivity.working,
      pendingApprovals: 0,
      approximate: false,
      provider: 'grok',
    );

/// A [MachineFeed] that answers the create sheet's two calls from a script.
/// The real one dials SSH and calls the bridge in its constructor, so it
/// cannot exist in a widget test.
class _FakeFeed implements MachineFeed {
  _FakeFeed({BridgeCrazeSnapshot craze = _live, this.reachable = true})
    : _state = MachineFeedState(
        machine: _mini3,
        reachable: reachable,
        connectedOnce: true,
        capabilities: _caps,
        craze: craze,
      );

  final bool reachable;
  MachineFeedState _state;
  final changes = StreamController<MachineFeedState>.broadcast();

  /// What `crazeOptions` answers: a value, or an error to throw. Null holds
  /// the read open on [optionsGate].
  Object? options = _recipe;
  Completer<void>? optionsGate;
  int optionReads = 0;

  /// Every create this feed was asked for, in order.
  final requests = <BridgeLaneCreateRequest>[];

  /// Whether each of [requests] went as a HELD replay (`crazeCreateHeld`)
  /// rather than a new create (`crazeCreate`) — in step with [requests].
  final replays = <bool>[];

  /// What each create answers, in turn: a [BridgeLaneCreated], an error to
  /// throw, or a [Completer] whose value (or error) is the answer.
  final answers = <Object>[];

  /// A created session is listed — the real feed folds it in before it
  /// returns. False: craze answered for a session that has already ended.
  bool listCreated = true;

  /// How many times the feed provider built this feed, and let it go — the
  /// real feed's teardown closes its craze source and cuts a create short.
  int builds = 0;
  int disposals = 0;

  /// The feed's incarnation (`MachineFeed.incarnation`) — a cell that
  /// rebuilds the feed provider onto ANOTHER fake gives it a larger one.
  @override
  int incarnation = 1;

  /// What `crazeSavedSessions` answers, in turn: a [BridgeLaneSavedSessions],
  /// an error to throw, or a [Completer] whose value (or error) is the
  /// answer.
  final savedAnswers = <Object>[];
  int savedReads = 0;

  /// Every reopen this feed was asked for, by saved id, in order.
  final reopens = <String>[];

  /// What each reopen answers, in turn: a [BridgeLaneReopened], an error to
  /// throw, or a [Completer] whose value (or error) is the answer.
  final reopenAnswers = <Object>[];

  /// A reopened session is listed — the real feed folds it in before it
  /// returns. False: it ended again before it was listed.
  bool listReopened = true;

  /// The reopen's answer came through a craze source the feed has let go of.
  bool reopenSuperseded = false;

  /// The next of [answers]' scripted answers: a [T], an error to throw, or a
  /// [Completer] whose value (or error) is the answer.
  static Future<T> _next<T extends Object>(List<Object> answers) async {
    var answer = answers.removeAt(0);
    if (answer is Completer<Object>) answer = await answer.future;
    if (answer is! T) throw answer;
    return answer;
  }

  /// List [session] — as the real feed folds a created or reopened row in
  /// before it returns.
  void _list(BridgeLaneSession session) => _state = _state.copyWith(
    craze: BridgeCrazeSnapshot(
      rows: [..._state.craze!.rows, session],
      live: true,
      caps: _live.caps,
      truncated: false,
    ),
  );

  @override
  Future<BridgeLaneSavedSessions> crazeSavedSessions() {
    savedReads++;
    return _next(savedAnswers);
  }

  @override
  Future<CrazeReopenAnswer> crazeReopenSession(String id) async {
    reopens.add(id);
    final answer = await _next<BridgeLaneReopened>(reopenAnswers);
    if (listReopened && !reopenSuperseded) _list(answer.session);
    return (reopened: answer, superseded: reopenSuperseded);
  }

  @override
  MachineRecord get machine => _mini3;

  @override
  MachineFeedState get state => _state;

  @override
  Stream<MachineFeedState> get updates => changes.stream;

  void push(MachineFeedState s) {
    _state = s;
    changes.add(s);
  }

  void setCraze(BridgeCrazeSnapshot craze) =>
      push(_state.copyWith(craze: craze));

  /// What `remoteHome` answers.
  String? home = '/home/me';

  @override
  Future<String?> remoteHome() async => home;

  @override
  Future<BridgeLaneCreateOptions> crazeOptions() async {
    optionReads++;
    final gate = optionsGate;
    if (gate != null) await gate.future;
    final o = options;
    if (o is BridgeLaneCreateOptions) return o;
    throw o!;
  }

  @override
  Future<BridgeLaneCreated> crazeCreateSession(
    BridgeLaneCreateRequest request, {
    bool held = false,
  }) async {
    requests.add(request);
    replays.add(held);
    final answer = await _next<BridgeLaneCreated>(answers);
    if (listCreated) _list(answer.session);
    return answer;
  }

  // What the transcript's lane provider reads to build its controller (the
  // screen logs its stamp); the lane itself is the overridden state stream.
  @override
  int? get crazeLiveEpoch => 1;

  @override
  Stream<int?> get crazeSources => const Stream<int?>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _caps = BridgeRcCapabilities(
  rcVersion: 2,
  kinds: [BridgeRcKind.claudeRc(), BridgeRcKind.opencode()],
  agents: {
    'claude': BridgeRcAgentInfo(installed: true),
    'opencode': BridgeRcAgentInfo(installed: true),
  },
  features: [],
  kindFeatures: {},
);

BridgeLaneCreated _created({
  BridgeLanePromptOutcome prompt = const BridgeLanePromptOutcome.accepted(),
  String? error,
}) => BridgeLaneCreated(
  session: _session(_newHost),
  prompt: prompt,
  promptError: error,
);

/// A deterministic mint: `shed-id-1`, `shed-id-2`, …
class _Mint {
  int n = 0;
  String call() => 'shed-id-${++n}';
}

/// Every LaneScreen a create opened: `(machine, kind, slug)`.
final _lanes = <(String, String, String)>[];

/// Pump a navigator whose home pushes the create screen for mini3 (so a
/// created session's transcript REPLACES it, and a pop returns home).
///
/// [then] are the feeds the provider builds AFTER [feed], in turn (the last
/// one again past the end): a cell that rebuilds the feed provider — the
/// machine removed and added again — gets a new incarnation.
Future<ProviderContainer> _pump(
  WidgetTester tester,
  _FakeFeed feed, {
  _Mint? mint,
  bool open = true,
  List<_FakeFeed> then = const [],
}) async {
  _lanes.clear();
  await tester.binding.setSurfaceSize(const Size(500, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final m = mint ?? _Mint();
  final feeds = [feed, ...then];
  var built = 0;
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        machinesProvider.overrideWith((ref) async => const [_mini3]),
        identitiesProvider.overrideWith((ref) async => <SSHKeyPair>[]),
        machineFeedControllerProvider('mini3').overrideWith((ref) {
          final f = feeds[built < feeds.length ? built : feeds.length - 1];
          built++;
          f.builds++;
          ref.onDispose(() => f.disposals++);
          return f;
        }),
        // The state stream holds the feed, as production's does.
        machineFeedProvider('mini3').overrideWith((ref) async* {
          final f =
              ref.watch(machineFeedControllerProvider('mini3')) as _FakeFeed;
          yield f.state;
          yield* f.changes.stream;
        }),
        crazeRequestIdMintProvider.overrideWithValue(m.call),
        laneStateProvider.overrideWith((ref, key) {
          _lanes.add((key.machine, key.kind, key.slug));
          return Stream.value(LaneState());
        }),
      ],
      child: MaterialApp(
        theme: shedLightTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const ValueKey('open-create'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CreateRcScreen(
                      target: MachineRcTarget(machineName: 'mini3'),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (open) await _open(tester);
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open-create')));
  await _settle(tester);
}

/// Bounded pumps — the loading spinner never settles — long enough for a
/// route transition to finish.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _chooseCraze(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('createrc-kind-craze')));
  await _settle(tester);
}

/// Press Back and stop partway through the create screen's reverse
/// animation: the screen — and the sheet in it, its listeners live — still
/// mounted, its route no longer the current one.
Future<void> _leaveMidway(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  final sheet = find.byType(CrazeCreateSheet, skipOffstage: false);
  expect(sheet, findsOneWidget, reason: 'still animating away');
  expect(ModalRoute.isCurrentOf(tester.element(sheet)), isFalse);
}

Finder _key(String k) => find.byKey(ValueKey(k));

bool _submitEnabled(WidgetTester tester) {
  final button = tester.widget<FilledButton>(
    find.descendant(
      of: _key('craze-create-submit'),
      matching: find.byType(FilledButton),
    ),
  );
  return button.onPressed != null;
}

/// The label of the button at [key].
String _buttonLabel(WidgetTester tester, String key) => tester
    .widget<Text>(find.descendant(of: _key(key), matching: find.byType(Text)))
    .data!;

String _submitLabel(WidgetTester tester) =>
    _buttonLabel(tester, 'craze-create-submit');

/// The semantics of the control at [key].
Semantics _semanticsAt(WidgetTester tester, String key) =>
    tester.widget<Semantics>(
      find.descendant(of: _key(key), matching: find.byType(Semantics)).first,
    );

bool _selected(WidgetTester tester, String provider) =>
    _semanticsAt(tester, 'craze-provider-$provider').properties.selected!;

String _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(_key(key)).controller!.text;

String _text(WidgetTester tester, String key) {
  final w = tester.widget(_key(key));
  return switch (w) {
    final Text t => t.data!,
    final SelectableText t => t.data!,
    final Container c => (c.child! as Text).data!,
    _ => throw StateError('no text at $key'),
  };
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.enterText(_key(key), text);
  await tester.pump();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.ensureVisible(_key('craze-create-submit'));
  await tester.tap(_key('craze-create-submit'));
  await _settle(tester);
}

void main() {
  testWidgets('craze is offered only where its source can create', (
    tester,
  ) async {
    await _pump(tester, _FakeFeed());
    expect(_key('createrc-kind-craze'), findsOneWidget);
    expect(_key('createrc-kind-claude-rc'), findsOneWidget);
    expect(_key('createrc-kind-opencode'), findsOneWidget);
    expect(
      _key('craze-create-sheet'),
      findsNothing,
      reason: 'the default kind stays Claude',
    );
  });

  testWidgets('a hub that cannot create offers no craze', (tester) async {
    await _pump(
      tester,
      _FakeFeed(
        craze: const BridgeCrazeSnapshot(
          rows: [],
          live: true,
          caps: BridgeSourceCapabilities(
            kind: 'craze',
            create: true,
            createOptions: false,
            createTitle: false,
            reopen: false,
          ),
          truncated: false,
        ),
      ),
    );
    expect(_key('createrc-kind-craze'), findsNothing);
    expect(_key('createrc-kind-claude-rc'), findsOneWidget);
  });

  testWidgets('an offline or too-old craze offers no craze', (tester) async {
    await _pump(
      tester,
      _FakeFeed(craze: _offline(const BridgeSourceOffline.tooOld())),
    );
    expect(_key('createrc-kind-craze'), findsNothing);
  });

  testWidgets('a machine with craze and no roost still offers craze', (
    tester,
  ) async {
    await _pump(tester, _FakeFeed(reachable: false));
    expect(_key('createrc-kind-craze'), findsOneWidget);
    expect(_key('createrc-kind-claude-rc'), findsNothing);
    expect(
      _text(tester, 'createrc-caps-note'),
      startsWith('roost on mini3 is unreachable'),
    );
  });

  testWidgets(
    'CONTROL: providers in craze\'s order; non-ready ones dimmed, '
    'with reason and fix, and NOT selectable; the ready default preselected',
    (tester) async {
      final feed = _FakeFeed();
      await _pump(tester, feed);
      await _chooseCraze(tester);
      expect(feed.optionReads, 1, reason: 'read on open, nothing cached');

      final rows = tester
          .widgetList<Widget>(
            find.byWidgetPredicate((w) {
              final k = w.key;
              return k is ValueKey<String> &&
                  RegExp(r'^craze-provider-[a-z]+$').hasMatch(k.value);
            }),
          )
          .map((w) => (w.key! as ValueKey<String>).value)
          .toList();
      expect(rows, [
        'craze-provider-cursor',
        'craze-provider-grok',
        'craze-provider-native',
      ]);
      expect(_text(tester, 'craze-provider-state-cursor'), 'unavailable');
      expect(
        _text(tester, 'craze-provider-reason-cursor'),
        'cursor-agent not found on PATH',
      );
      expect(
        _text(tester, 'craze-provider-fix-cursor'),
        'install cursor-agent',
      );
      expect(_text(tester, 'craze-provider-state-native'), 'needs setup');
      expect(_key('craze-provider-reason-grok'), findsNothing);
      expect(_selected(tester, 'grok'), isTrue, reason: 'the default, ready');
      expect(_selected(tester, 'cursor'), isFalse);

      // A tap on a dimmed provider is refused: the rule, not just the look.
      await tester.tap(_key('craze-provider-cursor'));
      await _settle(tester);
      expect(_selected(tester, 'cursor'), isFalse);
      expect(_selected(tester, 'grok'), isTrue);
      await tester.tap(_key('craze-provider-native'));
      await _settle(tester);
      expect(_selected(tester, 'native'), isFalse);
      expect(_selected(tester, 'grok'), isTrue);
    },
  );

  testWidgets('CONTROL: a not-ready default is never preselected', (
    tester,
  ) async {
    final feed = _FakeFeed()
      ..options = const BridgeLaneCreateOptions(
        providers: [
          BridgeLaneProvider(
            id: 'native',
            label: 'native',
            state: BridgeLaneProviderState.needsSetup(),
            reason: 'no key',
          ),
          BridgeLaneProvider(
            id: 'grok',
            label: 'grok',
            state: BridgeLaneProviderState.ready(),
          ),
        ],
        defaultProvider: 'native',
        recentDirs: [],
        reopen: false,
      );
    await _pump(tester, feed);
    await _chooseCraze(tester);
    expect(_selected(tester, 'native'), isFalse);
    expect(_selected(tester, 'grok'), isTrue, reason: 'the first ready one');
  });

  testWidgets('no ready provider: the sheet says so and Create is disabled', (
    tester,
  ) async {
    final feed = _FakeFeed()
      ..options = BridgeLaneCreateOptions(
        providers: [_recipe.providers[0], _recipe.providers[2]],
        defaultProvider: 'grok',
        recentDirs: const [],
        reopen: false,
      );
    await _pump(tester, feed);
    await _chooseCraze(tester);
    await _type(tester, 'craze-create-cwd', '/w');
    expect(_text(tester, 'craze-create-note'), noProviderReady);
    expect(_submitEnabled(tester), isFalse);
  });

  testWidgets('recent directories are one tap; a path must be absolute', (
    tester,
  ) async {
    await _pump(tester, _FakeFeed());
    await _chooseCraze(tester);
    expect(_submitEnabled(tester), isFalse, reason: 'no directory yet');
    expect(_key('craze-create-cwd-problem'), findsNothing, reason: 'untouched');

    await _type(tester, 'craze-create-cwd', 'relative/dir');
    expect(
      _text(tester, 'craze-create-cwd-problem'),
      'an absolute path, or one starting with ~/',
    );
    expect(_submitEnabled(tester), isFalse);

    await tester.tap(_key('craze-recent-dir-1'));
    await _settle(tester);
    expect(_field(tester, 'craze-create-cwd'), '/home/u/other');
    expect(_key('craze-create-cwd-problem'), findsNothing);
    expect(_submitEnabled(tester), isTrue);
  });

  testWidgets('the options read failing says why and retries; the form stays', (
    tester,
  ) async {
    final feed = _FakeFeed()
      ..options = const BridgeLaneError.unavailable(msg: 'hub went away');
    await _pump(tester, feed);
    await _chooseCraze(tester);
    await _type(tester, 'craze-create-cwd', '/typed');
    expect(_text(tester, 'craze-create-options-error'), contains('hub went'));
    expect(_submitEnabled(tester), isFalse);

    feed.options = _recipe;
    await tester.tap(_key('craze-create-options-retry'));
    await _settle(tester);
    expect(feed.optionReads, 2);
    expect(_selected(tester, 'grok'), isTrue);
    expect(_field(tester, 'craze-create-cwd'), '/typed');
    expect(_submitEnabled(tester), isTrue);
  });

  testWidgets('CONTROL: no state clears the typed form — offline, too old, '
      'and back', (tester) async {
    final feed = _FakeFeed();
    await _pump(tester, feed);
    await _chooseCraze(tester);
    await _type(tester, 'craze-create-cwd', '/typed/before/the/outage');
    await _type(tester, 'craze-create-prompt', 'kept\nacross the outage');
    expect(_submitEnabled(tester), isTrue);

    feed.setCraze(_offline(const BridgeSourceOffline.unreachable()));
    await _settle(tester);
    expect(
      _text(tester, 'craze-create-note'),
      'craze on mini3 is offline (unreachable) — your form is kept',
    );
    expect(_submitEnabled(tester), isFalse);
    expect(
      _key('createrc-kind-craze'),
      findsOneWidget,
      reason: 'the chosen craze stays on screen to say why',
    );
    expect(_field(tester, 'craze-create-cwd'), '/typed/before/the/outage');
    expect(_field(tester, 'craze-create-prompt'), 'kept\nacross the outage');
    expect(_selected(tester, 'grok'), isTrue);

    feed.setCraze(_offline(const BridgeSourceOffline.tooOld()));
    await _settle(tester);
    expect(_text(tester, 'craze-create-note'), contains('too old'));
    expect(_field(tester, 'craze-create-cwd'), '/typed/before/the/outage');

    feed.setCraze(_live);
    await _settle(tester);
    expect(_key('craze-create-note'), findsNothing);
    expect(_field(tester, 'craze-create-cwd'), '/typed/before/the/outage');
    expect(_field(tester, 'craze-create-prompt'), 'kept\nacross the outage');
    expect(_submitEnabled(tester), isTrue);
  });

  testWidgets('a machine with craze alone opens on the sheet, and keeps it on '
      'screen when its craze drops', (tester) async {
    final feed = _FakeFeed(reachable: false);
    await _pump(tester, feed);
    expect(
      _key('craze-create-sheet'),
      findsOneWidget,
      reason: 'craze is the only kind there is: the screen opens on it',
    );
    await _type(tester, 'craze-create-cwd', '/typed');

    feed.setCraze(_offline(const BridgeSourceOffline.unreachable()));
    await _settle(tester);
    expect(_key('craze-create-sheet'), findsOneWidget);
    expect(_text(tester, 'craze-create-note'), contains('offline'));
    expect(_field(tester, 'craze-create-cwd'), '/typed');
    expect(_submitEnabled(tester), isFalse);
  });

  testWidgets('a create opens its transcript at once, in place of the screen', (
    tester,
  ) async {
    final feed = _FakeFeed()..answers.add(_created());
    await _pump(tester, feed);
    await _chooseCraze(tester);
    await tester.tap(_key('craze-recent-dir-0'));
    await _type(tester, 'craze-create-prompt', 'hello sheet');
    await _submit(tester);

    expect(feed.requests, hasLength(1));
    final sent = feed.requests.single;
    expect(sent.cwd, '/home/u/proj');
    expect(sent.provider, 'grok');
    expect(sent.prompt, 'hello sheet');
    expect(sent.requestId, 'shed-id-1');
    expect(find.byType(LaneScreen), findsOneWidget);
    expect(
      find.byType(CreateRcScreen, skipOffstage: false),
      findsNothing,
      reason: 'replaced, not covered: back leaves the transcript for home',
    );
    expect(_lanes, [('mini3', crazeLaneKind, _newHost)]);
    expect(_key('craze-create-prompt-notice'), findsNothing);
  });

  testWidgets('a typed ~ path is sent expanded against the machine home', (
    tester,
  ) async {
    final feed = _FakeFeed()..answers.add(_created());
    await _pump(tester, feed);
    await _chooseCraze(tester);
    await _type(tester, 'craze-create-cwd', '~/projects/x');
    expect(_key('craze-create-cwd-problem'), findsNothing);
    await _submit(tester);
    expect(feed.requests.single.cwd, '/home/me/projects/x');
  });

  testWidgets('without a known home, a ~ path is refused', (tester) async {
    final feed = _FakeFeed()..home = null;
    await _pump(tester, feed);
    await _chooseCraze(tester);
    await _type(tester, 'craze-create-cwd', '~/projects/x');
    expect(_key('craze-create-cwd-problem'), findsOneWidget);
    expect(_submitEnabled(tester), isFalse);
  });

  testWidgets('a first prompt craze refused is said, and the session opens', (
    tester,
  ) async {
    final feed = _FakeFeed()
      ..answers.add(
        _created(
          prompt: const BridgeLanePromptOutcome.refused(),
          error: 'busy',
        ),
      );
    await _pump(tester, feed);
    await _chooseCraze(tester);
    await _type(tester, 'craze-create-cwd', '/w');
    await _type(tester, 'craze-create-prompt', 'go');
    await _submit(tester);
    expect(find.byType(LaneScreen), findsOneWidget);
    expect(
      find.textContaining('the session refused its first prompt'),
      findsOneWidget,
    );
    expect(find.textContaining('busy'), findsOneWidget);
  });

  testWidgets('a create craze answered for an ENDED session opens nothing', (
    tester,
  ) async {
    final feed = _FakeFeed()
      ..answers.add(_created())
      ..listCreated = false;
    await _pump(tester, feed);
    await _chooseCraze(tester);
    await _type(tester, 'craze-create-cwd', '/w');
    await _submit(tester);
    expect(find.byType(LaneScreen), findsNothing);
    expect(find.byType(CreateRcScreen), findsNothing, reason: 'closed');
    expect(find.text(crazeCreatedEnded), findsOneWidget);
  });

  testWidgets('CONTROL: an unknown outcome holds the id; Try again resumes it '
      '— one request, never a second session', (tester) async {
    final feed = _FakeFeed()
      ..answers.addAll([
        const BridgeLaneError.outcomeUnknown(
          msg: 'outcome unknown: craze did not answer the create, twice',
        ),
        _created(),
      ]);
    final container = await _pump(tester, feed);
    await _chooseCraze(tester);
    await _type(tester, 'craze-create-cwd', '/w/unknown');
    await _submit(tester);

    expect(_key('craze-create-unknown'), findsOneWidget);
    expect(_text(tester, 'craze-create-unknown'), outcomeUnknownNote);
    expect(_submitLabel(tester), 'Try again');
    final draft = container.read(crazeDraftProvider('mini3'));
    expect(draft.phase, CrazePhase.unknown);
    expect(draft.requestId, 'shed-id-1', reason: 'held');
    expect(_field(tester, 'craze-create-cwd'), '/w/unknown');

    await _submit(tester);
    expect(
      [for (final r in feed.requests) r.requestId],
      ['shed-id-1', 'shed-id-1'],
      reason: 'Try again resumed the SAME request',
    );
    expect(
      feed.replays,
      [false, true],
      reason: 'a new create first; Try again goes as a HELD replay (P11)',
    );
    expect(find.byType(LaneScreen), findsOneWidget);
  });

  testWidgets('CONTROL: an unknown outcome keeps its provider and id when a '
      're-open reads that provider as not ready; Try again resends the SAME '
      'request (CodeRabbit, shed-mobile#36)', (tester) async {
    final feed = _FakeFeed()
      ..answers.addAll([
        const BridgeLaneError.outcomeUnknown(msg: 'lost'),
        _created(),
      ]);
    final container = await _pump(tester, feed);
    await _chooseCraze(tester);
    await _type(tester, 'craze-create-cwd', '/w/held');
    await _submit(tester);
    expect(container.read(crazeDraftProvider('mini3')).requestId, 'shed-id-1');

    // A re-open reads the options again, and grok needs setup now: the held
    // request is not re-picked onto native for the person.
    feed.options = _grokNotReady;
    await tester.pageBack();
    await _settle(tester);
    await _open(tester);
    expect(feed.optionReads, 2, reason: 'read again on the re-open');
    final draft = container.read(crazeDraftProvider('mini3'));
    expect(draft.phase, CrazePhase.unknown);
    expect(draft.requestId, 'shed-id-1', reason: 'the held id survives');
    expect(draft.provider, 'grok');
    expect(_text(tester, 'craze-create-unknown'), outcomeUnknownNote);
    expect(_text(tester, 'craze-provider-state-grok'), 'needs setup');
    expect(_selected(tester, 'grok'), isTrue, reason: 'what Try again resends');
    expect(_selected(tester, 'native'), isFalse);
    expect(_submitLabel(tester), 'Try again');
    expect(
      _submitEnabled(tester),
      isTrue,
      reason: 'a replay is not refused over its provider\'s state now',
    );

    await _submit(tester);
    expect(
      [for (final r in feed.requests) (r.requestId, r.provider)],
      [('shed-id-1', 'grok'), ('shed-id-1', 'grok')],
      reason: 'Try again resent the SAME request',
    );
    expect(find.byType(LaneScreen), findsOneWidget);
  });

  testWidgets('CONTROL: an unknown outcome is resendable when its provider is '
      'no longer listed and none reads ready', (tester) async {
    final feed = _FakeFeed()
      ..answers.addAll([
        const BridgeLaneError.outcomeUnknown(msg: 'lost'),
        _created(),
      ]);
    final container = await _pump(tester, feed);
    await _chooseCraze(tester);
    await _type(tester, 'craze-create-cwd', '/w/none');
    await _submit(tester);

    // Only cursor is listed now, and it is unavailable.
    feed.options = BridgeLaneCreateOptions(
      providers: [_recipe.providers[0]],
      defaultProvider: 'grok',
      recentDirs: const [],
      reopen: false,
    );
    await tester.pageBack();
    await _settle(tester);
    await _open(tester);
    expect(container.read(crazeDraftProvider('mini3')).requestId, 'shed-id-1');
    expect(
      _key('craze-create-note'),
      findsNothing,
      reason: '"no provider is ready" does not gate a replay',
    );
    expect(_submitEnabled(tester), isTrue);
    await _submit(tester);
    expect(
      [for (final r in feed.requests) (r.requestId, r.provider)],
      [('shed-id-1', 'grok'), ('shed-id-1', 'grok')],
    );
  });

  testWidgets('CONTROL: a refused draft keeps its refusal across a re-open '
      'that reads its provider as not ready (CodeRabbit, shed-mobile#36)', (
    tester,
  ) async {
    const cause = 'Error: KEYCHAIN LOCKED\nRun unlock and retry.';
    final feed = _FakeFeed()
      ..answers.add(const BridgeLaneError.failed(msg: cause));
    final container = await _pump(tester, feed);
    await _chooseCraze(tester);
    await _type(tester, 'craze-create-cwd', '/w/refused');
    await _submit(tester);
    expect(_text(tester, 'craze-create-cause'), cause);

    feed.options = _grokNotReady;
    await tester.pageBack();
    await _settle(tester);
    await _open(tester);
    await _chooseCraze(tester);
    expect(feed.optionReads, 2, reason: 'read again on the re-open');
    final draft = container.read(crazeDraftProvider('mini3'));
    expect(draft.phase, CrazePhase.refused);
    expect(draft.refusal, const CrazeRefusal('failed', cause));
    expect(draft.provider, 'grok', reason: 'not re-picked for the person');
    expect(_text(tester, 'craze-create-cause'), cause);
    expect(_submitLabel(tester), 'Try again');
    // No id is held, so Try again would be a NEW request on a provider that
    // cannot start: it waits for a ready one, and picking one is the edit
    // that clears the refusal.
    expect(_submitEnabled(tester), isFalse);
    await tester.tap(_key('craze-provider-native'));
    await _settle(tester);
    expect(container.read(crazeDraftProvider('mini3')).phase, CrazePhase.idle);
    expect(_key('craze-create-cause'), findsNothing);
    expect(_submitLabel(tester), 'Create');
    expect(_submitEnabled(tester), isTrue);
  });

  testWidgets('CONTROL: a start failure shows craze\'s cause verbatim, keeps '
      'the form, and Try again sends a NEW id', (tester) async {
    const cause = 'Error: KEYCHAIN LOCKED\nRun unlock and retry.';
    final feed = _FakeFeed()
      ..answers.addAll([const BridgeLaneError.failed(msg: cause), _created()]);
    final container = await _pump(tester, feed);
    await _chooseCraze(tester);
    await _type(tester, 'craze-create-cwd', '/w/fail');
    await _type(tester, 'craze-create-prompt', 'this one will not start');
    await _submit(tester);

    expect(_text(tester, 'craze-create-cause'), cause);
    expect(_submitLabel(tester), 'Try again');
    expect(
      container.read(crazeDraftProvider('mini3')).requestId,
      isNull,
      reason: 'a definite answer ends the id\'s life',
    );
    expect(_field(tester, 'craze-create-cwd'), '/w/fail');
    expect(_field(tester, 'craze-create-prompt'), 'this one will not start');

    await _submit(tester);
    expect(
      [for (final r in feed.requests) r.requestId],
      ['shed-id-1', 'shed-id-2'],
    );
    expect(
      feed.replays,
      [false, false],
      reason: 'a definite answer ended the id: Try again is a NEW create',
    );
    expect(find.byType(LaneScreen), findsOneWidget);
  });

  testWidgets('the Name field shows when the hub takes a title, or while one '
      'is typed', (tester) async {
    final plain = _FakeFeed();
    final container = await _pump(tester, plain);
    await _chooseCraze(tester);
    expect(_key('craze-create-title'), findsNothing);
    expect(_key('craze-create-cwd'), findsOneWidget);
    container
        .read(crazeDraftProvider('mini3').notifier)
        .edit(title: 'Typed earlier');
    await tester.pump();
    expect(_key('craze-create-title'), findsOneWidget);
    expect(_field(tester, 'craze-create-title'), 'Typed earlier');
  });

  testWidgets('a new request without createTitle still carries the typed '
      'title', (tester) async {
    final feed = _FakeFeed()
      ..answers.addAll([
        const BridgeLaneError.badRequest(
          msg: 'params.title is not supported by this hub',
        ),
      ]);
    final container = await _pump(tester, feed);
    await _chooseCraze(tester);
    container
        .read(crazeDraftProvider('mini3').notifier)
        .edit(title: '  Kept  ');
    await tester.pump();
    await _type(tester, 'craze-create-cwd', '/w/a');
    await _submit(tester);
    expect(feed.requests.single.title, 'Kept');
    expect(_key('craze-create-title'), findsOneWidget);
    expect(
      _text(tester, 'craze-create-title-problem'),
      'params.title is not supported by this hub',
    );
  });

  testWidgets('a bad_request naming a path with "title" stays a directory '
      'error', (tester) async {
    final feed = _FakeFeed(craze: _liveTitled)
      ..answers.add(const BridgeLaneError.badRequest(msg: 'cwd /w/title nope'));
    await _pump(tester, feed);
    await _chooseCraze(tester);
    await _type(tester, 'craze-create-cwd', '/w/title');
    await _submit(tester);
    expect(_key('craze-create-title-problem'), findsNothing);
    expect(_text(tester, 'craze-create-cwd-problem'), 'cwd /w/title nope');
  });

  testWidgets('CONTROL: a Name is sent trimmed; blank is omitted', (
    tester,
  ) async {
    final feed = _FakeFeed(craze: _liveTitled)
      ..answers.addAll([_created(), _created()]);
    await _pump(tester, feed);
    await _chooseCraze(tester);
    expect(find.text('Name (optional)'), findsOneWidget);
    await _type(tester, 'craze-create-cwd', '/w/a');
    await _type(tester, 'craze-create-title', '  Fix login  ');
    await _submit(tester);
    expect(feed.requests.single.title, 'Fix login');
  });

  testWidgets('CONTROL: a blank Name is never sent', (tester) async {
    final feed = _FakeFeed(craze: _liveTitled)..answers.add(_created());
    await _pump(tester, feed);
    await _chooseCraze(tester);
    await _type(tester, 'craze-create-cwd', '/w/a');
    await _type(tester, 'craze-create-title', '   ');
    await _submit(tester);
    expect(feed.requests.single.title, isNull);
  });

  testWidgets('CONTROL: the held retry keeps the id AND the title; an edit '
      'mints a new id', (tester) async {
    final feed = _FakeFeed(craze: _liveTitled)
      ..answers.addAll([
        const BridgeLaneError.outcomeUnknown(msg: 'lost'),
        const BridgeLaneError.outcomeUnknown(msg: 'lost again'),
        _created(),
      ]);
    final container = await _pump(tester, feed);
    await _chooseCraze(tester);
    await _type(tester, 'craze-create-cwd', '/w/a');
    await _type(tester, 'craze-create-title', 'Fix login');
    await _submit(tester);
    expect(container.read(crazeDraftProvider('mini3')).sentTitle, 'Fix login');
    await _submit(tester);
    expect(
      [for (final r in feed.requests) (r.requestId, r.title)],
      [('shed-id-1', 'Fix login'), ('shed-id-1', 'Fix login')],
    );
    await _type(tester, 'craze-create-title', 'Fix logout');
    expect(container.read(crazeDraftProvider('mini3')).requestId, isNull);
    await _submit(tester);
    expect(feed.requests.last.requestId, 'shed-id-2');
    expect(feed.requests.last.title, 'Fix logout');
    expect(
      feed.replays,
      [false, true, false],
      reason:
          'only the retry of the held id is a held replay; the edit made '
          'a NEW request',
    );
  });

  testWidgets('CONTROL: Try again REPLAYS the held request — held, the same id '
      'and title — and stays held while its answer is unknown (P11: a titled '
      'replay whose hub no longer says createTitle)', (tester) async {
    final feed = _FakeFeed(craze: _liveTitled)
      ..answers.addAll([
        const BridgeLaneError.outcomeUnknown(msg: 'lost'),
        // What `craze_create_held` answers when the retry's hub lacks
        // createTitle: unknown again, never a definite Failed.
        const BridgeLaneError.outcomeUnknown(
          msg:
              'outcome unknown: the retry reached a hub that cannot name a '
              'session',
        ),
        _created(),
      ]);
    final container = await _pump(tester, feed);
    await _chooseCraze(tester);
    await _type(tester, 'craze-create-cwd', '/w/a');
    await _type(tester, 'craze-create-title', '  Fix login  ');
    await _submit(tester);
    await _submit(tester); // Try again: the hub has lost createTitle
    final draft = container.read(crazeDraftProvider('mini3'));
    expect(draft.phase, CrazePhase.unknown);
    expect(draft.requestId, 'shed-id-1', reason: 'still held');
    expect(draft.sentTitle, 'Fix login', reason: 'the exact title, still');
    expect(_text(tester, 'craze-create-unknown'), outcomeUnknownNote);
    expect(_submitLabel(tester), 'Try again');

    await _submit(tester); // Try again: createTitle is back
    expect(
      [
        for (final (i, r) in feed.requests.indexed)
          (r.requestId, r.title, feed.replays[i]),
      ],
      [
        ('shed-id-1', 'Fix login', false),
        ('shed-id-1', 'Fix login', true),
        ('shed-id-1', 'Fix login', true),
      ],
      reason: 'one request: every Try again replays it as a held create',
    );
    expect(find.byType(LaneScreen), findsOneWidget);
  });

  testWidgets('CONTROL: a held replay the feed could not send keeps its id; a '
      'new create it could not send is a definite refusal', (tester) async {
    const gone = 'craze is not connected on mini3';
    final feed = _FakeFeed()
      ..answers.addAll([
        StateError(gone),
        const BridgeLaneError.outcomeUnknown(msg: 'lost'),
        StateError(gone),
        _created(),
      ]);
    final container = await _pump(tester, feed);
    await _chooseCraze(tester);
    await _type(tester, 'craze-create-cwd', '/w/a');

    // A NEW create the feed refused before sending: definite.
    await _submit(tester);
    var draft = container.read(crazeDraftProvider('mini3'));
    expect(draft.phase, CrazePhase.refused);
    expect(draft.requestId, isNull, reason: 'nothing names this request');

    await _submit(tester); // a new request, and its answer is lost
    expect(container.read(crazeDraftProvider('mini3')).requestId, 'shed-id-2');

    // The REPLAY the feed refused before sending: the first attempt may have
    // started the session, so the outcome is still unknown and the id kept.
    await _submit(tester);
    draft = container.read(crazeDraftProvider('mini3'));
    expect(draft.phase, CrazePhase.unknown);
    expect(draft.requestId, 'shed-id-2', reason: 'still held');
    expect(_text(tester, 'craze-create-unknown'), outcomeUnknownNote);

    await _submit(tester);
    expect(
      [
        for (final (i, r) in feed.requests.indexed)
          (r.requestId, feed.replays[i]),
      ],
      [
        ('shed-id-1', false),
        ('shed-id-2', false),
        ('shed-id-2', true),
        ('shed-id-2', true),
      ],
    );
    expect(find.byType(LaneScreen), findsOneWidget);
  });

  testWidgets('a refusal about the title is said under Name, others beside '
      'the directory', (tester) async {
    final feed = _FakeFeed(craze: _liveTitled)
      ..answers.addAll([
        const BridgeLaneError.badRequest(
          msg: 'params.title is blank once normalized: send none instead',
        ),
        const BridgeLaneError.badRequest(msg: 'cwd /w/nope does not exist'),
      ]);
    await _pump(tester, feed);
    await _chooseCraze(tester);
    await _type(tester, 'craze-create-cwd', '/w/a');
    await _type(tester, 'craze-create-title', '\u200b');
    await _submit(tester);
    expect(
      _text(tester, 'craze-create-title-problem'),
      'params.title is blank once normalized: send none instead',
    );
    expect(_key('craze-create-cwd-problem'), findsNothing);
    await _submit(tester);
    expect(_key('craze-create-title-problem'), findsNothing);
    expect(
      _text(tester, 'craze-create-cwd-problem'),
      'cwd /w/nope does not exist',
    );
  });

  testWidgets('craze\'s bad_request is said beside the directory', (
    tester,
  ) async {
    final feed = _FakeFeed()
      ..answers.add(
        const BridgeLaneError.badRequest(msg: 'cwd /w/nope does not exist'),
      );
    await _pump(tester, feed);
    await _chooseCraze(tester);
    await _type(tester, 'craze-create-cwd', '/w/nope');
    await _submit(tester);
    expect(
      _text(tester, 'craze-create-cwd-problem'),
      'cwd /w/nope does not exist',
    );
  });

  testWidgets('leaving while a create runs keeps it running; a re-open finds '
      'the same form and id, and opens the session when it lands', (
    tester,
  ) async {
    final pending = Completer<Object>();
    final feed = _FakeFeed()..answers.add(pending);
    final container = await _pump(tester, feed);
    await _chooseCraze(tester);
    await _type(tester, 'craze-create-cwd', '/w/slow');
    await _submit(tester);
    expect(_submitLabel(tester), 'Creating…');
    expect(_submitEnabled(tester), isFalse);

    // Leave: the create keeps running.
    await tester.pageBack();
    await _settle(tester);
    expect(find.byType(CreateRcScreen), findsNothing);
    expect(
      container.read(crazeDraftProvider('mini3')).phase,
      CrazePhase.submitting,
    );

    // Re-open: the craze choice, the same form, the same id, still creating.
    await _open(tester);
    expect(_key('craze-create-sheet'), findsOneWidget);
    expect(_field(tester, 'craze-create-cwd'), '/w/slow');
    expect(_submitLabel(tester), 'Creating…');
    expect(container.read(crazeDraftProvider('mini3')).requestId, 'shed-id-1');

    pending.complete(_created());
    await _settle(tester);
    expect(feed.requests, hasLength(1), reason: 'one create, never two');
    expect(find.byType(LaneScreen), findsOneWidget);
  });

  testWidgets('the machine\'s feed is HELD while a create runs: leaving the '
      'screen does not tear it down under the create, and it goes after', (
    tester,
  ) async {
    final pending = Completer<Object>();
    final feed = _FakeFeed()..answers.add(pending);
    await _pump(tester, feed);
    await _chooseCraze(tester);
    await _type(tester, 'craze-create-cwd', '/w/held');
    await _submit(tester);
    expect(feed.builds, 1);

    await tester.pageBack();
    await _settle(tester);
    expect(
      feed.disposals,
      0,
      reason: 'the create in flight holds its feed (and so its connection)',
    );

    pending.complete(_created());
    await _settle(tester);
    expect(feed.disposals, 1, reason: 'and lets it go once it settles');
  });

  testWidgets('a create that lands with no sheet on screen opens nothing — '
      'the session is simply a row', (tester) async {
    final pending = Completer<Object>();
    final feed = _FakeFeed()..answers.add(pending);
    final container = await _pump(tester, feed);
    await _chooseCraze(tester);
    await _type(tester, 'craze-create-cwd', '/w/away');
    await _submit(tester);
    await tester.pageBack();
    await _settle(tester);

    pending.complete(_created());
    await _settle(tester);
    expect(find.byType(LaneScreen), findsNothing);
    final draft = container.read(crazeDraftProvider('mini3'));
    expect(draft.phase, CrazePhase.idle);
    expect(draft.cwd, '', reason: 'spent');
    expect(draft.lastCreated?.hostId, _newHost);

    // A later open starts clean, and does not re-open the old session.
    await _open(tester);
    await _chooseCraze(tester);
    expect(_field(tester, 'craze-create-cwd'), '');
    expect(find.byType(LaneScreen), findsNothing);
  });

  testWidgets('CONTROL: a create landing while the sheet is LEAVING — Back '
      'pressed, its screen still animating away — navigates nowhere: the '
      'screen beneath stays, the draft still spent', (tester) async {
    final pending = Completer<Object>();
    final feed = _FakeFeed()..answers.add(pending);
    final container = await _pump(tester, feed);
    await _chooseCraze(tester);
    await _type(tester, 'craze-create-cwd', '/w/leaving');
    await _submit(tester);

    await _leaveMidway(tester);
    pending.complete(_created());
    await tester.pump();
    expect(
      find.byType(CrazeCreateSheet, skipOffstage: false),
      findsOneWidget,
      reason: 'it landed while the sheet was still mounted',
    );
    expect(container.read(crazeDraftProvider('mini3')).lastCreated, isNotNull);

    await _settle(tester);
    expect(find.byType(LaneScreen), findsNothing, reason: 'nothing pushed');
    expect(find.byType(CreateRcScreen), findsNothing, reason: 'Back finished');
    expect(_key('open-create'), findsOneWidget, reason: 'the screen beneath');
    final draft = container.read(crazeDraftProvider('mini3'));
    expect(draft.phase, CrazePhase.idle);
    expect(draft.cwd, '', reason: 'spent: the session is simply a row');
    expect(draft.lastCreated?.hostId, _newHost);
  });

  testWidgets('an unknown outcome reopens on the craze choice', (tester) async {
    final feed = _FakeFeed()
      ..answers.add(const BridgeLaneError.outcomeUnknown(msg: 'lost'));
    await _pump(tester, feed);
    await _chooseCraze(tester);
    await _type(tester, 'craze-create-cwd', '/w/u');
    await _submit(tester);
    await tester.pageBack();
    await _settle(tester);
    await _open(tester);
    expect(_key('craze-create-sheet'), findsOneWidget);
    expect(_text(tester, 'craze-create-unknown'), outcomeUnknownNote);
    expect(_submitLabel(tester), 'Try again');
  });

  // -------------------------------------------------------------------------
  // Resume (plan 032 §3.4, M3)
  // -------------------------------------------------------------------------

  group('Resume', () {
    testWidgets('CONTROL: New | Resume is offered exactly where the options '
        'say reopen, and the sheet opens on New', (tester) async {
      final feed = _FakeFeed()..options = _recipeReopen;
      await _pump(tester, feed);
      await _chooseCraze(tester);
      expect(_key('craze-mode'), findsOneWidget);
      expect(_modeSelected(tester, 'new'), isTrue);
      expect(_modeEnabled(tester, 'resume'), isTrue);
      expect(_key('craze-create-submit'), findsOneWidget, reason: 'New');
      expect(feed.savedReads, 0, reason: 'nothing read until Resume');
    });

    testWidgets('a hub before 0.2.0 (no reopen) offers no Resume', (
      tester,
    ) async {
      await _pump(tester, _FakeFeed());
      await _chooseCraze(tester);
      expect(_key('craze-create-sheet'), findsOneWidget);
      expect(_key('craze-mode'), findsNothing);
      expect(_key('craze-create-submit'), findsOneWidget);
    });

    testWidgets('CONTROL: Resume reads the list on its FIRST choice — the '
        'title (or Untitled), provider, workspace with the home as ~, age, '
        'and "Showing the 50 most recent."', (tester) async {
      final feed = _FakeFeed()
        ..options = _recipeReopen
        ..savedAnswers.add(_savedList(more: true));
      await _pump(tester, feed);
      await _chooseCraze(tester);
      await _chooseMode(tester, 'resume');
      expect(feed.savedReads, 1);
      expect(_modeSelected(tester, 'resume'), isTrue);
      expect(
        _key('craze-create-submit'),
        findsNothing,
        reason: 'no Create in the Resume half',
      );
      expect(_text(tester, 'craze-saved-title-$_savedA'), 'fix the parser');
      expect(_text(tester, 'craze-saved-title-$_savedB'), 'Untitled');
      expect(_text(tester, 'craze-saved-provider-$_savedA'), 'grok');
      expect(
        _text(tester, 'craze-saved-workspace-$_savedA'),
        '~/proj',
        reason: 'the feed\'s home, shortened',
      );
      expect(
        _text(tester, 'craze-saved-workspace-$_savedB'),
        '/srv/other',
        reason: 'not under the home: whole',
      );
      expect(_text(tester, 'craze-saved-updated-$_savedA'), '5 min ago');
      expect(_text(tester, 'craze-saved-more'), 'Showing the 50 most recent.');
      expect(_resumeLabel(tester, _savedA), 'Resume');
      expect(_resumeEnabled(tester, _savedA), isTrue);

      // New and back: read once, not again.
      await _chooseMode(tester, 'new');
      expect(_key('craze-create-submit'), findsOneWidget);
      await _chooseMode(tester, 'resume');
      expect(feed.savedReads, 1, reason: 'not again until the sheet reopens');
    });

    testWidgets('a failed list read says why; its Retry reads again', (
      tester,
    ) async {
      final feed = _FakeFeed()
        ..options = _recipeReopen
        ..savedAnswers.addAll([
          const BridgeLaneError.unavailable(msg: 'the hub is busy'),
          _savedList(),
        ]);
      await _pump(tester, feed);
      await _chooseCraze(tester);
      await _chooseMode(tester, 'resume');
      expect(
        _text(tester, 'craze-saved-list-error'),
        'craze could not list saved sessions: the hub is busy',
      );
      await tester.tap(_key('craze-saved-list-retry'));
      await _settle(tester);
      expect(feed.savedReads, 2);
      expect(_key('craze-saved-title-$_savedA'), findsOneWidget);
    });

    testWidgets('CONTROL: a Resume runs one reopen — "Resuming… (this can '
        'take a few minutes)", every other button and the mode disabled — '
        'and opens the transcript at once', (tester) async {
      final pending = Completer<Object>();
      final feed = _FakeFeed()
        ..options = _recipeReopen
        ..savedAnswers.add(_savedList())
        ..reopenAnswers.add(pending);
      await _pump(tester, feed);
      await _chooseCraze(tester);
      await _chooseMode(tester, 'resume');
      await _resume(tester, _savedA);

      expect(feed.reopens, [_savedA]);
      expect(
        _resumeLabel(tester, _savedA),
        'Resuming… (this can take a few minutes)',
      );
      expect(_resumeEnabled(tester, _savedA), isFalse);
      expect(
        _resumeEnabled(tester, _savedB),
        isFalse,
        reason: 'one at a time: the other row waits',
      );
      expect(_modeEnabled(tester, 'new'), isFalse, reason: 'the mode waits');
      expect(_key('craze-resume-leaving'), findsOneWidget);
      // Pressed anyway, the other row's button sends nothing.
      await tester.tap(_key('craze-saved-resume-$_savedB'));
      await _settle(tester);
      expect(feed.reopens, [_savedA]);

      pending.complete(_reopened());
      await _settle(tester);
      expect(find.byType(LaneScreen), findsOneWidget);
      expect(_lanes.last, ('mini3', 'craze', _reopenedHost));
      expect(find.byType(CreateRcScreen), findsNothing, reason: 'replaced');
    });

    testWidgets('CONTROL: gone drops the row and says why where it was; '
        'start_failed keeps it with craze\'s cause; every button works '
        'again', (tester) async {
      const words = 'the session\'s directory /home/me/proj is gone';
      final feed = _FakeFeed()
        ..options = _recipeReopen
        ..savedAnswers.add(_savedList())
        ..reopenAnswers.addAll([
          const BridgeLaneReopenError.gone(msg: words),
          const BridgeLaneReopenError.startFailed(
            msg: 'could not start: grok exited\nsee its log',
          ),
        ]);
      final container = await _pump(tester, feed);
      await _chooseCraze(tester);
      await _chooseMode(tester, 'resume');
      await _resume(tester, _savedA);
      expect(_key('craze-saved-$_savedA'), findsNothing, reason: 'dropped');
      expect(
        _text(tester, 'craze-saved-gone'),
        '“fix the parser” cannot run here any more, so it was removed: '
        '$words',
      );
      expect(_resumeEnabled(tester, _savedB), isTrue);
      expect(_modeEnabled(tester, 'new'), isTrue);

      await _resume(tester, _savedB);
      expect(_key('craze-saved-$_savedB'), findsOneWidget, reason: 'kept');
      expect(
        _text(tester, 'craze-saved-error-$_savedB'),
        'could not start: grok exited\nsee its log',
        reason: 'the cause, verbatim',
      );
      expect(
        tester.widget(_key('craze-saved-error-$_savedB')),
        isA<SelectableText>(),
        reason: 'monospace and selectable, as the create\'s cause',
      );
      expect(_resumeLabel(tester, _savedB), 'Resume');
      expect(_resumeEnabled(tester, _savedB), isTrue);
      expect(find.byType(LaneScreen), findsNothing);
      expect(
        container.read(crazeResumeProvider('mini3')).gone,
        isNull,
        reason: 'the next reopen cleared the gone note',
      );
    });

    testWidgets('CONTROL: unavailable — a lost answer — offers Retry, the row '
        'kept, and Retry reopens it', (tester) async {
      const lost =
          'the reopen\'s answer was lost; the session may already be running '
          '— Retry is safe';
      final feed = _FakeFeed()
        ..options = _recipeReopen
        ..savedAnswers.add(_savedList())
        ..reopenAnswers.addAll([
          const BridgeLaneReopenError.unavailable(msg: lost),
          _reopened(joined: true),
        ]);
      await _pump(tester, feed);
      await _chooseCraze(tester);
      await _chooseMode(tester, 'resume');
      await _resume(tester, _savedA);
      expect(_resumeLabel(tester, _savedA), 'Retry');
      expect(_text(tester, 'craze-saved-error-$_savedA'), '$lost — Retry');
      expect(_key('craze-saved-$_savedA'), findsOneWidget);

      await _resume(tester, _savedA);
      expect(feed.reopens, [_savedA, _savedA]);
      expect(find.byType(LaneScreen), findsOneWidget);
    });

    testWidgets('a superseded answer opens nothing and is said on its row', (
      tester,
    ) async {
      final feed = _FakeFeed()
        ..options = _recipeReopen
        ..savedAnswers.add(_savedList())
        ..reopenAnswers.add(_reopened())
        ..reopenSuperseded = true;
      await _pump(tester, feed);
      await _chooseCraze(tester);
      await _chooseMode(tester, 'resume');
      await _resume(tester, _savedA);
      expect(find.byType(LaneScreen), findsNothing);
      expect(_text(tester, 'craze-saved-error-$_savedA'), supersededNote);
      expect(_resumeLabel(tester, _savedA), 'Resume');
      expect(_resumeEnabled(tester, _savedA), isTrue);
    });

    testWidgets('a reopened session that ended again before it was listed '
        'opens nothing: said, and the screen closes', (tester) async {
      final feed = _FakeFeed()
        ..options = _recipeReopen
        ..savedAnswers.add(_savedList())
        ..reopenAnswers.add(_reopened())
        ..listReopened = false;
      await _pump(tester, feed);
      await _chooseCraze(tester);
      await _chooseMode(tester, 'resume');
      await _resume(tester, _savedA);
      expect(find.byType(LaneScreen), findsNothing);
      expect(find.byType(CreateRcScreen), findsNothing);
      expect(find.text(resumedEnded), findsOneWidget);
    });

    testWidgets('leaving while a reopen runs keeps it running and its feed '
        'held; a re-open finds it Resuming…; landing with no sheet on screen '
        'opens nothing', (tester) async {
      final pending = Completer<Object>();
      final feed = _FakeFeed()
        ..options = _recipeReopen
        ..savedAnswers.addAll([_savedList(), _savedList()])
        ..reopenAnswers.add(pending);
      final container = await _pump(tester, feed);
      await _chooseCraze(tester);
      await _chooseMode(tester, 'resume');
      await _resume(tester, _savedA);

      await tester.pageBack();
      await _settle(tester);
      expect(find.byType(CreateRcScreen), findsNothing);
      expect(feed.disposals, 0, reason: 'the reopen in flight holds its feed');

      // Re-open: straight onto the craze choice, Resume, still running.
      await _open(tester);
      expect(_key('craze-create-sheet'), findsOneWidget);
      expect(_modeSelected(tester, 'resume'), isTrue);
      expect(
        _resumeLabel(tester, _savedA),
        'Resuming… (this can take a few minutes)',
      );
      expect(feed.savedReads, 1, reason: 'the list as it was left');

      // Leave again; the answer lands with no sheet on screen.
      await tester.pageBack();
      await _settle(tester);
      pending.complete(_reopened());
      await _settle(tester);
      expect(find.byType(LaneScreen), findsNothing);
      expect(feed.reopens, [_savedA], reason: 'one reopen, never two');
      expect(feed.disposals, 1, reason: 'the feed let go once it settled');
      final r = container.read(crazeResumeProvider('mini3'));
      expect(resumingId(r), isNull);
      expect(r.landed?.hostId, _reopenedHost);

      // A later open starts on New, nothing running, and opens nothing.
      await _open(tester);
      await _chooseCraze(tester);
      expect(_modeSelected(tester, 'new'), isTrue);
      expect(find.byType(LaneScreen), findsNothing);
      await _chooseMode(tester, 'resume');
      expect(feed.savedReads, 2, reason: 'read afresh');
    });

    testWidgets('CONTROL: a reopen landing while the sheet is LEAVING — Back '
        'pressed, its screen still animating away — navigates nowhere: the '
        'screen beneath stays, and the landing is kept', (tester) async {
      final pending = Completer<Object>();
      final feed = _FakeFeed()
        ..options = _recipeReopen
        ..savedAnswers.addAll([_savedList(), _savedList()])
        ..reopenAnswers.add(pending);
      final container = await _pump(tester, feed);
      await _chooseCraze(tester);
      await _chooseMode(tester, 'resume');
      await _resume(tester, _savedA);

      await _leaveMidway(tester);
      pending.complete(_reopened());
      await tester.pump();
      expect(
        find.byType(CrazeCreateSheet, skipOffstage: false),
        findsOneWidget,
        reason: 'it landed while the sheet was still mounted',
      );
      expect(
        container.read(crazeResumeProvider('mini3')).landed?.landing,
        ReopenLanding.open,
      );

      await _settle(tester);
      expect(find.byType(LaneScreen), findsNothing, reason: 'nothing pushed');
      expect(
        find.byType(CreateRcScreen),
        findsNothing,
        reason: 'Back finished',
      );
      expect(_key('open-create'), findsOneWidget, reason: 'the screen beneath');
      expect(feed.reopens, [_savedA], reason: 'one reopen, never two');
      final r = container.read(crazeResumeProvider('mini3'));
      expect(resumingId(r), isNull, reason: 'the state landed all the same');
      expect(r.landed?.hostId, _reopenedHost);

      // A later open starts on New, nothing running, and opens nothing.
      await _open(tester);
      await _chooseCraze(tester);
      expect(_modeSelected(tester, 'new'), isTrue);
      expect(find.byType(LaneScreen), findsNothing);
    });

    testWidgets('CONTROL: an ENDED reopen landing while the sheet is leaving '
        'pops nothing — the screen beneath stays', (tester) async {
      final pending = Completer<Object>();
      final feed = _FakeFeed()
        ..options = _recipeReopen
        ..savedAnswers.add(_savedList())
        ..reopenAnswers.add(pending)
        ..listReopened = false;
      final container = await _pump(tester, feed);
      await _chooseCraze(tester);
      await _chooseMode(tester, 'resume');
      await _resume(tester, _savedA);

      await _leaveMidway(tester);
      pending.complete(_reopened());
      await tester.pump();
      expect(
        find.byType(CrazeCreateSheet, skipOffstage: false),
        findsOneWidget,
        reason: 'it landed while the sheet was still mounted',
      );
      expect(
        container.read(crazeResumeProvider('mini3')).landed?.landing,
        ReopenLanding.ended,
      );

      await _settle(tester);
      expect(
        find.byType(CreateRcScreen),
        findsNothing,
        reason: 'Back finished',
      );
      expect(
        _key('open-create'),
        findsOneWidget,
        reason: 'the screen beneath is not popped',
      );
      expect(find.text(resumedEnded), findsNothing, reason: 'nothing said');
    });

    testWidgets('CONTROL: a feed rebuilt while a reopen runs is a new '
        'incarnation: the sheet starts afresh on New, and the old reopen\'s '
        'late answer is dropped whole', (tester) async {
      final pending = Completer<Object>();
      final feed = _FakeFeed()
        ..options = _recipeReopen
        ..savedAnswers.add(_savedList())
        ..reopenAnswers.add(pending);
      final next = _FakeFeed()
        ..incarnation = 2
        ..options = _recipeReopen;
      final container = await _pump(tester, feed, then: [next]);
      await _chooseCraze(tester);
      await _chooseMode(tester, 'resume');
      await _resume(tester, _savedA);
      expect(_modeEnabled(tester, 'new'), isFalse);

      // The machine removed and added again under the same name.
      container.invalidate(machineFeedControllerProvider('mini3'));
      await _settle(tester);
      expect(next.builds, 1);
      final fresh = container.read(crazeResumeProvider('mini3'));
      expect(fresh.gen, 2);
      expect(fresh.mode, CrazeSheetMode.newSession);
      expect(resumingId(fresh), isNull, reason: 'nothing running here');
      expect(_modeSelected(tester, 'new'), isTrue);
      expect(_modeEnabled(tester, 'resume'), isTrue, reason: 'not locked');

      // The old incarnation's answer, late: no state change, no navigation.
      pending.complete(_reopened());
      await _settle(tester);
      expect(find.byType(LaneScreen), findsNothing);
      expect(container.read(crazeResumeProvider('mini3')).landed, isNull);
      expect(container.read(crazeResumeProvider('mini3')).gen, 2);
    });

    testWidgets('the drive log names the mode, the rows and each row\'s state; '
        'MRESULT says each read and reopen', (tester) async {
      final lines = <String>[];
      final saved = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) lines.add(message);
      };
      try {
        final pending = Completer<Object>();
        final feed = _FakeFeed()
          ..options = _recipeReopen
          ..savedAnswers.add(_savedList(more: true))
          ..reopenAnswers.add(pending);
        await _pump(tester, feed);
        await _chooseCraze(tester);
        String state() => lines.lastWhere(
          (l) => l.startsWith('MSTATE screen=craze-create machine='),
        );
        expect(state(), contains(' mode=new modes=on saved=unloaded rows=- '));
        await _chooseMode(tester, 'resume');
        expect(lines, contains('MRESULT craze-saved ok'));
        expect(
          state(),
          contains(
            ' mode=resume modes=on saved=ready '
            'rows=$_savedA:idle,$_savedB:idle more=true gone=-',
          ),
        );
        await _resume(tester, _savedA);
        expect(
          state(),
          contains(' modes=locked saved=ready rows=$_savedA:resuming,'),
        );
        pending.complete(const BridgeLaneReopenError.startFailed(msg: 'x'));
        await _settle(tester);
        expect(lines, isNot(contains('MRESULT craze-resume ok')));
        expect(lines, contains(startsWith('MRESULT craze-resume error=')));
        expect(state(), contains('rows=$_savedA:refused,$_savedB:idle'));
      } finally {
        debugPrint = saved;
      }
    });
  });
}

/// The recipe's create options from a 0.2.0 hub: it can reopen.
const _recipeReopen = BridgeLaneCreateOptions(
  providers: [
    BridgeLaneProvider(
      id: 'grok',
      label: 'grok',
      state: BridgeLaneProviderState.ready(),
    ),
  ],
  defaultProvider: 'grok',
  recentDirs: ['/home/u/proj'],
  reopen: true,
);

/// The saved sessions' ids: one titled, under the home; one untitled, not.
const _savedA = '0192f0aa-a';
const _savedB = 'grok:legacy';

/// The hostId a reopen answers with.
const _reopenedHost = 'dddddddddddd';

/// craze's saved list: [_savedA] last active five minutes ago, [_savedB]
/// yesterday.
BridgeLaneSavedSessions _savedList({bool more = false}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return BridgeLaneSavedSessions(
    sessions: [
      BridgeLaneSavedSession(
        id: _savedA,
        provider: 'grok',
        workspace: '/home/me/proj',
        title: 'fix the parser',
        updatedUnixMs: now - 5 * 60 * 1000 - 1000,
      ),
      BridgeLaneSavedSession(
        id: _savedB,
        provider: 'grok',
        workspace: '/srv/other',
        updatedUnixMs: now - 30 * 3600 * 1000,
      ),
    ],
    more: more,
  );
}

BridgeLaneReopened _reopened({bool joined = false}) => BridgeLaneReopened(
  session: _session(_reopenedHost, cwd: '/home/me/proj'),
  joined: joined,
);

Future<void> _chooseMode(WidgetTester tester, String mode) async {
  await tester.tap(_key('craze-mode-$mode'));
  await _settle(tester);
}

/// Press the saved row [id]'s Resume (or Retry).
Future<void> _resume(WidgetTester tester, String id) async {
  final button = _key('craze-saved-resume-$id');
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await _settle(tester);
}

bool _modeSelected(WidgetTester tester, String mode) =>
    _semanticsAt(tester, 'craze-mode-$mode').properties.selected!;

bool _modeEnabled(WidgetTester tester, String mode) =>
    _semanticsAt(tester, 'craze-mode-$mode').properties.enabled!;

bool _resumeEnabled(WidgetTester tester, String id) =>
    tester.widget<FilledButton>(_key('craze-saved-resume-$id')).onPressed !=
    null;

String _resumeLabel(WidgetTester tester, String id) =>
    _buttonLabel(tester, 'craze-saved-resume-$id');
