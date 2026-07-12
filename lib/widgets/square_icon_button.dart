import 'package:flutter/material.dart';

import '../theme/shed_colors.dart';

/// A compact square icon button (the design's per-row action button, radius 9).
/// Default: surface fill + hairline border. Pass [background] for the tinted,
/// borderless variant (the design's start/stop/restart actions in ok/warn/err
/// tones). Pass a `ValueKey` via `key` so the drive harness can target it.
class SquareIconButton extends StatelessWidget {
  const SquareIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.iconColor,
    this.background,
    this.size = 34,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final Color? iconColor;
  final Color? background;
  final double size;

  @override
  Widget build(BuildContext context) {
    final shed = context.shed;
    final radius = BorderRadius.circular(9);
    Widget body = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? shed.surface,
        border: background == null ? Border.all(color: shed.line) : null,
        borderRadius: radius,
      ),
      child: Icon(icon, size: 16, color: iconColor ?? shed.fg2),
    );
    // The Tooltip sits INSIDE the InkWell (not around it) so this widget's
    // root — the element a drive-harness ValueKey tap resolves to — IS the
    // gesture target, matching OpenPill (whose key-taps work). With the
    // Tooltip outermost, a key-tap landed on the Tooltip's own recognizer and
    // never reached the InkWell.
    if (tooltip != null) body = Tooltip(message: tooltip!, child: body);
    return InkWell(onTap: onPressed, borderRadius: radius, child: body);
  }
}
