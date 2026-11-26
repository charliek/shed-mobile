import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../../providers.dart';
import '../../shed/cloud.dart';
import '../../src/rust/api/dto.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';
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
      body: Column(
        children: [
          CloudUsageLine(serverName: serverName),
          Expanded(child: _body(context, ref, sheds)),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<BridgeShed>> sheds,
  ) => sheds.when(
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
  );
}

/// The server's cloud usage under its header (plan 041):
/// `2 of 4 machines (1 running, 1 stopped) · organization 7 of 10`. Absent for a
/// server with no cloud sheds, and while the usage is loading or unreadable.
class CloudUsageLine extends ConsumerWidget {
  const CloudUsageLine({required this.serverName, super.key});

  final String serverName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(cloudUsageProvider(serverName)).asData?.value;
    if (usage == null) return const SizedBox.shrink();
    final c = context.shed;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_outlined, size: 15, color: c.fg3),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              cloudUsageWords(usage),
              key: ValueKey('sheds-cloud-usage-$serverName'),
              style: monoStyle(fontSize: 12, color: c.fg2),
            ),
          ),
        ],
      ),
    );
  }
}
