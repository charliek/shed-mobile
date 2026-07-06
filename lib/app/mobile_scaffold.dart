import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/rc/all_sessions_view.dart';
import '../features/servers/server_list_screen.dart';
import '../features/sheds/all_sheds_view.dart';
import '../features/create/target_picker.dart';
import '../marionette/drive_state.dart';
import '../providers.dart';
import '../theme/shed_colors.dart';
import '../theme/shed_theme.dart';
import 'app_section.dart';

/// The mobile layout: the active section above a bottom tab bar (Hosts · Sheds ·
/// Sessions). Drill-in screens (per-host sheds, sessions, create flows, terminal)
/// push full-screen routes on the root Navigator, which naturally cover the tab
/// bar — so there's no separate "hide tabs" state to track.
class MobileScaffold extends ConsumerWidget {
  const MobileScaffold({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(appSectionProvider);
    logDriveState('layout=mobile section=${section.name}');
    final body = switch (section) {
      // The Hosts tab is the merged host list (its own Scaffold: brand header
      // with the theme/identity actions, host cards with disk usage, Add-host
      // FAB).
      AppSection.hosts => const ServerListScreen(),
      AppSection.sheds => const _Section(
        title: 'Sheds',
        fab: _CreateFab(
          key: ValueKey('allsheds-create'),
          target: CreateTarget.shed,
        ),
        child: AllShedsView(),
      ),
      AppSection.sessions => const _Section(
        title: 'Sessions',
        fab: _CreateFab(
          key: ValueKey('allsessions-create'),
          target: CreateTarget.session,
        ),
        child: AllSessionsView(),
      ),
    };
    return PopScope(
      // From a non-Hosts tab, Android back returns to Hosts before exiting.
      canPop: section == AppSection.hosts,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          ref.read(appSectionProvider.notifier).select(AppSection.hosts);
        }
      },
      child: Scaffold(body: body, bottomNavigationBar: const _TabBar()),
    );
  }
}

/// A cross-host section tab: a titled app bar over the shared section view, with
/// an optional create FAB (New shed / New session).
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.fab});

  final String title;
  final Widget child;
  final Widget? fab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: child,
      floatingActionButton: fab,
    );
  }
}

/// The cross-host create FAB: picks a target (host for a shed, running shed for a
/// session) then pushes the existing create screen. See [startCreate].
class _CreateFab extends ConsumerWidget {
  const _CreateFab({required this.target, super.key});

  final CreateTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FloatingActionButton.extended(
      onPressed: () => startCreate(context, ref, target),
      icon: const Icon(Icons.add, size: 20),
      label: Text(createLabel(target)),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar();

  @override
  Widget build(BuildContext context) {
    final shed = context.shed;
    return Container(
      decoration: BoxDecoration(
        color: shed.surface,
        border: Border(top: BorderSide(color: shed.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: const [
              _Tab(AppSection.hosts, Icons.dns_outlined, 'Hosts'),
              _Tab(AppSection.sheds, Icons.view_in_ar_outlined, 'Sheds'),
              _Tab(AppSection.sessions, Icons.terminal_outlined, 'Sessions'),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends ConsumerWidget {
  const _Tab(this.section, this.icon, this.label);

  final AppSection section;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shed = context.shed;
    final selected = ref.watch(appSectionProvider) == section;
    final color = selected ? shed.accent : shed.fg3;
    return Expanded(
      child: InkWell(
        key: ValueKey('nav-${section.name}'),
        onTap: () => ref.read(appSectionProvider.notifier).select(section),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 21, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              style: monoStyle(
                fontSize: 9.5,
                color: color,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
