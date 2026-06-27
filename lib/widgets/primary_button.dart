import 'package:flutter/material.dart';

import '../theme/shed_theme.dart';

/// The design's primary call-to-action: a full-width, tall, fully-rounded accent
/// pill. `onPressed: null` disables it (the theme greys it via surface2/fg3).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: const StadiumBorder(),
          textStyle: sansStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      ),
    );
  }
}
