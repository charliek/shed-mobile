import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../marionette/drive_state.dart';
import '../../providers.dart';
import '../../theme/shed_colors.dart';
import '../../widgets/host_groups.dart';

/// Cross-host Sheds — every host's sheds grouped by host. P2a renders a minimal
/// per-host summary so the shell is data-wired and drivable; the rich cards with
/// runtime badges + start/stop/restart land in P3.
class AllShedsView extends StatelessWidget {
  const AllShedsView({super.key});

  @override
  Widget build(BuildContext context) => HostGroups(
    section: 'all-sheds',
    emptyMessage: 'Add a host to see its sheds.',
    hostBuilder: (s) => _HostSheds(serverName: s.name),
  );
}

class _HostSheds extends ConsumerWidget {
  const _HostSheds({required this.serverName});

  final String serverName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shed = context.shed;
    final sheds = ref.watch(shedsProvider(serverName));
    return sheds.when(
      loading: () => const HostNote('Loading…'),
      error: (e, _) {
        logDriveState('all-sheds host=$serverName reachable=false');
        return HostNote('unreachable', color: shed.errFg);
      },
      data: (list) {
        logDriveState(
          'all-sheds host=$serverName reachable=true count=${list.length}',
        );
        if (list.isEmpty) return const HostNote('No sheds');
        return HostNote(
          '${list.length} ${list.length == 1 ? 'shed' : 'sheds'}: '
          '${list.map((s) => s.name).join(', ')}',
        );
      },
    );
  }
}
