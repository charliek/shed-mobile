import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../marionette/drive_state.dart';
import '../../providers.dart';
import '../../theme/shed_colors.dart';
import '../../widgets/host_groups.dart';
import 'shed_card.dart';

/// Cross-host Sheds — every host's sheds grouped by host, as rich cards (status
/// dot, runtime badge, image chip, meta). Desktop cards carry inline
/// open/restart/stop-start; mobile cards drill into the shed's sessions.
class AllShedsView extends StatelessWidget {
  const AllShedsView({super.key});

  @override
  Widget build(BuildContext context) => HostGroups(
    section: 'all-sheds',
    emptyMessage: 'Add a host to see its sheds.',
    // Extra bottom inset so the last card clears the "New shed" FAB (mobile).
    bottomInset: 96,
    onRefresh: (ref) {
      ref.invalidate(serversProvider);
      ref.invalidate(shedsProvider);
    },
    hostBuilder: (s) => _HostSheds(serverName: s.name),
  );
}

class _HostSheds extends ConsumerWidget {
  const _HostSheds({required this.serverName});

  final String serverName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sheds = ref.watch(shedsProvider(serverName));
    return sheds.when(
      loading: () => const HostNote('Loading…'),
      error: (e, _) {
        logDriveState('all-sheds host=$serverName reachable=false');
        return HostBanner(
          key: ValueKey('all-sheds-unreachable-$serverName'),
          text: 'Unreachable',
          tone: ShedStatusTone.warn,
        );
      },
      data: (list) {
        logDriveState(
          'all-sheds host=$serverName reachable=true count=${list.length}',
        );
        if (list.isEmpty) return const HostNote('No sheds');
        return Column(
          children: [
            for (final s in list)
              ShedCard(
                key: ValueKey('all-shed-$serverName-${s.name}'),
                serverName: serverName,
                shed: s,
              ),
          ],
        );
      },
    );
  }
}
