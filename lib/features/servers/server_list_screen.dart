import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../marionette/drive_state.dart';
import '../../providers.dart';
import '../identity/identity_screen.dart';
import '../sheds/shed_list_screen.dart';
import 'add_server_screen.dart';

/// Home screen: the configured shed servers. Add one, tap to browse its sheds.
class ServerListScreen extends ConsumerWidget {
  const ServerListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    return Scaffold(
      key: const ValueKey('servers-screen'),
      appBar: AppBar(
        title: const Text('shed-mobile'),
        actions: [
          IconButton(
            key: const ValueKey('servers-identity'),
            icon: const Icon(Icons.vpn_key),
            tooltip: 'SSH identity',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const IdentityScreen()),
            ),
          ),
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
        icon: const Icon(Icons.add),
        label: const Text('Add server'),
      ),
      body: servers.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          logDriveState('screen=servers count=${list.length}');
          if (list.isEmpty) {
            return const Center(
              key: ValueKey('servers-empty'),
              child: Text('No servers yet. Tap "Add server" to begin.'),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(serversProvider),
            child: ListView(
              children: [
                for (final s in list)
                  ListTile(
                    key: ValueKey('server-${s.name}'),
                    leading: const Icon(Icons.dns),
                    title: Text(s.name),
                    subtitle: Text(s.apiUrl),
                    trailing: IconButton(
                      key: ValueKey('server-remove-${s.name}'),
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Remove',
                      onPressed: () async {
                        await ref.read(serverStoreProvider).remove(s.name);
                        logDriveResult('server-remove', ok: true);
                        ref.invalidate(serversProvider);
                      },
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ShedListScreen(serverName: s.name),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
