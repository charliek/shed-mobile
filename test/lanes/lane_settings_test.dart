import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/bridge/bridge_adapters.dart';
import 'package:shed_mobile/core/app_error.dart';
import 'package:shed_mobile/lanes/lane_settings.dart';
import 'package:shed_mobile/src/rust/api/dto_lane.dart';

/// **The settings sheet's pure rules** (`lib/lanes/lane_settings.dart`, plan
/// 025 §3.10) — the desktop's `laneSettings.test.mjs`, case for case, against
/// the phone's port of `laneSettings.ts`.
///
/// The cases marked CONTROL are the ones plan 025's CM6 control list names:
/// the sheet offered when the capabilities say `settings: false`, and a change
/// lost to a drop shown as applied before the next `Settings`.
void main() {
  test('≤ 4 values is a segmented control, more is a list', () {
    expect(segmentedMax, 4);
    expect(controlFor(2), SettingControl.segmented);
    expect(controlFor(4), SettingControl.segmented);
    expect(controlFor(5), SettingControl.list);
  });

  test('the rows: the model (a list), the options in the order given, then '
      'the mode', () {
    final rows = sheetRows(_opus);
    expect(
      [for (final r in rows) (r.id, r.kind, r.control)],
      [
        ('model', SettingKind.model, SettingControl.list),
        ('thinking', SettingKind.config, SettingControl.segmented),
        ('effort', SettingKind.config, SettingControl.list),
        ('context', SettingKind.config, SettingControl.segmented),
        ('fast', SettingKind.config, SettingControl.segmented),
        ('mode', SettingKind.mode, SettingControl.segmented),
      ],
    );
    expect(rows.first.current, 'claude-opus-5');
    expect(rows.last.current, 'agent');
    expect(rows[1].category, 'thought_level');
    expect(rows.first.category, isNull);
    // A model list of two is still a list: there can be hundreds.
    expect(
      sheetRows(_with(_opus, models: _opus.models.sublist(0, 2))).first.control,
      SettingControl.list,
    );
  });

  test('a row with nothing to pick is not drawn', () {
    expect(
      sheetRows(
        const BridgeLaneSettings(
          models: [],
          modes: [],
          options: [
            BridgeLaneSetting(
              id: 'empty',
              name: 'Empty',
              category: 'x',
              current: '',
              values: [],
            ),
          ],
        ),
      ),
      isEmpty,
    );
  });

  test('an option row is named by its name, else its id', () {
    final rows = sheetRows(
      const BridgeLaneSettings(
        models: [],
        modes: [],
        options: [
          BridgeLaneSetting(
            id: 'raw_id',
            name: '',
            category: 'model_config',
            current: 'a',
            values: [BridgeLaneChoice(id: 'a', name: 'A')],
          ),
        ],
      ),
    );
    expect(rows.single.name, 'raw_id');
  });

  test('a row\'s key names its kind: an option called "model" is not the '
      'model row', () {
    final rows = sheetRows(
      _with(
        _grok46,
        options: [
          const BridgeLaneSetting(
            id: 'model',
            name: 'Model variant',
            category: 'model_config',
            current: 'a',
            values: [BridgeLaneChoice(id: 'a', name: 'A')],
          ),
        ],
      ),
    );
    expect(rows.map((r) => r.key), [
      'model:model',
      'config:model',
      'mode:mode',
    ]);
  });

  test('rowNow finds a row as the settings draw it now', () {
    final effort = _row(_grok46, 'effort');
    expect(rowNow(_opus, effort)?.values.length, 5);
    expect(rowNow(_opus, effort)?.current, 'max');
    expect(
      rowNow(_with(_grok46, options: const []), effort),
      isNull,
      reason: 'a row no longer drawn',
    );
  });

  test('what a press sends, row by row', () {
    expect(
      changeFor(_row(_grok46, 'model'), 'claude-opus-5', null),
      const BridgeLaneSettingChange.model(id: 'claude-opus-5'),
    );
    expect(
      changeFor(_row(_grok46, 'mode'), 'plan', null),
      const BridgeLaneSettingChange.mode(id: 'plan'),
    );
    expect(
      changeFor(_row(_grok46, 'effort'), 'low', null),
      const BridgeLaneSettingChange.config(id: 'effort', value: 'low'),
    );
  });

  test(
    'CONTROL (A13): an option is bound to the model the sheet DISPLAYED',
    () {
      final effort = _row(_grok46, 'effort');
      // The adapter's fold may already have moved on; the press names what was
      // shown.
      expect(
        changeFor(effort, 'low', _grok46.model),
        const BridgeLaneSettingChange.config(
          id: 'effort',
          value: 'low',
          forModel: 'grok-4.6',
        ),
      );
      expect(
        changeFor(effort, 'low', null),
        const BridgeLaneSettingChange.config(id: 'effort', value: 'low'),
        reason: 'no model shown, no binding',
      );
      expect(
        changeFor(effort, 'low', ''),
        const BridgeLaneSettingChange.config(id: 'effort', value: 'low'),
        reason: 'an empty model is none',
      );
      expect(
        changeFor(_row(_grok46, 'model'), 'glm-5.2', _grok46.model),
        const BridgeLaneSettingChange.model(id: 'glm-5.2'),
        reason: 'a model change takes none',
      );
      expect(
        changeFor(_row(_grok46, 'mode'), 'ask', _grok46.model),
        const BridgeLaneSettingChange.mode(id: 'ask'),
      );
    },
  );

  test('the chip: model name · effort value · fast, from the current '
      'values', () {
    expect(settingsChip(_grok46), 'Grok 4.6 · High · fast');
    // fast OFF says nothing; `effort` outranks `thinking`, both thought_level.
    expect(settingsChip(_opus), 'Claude Opus 5 · Max');
    // grok's own effort is a model_option named reasoning_effort.
    expect(
      settingsChip(
        const BridgeLaneSettings(
          model: 'grok-4.6',
          models: [BridgeLaneChoice(id: 'grok-4.6', name: 'Grok 4.6')],
          modes: [],
          options: [
            BridgeLaneSetting(
              id: 'reasoning_effort',
              name: 'Effort',
              category: 'model_option',
              current: 'high',
              values: [
                BridgeLaneChoice(id: 'low', name: 'Low'),
                BridgeLaneChoice(id: 'high', name: 'High'),
              ],
            ),
          ],
        ),
      ),
      'Grok 4.6 · High',
    );
    // A model the list does not name reads as its id; nothing at all reads
    // Settings.
    expect(
      settingsChip(
        const BridgeLaneSettings(
          model: 'm-1',
          models: [],
          modes: [],
          options: [],
        ),
      ),
      'm-1',
    );
    expect(
      settingsChip(
        const BridgeLaneSettings(
          models: [],
          modes: [BridgeLaneChoice(id: 'a', name: 'A')],
          options: [],
        ),
      ),
      'Settings',
    );
  });

  test('the effort select and the fast toggle are craze\'s own readings', () {
    expect(effortOption(_opus.options)?.id, 'effort');
    expect(
      effortOption([_opus.options.first]),
      isNull,
      reason: 'thinking is no effort',
    );
    expect(fastOn(_grok46.options), isTrue);
    expect(fastOn(_opus.options), isFalse);
    // On is the value that is not off — by name or spelling, never by
    // position.
    expect(
      fastOn(const [
        BridgeLaneSetting(
          id: 'fast',
          name: 'Fast',
          category: 'model_config',
          current: 'on',
          values: [
            BridgeLaneChoice(id: 'on', name: 'Turbo'),
            BridgeLaneChoice(id: 'off', name: 'Off'),
          ],
        ),
      ]),
      isTrue,
    );
    expect(choiceName(_grok46.models, 'glm-5.2'), 'GLM 5.2');
    expect(choiceName(_grok46.models, null), isNull);
    expect(choiceName(_grok46.models, 'unlisted'), 'unlisted');
  });

  test('CONTROL: offered only when the capabilities say settings — the '
      'capability alone decides', () {
    expect(settingsOffered(_caps(settings: true)), isTrue);
    expect(settingsOffered(_caps(settings: false)), isFalse);
    expect(settingsOffered(null), isFalse, reason: 'no seed yet says nothing');
    // Offered before the first Settings: an empty sheet, a "Settings" chip.
    expect(sheetRows(noSettings), isEmpty);
    expect(settingsChip(noSettings), 'Settings');
  });

  test('a change\'s life: pending, then cleared, refused inline, or not '
      'confirmed', () {
    expect(settle(SettingKind.config, null, 3), isNull);
    expect(
      settle(SettingKind.config, _notAccepting, 3),
      const RowRefused(staleModelText),
    );
    expect(
      settle(SettingKind.model, _notAccepting, 3),
      const RowRefused('the session is not accepting that right now'),
    );
    expect(
      settle(
        SettingKind.mode,
        AppError('LANE_FAILED', 'json-rpc error -32602: Invalid params', 500),
        3,
      ),
      const RowRefused('json-rpc error -32602: Invalid params'),
    );
    expect(settle(SettingKind.config, _lost, 3), const RowNotConfirmed(3));
    expect(markText(const RowPending()), pendingText);
    expect(markText(const RowNotConfirmed(0)), notConfirmedText);
    expect(markText(const RowRefused('no')), 'no');
    expect(markText(null), isNull);
  });

  test('CONTROL: a lost answer whose value is already ON SCREEN is not '
      '"not confirmed"', () {
    expect(
      settle(SettingKind.config, _lost, 4, confirmedOnScreen: true),
      isNull,
      reason: 'the session\'s Settings already said it took',
    );
    expect(settle(SettingKind.config, _lost, 4), const RowNotConfirmed(4));
    expect(
      settle(SettingKind.config, _notAccepting, 4, confirmedOnScreen: true),
      const RowRefused(staleModelText),
      reason: 'a refusal is shown whatever is on screen',
    );
  });

  test('CONTROL: not confirmed until the NEXT Settings, which replaces it', () {
    final lost = settle(SettingKind.config, _lost, 5);
    expect(
      shownMark(lost, 5),
      lost,
      reason: 'no Settings since: still not confirmed',
    );
    expect(
      shownMark(lost, 6),
      isNull,
      reason: 'the next Settings states the real value',
    );
    const refused = RowRefused(staleModelText);
    expect(
      shownMark(refused, 99),
      refused,
      reason: 'a refusal stays until the row is pressed again',
    );
    expect(shownMark(const RowPending(), 99), isA<RowPending>());
  });

  test('a press sends only a change: never while pending, never the current '
      'value', () {
    final effort = _row(_grok46, 'effort');
    expect(pressSends(effort, 'low', null), isTrue);
    expect(pressSends(effort, 'high', null), isFalse, reason: 'already high');
    expect(pressSends(effort, 'low', const RowPending()), isFalse);
    expect(
      pressSends(effort, 'max', null),
      isFalse,
      reason: 'a value the row does not offer',
    );
    expect(
      pressSends(effort, 'low', const RowRefused(staleModelText)),
      isTrue,
      reason: 'the retry',
    );
  });

  test('the context meter: tokens and a known window only', () {
    final meter = usageMeter(
      BridgeLaneUsage(
        contextTokens: BigInt.from(68000),
        contextWindow: BigInt.from(200000),
      ),
    );
    expect(meter?.tokens, 68000);
    expect(meter?.window, 200000);
    expect(meter?.percent, 34);
    expect(meter?.text, '68k / 200k tokens · 34%');
    expect(usageMeter(BridgeLaneUsage(contextTokens: BigInt.from(5))), isNull);
    expect(
      usageMeter(
        BridgeLaneUsage(
          contextTokens: BigInt.from(5),
          contextWindow: BigInt.zero,
        ),
      ),
      isNull,
    );
    expect(usageMeter(null), isNull);
    expect(
      usageMeter(
        BridgeLaneUsage(
          contextTokens: BigInt.from(300000),
          contextWindow: BigInt.from(200000),
        ),
      )?.percent,
      100,
    );
    expect(compactTokens(1500), '1.5k');
    expect(compactTokens(1000000), '1M');
    expect(compactTokens(999), '999');
  });

  test('CONTROL: the fixtures\' labels carry no invisible characters', () {
    // A zero-width character in a label is invisible in a diff and changes
    // what an equality reads (CodeRabbit, C11). Every name a fixture here
    // offers is plain text.
    final invisible = RegExp('[​-‍⁠﻿]');
    for (final s in [_grok46, _opus]) {
      final names = [
        ...s.models.map((m) => m.name),
        ...s.modes.map((m) => m.name),
        for (final o in s.options) ...[o.name, ...o.values.map((v) => v.name)],
      ];
      for (final n in names) {
        expect(invisible.hasMatch(n), isFalse, reason: n);
      }
    }
  });
}

final _notAccepting = appErrorFromLane(const BridgeLaneError.notAccepting());
final _lost = appErrorFromLane(
  const BridgeLaneError.outcomeUnknown(msg: 'outcome unknown: dropped'),
);

List<BridgeLaneChoice> _offOn(String on) => [
  const BridgeLaneChoice(id: 'false', name: 'Off'),
  BridgeLaneChoice(id: 'true', name: on),
];

/// craze's permodel cursor on grok-4.6, as shed-craze hands it over (ordered).
final _grok46 = BridgeLaneSettings(
  model: 'grok-4.6',
  models: const [
    BridgeLaneChoice(id: 'grok-4.6', name: 'Grok 4.6'),
    BridgeLaneChoice(id: 'composer-2.5', name: 'Composer 2.5'),
    BridgeLaneChoice(id: 'claude-opus-5', name: 'Claude Opus 5'),
    BridgeLaneChoice(id: 'glm-5.2', name: 'GLM 5.2'),
  ],
  mode: 'agent',
  modes: const [
    BridgeLaneChoice(id: 'agent', name: 'Agent'),
    BridgeLaneChoice(id: 'plan', name: 'Plan'),
    BridgeLaneChoice(id: 'ask', name: 'Ask'),
  ],
  options: [
    const BridgeLaneSetting(
      id: 'effort',
      name: 'Effort',
      category: 'thought_level',
      current: 'high',
      values: [
        BridgeLaneChoice(id: 'low', name: 'Low'),
        BridgeLaneChoice(id: 'medium', name: 'Medium'),
        BridgeLaneChoice(id: 'high', name: 'High'),
        BridgeLaneChoice(id: 'xhigh', name: 'Extra High'),
      ],
    ),
    BridgeLaneSetting(
      id: 'fast',
      name: 'Fast',
      category: 'model_config',
      current: 'true',
      values: _offOn('Fast'),
    ),
  ],
);

/// …and on claude-opus-5: thinking AND effort under thought_level.
final _opus = _with(
  _grok46,
  model: 'claude-opus-5',
  options: [
    BridgeLaneSetting(
      id: 'thinking',
      name: 'Thinking',
      category: 'thought_level',
      current: 'true',
      values: _offOn('On'),
    ),
    const BridgeLaneSetting(
      id: 'effort',
      name: 'Effort',
      category: 'thought_level',
      current: 'max',
      values: [
        BridgeLaneChoice(id: 'low', name: 'Low'),
        BridgeLaneChoice(id: 'medium', name: 'Medium'),
        BridgeLaneChoice(id: 'high', name: 'High'),
        BridgeLaneChoice(id: 'xhigh', name: 'Extra High'),
        BridgeLaneChoice(id: 'max', name: 'Max'),
      ],
    ),
    const BridgeLaneSetting(
      id: 'context',
      name: 'Context',
      category: 'model_config',
      current: '300k',
      values: [
        BridgeLaneChoice(id: '300k', name: '300K'),
        BridgeLaneChoice(id: '1m', name: '1M'),
      ],
    ),
    BridgeLaneSetting(
      id: 'fast',
      name: 'Fast',
      category: 'model_config',
      current: 'false',
      values: _offOn('Fast'),
    ),
  ],
);

BridgeLaneSettings _with(
  BridgeLaneSettings s, {
  String? model,
  List<BridgeLaneChoice>? models,
  List<BridgeLaneSetting>? options,
}) => BridgeLaneSettings(
  model: model ?? s.model,
  models: models ?? s.models,
  mode: s.mode,
  modes: s.modes,
  options: options ?? s.options,
  usage: s.usage,
);

SettingsRow _row(BridgeLaneSettings s, String id) =>
    sheetRows(s).firstWhere((r) => r.id == id);

BridgeLaneCapabilities _caps({required bool settings}) =>
    BridgeLaneCapabilities(
      kind: 'craze',
      interject: true,
      cancel: true,
      approvals: true,
      historyCursor: true,
      settings: settings,
      stop: true,
    );
