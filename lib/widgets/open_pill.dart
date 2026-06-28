import 'package:flutter/material.dart';

import '../theme/shed_colors.dart';
import '../theme/shed_theme.dart';

/// The dark "›_ open" pill that opens a session's in-app terminal. Shared by the
/// per-shed sessions list and the cross-host Sessions cards. Pass a `ValueKey` via
/// [key] for the drive harness; [padding] widens it (the cross-host card's pill).
class OpenPill extends StatelessWidget {
  const OpenPill({required this.onTap, this.padding, super.key});

  final VoidCallback onTap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 40,
        alignment: Alignment.center,
        padding: padding,
        decoration: BoxDecoration(
          color: c.btnDark,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '›_ open',
          style: monoStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: c.btnDarkFg,
          ),
        ),
      ),
    );
  }
}
