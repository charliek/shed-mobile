import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';
import '../../widgets/count_chip.dart';
import '../../widgets/host_groups.dart';
import '../../widgets/owl.dart';
import '../../widgets/theme_toggle_button.dart';
import '../hosts/host_card.dart';
import '../identity/identity_screen.dart';
import '../sheds/shed_list_screen.dart';
import 'add_server_screen.dart';

/// The mobile Hosts tab: the configured hosts, each a merged [HostCard] (status +
/// disk usage). Add a host, tap one to browse its sheds, or remove it. (Absorbed
/// the former System section — every card carries its own df breakdown.) The body
/// is the shared [HostGroups] (same iteration as the desktop Hosts pane), wrapped
/// in this screen's brand app bar + `servers-add` FAB.
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
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('servers-add'),
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AddServerScreen()),
          );
          ref.invalidate(serversProvider);
        },
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Add host'),
      ),
      // Shared cross-host body (same as the desktop Hosts pane), with extra
      // bottom inset so the last card clears the Add-host FAB. Empty state is
      // keyed `hosts-empty` by HostGroups.
      body: HostGroups(
        section: 'hosts',
        header: false,
        bottomInset: 96,
        emptyMessage: 'Tap "Add host" to connect one.',
        onRefresh: invalidateHosts,
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
