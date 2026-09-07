import 'package:flutter/material.dart';

import '../theme/shed_colors.dart';
import '../theme/shed_theme.dart';

/// The dark "›_ open" pill that opens a session's in-app terminal — or, for a
/// roost-backed machine row, the read-only peek. Shared by the per-shed
/// sessions list and the cross-host Sessions cards. Pass a `ValueKey` via [key]
/// for the drive harness; [padding] widens it (the cross-host card's pill).
///
/// [tooltip], when given, wraps the pill in a [Tooltip] — both the hover/
/// long-press hint and its accessibility label. The peek affordance
/// (`attachKind == 'native-remote'`) passes `'Peek'` here: the glyph stays the
/// same `›_ open` pill so the two attach kinds read as "the same kind of
/// button", but a person (or a screen reader) can tell what it actually does.
class OpenPill extends StatelessWidget {
  const OpenPill({required this.onTap, this.padding, this.tooltip, super.key});

  final VoidCallback onTap;
  final EdgeInsetsGeometry? padding;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    final pill = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 34,
        alignment: Alignment.center,
        padding: padding,
        decoration: BoxDecoration(
          color: c.btnDark,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '›_ open',
          style: monoStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: c.btnDarkFg,
          ),
        ),
      ),
    );
    final t = tooltip;
    return t == null ? pill : Tooltip(message: t, child: pill);
  }
}
