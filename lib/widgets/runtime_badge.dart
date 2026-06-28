import 'package:flutter/material.dart';

import '../shed/shed_status.dart';
import '../theme/shed_colors.dart';
import '../theme/shed_theme.dart';

/// A small mono backend badge — vz (blue) / firecracker (amber). Renders nothing
/// for an unknown or runtime-less backend, so callers can drop it in
/// unconditionally.
class RuntimeBadge extends StatelessWidget {
  const RuntimeBadge(this.backend, {super.key});

  final String? backend;

  @override
  Widget build(BuildContext context) {
    final style = runtimeBadge(context.shed, backend);
    if (style == null) return const SizedBox.shrink();
    final (bg, fg, label) = style;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: monoStyle(
          fontSize: 9.5,
          color: fg,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
