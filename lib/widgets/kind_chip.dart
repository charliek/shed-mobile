import 'package:flutter/material.dart';

import '../shed/shed_status.dart';
import '../theme/shed_colors.dart';
import '../theme/shed_theme.dart';

/// The agent-kind chip: the wire kind in a bordered pill with a colored left
/// accent bar (via [kindColor]). Takes the raw wire string so it serves both the
/// enum path (claude/shell) and the cross-host HTTP path (codex/cursor/…).
class KindChip extends StatelessWidget {
  const KindChip(this.kind, {super.key});

  final String kind;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: kindColor(c, kind)),
            Container(
              padding: const EdgeInsets.fromLTRB(7, 3, 8, 3),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border(
                  top: BorderSide(color: c.line),
                  right: BorderSide(color: c.line),
                  bottom: BorderSide(color: c.line),
                ),
              ),
              child: Text(
                kind,
                style: monoStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: c.fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
