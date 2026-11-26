import 'package:flutter/material.dart';

import '../shed/cloud.dart';
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
    return _Tag(bg: bg, fg: fg, label: label);
  }
}

/// The `Cloud` tag a cloud shed wears (plan 041), in the runtime badge's shape
/// with its own colour.
class CloudBadge extends StatelessWidget {
  const CloudBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    return _Tag(
      bg: c.runtimeCloudBg,
      fg: c.runtimeCloudFg,
      label: cloudBadgeLabel,
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.bg, required this.fg, required this.label});

  final Color bg;
  final Color fg;
  final String label;

  @override
  Widget build(BuildContext context) {
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
