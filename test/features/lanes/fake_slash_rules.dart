import 'package:shed_mobile/lanes/slash_rules.dart';
import 'package:shed_mobile/src/rust/api/dto_lane.dart';
import 'package:shed_mobile/src/rust/api/dto_rc.dart';

/// **A stand-in for `shed_app::slash_menu` behind [SlashRules]** — a widget
/// test runs with no native library loaded, so this is the only way it can
/// drive the composer's `/` menu at all.
///
/// It follows the module's documented rules for the menus these tests build
/// (the four filter buckets and the caret rule, the grammar and its guard, the
/// three accept keys — `slash_menu.rs`'s module doc), and RECORDS every call,
/// so a cell asserts what the SCREEN asked (the draft as typed, the UTF-16
/// caret, the key, the working flag) as well as what it did with the answer.
/// It is a test double, not a port: nothing in `lib/` decides a command, and
/// the real rules are driven end to end against the real hub by
/// `integration_test/craze_test.dart`'s `/` menu cells.
class FakeSlashRules implements SlashRules {
  /// Every filter the screen asked for, in order.
  final filters = <({String draft, int caret, bool working})>[];

  /// Every dispatch (a Send, or Enter with no menu up), in order.
  final dispatches = <({String draft, bool working})>[];

  /// Every accept (Enter / Tab on the highlight, a tap on a row), in order.
  final accepts =
      <({String draft, String row, BridgeSlashAcceptKey key, bool working})>[];

  @override
  BridgeSlashFilter filter(
    BridgeSlashMenu menu,
    String draft,
    int caret,
    bool working,
  ) {
    filters.add((draft: draft, caret: caret, working: working));
    final command = _parse(draft);
    if (command == null) {
      return const BridgeSlashFilter(open: false, token: '', rows: []);
    }
    final token = '/${command.typed}';
    final at = caret > draft.length ? draft.length : caret;
    if (at == 0 || at > token.length) {
      return BridgeSlashFilter(open: false, token: token, rows: const []);
    }
    final query = _fold(command.typed);
    final buckets = List.generate(4, (_) => <BridgeSlashMenuRow>[]);
    for (final row in menu.rows) {
      final name = _fold(row.name);
      final qualified = _fold(row.qualified ?? '');
      if (name.startsWith(query)) {
        buckets[0].add(row);
      } else if (qualified.startsWith(query)) {
        buckets[1].add(row);
      } else if (name.contains(query)) {
        buckets[2].add(row);
      } else if (qualified.contains(query)) {
        buckets[3].add(row);
      }
    }
    final rows = [
      for (final bucket in buckets)
        for (final row in bucket)
          BridgeSlashFilterRow(row: row, dimmed: working && _waits(row)),
    ];
    return BridgeSlashFilter(open: rows.isNotEmpty, token: token, rows: rows);
  }

  @override
  BridgeSlashDispatch dispatch(
    BridgeSlashMenu menu,
    String draft,
    bool working,
  ) {
    dispatches.add((draft: draft, working: working));
    return _dispatch(menu, draft, working);
  }

  @override
  BridgeSlashAccept? accept(
    BridgeSlashMenu menu,
    String draft,
    String rowName,
    BridgeSlashAcceptKey key,
    bool working,
  ) {
    accepts.add((draft: draft, row: rowName, key: key, working: working));
    final command = _parse(draft);
    if (command == null) return null;
    final row = menu.rows
        .where((r) => _fold(r.name) == _fold(rowName))
        .firstOrNull;
    if (row == null) return null;
    final typed = _fold(command.typed);
    final spelled =
        typed.isNotEmpty &&
        (typed == _fold(row.name) ||
            (row.qualified != null && typed == _fold(row.qualified!)));
    if (key == BridgeSlashAcceptKey.enter && spelled) {
      return BridgeSlashAccept.dispatch(
        dispatch: _dispatch(menu, draft, working),
      );
    }
    if (key != BridgeSlashAcceptKey.tab && working && _waits(row)) {
      return BridgeSlashAccept.dispatch(
        dispatch: _refuse(row.name, 'runs after this turn'),
      );
    }
    final spelling = row.qualified != null && command.typed.contains(':')
        ? row.qualified!
        : row.name;
    final head = '/$spelling ';
    final tail = command.rest.startsWith(' ')
        ? command.rest.substring(1)
        : command.rest;
    final completed = '$head$tail';
    if (key != BridgeSlashAcceptKey.tab && !_takesArgument(row.action)) {
      return BridgeSlashAccept.dispatch(
        dispatch: _dispatch(menu, completed, working),
      );
    }
    return BridgeSlashAccept.complete(draft: completed, caret: head.length);
  }

  @override
  bool isWorking(BridgeRcActivity activity) =>
      activity == BridgeRcActivity.working ||
      activity == BridgeRcActivity.needsApproval;

  BridgeSlashDispatch _dispatch(
    BridgeSlashMenu menu,
    String draft,
    bool working,
  ) {
    final command = _parse(draft.trim());
    if (command == null) return const BridgeSlashDispatch.notCommand();
    final arg = command.rest.trim();
    final wanted = _fold(command.typed);
    final named = menu.rows.where((r) => _fold(r.name) == wanted).firstOrNull;
    final row =
        named ??
        menu.rows
            .where((r) => r.qualified != null && _fold(r.qualified!) == wanted)
            .firstOrNull;
    if (row == null) {
      final hidden = menu.hidden
          .where((h) => _fold(h.name) == wanted)
          .firstOrNull;
      return hidden == null
          ? const BridgeSlashDispatch.notCommand()
          : _refuse(hidden.name, hidden.reason);
    }
    final spelling = named != null ? row.name : row.qualified;
    final action = row.action;
    if (action is BridgeSlashAction_Prompt) {
      return BridgeSlashDispatch.prompt(
        text: arg.isEmpty ? '/$spelling' : '/$spelling $arg',
      );
    }
    if (action is BridgeSlashAction_SetTitle && arg.isEmpty) {
      return BridgeSlashDispatch.refuse(
        reason: 'type a title after /${row.name}',
      );
    }
    if (action is BridgeSlashAction_ModelPicker && arg.isNotEmpty) {
      return _refuse(
        row.name,
        'takes no argument — pick a model from the list',
      );
    }
    if (!_takesArgument(action) && arg.isNotEmpty) {
      return _refuse(row.name, 'takes no argument');
    }
    if (working && _waits(row)) {
      return _refuse(row.name, 'runs after this turn');
    }
    return BridgeSlashDispatch.run(
      action: action,
      arg: action is BridgeSlashAction_SetTitle ? arg : null,
    );
  }

  static BridgeSlashDispatch _refuse(String name, String why) =>
      BridgeSlashDispatch.refuse(reason: '/$name: $why');

  static String _fold(String s) => s.toLowerCase();

  static bool _waits(BridgeSlashMenuRow row) =>
      !row.whileWorking && row.action is! BridgeSlashAction_Prompt;

  static bool _takesArgument(BridgeSlashAction action) =>
      action is BridgeSlashAction_Prompt ||
      action is BridgeSlashAction_SetTitle;

  /// One line whose first character is `/`: the token without its `/` (to
  /// the first whitespace) and everything after it.
  static ({String typed, String rest})? _parse(String draft) {
    if (draft.contains('\n') || draft.contains('\r')) return null;
    if (!draft.startsWith('/')) return null;
    final body = draft.substring(1);
    final end = RegExp(r'\s').firstMatch(body)?.start ?? body.length;
    return (typed: body.substring(0, end), rest: body.substring(end));
  }
}

/// A menu row, as the shared resolver hands one out.
BridgeSlashMenuRow slashRow(
  String name,
  BridgeSlashAction action, {
  bool whileWorking = false,
  BridgeSlashSource source = const BridgeSlashSource.builtin(),
  BridgeSlashArg arg = const BridgeSlashArg.none(),
  String? argHint,
  String? description,
  String? qualified,
}) => BridgeSlashMenuRow(
  name: name,
  qualified: qualified,
  description: description,
  source: source,
  arg: arg,
  argHint: argHint,
  whileWorking: whileWorking,
  action: action,
);

/// **A hub-created craze 0.1.1 session's menu**, as the shared core resolves
/// it on this client (the desktop harness's `MENU_ROWS`): the builtins it can
/// run, in catalog order, then the agent's `research`; the phase-1 hidden
/// builtins a typed command is refused for.
final crazeMenu = BridgeSlashMenu(
  rows: [
    slashRow(
      'model',
      const BridgeSlashAction.modelPicker(),
      arg: const BridgeSlashArg.optional(),
      argHint: '<model> [effort]',
      description: 'Switch the model',
    ),
    slashRow(
      'rename',
      const BridgeSlashAction.setTitle(),
      whileWorking: true,
      arg: const BridgeSlashArg.required_(),
      argHint: '<title>',
      description: 'Rename the session',
    ),
    slashRow(
      'plan',
      const BridgeSlashAction.setMode(id: 'plan'),
      description: 'Plan mode',
    ),
    slashRow(
      'ask',
      const BridgeSlashAction.setMode(id: 'ask'),
      description: 'Ask mode',
    ),
    slashRow(
      'agent',
      const BridgeSlashAction.setMode(id: 'agent'),
      description: 'Agent mode',
    ),
    slashRow(
      'exit',
      const BridgeSlashAction.stop(),
      whileWorking: true,
      description: 'End the session',
    ),
    slashRow(
      'research',
      const BridgeSlashAction.prompt(),
      source: const BridgeSlashSource.agent(),
      arg: const BridgeSlashArg.optional(),
      description: 'Agent-advertised command',
    ),
  ],
  hidden: const [
    BridgeSlashHidden(name: 'help', reason: 'not available here yet'),
    BridgeSlashHidden(name: 'clear', reason: 'not available here yet'),
    BridgeSlashHidden(name: 'btw', reason: 'not available here yet'),
  ],
);

/// The names [crazeMenu] lists, in order.
const crazeMenuNames = [
  'model',
  'rename',
  'plan',
  'ask',
  'agent',
  'exit',
  'research',
];

/// The rows of [crazeMenu] that wait for a running turn (no `whileWorking`,
/// not a prompt): dimmed and refused while one runs.
const crazeWaitingRows = {'model', 'plan', 'ask', 'agent'};
