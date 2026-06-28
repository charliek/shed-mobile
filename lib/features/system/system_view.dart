import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../marionette/drive_state.dart';
import '../../providers.dart';
import '../../shed/shed_dtos.dart';
import '../../theme/shed_colors.dart';
import '../../widgets/host_groups.dart';

/// System — per-host disk usage (`GET /api/system/df`). P2a renders a minimal
/// per-host total; the full Images/Sheds/Snapshots/Orphans breakdown lands in P5.
/// Best-effort: a host whose agent lacks the endpoint shows "unavailable".
class SystemView extends StatelessWidget {
  const SystemView({super.key});

  @override
  Widget build(BuildContext context) => HostGroups(
    section: 'system',
    emptyMessage: 'Add a host to see its disk usage.',
    hostBuilder: (s) => _HostDf(serverName: s.name),
  );
}

class _HostDf extends ConsumerWidget {
  const _HostDf({required this.serverName});

  final String serverName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shed = context.shed;
    final df = ref.watch(hostSystemDfProvider(serverName));
    return df.when(
      loading: () => const HostNote('Loading…'),
      error: (e, _) {
        logDriveState('system host=$serverName ok=false');
        return HostNote('unavailable', color: shed.errFg);
      },
      data: (usage) {
        logDriveState('system host=$serverName ok=true');
        return HostNote('total ${formatBytes(usage.totals.all.physicalBytes)}');
      },
    );
  }
}
