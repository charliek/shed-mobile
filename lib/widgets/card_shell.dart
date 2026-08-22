import 'package:flutter/material.dart';

import '../theme/shed_colors.dart';

/// The shared cross-host card chrome: a surface-filled, hairline-bordered, radius
/// -13 rounded box. Defaults to the Sheds/Sessions card insets; the System card
/// overrides [padding]. Centralizes "the card look" across the three sections.
class CardShell extends StatelessWidget {
  const CardShell({
    required this.child,
    this.margin,
    this.padding,
    this.rail,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  /// A coloured left edge encoding what most wants attention.
  ///
  /// The point is a COLUMN, not a card: eight sessions read as a strip of
  /// edges, and the ones asking for you find you without any of them being
  /// read. Null leaves the card as it was, so a caller with nothing to say
  /// says nothing.
  final Color? rail;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    final r = rail;
    final radius = BorderRadius.circular(13);
    final body = Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(16, 14, 14, 14),
      child: child,
    );
    return Container(
      margin: margin ?? const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: radius,
      ),
      child: ClipRRect(
        borderRadius: radius,
        // A STACK, not a Row and not a mixed-colour border. A stretched Row
        // needs a bounded height and these cards live in scroll views where it
        // is unbounded; a `Border` with one differently-coloured side cannot be
        // painted with a radius at all. The stack takes its size from the body,
        // so the rail can stretch against it without constraining anything.
        child: Stack(
          children: [
            body,
            if (r != null)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 4,
                child: ColoredBox(color: r),
              ),
          ],
        ),
      ),
    );
  }
}
