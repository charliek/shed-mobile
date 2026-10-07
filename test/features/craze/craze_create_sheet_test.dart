import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/craze/craze_create.dart';
import 'package:shed_mobile/features/craze/craze_create_sheet.dart';
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
);

const _live = BridgeCrazeSnapshot(
  rows: [],
  live: true,
  caps: BridgeSourceCapabilities(
    kind: 'craze',
    create: true,
    createOptions: true,
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
    BridgeLaneCreateRequest request,
  ) async {
    requests.add(request);
    var answer = answers.removeAt(0);
    if (answer is Completer<Object>) answer = await answer.future;
    if (answer is! BridgeLaneCreated) throw answer;
    if (listCreated) {
      _state = _state.copyWith(
        craze: BridgeCrazeSnapshot(
          rows: [..._state.craze!.rows, answer.session],
          live: true,
          caps: _live.caps,
          truncated: false,
        ),
      );
    }
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
Future<ProviderContainer> _pump(
  WidgetTester tester,
  _FakeFeed feed, {
  _Mint? mint,
  bool open = true,
}) async {
  _lanes.clear();
  await tester.binding.setSurfaceSize(const Size(500, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final m = mint ?? _Mint();
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        machinesProvider.overrideWith((ref) async => const [_mini3]),
        identitiesProvider.overrideWith((ref) async => <SSHKeyPair>[]),
        machineFeedControllerProvider('mini3').overrideWith((ref) {
          feed.builds++;
          ref.onDispose(() => feed.disposals++);
          return feed;
        }),
        // The state stream holds the feed, as production's does.
        machineFeedProvider('mini3').overrideWith((ref) async* {
          ref.watch(machineFeedControllerProvider('mini3'));
          yield feed.state;
          yield* feed.changes.stream;
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

String _submitLabel(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: _key('craze-create-submit'),
        matching: find.byType(Text),
      ),
    )
    .data!;

bool _selected(WidgetTester tester, String provider) => tester
    .widget<Semantics>(
      find
          .descendant(
            of: _key('craze-provider-$provider'),
            matching: find.byType(Semantics),
          )
          .first,
    )
    .properties
    .selected!;

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
      'an absolute path, starting with /',
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
    expect(find.byType(LaneScreen), findsOneWidget);
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
}
