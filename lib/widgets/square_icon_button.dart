import 'package:flutter/material.dart';

import '../theme/shed_colors.dart';

/// A compact bordered square icon button (the design's per-row action button:
/// surface fill, hairline border, radius 9). Pass a `ValueKey` via `key` so the
/// drive harness can target it.
class SquareIconButton extends StatelessWidget {
  const SquareIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.iconColor,
    this.size = 34,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final Color? iconColor;
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
          color: shed.surface,
          border: Border.all(color: shed.line),
          borderRadius: radius,
        ),
        child: Icon(icon, size: 16, color: iconColor ?? shed.fg2),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
