import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../marionette/drive_state.dart';
import '../../providers.dart';
import '../../theme/shed_colors.dart';
import '../../widgets/host_groups.dart';
import 'session_card.dart';

/// Cross-host Sessions — every host's rc sessions grouped by host, gathered by
/// fanning `shed-ext-rc list` over SSH across each host's running sheds. Cards:
/// status badge, kind chip, meta, "›_ open" (→ terminal), delete.
class AllSessionsView extends StatelessWidget {
  const AllSessionsView({super.key});

  @override
  Widget build(BuildContext context) => HostGroups(
    section: 'all-sessions',
    emptyMessage: 'Add a host to see its sessions.',
    onRefresh: (ref) {
      ref.invalidate(serversProvider);
      ref.invalidate(shedsProvider);
      ref.invalidate(hostSessionsProvider);
    },
    hostBuilder: (s) => _HostSessions(serverName: s.name),
  );
}

class _HostSessions extends ConsumerWidget {
  const _HostSessions({required this.serverName});

  final String serverName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(hostSessionsProvider(serverName));
    return sessions.when(
      loading: () => const HostNote('Loading…'),
      error: (e, _) {
        logDriveState('all-sessions host=$serverName reachable=false');
        return HostBanner(
          key: ValueKey('all-sessions-unreachable-$serverName'),
          text: 'Unreachable',
          tone: ShedStatusTone.warn,
        );
      },
      data: (list) {
        logDriveState(
          'all-sessions host=$serverName reachable=true count=${list.length}',
        );
        if (list.isEmpty) return const HostNote('No sessions');
        return Column(
          children: [
            for (final e in list)
              SessionCard(
                key: ValueKey(
                  'all-session-$serverName-${e.shedName}-${e.session.slug}',
                ),
                serverName: serverName,
                shedName: e.shedName,
                session: e.session,
              ),
          ],
        );
      },
    );
  }
}
