import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../marionette/drive_state.dart';
import '../../providers.dart';
import '../../servers/server_record.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';
import '../../theme/theme_mode_provider.dart';
import '../../widgets/count_chip.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/owl.dart';
import '../identity/identity_screen.dart';
import '../sheds/shed_list_screen.dart';
import 'add_server_screen.dart';

/// Home screen: the configured shed servers. Add one, tap to browse its sheds.
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
                  '${list.length} ${list.length == 1 ? 'server' : 'servers'}',
                ),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            key: const ValueKey('servers-theme-toggle'),
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
            tooltip: 'Toggle theme',
            onPressed: () => ref
                .read(themeModeProvider.notifier)
                .toggle(Theme.of(context).brightness),
          ),
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
        label: const Text('Add server'),
      ),
      body: servers.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          logDriveState('screen=servers count=${list.length}');
          if (list.isEmpty) {
            return const EmptyState(
              key: ValueKey('servers-empty'),
              title: 'No servers yet',
              message: 'Tap "Add server" to connect a host.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(serversProvider),
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: list.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: shed.line),
              itemBuilder: (_, i) => _ServerTile(
                record: list[i],
                onOpen: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ShedListScreen(serverName: list[i].name),
                  ),
                ),
                onRemove: () async {
                  await ref.read(serverStoreProvider).remove(list[i].name);
                  logDriveResult('server-remove', ok: true);
                  if (context.mounted) ref.invalidate(serversProvider);
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.record,
    required this.onOpen,
    required this.onRemove,
  });

  final ServerRecord record;
  final VoidCallback onOpen;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final shed = context.shed;
    return InkWell(
      key: ValueKey('server-${record.name}'),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 15, 12, 15),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: shed.surface2,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(Icons.dns_outlined, size: 19, color: shed.fg2),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.name,
                    style: sansStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: shed.fg,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    record.apiUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle(fontSize: 11.5, color: shed.fg3),
                  ),
                ],
              ),
            ),
            IconButton(
              key: ValueKey('server-remove-${record.name}'),
              icon: Icon(Icons.delete_outline, color: shed.fg3),
              tooltip: 'Remove',
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}
