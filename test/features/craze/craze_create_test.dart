import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/features/craze/craze_create.dart';
import 'package:shed_mobile/machines/machine_feed.dart';
import 'package:shed_mobile/src/rust/api/craze.dart';
import 'package:shed_mobile/src/rust/api/dto_lane.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';

/// **The craze create sheet's pure rules** (plan 025 §3.8, CM4) — the
/// desktop's `crazeCreate.test.mjs`, case for case where the rule is the same.
///
/// The cases marked CONTROL are the ones plan 025's C10/CM4 control list
/// names: a non-ready provider is never selectable, a not-ready default never
/// preselected, the request id kept ONLY across an unknown outcome and minted
/// anew after any definite one, and the typed form never cleared.

/// craze's own createOptions on the recipe rig (cursor missing, native with no
/// key, grok ready and the default).
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
  recentDirs: ['/w/a', '/w/b'],
);

BridgeLaneCreateOptions _with({
  String? defaultProvider,
  bool dropGrok = false,
}) => BridgeLaneCreateOptions(
  providers: [
    for (final p in _recipe.providers)
      if (!(dropGrok && p.id == 'grok')) p,
  ],
  defaultProvider: defaultProvider,
  recentDirs: _recipe.recentDirs,
);

/// A deterministic mint: `shed-id-1`, `shed-id-2`, …
String Function() _minter() {
  var n = 0;
  return () => 'shed-id-${++n}';
}

BridgeCrazeSnapshot _snap({
  bool live = true,
  bool create = true,
  bool createOptions = true,
  BridgeSourceOffline? offline,
}) => BridgeCrazeSnapshot(
  rows: const [],
  live: live,
  offline: offline == null
      ? null
      : BridgeCrazeOffline(cause: offline, reason: 'why'),
  caps: BridgeSourceCapabilities(
    kind: 'craze',
    create: create,
    createOptions: createOptions,
  ),
  truncated: false,
);

void main() {
  test('CONTROL: only a ready provider is selectable', () {
    expect(
      [for (final p in _recipe.providers) (p.id, providerSelectable(p))],
      [('cursor', false), ('grok', true), ('native', false)],
    );
    expect(
      providerSelectable(
        const BridgeLaneProvider(
          id: 'x',
          label: 'x',
          state: BridgeLaneProviderState.other(raw: 'warming_up'),
        ),
      ),
      isFalse,
      reason: 'a word this build does not know is not ready',
    );
  });

  test('CONTROL: the default is preselected only when listed and ready', () {
    expect(preselectedProvider(_recipe), 'grok');
    // A not-ready default: the first READY provider instead.
    expect(preselectedProvider(_with(defaultProvider: 'native')), 'grok');
    expect(preselectedProvider(_with(defaultProvider: 'cursor')), 'grok');
    // A default craze does not list (a missing gx): the first ready.
    expect(preselectedProvider(_with(defaultProvider: 'gx')), 'grok');
    // None ready: nothing preselected.
    expect(
      preselectedProvider(_with(defaultProvider: 'native', dropGrok: true)),
      isNull,
    );
  });

  test('a carried-over selection survives only while still ready', () {
    expect(reconcileProvider('grok', _recipe), 'grok');
    expect(
      reconcileProvider('cursor', _recipe),
      'grok',
      reason: 'a dimmed provider is never kept',
    );
    expect(reconcileProvider('gone', _recipe), 'grok');
    expect(reconcileProvider(null, _recipe), 'grok');
  });

  test('a directory must be absolute', () {
    expect(directoryProblem(''), isNotNull);
    expect(directoryProblem('   '), isNotNull);
    expect(directoryProblem('relative/path'), isNotNull);
    expect(directoryProblem('~/w'), isNotNull);
    expect(directoryProblem('/w/a'), isNull);
    expect(directoryProblem('  /w/a  '), isNull);
  });

  test('CONTROL: an unknown outcome keeps the id, and the retry reuses it', () {
    final mint = _minter();
    var d = const CrazeDraft(provider: 'grok', cwd: '/w', prompt: 'hi');
    d = d.beginSubmit(mint);
    final first = d.requestId;
    expect(first, 'shed-id-1');
    expect(d.phase, CrazePhase.submitting);
    expect(primaryLabel(d), 'Creating…');
    d = d.settle(
      const CrazeRefusal('outcome_unknown', 'outcome unknown: lost twice'),
    );
    expect(d.phase, CrazePhase.unknown);
    expect(d.requestId, first, reason: 'kept while the outcome is unknown');
    expect(primaryLabel(d), 'Try again');
    d = d.beginSubmit(mint);
    expect(d.requestId, first, reason: 'Try again resumes the SAME request');
  });

  test('only an unknown outcome\'s held id is a replay (CodeRabbit, '
      'shed-mobile#36)', () {
    final mint = _minter();
    const typed = CrazeDraft(provider: 'grok', cwd: '/w');
    expect(replaysHeldRequest(typed), isFalse, reason: 'idle: no id');
    final submitting = typed.beginSubmit(mint);
    expect(replaysHeldRequest(submitting), isFalse, reason: 'in flight');
    expect(
      replaysHeldRequest(
        submitting.settle(const CrazeRefusal('outcome_unknown', 'lost')),
      ),
      isTrue,
    );
    expect(
      replaysHeldRequest(submitting.settle(const CrazeRefusal('failed', 'no'))),
      isFalse,
      reason: 'a definite answer holds no id: Try again is a new request',
    );
  });

  test('CONTROL: any definite answer ends the id, so Try again mints anew', () {
    final mint = _minter();
    for (final code in [
      'failed',
      'bad_request',
      'unavailable',
      'not_accepting',
    ]) {
      var d = const CrazeDraft(provider: 'grok', cwd: '/w').beginSubmit(mint);
      final first = d.requestId;
      d = d.settle(CrazeRefusal(code, 'no'));
      expect(d.phase, CrazePhase.refused, reason: code);
      expect(d.requestId, isNull, reason: '$code: the id\'s life is over');
      expect(primaryLabel(d), 'Try again');
      d = d.beginSubmit(mint);
      expect(d.requestId, isNot(first), reason: '$code: a fresh id');
    }
  });

  test('CONTROL: no refusal clears the typed form; a create spends it', () {
    final mint = _minter();
    const typed = CrazeDraft(
      provider: 'grok',
      cwd: '/w/x',
      prompt: 'line one\nline two',
    );
    var d = typed;
    for (final refusal in const [
      CrazeRefusal('outcome_unknown', 'lost'),
      CrazeRefusal('failed', 'Error: KEYCHAIN LOCKED\nRun unlock and retry.'),
      CrazeRefusal('bad_request', 'no such directory'),
    ]) {
      d = d.beginSubmit(mint).settle(refusal);
      expect(
        [d.provider, d.cwd, d.prompt],
        ['grok', '/w/x', 'line one\nline two'],
        reason: refusal.code,
      );
    }
    final created = CrazeCreated(_created(), ended: false);
    final spent = d.beginSubmit(mint).spent(created);
    expect([spent.provider, spent.cwd, spent.prompt], [null, '', '']);
    expect(spent.requestId, isNull);
    expect(spent.phase, CrazePhase.idle);
    expect(spent.lastCreated, same(created));
  });

  test(
    'an edit mints a new id and clears the settled outcome, not the form',
    () {
      var d = const CrazeDraft(provider: 'grok', cwd: '/w')
          .beginSubmit(_minter())
          .settle(const CrazeRefusal('outcome_unknown', 'lost'));
      expect(d.requestId, isNotNull);
      d = d.edit(prompt: 'changed');
      expect(d.requestId, isNull, reason: 'another request now');
      expect(d.phase, CrazePhase.idle);
      expect(d.refusal, isNull);
      expect(d.cwd, '/w');
      expect(d.provider, 'grok');
      // A provider change is an edit too; null is a provider value.
      expect(d.edit(provider: null).provider, isNull);
      // An edit that changes nothing is no edit — the held id survives it.
      final held = const CrazeDraft(cwd: '/w')
          .beginSubmit(_minter())
          .settle(const CrazeRefusal('outcome_unknown', 'x'));
      expect(held.edit(cwd: '/w'), same(held));
      // A submission in flight is not edited.
      final flying = d.beginSubmit(_minter());
      expect(flying.edit(cwd: '/elsewhere'), same(flying));
    },
  );

  test('the request sent is the desktop\'s create_request rule', () {
    final d = const CrazeDraft(
      provider: '  ',
      cwd: '  /w/a  ',
      prompt: '  keep\nthis  ',
    ).beginSubmit(() => 'shed-x');
    final r = d.request();
    expect(r.cwd, '/w/a');
    expect(r.provider, isNull, reason: 'blank → craze\'s default');
    expect(
      r.prompt,
      '  keep\nthis  ',
      reason: 'a prompt goes EXACTLY as typed',
    );
    expect(r.requestId, 'shed-x');
    final idle = const CrazeDraft(
      provider: 'grok',
      cwd: '/w',
      prompt: '   ',
    ).beginSubmit(() => 'shed-y').request();
    expect(idle.prompt, isNull, reason: 'a blank prompt is an idle session');
    expect(idle.provider, 'grok');
  });

  test(
    'a create\'s failure is read by VARIANT; only lost answers keep the id',
    () {
      expect(
        crazeRefusalOf(const BridgeLaneError.outcomeUnknown(msg: 'lost')).code,
        'outcome_unknown',
      );
      expect(
        crazeRefusalOf(const BridgeLaneError.failed(msg: 'outcome unknown: x')),
        const CrazeRefusal('failed', 'outcome unknown: x'),
        reason: 'never by the text: Failed is definite whatever it says',
      );
      expect(
        crazeRefusalOf(const BridgeLaneError.badRequest(msg: 'no dir')),
        const CrazeRefusal('bad_request', 'no dir'),
      );
      expect(
        crazeRefusalOf(const BridgeLaneError.unavailable(msg: 'busy')).code,
        'unavailable',
      );
      expect(
        crazeRefusalOf(const BridgeLaneError.notAccepting()).code,
        'not_accepting',
      );
      expect(
        crazeRefusalOf(StateError('craze is not connected on mini3')),
        const CrazeRefusal('unavailable', 'craze is not connected on mini3'),
        reason: 'the feed refused before sending anything: definite',
      );
      expect(
        crazeRefusalOf(Exception('panic mid-create')).code,
        'outcome_unknown',
        reason: 'an error nobody can read is an outcome nobody knows',
      );
    },
  );

  test('refusals are shown by code', () {
    expect(
      refusalView(const CrazeRefusal('bad_request', 'cwd /nope is no dir')),
      (where: RefusalWhere.cwd, text: 'cwd /nope is no dir'),
    );
    expect(
      refusalView(
        const CrazeRefusal(
          'bad_request',
          'requestId shed-1 was used already for a create with other params',
        ),
      ).where,
      RefusalWhere.general,
    );
    const cause = 'Error: KEYCHAIN LOCKED\nRun unlock and retry.';
    expect(refusalView(const CrazeRefusal('failed', cause)), (
      where: RefusalWhere.cause,
      text: cause,
    ), reason: 'verbatim');
    expect(
      refusalView(const CrazeRefusal('unavailable', 'busy')).text,
      contains('try again'),
    );
  });

  test('a first prompt craze did not take is said; one it took is not', () {
    expect(promptNotice(_created()), isNull);
    expect(
      promptNotice(_created(prompt: const BridgeLanePromptOutcome.none())),
      isNull,
    );
    expect(
      promptNotice(
        _created(
          prompt: const BridgeLanePromptOutcome.refused(),
          error: 'busy',
        ),
      ),
      [
        'craze started the session, and the session refused its first prompt.',
        'busy',
      ],
    );
    expect(
      promptNotice(_created(prompt: const BridgeLanePromptOutcome.unknown())),
      [
        'craze started the session, and the answer to its first prompt was '
            'lost.',
      ],
    );
  });

  test('the sheet is offered only on a live hub that can create', () {
    expect(crazeCreateOffered(_snap()), isTrue);
    expect(crazeCreateOffered(_snap(create: false)), isFalse);
    expect(crazeCreateOffered(_snap(createOptions: false)), isFalse);
    expect(
      crazeCreateOffered(
        _snap(live: false, offline: const BridgeSourceOffline.tooOld()),
      ),
      isFalse,
    );
    expect(
      crazeCreateOffered(
        _snap(live: false, offline: const BridgeSourceOffline.unreachable()),
      ),
      isFalse,
    );
    expect(crazeCreateOffered(null), isFalse);
    expect(
      crazeCreateUpdateNote(_snap(createOptions: false)),
      contains('update craze on this machine'),
    );
    expect(crazeCreateUpdateNote(_snap()), isNull);
  });

  test('an open sheet\'s note follows its machine\'s craze', () {
    expect(crazeSheetNote(_snap(), 'm'), isNull);
    expect(
      crazeSheetNote(
        _snap(live: false, offline: const BridgeSourceOffline.unreachable()),
        'm',
      ),
      'craze on m is offline (unreachable) — your form is kept',
    );
    expect(
      crazeSheetNote(
        _snap(live: false, offline: const BridgeSourceOffline.tooOld()),
        'm',
      ),
      contains('too old'),
    );
    expect(
      crazeSheetNote(
        _snap(live: false, offline: const BridgeSourceOffline.notInstalled()),
        'm',
      ),
      contains('not installed'),
    );
    expect(crazeSheetNote(_snap(live: false), 'm'), contains('connecting'));
    expect(crazeSheetNote(null, 'm'), contains('connecting'));
    expect(
      crazeSheetNote(_snap(create: false), 'm'),
      contains('update craze on this machine'),
    );
  });
}

BridgeLaneCreated _created({
  BridgeLanePromptOutcome prompt = const BridgeLanePromptOutcome.accepted(),
  String? error,
}) => BridgeLaneCreated(
  session: const BridgeLaneSession(
    id: 'cccccccccccc',
    title: 'new',
    cwd: '/w',
    activity: BridgeRcActivity.working,
    pendingApprovals: 0,
    approximate: false,
  ),
  prompt: prompt,
  promptError: error,
);
