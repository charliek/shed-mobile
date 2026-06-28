import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme_mode_provider.dart';

/// The shared light/dark toggle (sun/moon) used across the app chrome — the
/// mobile Hosts header and the desktop main-pane header. Pass a `ValueKey` via
/// [key] so the drive harness can target the specific instance.
class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      tooltip: 'Toggle theme',
      onPressed: () => ref
          .read(themeModeProvider.notifier)
          .toggle(Theme.of(context).brightness),
    );
  }
}
