import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';
import '../../widgets/count_chip.dart';
import '../../widgets/host_groups.dart';
import '../../widgets/owl.dart';
import '../../widgets/theme_toggle_button.dart';
import '../create/target_picker.dart';
import '../hosts/host_card.dart';
import '../machines/machines_section.dart';
import '../identity/identity_screen.dart';
import '../sheds/shed_list_screen.dart';

/// The mobile Hosts tab: the configured hosts, each a merged [HostCard] (status +
/// disk usage). Add a host, tap one to browse its sheds, or remove it. (Absorbed
/// the former System section — every card carries its own df breakdown.) The body
/// is the shared [HostGroups] (same iteration as the desktop Hosts pane), wrapped
/// in this screen's brand app bar. Both sections carry their own add action in
/// their header — there is no floating button, so the two kinds of place a
/// session can run are added the same way.
class ServerListScreen extends ConsumerWidget {
  const ServerListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    final shed = context.shed;
    return Scaffold(
      key: const ValueKey('servers-screen'),
      appBar: AppBar(
        titleSpacing: 16,
        // scaleDown keeps the owl+title+chip from overflowing the title slot
        // under large text scaling or a very narrow window.
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const OwlLogo(width: 24),
              const SizedBox(width: 10),
              Text(
                'Shed',
                style: sansStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: shed.fg,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(width: 10),
              servers.maybeWhen(
                data: (list) => CountChip(
                  '${list.length} ${list.length == 1 ? 'host' : 'hosts'}',
                ),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        actions: [
          const ThemeToggleButton(key: ValueKey('servers-theme-toggle')),
          IconButton(
            key: const ValueKey('servers-identity'),
            icon: const Icon(Icons.vpn_key_outlined),
            tooltip: 'SSH identity',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const IdentityScreen()),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      // Shared cross-host body (same as the desktop Hosts pane), with extra
      // bottom inset so the last card clears the Add-host FAB. Empty state is
      // keyed `hosts-empty` by HostGroups.
      // Hosts first, machines second. Both are "somewhere your sessions run",
      // so they are configured in one place with one card vocabulary; only the
      // way they are REACHED differs, and that belongs in the plumbing.
      // ONE scroll view, two labelled sections: shed servers, then machines.
      // They share the pull-to-refresh and scroll together, so machines are part
      // of the page rather than pinned to the bottom of the screen.
      body: HostGroups(
        section: 'hosts',
        header: false,
        bottomInset: 24,
        emptyMessage: 'Tap "Add host" to connect one.',
        onRefresh: invalidateHosts,
        // "Add server", not "Add shed": what this adds is a shed SERVER. Creating
        // a shed is a different thing entirely and lives on the Sheds tab, so
        // borrowing its name here would send people to the wrong place.
        leading: SectionHeader(
          label: 'SHED SERVERS',
          action: TextButton.icon(
            key: const ValueKey('servers-add'),
            onPressed: () => openAddHost(context, ref),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add server'),
          ),
        ),
        trailing: const MachinesSection(),
        hostBuilder: (rec) => HostCard(
          record: rec,
          onOpen: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ShedListScreen(serverName: rec.name),
            ),
          ),
        ),
      ),
    );
  }
}
