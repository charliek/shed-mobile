import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../../providers.dart';
import '../../theme/shed_colors.dart';
import '../../widgets/host_groups.dart';
import 'session_card.dart';

/// Cross-host Sessions — every host's rc sessions grouped by host, read from one
/// `GET /api/overview` call per host (the server rc-enriches the sessions). Cards:
/// status badge, kind chip, meta, "›_ open" (→ terminal), delete.
class AllSessionsView extends StatelessWidget {
  const AllSessionsView({super.key});

  @override
  Widget build(BuildContext context) => HostGroups(
    section: 'all-sessions',
    emptyMessage: 'Add a host to see its sessions.',
    // Extra bottom inset so the last card clears the "New session" FAB (mobile).
    bottomInset: 96,
    onRefresh: (ref) {
      ref.invalidate(serversProvider);
      ref.invalidate(overviewProvider);
    },
    hostBuilder: (s) => _HostSessions(serverName: s.name),
  );
}

class _HostSessions extends ConsumerWidget {
  const _HostSessions({required this.serverName});

  final String serverName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(overviewProvider(serverName));
    return overview.when(
      loading: () => const HostNote('Loading…'),
      error: (e, _) {
        logDriveState('all-sessions host=$serverName reachable=false');
        return HostBanner(
          key: ValueKey('all-sessions-unreachable-$serverName'),
          text: 'Unreachable',
          tone: ShedStatusTone.warn,
        );
      },
      data: (r) => switch (r) {
        // A server too old for /api/overview is a hard-require: a TERMINAL
        // value rendered as a clear upgrade banner (not a retryable error, not
        // silent emptiness, not a generic "unreachable" that reads as a blip).
        OverviewUnsupported() => () {
          logDriveState(
            'all-sessions host=$serverName reachable=needs-upgrade',
          );
          return HostBanner(
            key: ValueKey('all-sessions-needs-upgrade-$serverName'),
            text: 'Server needs upgrade for the sessions view',
            tone: ShedStatusTone.err,
          );
        }(),
        OverviewData(:final overview) => _sessions(shedSessionPairs(overview)),
      },
    );
  }

  Widget _sessions(List<ShedSession> list) {
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
  }
}
