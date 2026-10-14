// **The widget tests' `/` menu double, held to the REAL rules** (plan 029
// M3 review, item 7).
//
// A widget test runs with no native library, so every `/` menu cell in
// `test/features/lanes/lane_screen_test.dart` drives the composer through
// `FakeSlashRules` (`test/features/lanes/fake_slash_rules.dart`), and every
// menu, completion, dispatch and refusal those cells expect is the DOUBLE's
// answer. This file is where the native library IS loaded: it runs one table —
// every situation those cells rely on the double for — through BOTH the
// production `BridgeSlashRules` (real FRB → `shed_app::slash_menu`) and the
// double, and asserts identical `filter`, `dispatch`, `accept` and `isWorking`
// answers. A disagreement is a bug in the double (fix the double) or a widget
// test expecting something the real rules would not do.
//
// The double is imported from `test/` on purpose — one copy, the very one the
// widget tests use — and stays test-only: nothing in `lib/` can reach it.
//
// What it does not cover: `resolve` (which rows a catalog becomes for a
// session's capabilities) is not on the seam — the double is handed a menu
// already resolved — so the menus here are the fixtures the widget tests
// hand it; the real resolver is driven end to end by `craze_test.dart`'s `/`
// menu cells against the real hub.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shed_mobile/lanes/slash_rules.dart';
import 'package:shed_mobile/src/rust/api/dto_lane.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';
import 'package:shed_mobile/src/rust/frb_generated.dart';

import '../test/features/lanes/fake_slash_rules.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());

  testWidgets('the double answers as shed_app::slash_menu does, case by case', (
    _,
  ) async {
    const real = BridgeSlashRules();
    final fake = FakeSlashRules();
    final mismatches = <String>[];
    var compared = 0;
    void same(String what, String real, String fake) {
      compared++;
      if (real != fake) mismatches.add('$what\n  real: $real\n  fake: $fake');
    }

    for (final c in _filters) {
      same(
        'filter ${c.label} ${_q(c.draft)} @${c.caret}${c.working ? ' working' : ''}',
        _showFilter(real.filter(c.menu, c.draft, c.caret, c.working)),
        _showFilter(fake.filter(c.menu, c.draft, c.caret, c.working)),
      );
    }
    for (final c in _dispatches) {
      same(
        'dispatch ${c.label} ${_q(c.draft)}${c.working ? ' working' : ''}',
        '${real.dispatch(c.menu, c.draft, c.working)}',
        '${fake.dispatch(c.menu, c.draft, c.working)}',
      );
    }
    for (final c in _accepts) {
      same(
        'accept ${c.label} ${_q(c.draft)} ${c.row} ${c.key.name}'
            '${c.working ? ' working' : ''}',
        '${real.accept(c.menu, c.draft, c.row, c.key, c.working)}',
        '${fake.accept(c.menu, c.draft, c.row, c.key, c.working)}',
      );
    }
    for (final activity in BridgeRcActivity.values) {
      same(
        'isWorking ${activity.name}',
        '${real.isWorking(activity)}',
        '${fake.isWorking(activity)}',
      );
    }

    // ignore: avoid_print
    print('slash parity: $compared answers compared');
    expect(
      compared,
      _filters.length +
          _dispatches.length +
          _accepts.length +
          BridgeRcActivity.values.length,
    );
    expect(mismatches, isEmpty, reason: mismatches.join('\n'));

    // The table is not vacuous: it reaches every answer shape.
    expect(
      {
        for (final c in _dispatches)
          switch (real.dispatch(c.menu, c.draft, c.working)) {
            BridgeSlashDispatch_NotCommand() => 'not_command',
            BridgeSlashDispatch_Prompt() => 'prompt',
            BridgeSlashDispatch_Run() => 'run',
            BridgeSlashDispatch_Refuse() => 'refuse',
          },
      },
      {'not_command', 'prompt', 'run', 'refuse'},
    );
    expect(
      {
        for (final c in _accepts)
          switch (real.accept(c.menu, c.draft, c.row, c.key, c.working)) {
            null => 'none',
            BridgeSlashAccept_Complete() => 'complete',
            BridgeSlashAccept_Dispatch() => 'dispatch',
          },
      },
      {'none', 'complete', 'dispatch'},
    );
    expect(
      {
        for (final c in _filters)
          real.filter(c.menu, c.draft, c.caret, c.working).open,
      },
      {true, false},
    );
    // `start` is compared past dimmed rows AND on an open list whose every
    // row is dimmed (the "else 0" of the rule), not only on idle answers.
    final answers = [
      for (final c in _filters)
        real.filter(c.menu, c.draft, c.caret, c.working),
    ];
    expect(answers.any((f) => f.start > 0), isTrue);
    expect(
      answers.any(
        (f) => f.open && f.start == 0 && f.rows.every((r) => r.dimmed),
      ),
      isTrue,
    );
  });
}

// ---------------------------------------------------------------------------
// the answers, rendered for comparison
// ---------------------------------------------------------------------------

/// A filter answer as text: the generated `==` compares its row LIST by
/// identity, so two equal answers would never be equal. `start` (the row a
/// reset highlight lands on, plan 030 FU8) is part of every answer compared.
String _showFilter(BridgeSlashFilter f) =>
    'open=${f.open} token=${_q(f.token)} start=${f.start} rows=[${[for (final r in f.rows) '${r.row.name}${r.dimmed ? '(dimmed)' : ''}'].join(', ')}]';

String _q(String s) => '"${s.replaceAll('\n', r'\n')}"';

// ---------------------------------------------------------------------------
// the menus — the widget tests' fixtures
// ---------------------------------------------------------------------------

/// The hub-created session's menu without the model row, as a session with
/// no `settings` capability resolves it — the "a mode from the composer needs
/// no settings capability" cell's menu.
final _noSettings = BridgeSlashMenu(
  rows: crazeMenu.rows
      .where((r) => r.action is! BridgeSlashAction_ModelPicker)
      .toList(),
  hidden: crazeMenu.hidden,
);

/// The 600-command catalog of the panel-cap and keyboard cells.
final _big = BridgeSlashMenu(
  rows: [
    for (var i = 0; i < 600; i++)
      slashRow(
        'cmd-${i.toString().padLeft(3, '0')}',
        const BridgeSlashAction.prompt(),
        source: const BridgeSlashSource.agent(),
      ),
  ],
  hidden: const [],
);

/// Only the rows of the hub's menu that wait for a turn: while one runs,
/// EVERY row is dimmed, and the highlight starts on row 0 (plan 030 FU8).
final _waiting = BridgeSlashMenu(
  rows: crazeMenu.rows.where((r) => crazeWaitingRows.contains(r.name)).toList(),
  hidden: crazeMenu.hidden,
);

/// The highlight cell's replacement catalog: a new first row.
final _alpha = BridgeSlashMenu(
  rows: [
    slashRow(
      'alpha',
      const BridgeSlashAction.prompt(),
      source: const BridgeSlashSource.agent(),
    ),
    ...crazeMenu.rows,
  ],
  hidden: crazeMenu.hidden,
);

/// A plugin row with a second spelling, for the `qualified` rules the double
/// implements.
final _plugin = BridgeSlashMenu(
  rows: [
    ...crazeMenu.rows,
    slashRow(
      'deploy',
      const BridgeSlashAction.prompt(),
      source: const BridgeSlashSource.plugin(),
      qualified: 'ops:deploy',
      arg: const BridgeSlashArg.optional(),
    ),
  ],
  hidden: crazeMenu.hidden,
);

// ---------------------------------------------------------------------------
// the table
// ---------------------------------------------------------------------------

typedef _Filter = ({
  String label,
  BridgeSlashMenu menu,
  String draft,
  int caret,
  bool working,
});

_Filter _f(
  String draft, {
  int? caret,
  bool working = false,
  BridgeSlashMenu? menu,
  String label = 'craze',
}) => (
  label: label,
  menu: menu ?? crazeMenu,
  draft: draft,
  caret: caret ?? draft.length,
  working: working,
);

final _filters = <_Filter>[
  // `/` lists every row, in order; idle and while a turn runs (NeedsApproval
  // counts — `isWorking` below) the waiting rows dimmed.
  _f('/'),
  _f('/', working: true),
  _f('/', caret: 0),
  // Where the highlight starts mid-turn: past the dimmed rows (`/a` lists
  // two waiting rows first), and on row 0 when every row is dimmed.
  _f('/a', working: true),
  _f('/', menu: _waiting, working: true, label: 'all-waiting'),
  // The highlight cells' tokens, and a caret moved inside one.
  _f('/r'),
  _f('/re'),
  _f('/re', caret: 2),
  _f('/re', caret: 1),
  _f('/a'),
  _f('/m'),
  _f('/pl'),
  _f('/R'),
  _f('/zz'),
  _f('/help'),
  _f('/rename'),
  // The caret past the token: closed, the token still reported.
  _f('/rename '),
  _f('/rename x', caret: 3),
  _f('/Research   deep dive '),
  // UTF-16 carets around an astral character (the crab is two code units).
  _f('/re 🦀'),
  _f('/re 🦀', caret: 5),
  _f('/🦀'),
  _f('/🦀', caret: 1),
  _f('/🦀', caret: 2),
  _f('/r🦀', caret: 2),
  _f('/r🦀', caret: 4),
  _f('/🦀re x', caret: 5),
  _f('/re', caret: 100),
  // Not a command draft at all.
  _f(''),
  _f('hello'),
  _f(' /help'),
  _f('/\n'),
  _f('/re\nmore', caret: 3),
  _f('/re\r', caret: 3),
  // The other fixtures.
  _f('/', menu: _noSettings, label: 'no-settings'),
  _f('/', menu: _big, label: '600'),
  _f('/', menu: _big, working: true, label: '600'),
  _f('/cmd-59', menu: _big, label: '600'),
  _f('/9', menu: _big, label: '600'),
  _f('/a', menu: _alpha, label: 'alpha'),
  _f('/dep', menu: _plugin, label: 'plugin'),
  _f('/ops', menu: _plugin, label: 'plugin'),
  _f('/ops:', menu: _plugin, label: 'plugin'),
  _f('/:dep', menu: _plugin, label: 'plugin'),
];

typedef _Dispatch = ({
  String label,
  BridgeSlashMenu menu,
  String draft,
  bool working,
});

_Dispatch _d(
  String draft, {
  bool working = false,
  BridgeSlashMenu? menu,
  String label = 'craze',
}) => (label: label, menu: menu ?? crazeMenu, draft: draft, working: working);

final _dispatches = <_Dispatch>[
  // Hidden builtins, as typed and as they would be sent (` /help`).
  _d('/help'),
  _d(' /help'),
  _d('/HELP'),
  _d('/help '),
  _d('/help me'),
  _d('/clear'),
  _d('/btw a side note'),
  // Unknown commands go out as text.
  _d('/zz top'),
  _d('/nosuch x'),
  _d('/nosuch'),
  _d('/'),
  _d('/ '),
  _d('hello'),
  _d(''),
  _d('   '),
  // `/rename`: with no argument (exact and after a completion), with one,
  // trimmed and literal, during a turn (whileWorking).
  _d('/rename'),
  _d('/rename '),
  _d('/rename    '),
  _d('/Rename x'),
  _d('/rename   plan 029 desk '),
  _d('/rename "quoted"  inner  space'),
  _d('/rename mid-turn', working: true),
  _d('/rename x\n'),
  _d('/rename a\nb'),
  // Modes: idle runs, a turn refuses, an argument refuses first.
  _d('/plan'),
  _d('/ask'),
  _d('/PLAN'),
  _d('/plan', working: true),
  _d('/ask', working: true),
  _d('/plan now'),
  _d('/plan now', working: true),
  _d('/plan', menu: _noSettings, label: 'no-settings'),
  _d('/plan', menu: _noSettings, working: true, label: 'no-settings'),
  // `/exit` (whileWorking) and `/model` (the picker).
  _d('/exit'),
  _d('/exit', working: true),
  _d('/exit now'),
  _d('/model'),
  _d('/model', working: true),
  _d('/model grok-4.6'),
  _d('/model', menu: _noSettings, label: 'no-settings'),
  // Prompt rows: the canonical spelling, queued during a turn.
  _d('/research'),
  _d('/Research   deep dive '),
  _d('/Research   deep dive ', working: true),
  _d('/research\nmore'),
  _d('/cmd-599', menu: _big, label: '600'),
  _d('/CMD-000 go', menu: _big, label: '600'),
  _d('/alpha', menu: _alpha, label: 'alpha'),
  _d('/ops:deploy now', menu: _plugin, label: 'plugin'),
  _d('/deploy', menu: _plugin, label: 'plugin'),
  _d('/OPS:DEPLOY', menu: _plugin, label: 'plugin'),
];

typedef _Accept = ({
  String label,
  BridgeSlashMenu menu,
  String draft,
  String row,
  BridgeSlashAcceptKey key,
  bool working,
});

_Accept _a(
  String draft,
  String row,
  BridgeSlashAcceptKey key, {
  bool working = false,
  BridgeSlashMenu? menu,
  String label = 'craze',
}) => (
  label: label,
  menu: menu ?? crazeMenu,
  draft: draft,
  row: row,
  key: key,
  working: working,
);

const _enter = BridgeSlashAcceptKey.enter;
const _tab = BridgeSlashAcceptKey.tab;
const _pick = BridgeSlashAcceptKey.pick;

final _accepts = <_Accept>[
  // Tab completion, and Enter / a tap on a row that takes an argument.
  _a('/re', 'rename', _tab),
  _a('/re', 'rename', _enter),
  _a('/re', 'rename', _pick),
  _a('/r', 'research', _enter),
  _a('/', 'research', _enter),
  _a('/', 'rename', _tab, working: true),
  _a('/pl', 'plan', _tab),
  _a('/re x', 'rename', _tab),
  _a('/re  x', 'rename', _tab),
  _a('/re🦀', 'rename', _tab),
  _a('/RE', 'rename', _tab),
  // A token that already spells the row: Enter sends (the guard decides).
  _a('/rename', 'rename', _enter),
  _a('/rename', 'rename', _tab),
  _a('/exit', 'exit', _enter),
  _a('/ask', 'ask', _enter),
  _a('/ask', 'ask', _enter, working: true),
  _a('/model', 'model', _enter),
  // Rows that take no argument run at once on Enter / a tap.
  _a('/pl', 'plan', _enter),
  _a('/', 'model', _enter),
  _a('/', 'exit', _pick),
  _a('/', 'agent', _pick),
  _a('/model x', 'model', _pick),
  _a('/ex now', 'exit', _enter),
  // A dimmed row: a tap / Enter is refused; Tab still completes.
  _a('/', 'plan', _pick, working: true),
  _a('/', 'plan', _enter, working: true),
  _a('/', 'plan', _tab, working: true),
  _a('/', 'exit', _pick, working: true),
  _a('/', 'research', _pick, working: true),
  // Nothing to accept.
  _a('hello', 'rename', _enter),
  _a('/', 'nosuch', _enter),
  _a('/', 'help', _enter),
  _a('/\n', 'rename', _enter),
  // The other fixtures.
  _a('/', 'cmd-599', _enter, menu: _big, label: '600'),
  _a('/cmd-599', 'cmd-599', _enter, menu: _big, label: '600'),
  _a('/', 'plan', _pick, menu: _noSettings, label: 'no-settings'),
  _a('/a', 'alpha', _enter, menu: _alpha, label: 'alpha'),
  _a('/ops:', 'deploy', _tab, menu: _plugin, label: 'plugin'),
  _a('/dep', 'deploy', _tab, menu: _plugin, label: 'plugin'),
  _a('/ops:deploy', 'deploy', _enter, menu: _plugin, label: 'plugin'),
];
