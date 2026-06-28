import 'package:flutter/material.dart';

import 'app_section.dart';
import 'desktop_scaffold.dart';
import 'mobile_scaffold.dart';

/// The responsive root behind the onboarding gate. At >= [kDesktopBreakpoint] it
/// renders the desktop sidebar layout; below it, the mobile bottom-tab layout.
/// The selected section is shared across layouts via `appSectionProvider`.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => isDesktopWidth(constraints.maxWidth)
          ? const DesktopScaffold(key: ValueKey('shell-desktop'))
          : const MobileScaffold(key: ValueKey('shell-mobile')),
    );
  }
}
