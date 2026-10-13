import 'package:flutter/material.dart';

import '../../src/rust/api/dto_lane.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';

/// One menu row's height. Fixed, so a catalog of hundreds of rows lays out
/// lazily (only the rows on screen are built) and the highlight can be
/// scrolled into view by arithmetic.
const slashMenuRowExtent = 44.0;

/// The share of the viewport's height the panel may take before it scrolls
/// (P24) — the transcript and the composer stay on screen.
const slashMenuMaxHeightFraction = 0.4;

/// **The transcript composer's `/` menu panel** (plan 029 §3.5, D17) — above
/// the composer, while the shared filter says the menu is open.
///
/// It RENDERS what the shared core answered (`SlashRules.filter`): the rows in
/// the order given, the highlighted one, and the dimmed ones. It decides
/// nothing — which rows exist, what a tap on one does and whether it is
/// refused are `shed_app::slash_menu`'s, and the keys are the composer's
/// (`slash_keys.dart`). The desktop's `SlashMenu.tsx`.
///
/// * **Capped at 40 % of the viewport's height, and it scrolls** (P24): a
///   catalog has no row cap (P16), and 600 rows lay out lazily. ↑/↓ keep the
///   highlighted row in view.
/// * **A while-working row is DIMMED, not hidden** (X7/P29) — a deliberate
///   deviation from this app's hidden-never-disabled rule: the gate is
///   TEMPORAL, not a capability the session lacks, and craze's guidance is to
///   list such a row and refuse it client-side. It reads "after this turn",
///   and a tap on it is answered with the refusal, the draft kept.
/// * **A tap keeps the composer's focus**: the panel is part of the text
///   field's tap region, so choosing a row is not a tap "outside" that drops
///   the caret (the desktop's `onMouseDown` `preventDefault`).
class SlashMenuPanel extends StatefulWidget {
  const SlashMenuPanel({
    required this.rows,
    required this.highlight,
    required this.onPick,
    super.key,
  });

  /// The open menu's rows, in the shared filter's order.
  final List<BridgeSlashFilterRow> rows;

  /// The index of the row Enter and Tab accept.
  final int highlight;

  /// A tap on a row, by name — the menu's `pick`, the shared rule deciding
  /// what it does (run at once, complete, or refuse while working).
  final void Function(String name) onPick;

  @override
  State<SlashMenuPanel> createState() => _SlashMenuPanelState();
}

class _SlashMenuPanelState extends State<SlashMenuPanel> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(SlashMenuPanel old) {
    super.didUpdateWidget(old);
    if (old.highlight != widget.highlight ||
        !identical(old.rows, widget.rows)) {
      _reveal();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Keep the highlighted row in view once this frame has laid out: scrolled
  /// to just enough that it is wholly visible — the nearest edge, as the
  /// desktop's `scrollIntoView({block: "nearest"})`.
  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      final top = widget.highlight * slashMenuRowExtent;
      final bottom = top + slashMenuRowExtent;
      if (top < position.pixels) {
        _scroll.jumpTo(top);
      } else if (bottom > position.pixels + position.viewportDimension) {
        _scroll.jumpTo(bottom - position.viewportDimension);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    return TextFieldTapRegion(
      child: Container(
        key: const ValueKey('lane-slash-menu'),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.line)),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                MediaQuery.sizeOf(context).height * slashMenuMaxHeightFraction,
          ),
          child: Material(
            color: c.surface2,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
              side: BorderSide(color: c.line),
            ),
            child: Semantics(
              label: 'Commands',
              container: true,
              child: ListView.builder(
                key: const ValueKey('lane-slash-list'),
                controller: _scroll,
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemExtent: slashMenuRowExtent,
                itemCount: widget.rows.length,
                itemBuilder: (context, i) => _SlashRow(
                  row: widget.rows[i],
                  highlighted: i == widget.highlight,
                  onPick: widget.onPick,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One row: `/name`, its argument hint, its description (or its second
/// spelling), and — dimmed — "after this turn".
class _SlashRow extends StatelessWidget {
  const _SlashRow({
    required this.row,
    required this.highlighted,
    required this.onPick,
  });

  final BridgeSlashFilterRow row;
  final bool highlighted;
  final void Function(String name) onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    final r = row.row;
    final detail =
        r.description ?? (r.qualified == null ? '' : '/${r.qualified}');
    return Semantics(
      selected: highlighted,
      button: true,
      child: InkWell(
        key: ValueKey('lane-slash-row-${r.name}'),
        onTap: () => onPick(r.name),
        child: Container(
          color: highlighted ? c.accentSoft : null,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          child: Opacity(
            // DIMMED, not hidden (X7/P29): the class doc.
            opacity: row.dimmed ? 0.5 : 1,
            child: Row(
              children: [
                Text(
                  '/${r.name}',
                  style: monoStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: highlighted ? c.accent : c.fg,
                  ),
                ),
                if (r.argHint case final hint?) ...[
                  const SizedBox(width: 6),
                  Text(hint, style: monoStyle(fontSize: 11.5, color: c.fg3)),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sansStyle(fontSize: 12.5, color: c.fg2),
                  ),
                ),
                if (row.dimmed) ...[
                  const SizedBox(width: 8),
                  Text(
                    'after this turn',
                    key: ValueKey('lane-slash-after-${r.name}'),
                    style: sansStyle(fontSize: 11, color: c.fg3),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
