import 'package:flutter/material.dart';

import '../theme/shed_colors.dart';
import '../theme/shed_theme.dart';
import 'owl.dart';

/// The design's empty-state block: a faded owl ghost, a heading, and a mono
/// helper line. Shared by the server/shed/session lists. Pass a `ValueKey` so
/// the drive harness can find it (e.g. `servers-empty`, `sheds-empty`).
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final shed = context.shed;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const OwlGhost(width: 64),
            const SizedBox(height: 16),
            Text(
              title,
              style: sansStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: shed.fg2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: monoStyle(fontSize: 12, color: shed.fg3),
            ),
          ],
        ),
      ),
    );
  }
}
