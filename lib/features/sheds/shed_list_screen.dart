import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../marionette/drive_state.dart';
import '../../providers.dart';
import '../../shed/shed_client.dart';
import '../../shed/shed_dtos.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';
import '../../widgets/app_bar_count_title.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_retry.dart';
import '../../widgets/square_icon_button.dart';
import '../../widgets/status_badge.dart';
import '../rc/shed_detail_screen.dart';
import 'create_shed_screen.dart';

/// Sheds on one server: list, start/stop/delete, and create.
class ShedListScreen extends ConsumerWidget {
  const ShedListScreen({required this.serverName, super.key});

  final String serverName;

  /// Map a server-reported status string to a display tone + whether it pulses.
  static (ShedStatusTone, bool) toneFor(String status) => switch (status) {
    'running' => (ShedStatusTone.ok, false),
    'starting' || 'creating' || 'provisioning' => (ShedStatusTone.warn, true),
    _ => (ShedStatusTone.idle, false),
  };

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
        title: AppBarCountTitle(
          title: serverName,
          count: sheds.asData?.value.length,
          noun: 'shed',
        ),
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
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Create shed'),
      ),
      body: sheds.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(
          error: e,
          messageKey: const ValueKey('sheds-error'),
          onRetry: () => ref.invalidate(shedsProvider(serverName)),
        ),
        data: (list) {
          logDriveState('screen=sheds server=$serverName count=${list.length}');
          if (list.isEmpty) {
            return EmptyState(
              key: const ValueKey('sheds-empty'),
              title: 'No sheds yet',
              message: 'Spin up a shed on $serverName to run an agent.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(shedsProvider(serverName)),
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: list.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: context.shed.line),
              itemBuilder: (_, i) {
                final s = list[i];
                return _ShedTile(
                  shed: s,
                  onOpen: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ShedDetailScreen(
                        serverName: serverName,
                        shedName: s.name,
                      ),
                    ),
                  ),
                  onStart: () => _run(
                    context,
                    ref,
                    'shed-start',
                    (c) => c.startShed(s.name),
                  ),
                  onStop: () => _run(
                    context,
                    ref,
                    'shed-stop',
                    (c) => c.stopShed(s.name),
                  ),
                  onDelete: () => _confirmDelete(context, ref, s.name),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ShedTile extends StatelessWidget {
  const _ShedTile({
    required this.shed,
    required this.onOpen,
    required this.onStart,
    required this.onStop,
    required this.onDelete,
  });

  final Shed shed;
  final VoidCallback onOpen;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.shed;
    final (tone, animate) = ShedListScreen.toneFor(shed.status);
    final running = shed.isRunning;
    return InkWell(
      key: ValueKey('shed-${shed.name}'),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 15, 12, 15),
        child: Row(
          children: [
            StatusDot(tone: tone, animate: animate),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shed.name,
                    style: sansStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: colors.fg,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    shed.status,
                    style: monoStyle(
                      fontSize: 11.5,
                      color: colors.toneFg(tone),
                    ),
                  ),
                ],
              ),
            ),
            if (running)
              SquareIconButton(
                key: ValueKey('shed-stop-${shed.name}'),
                icon: Icons.stop,
                tooltip: 'Stop',
                onPressed: onStop,
              )
            else
              SquareIconButton(
                key: ValueKey('shed-start-${shed.name}'),
                icon: Icons.play_arrow,
                tooltip: 'Start',
                iconColor: colors.dotOk,
                onPressed: onStart,
              ),
            const SizedBox(width: 8),
            SquareIconButton(
              key: ValueKey('shed-delete-${shed.name}'),
              icon: Icons.delete_outline,
              tooltip: 'Delete',
              iconColor: colors.fg3,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
