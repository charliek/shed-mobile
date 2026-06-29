import 'package:flutter/material.dart';

import '../theme/shed_colors.dart';

/// The shared cross-host card chrome: a surface-filled, hairline-bordered, radius
/// -13 rounded box. Defaults to the Sheds/Sessions card insets; the System card
/// overrides [padding]. Centralizes "the card look" across the three sections.
class CardShell extends StatelessWidget {
  const CardShell({required this.child, this.margin, this.padding, super.key});

  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    return Container(
      margin: margin ?? const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: padding ?? const EdgeInsets.fromLTRB(16, 14, 14, 14),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(13),
      ),
      child: child,
    );
  }
}
