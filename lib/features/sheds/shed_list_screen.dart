import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../../providers.dart';
import '../../theme/shed_colors.dart';
import '../../widgets/app_bar_count_title.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_retry.dart';
import 'create_shed_screen.dart';
import 'shed_card.dart';

/// Sheds on one server: list, start/stop/restart/delete, and create. Each row is
/// the shared [ShedCard] — the same widget the cross-host Sheds tab renders — so
/// both surfaces expose the identical `all-shed-*` actions (incl.
/// delete-with-confirm) at both widths.
class ShedListScreen extends ConsumerWidget {
  const ShedListScreen({required this.serverName, super.key});

  final String serverName;

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
            onPressed: () => invalidateShedViews(ref, serverName),
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
          invalidateShedViews(ref, serverName);
        },
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Create shed'),
      ),
      body: sheds.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(
          error: e,
          messageKey: const ValueKey('sheds-error'),
          onRetry: () => invalidateShedViews(ref, serverName),
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
            onRefresh: () async => invalidateShedViews(ref, serverName),
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: list.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: context.shed.line),
              itemBuilder: (_, i) {
                final s = list[i];
                return ShedCard(
                  key: ValueKey('all-shed-$serverName-${s.name}'),
                  serverName: serverName,
                  shed: s,
                );
              },
            ),
          );
        },
      ),
    );
  }
}
