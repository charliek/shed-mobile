import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../../lanes/lane_controller.dart';
import '../../lanes/lane_settings.dart';
import '../../lanes/lane_state.dart';
import '../../providers.dart';
import '../../src/rust/api/dto_lane.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';

/// **A session's settings sheet, on a phone** (plan 025 §3.10, CM6) — opened
/// from the transcript header's settings chip, as a bottom sheet.
///
/// One sheet, rendered generically from the session's streamed settings
/// ([LaneState.settings], the lane's own snapshot): the model (a list), then
/// the current model's options — each a segmented control when it has four
/// values or fewer, else a list — then the mode, and a context meter when the
/// session reports both its tokens and its window. The desktop's
/// `LaneSettings.tsx`, with its rules in `lanes/lane_settings.dart`.
///
/// Load-bearing rather than stylistic:
///
/// * **It folds nothing and remembers no value.** Every row is drawn from the
///   lane's state as it is NOW (it watches [laneStateProvider]), so the sheet
///   re-renders from the session's next `Settings` — a model change redraws
///   the options as the NEW model offers them, and a change made by another
///   client (an attached TUI, the desktop) appears here live. A press shows no
///   optimistic value: the row says "applying…" until craze answers, and the
///   value it then shows is the session's.
/// * **A change's life is per row, and the LANE holds it**
///   ([LaneState.settingMarks], `LaneController.setSetting`): pending until
///   the answer; a refusal inline on its row — an option refused because the
///   model moved under it reads "the model changed; try again", and the retry
///   is a press, which is a NEW command; an answer lost to a drop is "not
///   confirmed" until the next `Settings` says what the session is at. Nothing
///   is ever resent. Closing the sheet mid-change loses nothing.
/// * **Hidden, never disabled.** The sheet exists only while the session's
///   capabilities say `settings` ([settingsOffered]); a session that stops
///   saying so while the sheet is open takes the sheet away with it.
/// * **An option is bound to the model the sheet SHOWS** (Amendment A13): a
///   press sends the model this sheet drew it under, never one the adapter may
///   have folded since.
class LaneSettingsSheet extends ConsumerWidget {
  const LaneSettingsSheet({required this.lane, super.key});

  /// The lane whose session this is — the same [LaneRef] the transcript
  /// screen watches, so both read one [LaneState].
  final LaneRef lane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(laneStateProvider(lane)).value;
    if (state == null || !settingsOffered(state.capabilities)) {
      _leave(context);
      return const SizedBox.shrink(key: ValueKey('lane-settings-gone'));
    }
    final settings = state.settings ?? noSettings;
    final rows = sheetRows(settings);
    final meter = usageMeter(settings.usage);
    final c = context.shed;
    logDriveState(
      'screen=lane-settings machine=${lane.machine} slug=${lane.slug} '
      'chip=${settingsChip(settings)} rows=${rows.map((r) => r.id).join(',')}',
    );
    return SafeArea(
      key: const ValueKey('lane-settings'),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Session settings',
                style: sansStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: c.fg,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                key: const ValueKey('lane-settings-list'),
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                children: [
                  if (rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No settings yet — the session has not said what it '
                        'offers.',
                        key: const ValueKey('lane-settings-empty'),
                        style: sansStyle(fontSize: 12.5, color: c.fg2),
                      ),
                    ),
                  for (final row in rows)
                    _SettingRow(
                      key: ValueKey('lane-setting-${row.key}'),
                      row: row,
                      mark: shownMark(
                        state.settingMarks[row.key],
                        state.settingsSeen,
                      ),
                      onPress: (value) => _press(
                        ref,
                        row,
                        value,
                        // The model THIS sheet shows, as drawn (A13).
                        displayedModel: settings.model,
                      ),
                    ),
                  if (meter != null) _ContextMeter(meter: meter),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _press(
    WidgetRef ref,
    SettingsRow row,
    String value, {
    required String? displayedModel,
  }) async {
    final LaneController controller;
    try {
      controller = ref.read(laneControllerProvider(lane));
    } on StateError {
      // The row is gone (laneControllerProvider's refusal): nothing to set.
      return;
    }
    await controller.setSetting(row, value, displayedModel: displayedModel);
    // Never threw: the outcome is the row's mark, read off the same lane.
    final mark = controller.state.settingMarks[row.key];
    logDriveResult('lane-set', ok: mark == null, error: markText(mark));
  }

  /// The sheet's session no longer offers settings (or its lane is gone):
  /// take THIS sheet's route away — hidden, never disabled — once the frame
  /// that noticed is done.
  void _leave(BuildContext context) {
    final route = ModalRoute.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route != null && route.isActive) {
        route.navigator?.removeRoute(route);
      }
    });
  }
}

/// **Open the settings sheet** for [lane] — the chip's tap. Only ever called
/// while the session's capabilities say `settings`; the sheet re-checks on
/// every frame and leaves when they stop.
Future<void> showLaneSettingsSheet(BuildContext context, LaneRef lane) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.shed.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => LaneSettingsSheet(lane: lane),
    );

/// One row: its name, its mark (pending / refused / not confirmed) inline,
/// and its control.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.row,
    required this.mark,
    required this.onPress,
    super.key,
  });

  final SettingsRow row;
  final RowMark? mark;
  final void Function(String value) onPress;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    final text = markText(mark);
    final pending = mark is RowPending;
    final markColor = switch (mark) {
      RowRefused() => c.errFg,
      RowNotConfirmed() => c.warnFg,
      _ => c.fg3,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                row.name.toUpperCase(),
                style: monoStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: c.fg2,
                ).copyWith(letterSpacing: 1.1),
              ),
              if (text != null)
                Text(
                  text,
                  key: ValueKey('lane-setting-mark-${row.key}'),
                  style: monoStyle(fontSize: 11.5, color: markColor),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (row.control == SettingControl.segmented)
            _Segmented(row: row, enabled: !pending, onPress: onPress)
          else
            _ChoiceList(row: row, enabled: !pending, onPress: onPress),
        ],
      ),
    );
  }
}

/// ≤ 4 values side by side, the current one accent-filled.
class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.row,
    required this.enabled,
    required this.onPress,
  });

  final SettingsRow row;
  final bool enabled;
  final void Function(String value) onPress;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(9),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < row.values.length; i++) ...[
                if (i > 0) VerticalDivider(width: 1, color: c.line),
                Expanded(
                  child: _Choice(
                    key: ValueKey(
                      'lane-setting-${row.key}-${row.values[i].id}',
                    ),
                    choice: row.values[i],
                    selected: row.values[i].id == row.current,
                    enabled: enabled,
                    filled: true,
                    onTap: () => onPress(row.values[i].id),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// More than four values (and every model list — there can be hundreds): a
/// bounded list, the current one checked.
class _ChoiceList extends StatelessWidget {
  const _ChoiceList({
    required this.row,
    required this.enabled,
    required this.onPress,
  });

  final SettingsRow row;
  final bool enabled;
  final void Function(String value) onPress;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 220),
        decoration: BoxDecoration(
          color: c.surface2,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(9),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          children: [
            for (var i = 0; i < row.values.length; i++) ...[
              if (i > 0) Divider(height: 1, color: c.line),
              _Choice(
                key: ValueKey('lane-setting-${row.key}-${row.values[i].id}'),
                choice: row.values[i],
                selected: row.values[i].id == row.current,
                enabled: enabled,
                filled: false,
                onTap: () => onPress(row.values[i].id),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One value: a segment ([filled], the current one accent-filled) or a list
/// line (the current one checked). Its own button and selected semantics, so
/// a reader — and a test — can ask which value a row shows.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.choice,
    required this.selected,
    required this.enabled,
    required this.filled,
    required this.onTap,
    super.key,
  });

  final BridgeLaneChoice choice;
  final bool selected;
  final bool enabled;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    final label = choice.name.isEmpty ? choice.id : choice.name;
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: filled ? TextAlign.center : TextAlign.start,
      style: sansStyle(
        fontSize: 12.5,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        color: filled
            ? (selected ? c.accent : c.fg2)
            : (selected ? c.accent : c.fg),
      ),
    );
    final body = filled
        ? Container(
            alignment: Alignment.center,
            color: selected ? c.accentSoft : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            child: text,
          )
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: selected
                      ? Icon(Icons.check, size: 16, color: c.accent)
                      : null,
                ),
                Expanded(child: text),
              ],
            ),
          );
    final tappable = InkWell(onTap: enabled ? onTap : null, child: body);
    final description = choice.description;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: description == null || description.isEmpty
          ? tappable
          : Tooltip(message: description, child: tappable),
    );
  }
}

/// How full the session's context is — only when it reports both its tokens
/// and its window ([usageMeter]).
class _ContextMeter extends StatelessWidget {
  const _ContextMeter({required this.meter});

  final UsageMeter meter;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    return Padding(
      key: const ValueKey('lane-settings-meter'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'CONTEXT',
            style: monoStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: c.fg2,
            ).copyWith(letterSpacing: 1.1),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: meter.percent / 100,
              minHeight: 6,
              color: c.accent,
              backgroundColor: c.surface2,
            ),
          ),
          const SizedBox(height: 4),
          Text(meter.text, style: monoStyle(fontSize: 11.5, color: c.fg3)),
        ],
      ),
    );
  }
}
