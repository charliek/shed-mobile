/// **The settings sheet's pure rules** (plan 025 §3.10, CM6) — the header
/// chip's words, the sheet's rows and the control each one is, what a press
/// sends, a change's life on its row, and the context meter.
///
/// The desktop's `laneSettings.ts`, ported rule for rule (shed `9a84ddf`): both
/// clients show one sheet, and a rule that read differently on the phone would
/// be a second product. Pure (no provider, no widget, no native call) so
/// `test/lanes/lane_settings_test.dart` pins every one without the bridge; the
/// controller (`LaneController.setSetting`, which owns each row's mark) and the
/// sheet (`features/lanes/lane_settings_sheet.dart`, which draws them) only
/// apply them.
///
/// **The data is the adapter's, ordered already.** shed-craze computes craze's
/// model order (the current model, then the remembered ones by rank, then the
/// catalog's) and the options' (the current model's own, `thought_level`
/// first, then `model_config`, each in the provider's order) ONCE; this module
/// never re-sorts what it is given. It only decides how each row is drawn.
library;

import 'package:flutter/foundation.dart' show immutable;

import '../bridge/bridge_adapters.dart'
    show laneNotAcceptingCode, laneOutcomeUnknownCode;
import '../core/app_error.dart';
import '../src/rust/api/dto_lane.dart';

// ---- where they are offered --------------------------------------------------

/// **Where the settings are offered at all**: on a session whose streamed
/// capabilities say `settings`, and NOWHERE else — hidden, never disabled
/// (plan 025 §3.10): no chip, and no sheet even when one is asked for. The
/// capability alone decides; a session that says `settings` before its first
/// `Settings` has arrived shows an empty sheet ([noSettings]), not none.
bool settingsOffered(BridgeLaneCapabilities? capabilities) =>
    capabilities?.settings ?? false;

/// Settings with nothing in them — what a sheet draws before the first
/// `Settings` of a session that offers them.
const noSettings = BridgeLaneSettings(models: [], modes: [], options: []);

// ---- the rows ------------------------------------------------------------------

/// The most values a row shows side by side; a longer list is a list.
const segmentedMax = 4;

/// `segmented` (every value one press away, side by side) or `list`.
enum SettingControl { segmented, list }

/// **≤ 4 values → a segmented control, more → a list** (plan 025 §3.10).
SettingControl controlFor(int values) =>
    values <= segmentedMax ? SettingControl.segmented : SettingControl.list;

/// What a press on a row changes.
enum SettingKind { model, mode, config }

/// One row of the sheet. [id] is the row's name — `model`, `mode`, or the
/// option's own id — and [kind] what a press on it changes.
@immutable
class SettingsRow {
  const SettingsRow({
    required this.id,
    required this.kind,
    required this.name,
    required this.control,
    required this.current,
    required this.values,
    required this.category,
  });

  final String id;
  final SettingKind kind;
  final String name;
  final SettingControl control;

  /// The current value's id, as the session last said (null when it does not
  /// say).
  final String? current;
  final List<BridgeLaneChoice> values;

  /// The option's category (`thought_level`, `model_config`, …); null for the
  /// model and mode rows.
  final String? category;

  /// The row's key in the marks: its kind and id — an option could be named
  /// `model`, and its row is not the model row.
  String get key => '${kind.name}:$id';
}

/// **The sheet's rows, in the order plan 025 §3.10 pins**: the model (always a
/// list — there can be hundreds), then the current model's options in the
/// order given, then the mode, when there are modes. A row with nothing to
/// pick is not drawn (hidden, never disabled).
List<SettingsRow> sheetRows(BridgeLaneSettings s) => [
  if (s.models.isNotEmpty)
    SettingsRow(
      id: 'model',
      kind: SettingKind.model,
      name: 'Model',
      control: SettingControl.list,
      current: s.model,
      values: s.models,
      category: null,
    ),
  for (final o in s.options)
    if (o.values.isNotEmpty)
      SettingsRow(
        id: o.id,
        kind: SettingKind.config,
        name: o.name.isEmpty ? o.id : o.name,
        control: controlFor(o.values.length),
        current: o.current,
        values: o.values,
        category: o.category,
      ),
  if (s.modes.isNotEmpty)
    SettingsRow(
      id: 'mode',
      kind: SettingKind.mode,
      name: 'Mode',
      control: controlFor(s.modes.length),
      current: s.mode,
      values: s.modes,
      category: null,
    ),
];

/// [row] as [settings] draw it NOW — the same kind and id — or null when it is
/// no longer drawn.
SettingsRow? rowNow(BridgeLaneSettings settings, SettingsRow row) {
  for (final r in sheetRows(settings)) {
    if (r.kind == row.kind && r.id == row.id) return r;
  }
  return null;
}

/// **What pressing [value] on [row] sends.** An option is bound to
/// [displayedModel] — the model the sheet SHOWED when it was pressed (plan 025
/// Amendment A13): the session's adapter may already have folded a move the
/// sheet has not drawn, and the change must be refused (`stale_model`) rather
/// than applied to a model nobody chose it for. No model shown, no binding.
BridgeLaneSettingChange changeFor(
  SettingsRow row,
  String value,
  String? displayedModel,
) => switch (row.kind) {
  SettingKind.model => BridgeLaneSettingChange.model(id: value),
  SettingKind.mode => BridgeLaneSettingChange.mode(id: value),
  SettingKind.config => BridgeLaneSettingChange.config(
    id: row.id,
    value: value,
    forModel: (displayedModel?.isEmpty ?? true) ? null : displayedModel,
  ),
};

// ---- the chip ------------------------------------------------------------------

/// Words that make an option an effort select (craze's own reading,
/// `agent.isEffortSelect`): the id or the name says effort or reasoning.
bool _isEffort(BridgeLaneSetting o) {
  final id = o.id.toLowerCase();
  final name = o.name.toLowerCase();
  return o.values.isNotEmpty &&
      (id.contains('effort') ||
          id.contains('reasoning') ||
          name.contains('effort') ||
          name.contains('reasoning'));
}

/// craze's rank among effort selects (`agent.effortRank`): the exact id
/// `effort` first — cursor files `thinking` under `thought_level` beside it,
/// so a category is no evidence — then `model_option`, then `thought_level`.
int _effortRank(BridgeLaneSetting o) {
  if (o.id.toLowerCase() == 'effort') return 0;
  if (o.category == 'model_option') return 1;
  if (o.category == 'thought_level') return 2;
  return 3;
}

/// The session's effort select, or null when it offers none.
BridgeLaneSetting? effortOption(List<BridgeLaneSetting> options) {
  BridgeLaneSetting? best;
  for (final o in options) {
    if (_isEffort(o) && (best == null || _effortRank(o) < _effortRank(best))) {
      best = o;
    }
  }
  return best;
}

/// Whether the session's fast toggle exists AND is on (craze's `FastOn`): a
/// `model_config` option named fast, whose current value is its ON one — the
/// value that is not the off one, read off the value's own name or spelling
/// (`Off` / `false`), never its position.
bool fastOn(List<BridgeLaneSetting> options) {
  BridgeLaneSetting? opt;
  for (final o in options) {
    if (o.category == 'model_config' &&
        (o.id == 'fast' || o.name.toLowerCase().contains('fast'))) {
      opt = o;
      break;
    }
  }
  if (opt == null) return false;
  bool isOff(BridgeLaneChoice v) =>
      v.name.trim().toLowerCase() == 'off' ||
      v.id.trim().toLowerCase() == 'false';
  for (final v in opt.values) {
    if (!isOff(v)) return opt.current == v.id;
  }
  return false;
}

/// What a value is called: its own name, else its id.
String? choiceName(List<BridgeLaneChoice> values, String? id) {
  if (id == null || id.isEmpty) return null;
  for (final v in values) {
    if (v.id == id) return v.name.isEmpty ? id : v.name;
  }
  return id;
}

/// **The transcript header's chip** (plan 025 §3.10):
/// `<model name> · <effort value> · fast`, from the CURRENT values, each part
/// only when the session has it — and "fast" only when the toggle is ON (off
/// is the quiet default and says nothing, craze's own status-row rule). A
/// session whose current values say none of the three reads "Settings".
String settingsChip(BridgeLaneSettings s) {
  final parts = <String>[];
  final model = choiceName(s.models, s.model);
  if (model != null) parts.add(model);
  final effort = effortOption(s.options);
  final effortName = effort == null
      ? null
      : choiceName(effort.values, effort.current);
  if (effortName != null) parts.add(effortName);
  if (fastOn(s.options)) parts.add('fast');
  return parts.isEmpty ? 'Settings' : parts.join(' · ');
}

// ---- a change's life on its row ----------------------------------------------

/// **A row's mark** (plan 025 §3.10's command lifecycle):
///
/// - [RowPending] — the change is sent and craze has not answered; the row
///   takes no other press until it does.
/// - [RowRefused] — craze said no; shown INLINE on the row, until the next
///   press on it (which is a NEW command, never a resend).
/// - [RowNotConfirmed] — the answer was lost with the connection: the change
///   may have run, and it is never resent. Shown until the next `Settings` the
///   session sends ([RowNotConfirmed.since] is how many had arrived when the
///   answer was lost), which states the real value and replaces it.
@immutable
sealed class RowMark {
  const RowMark();
}

final class RowPending extends RowMark {
  const RowPending();
}

final class RowRefused extends RowMark {
  const RowRefused(this.text);

  final String text;

  @override
  bool operator ==(Object other) => other is RowRefused && other.text == text;

  @override
  int get hashCode => Object.hash(RowRefused, text);

  @override
  String toString() => 'RowRefused($text)';
}

final class RowNotConfirmed extends RowMark {
  const RowNotConfirmed(this.since);

  final int since;

  @override
  bool operator ==(Object other) =>
      other is RowNotConfirmed && other.since == since;

  @override
  int get hashCode => Object.hash(RowNotConfirmed, since);

  @override
  String toString() => 'RowNotConfirmed($since)';
}

/// The text a `stale_model` refusal shows: craze's `stale_model` — the session
/// left the model an option was chosen for — reaches a client as the table's
/// `not_accepting`, which is what an option row reads it as.
const staleModelText = 'the model changed; try again';

/// What a "not confirmed" row says.
const notConfirmedText =
    'not confirmed — the connection dropped before craze answered';

/// What a pending row says.
const pendingText = 'applying…';

/// **A row's mark once craze has answered** — null when the change took
/// ([error] null: the row re-renders from the next `Settings`, which craze
/// sends ahead of its answer), [RowNotConfirmed] when the answer was lost
/// ([laneOutcomeUnknownCode]), and otherwise the refusal, inline: on an option
/// row `not_accepting` is the model having moved under the choice.
///
/// [confirmedOnScreen] — the row already SHOWS the value that was asked for —
/// makes a lost answer nothing to mark: the session's own `Settings` said the
/// change took before the loss was known, and "not confirmed" would contradict
/// the value on screen (and could outlive a lane that never reconnects).
RowMark? settle(
  SettingKind kind,
  AppError? error,
  int settingsSeen, {
  bool confirmedOnScreen = false,
}) {
  if (error == null) return null;
  if (error.code == laneOutcomeUnknownCode) {
    return confirmedOnScreen ? null : RowNotConfirmed(settingsSeen);
  }
  if (error.code == laneNotAcceptingCode && kind == SettingKind.config) {
    return const RowRefused(staleModelText);
  }
  return RowRefused(error.message.isEmpty ? error.code : error.message);
}

/// The mark a row SHOWS now: a [RowNotConfirmed] one only until a `Settings`
/// has arrived since the answer was lost.
RowMark? shownMark(RowMark? mark, int settingsSeen) => switch (mark) {
  RowNotConfirmed(:final since) when settingsSeen > since => null,
  _ => mark,
};

/// The line a mark shows under its row.
String? markText(RowMark? mark) => switch (mark) {
  null => null,
  RowPending() => pendingText,
  RowRefused(:final text) => text,
  RowNotConfirmed() => notConfirmedText,
};

/// **Whether a press on a row is a change to send**: not while its last change
/// is pending, not a value the row does not offer, and not the value the row
/// already shows (nothing changes).
bool pressSends(SettingsRow row, String value, RowMark? mark) {
  if (mark is RowPending) return false;
  if (!row.values.any((v) => v.id == value)) return false;
  return value != row.current;
}

// ---- the context meter ---------------------------------------------------------

/// `68000` → `68k`, `1000000` → `1M`, `1500` → `1.5k`.
String compactTokens(int n) {
  String fmt(double v, String unit) {
    final text = v == v.truncateToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
    return '$text$unit';
  }

  if (n >= 1000000) return fmt((n / 100000).round() / 10, 'M');
  if (n >= 1000) return fmt((n / 100).round() / 10, 'k');
  return '$n';
}

/// One context meter: how full, of what, in words.
typedef UsageMeter = ({int tokens, int window, int percent, String text});

/// **The context meter** (plan 025 §3.10): only when the usage has BOTH the
/// tokens and a known window (a native session's); `percent` capped at 100.
UsageMeter? usageMeter(BridgeLaneUsage? u) {
  final tokens = u?.contextTokens?.toInt();
  final window = u?.contextWindow?.toInt();
  if (tokens == null || window == null || window <= 0) return null;
  final raw = (tokens / window * 100).round();
  final percent = raw > 100 ? 100 : raw;
  return (
    tokens: tokens,
    window: window,
    percent: percent,
    text:
        '${compactTokens(tokens)} / ${compactTokens(window)} tokens · '
        '$percent%',
  );
}
