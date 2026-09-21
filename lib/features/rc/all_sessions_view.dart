import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../../bridge/bridge_adapters.dart';
import '../../providers.dart';
import '../../src/rust/api/dto.dart';
import '../../theme/shed_colors.dart';
import '../../widgets/host_groups.dart';
import '../machines/machine_sessions_view.dart';
import 'shed_session_group.dart';

/// Cross-host Sessions — every host's agent sessions grouped by host, then by
/// shed.
///
/// **The rows are roost tabs** (plan 022 S6, shed#328). The RC hub that used to
/// enrich `GET /api/overview`'s session rows is gone, so the overview is read
/// for ONE thing here: which sheds exist and which are running. Each running
/// shed's rows then come from its own `roost-session`, over the phone's SSH
/// tunnel — the identical path a machine's rows take, which is why a machine
/// group and a shed group differ only by the header above them.
class AllSessionsView extends StatelessWidget {
  const AllSessionsView({super.key});

  @override
  // ONE scroll view: the machine groups lead, the per-host groups follow, and
  // both scroll and pull-to-refresh together. A machine session and a shed
  // session then differ only by the header above them, which is the point —
  // where a session runs is a label, not a different kind of screen.
  Widget build(BuildContext context) => HostGroups(
    section: 'all-sessions',
    emptyMessage: 'Add a host to see its sessions.',
    // Extra bottom inset so the last card clears the "New session" FAB (mobile).
    bottomInset: 96,
    onRefresh: (ref) {
      ref.invalidate(serversProvider);
      ref.invalidate(overviewProvider);
    },
    // Machines first: they are reached DIRECTLY over SSH (no shed server in
    // the path), so they stay visible even when every configured server is
    // unreachable — which is exactly when you most want to know what is
    // still running on mini3.
    leading: const MachineSessionsView(),
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
        OverviewData(:final overview) => _sheds(overview),
      },
    );
  }

  /// One group per RUNNING shed. A stopped shed is skipped rather than listed
  /// as unreachable: it has no `roost-session` because it has no kernel, the
  /// fix is on its own card in the Sheds tab, and a permanent "unreachable"
  /// badge for a box nobody asked to be running is noise.
  Widget _sheds(BridgeOverview overview) {
    final running = overview.sheds
        .where((s) => bridgeShedIsRunning(s.shed))
        .toList();
    logDriveState(
      'all-sessions host=$serverName reachable=true sheds=${running.length}',
    );
    if (running.isEmpty) return const HostNote('No running sheds');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in running)
          ShedSessionGroup(
            key: ValueKey('all-sessions-shed-$serverName-${s.shed.name}'),
            serverName: serverName,
            shedName: s.shed.name,
            // A 0.9.0 server contributes NO sessions here — its rows carry no
            // `rc` block, so the decoder drops them (`dto.rs`'s
            // `overview_0_9_0_rows_are_not_sessions`). A non-empty list is
            // therefore a reliable "this server predates 0.9.0" signal, and
            // the only one the phone gets for free.
            serverPredatesRoost: s.sessions.isNotEmpty,
          ),
      ],
    );
  }
}
