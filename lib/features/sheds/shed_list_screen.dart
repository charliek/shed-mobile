import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../marionette/drive_state.dart';
import '../../providers.dart';
import '../../shed/shed_client.dart';
import 'create_shed_screen.dart';

/// Sheds on one server: list, start/stop/delete, and create.
class ShedListScreen extends ConsumerWidget {
  const ShedListScreen({required this.serverName, super.key});

  final String serverName;

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    String action,
    Future<void> Function(ShedClient c) op,
  ) async {
    try {
      final client = await ref.read(shedClientProvider(serverName).future);
      await op(client);
      logDriveResult(action, ok: true);
    } catch (e) {
      logDriveResult(action, ok: false, error: e);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$action failed: $e')));
      }
    } finally {
      ref.invalidate(shedsProvider(serverName));
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String name,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $name?'),
        content: const Text('This permanently deletes the shed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('shed-delete-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await _run(context, ref, 'shed-delete', (c) => c.deleteShed(name));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sheds = ref.watch(shedsProvider(serverName));
    return Scaffold(
      key: const ValueKey('sheds-screen'),
      appBar: AppBar(
        title: Text(serverName),
        actions: [
          IconButton(
            key: const ValueKey('sheds-refresh'),
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(shedsProvider(serverName)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('sheds-create'),
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CreateShedScreen(serverName: serverName),
            ),
          );
          ref.invalidate(shedsProvider(serverName));
        },
        icon: const Icon(Icons.add),
        label: const Text('Create shed'),
      ),
      body: sheds.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$e', key: const ValueKey('sheds-error')),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.invalidate(shedsProvider(serverName)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (list) {
          logDriveState('screen=sheds server=$serverName count=${list.length}');
          if (list.isEmpty) {
            return const Center(
              key: ValueKey('sheds-empty'),
              child: Text('No sheds. Tap "Create shed".'),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(shedsProvider(serverName)),
            child: ListView(
              children: [
                for (final s in list)
                  ListTile(
                    key: ValueKey('shed-${s.name}'),
                    leading: Icon(
                      s.isRunning ? Icons.play_circle : Icons.stop_circle,
                      color: s.isRunning ? Colors.green : Colors.grey,
                    ),
                    title: Text(s.name),
                    subtitle: Text(s.status),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!s.isRunning)
                          IconButton(
                            key: ValueKey('shed-start-${s.name}'),
                            icon: const Icon(Icons.play_arrow),
                            tooltip: 'Start',
                            onPressed: () => _run(
                              context,
                              ref,
                              'shed-start',
                              (c) => c.startShed(s.name),
                            ),
                          ),
                        if (s.isRunning)
                          IconButton(
                            key: ValueKey('shed-stop-${s.name}'),
                            icon: const Icon(Icons.stop),
                            tooltip: 'Stop',
                            onPressed: () => _run(
                              context,
                              ref,
                              'shed-stop',
                              (c) => c.stopShed(s.name),
                            ),
                          ),
                        IconButton(
                          key: ValueKey('shed-delete-${s.name}'),
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Delete',
                          onPressed: () => _confirmDelete(context, ref, s.name),
                        ),
                      ],
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
