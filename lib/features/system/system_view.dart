import 'package:flutter/material.dart';

import '../../providers.dart';
import '../../widgets/host_groups.dart';
import 'system_card.dart';

/// System — per-host disk usage (`GET /api/system/df`), one card per host with the
/// Images / Sheds / Snapshots / Orphans breakdown. No per-host header (the card
/// carries the host name). Pull-to-refresh re-fetches the df for every host.
class SystemView extends StatelessWidget {
  const SystemView({super.key});

  @override
  Widget build(BuildContext context) => HostGroups(
    section: 'system',
    header: false,
    emptyMessage: 'Add a host to see its disk usage.',
    onRefresh: (ref) {
      ref.invalidate(serversProvider);
      ref.invalidate(hostSystemDfProvider);
    },
    hostBuilder: (s) => SystemCard(serverName: s.name),
  );
}
