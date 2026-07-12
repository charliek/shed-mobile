import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../features/create/target_picker.dart';
import '../features/hosts/hosts_view.dart';
import '../features/identity/identity_screen.dart';
import '../features/rc/all_sessions_view.dart';
import '../features/sheds/all_sheds_view.dart';
import '../providers.dart';
import '../theme/shed_colors.dart';
import '../theme/shed_theme.dart';
import '../widgets/owl.dart';
import '../widgets/status_badge.dart';
import '../widgets/theme_toggle_button.dart';
import 'app_section.dart';

/// The desktop layout: a left sidebar (brand, section nav, host list, identity) +
/// a main pane (section header with the theme toggle, and the active section).
/// Drill-in (terminal, per-shed detail) pushes a full route over this shell.
class DesktopScaffold extends ConsumerWidget {
  const DesktopScaffold({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Every section has a real desktop pane now (Hosts absorbed System), so the
    // shared section renders directly — no cross-breakpoint fold.
    final section = ref.watch(appSectionProvider);
    logDriveState(
      'layout=desktop section=${section.name} '
      'theme=${Theme.of(context).brightness.name}',
    );
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Sidebar(),
          Expanded(child: _MainPane(section: section)),
        ],
      ),
    );
  }
}

class _MainPane extends StatelessWidget {
  const _MainPane({required this.section});

  final AppSection section;

  @override
  Widget build(BuildContext context) {
    final shed = context.shed;
    final (title, body) = switch (section) {
      AppSection.hosts => ('Hosts', const HostsView()),
      AppSection.sessions => ('Sessions', const AllSessionsView()),
      _ => ('Sheds', const AllShedsView()),
    };
    return Column(
      children: [
        Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 26),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: shed.line)),
          ),
          child: Row(
            children: [
              Text(
                title,
                style: sansStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: shed.fg,
                ),
              ),
              const Spacer(),
              if (section == AppSection.hosts)
                const _AddHostHeaderButton(
                  key: ValueKey('desktop-add-host-header'),
                ),
              if (section == AppSection.sheds)
                const _CreateButton(
                  key: ValueKey('desktop-new-shed'),
                  target: CreateTarget.shed,
                ),
              if (section == AppSection.sessions)
                const _CreateButton(
                  key: ValueKey('desktop-new-session'),
                  target: CreateTarget.session,
                ),
              const SizedBox(width: 8),
              const ThemeToggleButton(key: ValueKey('desktop-theme-toggle')),
            ],
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}

/// A desktop pane-header action rendered as an accent "+ label" text button —
/// the shared chrome for New shed / New session / Add host.
class _AccentHeaderButton extends StatelessWidget {
  const _AccentHeaderButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final shed = context.shed;
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(Icons.add, size: 17, color: shed.accent),
      label: Text(
        label,
        style: sansStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: shed.accent,
        ),
      ),
    );
  }
}

/// The Sheds/Sessions pane-header create action: picks a target, then pushes the
/// existing create screen. See [startCreate].
class _CreateButton extends ConsumerWidget {
  const _CreateButton({required this.target, super.key});

  final CreateTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _AccentHeaderButton(
    label: createLabel(target),
    onPressed: () => startCreate(context, ref, target),
  );
}

/// The Hosts pane-header add-host action (matches New shed / New session).
class _AddHostHeaderButton extends ConsumerWidget {
  const _AddHostHeaderButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _AccentHeaderButton(
    label: 'Add host',
    onPressed: () => openAddHost(context, ref),
  );
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shed = context.shed;
    final servers = ref.watch(serversProvider);
    return Container(
      width: 244,
      decoration: BoxDecoration(
        color: shed.sidebar,
        border: Border(right: BorderSide(color: shed.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Row(
              children: [
                const OwlLogo(width: 26),
                const SizedBox(width: 10),
                Text(
                  'Shed',
                  style: sansStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: shed.fg,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          const _NavItem(
            section: AppSection.sheds,
            icon: Icons.view_in_ar_outlined,
            label: 'Sheds',
          ),
          const _NavItem(
            section: AppSection.sessions,
            icon: Icons.terminal_outlined,
            label: 'Sessions',
          ),
          const _NavItem(
            section: AppSection.hosts,
            icon: Icons.dns_outlined,
            label: 'Hosts',
          ),
          // The saved-host quick list, pinned to the bottom (reverse), scrolling
          // up on overflow. A reference list (not nav) — the Hosts nav item above
          // opens the pane; these rows just show what's configured.
          Expanded(
            child: SingleChildScrollView(
              reverse: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
                    child: Row(
                      children: [
                        Text(
                          'HOSTS',
                          style: monoStyle(
                            fontSize: 10,
                            color: shed.fg3,
                            letterSpacing: 1,
                          ),
                        ),
                        const Spacer(),
                        const _AddHostButton(),
                      ],
                    ),
                  ),
                  ...switch (servers) {
                    AsyncData(:final value) => [
                      for (final s in value) _HostRow(name: s.name),
                    ],
                    _ => const <Widget>[],
                  },
                ],
              ),
            ),
          ),
          Divider(height: 1, color: shed.line),
          const _IdentityButton(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _NavItem extends ConsumerWidget {
  const _NavItem({
    required this.section,
    required this.icon,
    required this.label,
  });

  final AppSection section;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shed = context.shed;
    final active = ref.watch(appSectionProvider) == section;
    final fg = active ? shed.accent : shed.fg2;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: Material(
        color: active ? shed.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          key: ValueKey('nav-${section.name}'),
          borderRadius: BorderRadius.circular(9),
          onTap: () => ref.read(appSectionProvider.notifier).select(section),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            child: Row(
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 11),
                Text(
                  label,
                  style: sansStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddHostButton extends ConsumerWidget {
  const _AddHostButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shed = context.shed;
    return InkWell(
      key: const ValueKey('desktop-add-host'),
      onTap: () => openAddHost(context, ref),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add, size: 14, color: shed.accent),
          const SizedBox(width: 4),
          Text(
            'Add',
            style: monoStyle(
              fontSize: 11,
              color: shed.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _HostRow extends StatelessWidget {
  const _HostRow({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final shed = context.shed;
    return Padding(
      key: ValueKey('desktop-host-$name'),
      padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 6),
      child: Row(
        children: [
          // Reachability isn't probed at the sidebar yet (P6); show online.
          const StatusDot(tone: ShedStatusTone.ok, size: 8),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sansStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: shed.fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IdentityButton extends StatelessWidget {
  const _IdentityButton();

  @override
  Widget build(BuildContext context) {
    final shed = context.shed;
    return InkWell(
      key: const ValueKey('desktop-identity'),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const IdentityScreen())),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.vpn_key_outlined, size: 16, color: shed.fg2),
            const SizedBox(width: 10),
            Text(
              'SSH identity',
              style: sansStyle(fontSize: 13, color: shed.fg2),
            ),
          ],
        ),
      ),
    );
  }
}
