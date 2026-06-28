import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../marionette/drive_state.dart';
import '../../providers.dart';
import '../../theme/shed_colors.dart';
import '../../widgets/host_groups.dart';

/// Cross-host Sessions — every host's rc sessions grouped by host (one HTTP call
/// per host). P2a renders a minimal per-host summary; the rich session cards with
/// kind chips + open/delete land in P4.
class AllSessionsView extends StatelessWidget {
  const AllSessionsView({super.key});

  @override
  Widget build(BuildContext context) => HostGroups(
    section: 'all-sessions',
    emptyMessage: 'Add a host to see its sessions.',
    hostBuilder: (s) => _HostSessions(serverName: s.name),
  );
}

class _HostSessions extends ConsumerWidget {
  const _HostSessions({required this.serverName});

  final String serverName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shed = context.shed;
    final sessions = ref.watch(hostSessionsProvider(serverName));
    return sessions.when(
      loading: () => const HostNote('Loading…'),
      error: (e, _) {
        logDriveState('all-sessions host=$serverName reachable=false');
        return HostNote('unreachable', color: shed.errFg);
      },
      data: (list) {
        logDriveState(
          'all-sessions host=$serverName reachable=true count=${list.length}',
        );
        if (list.isEmpty) return const HostNote('No sessions');
        return HostNote(
          '${list.length} ${list.length == 1 ? 'session' : 'sessions'}: '
          '${list.map((s) => s.rc?.displayName ?? s.name).join(', ')}',
        );
      },
    );
  }
}
