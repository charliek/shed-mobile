import 'package:flutter/material.dart';

import '../theme/shed_colors.dart';
import '../theme/shed_theme.dart';

/// A small mono count pill (e.g. "3 servers", "2 sheds") shown next to a title.
/// The design's `surface2`-filled, `fg3`, radius-6 chip.
class CountChip extends StatelessWidget {
  const CountChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final shed = context.shed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: shed.surface2,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: monoStyle(fontSize: 11, color: shed.fg3)),
    );
  }
}
