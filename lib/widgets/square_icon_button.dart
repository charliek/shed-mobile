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
    final button = InkWell(
      onTap: onPressed,
      borderRadius: radius,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background ?? shed.surface,
          border: background == null ? Border.all(color: shed.line) : null,
          borderRadius: radius,
        ),
        child: Icon(icon, size: 16, color: iconColor ?? shed.fg2),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
