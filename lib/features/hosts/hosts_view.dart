import 'package:flutter/material.dart';

import '../../providers.dart';
import '../../widgets/host_groups.dart';
import 'host_card.dart';

/// The desktop Hosts pane body: one merged [HostCard] per saved host (status +
/// disk usage), via the shared [HostGroups] iteration. No per-host header (the
/// card carries the host name). Pull-to-refresh re-lists the hosts and re-fetches
/// each host's sheds + df. Desktop cards are non-tappable (drill-in is via the
/// Sheds pane) and carry an inline delete.
class HostsView extends StatelessWidget {
  const HostsView({super.key});

  @override
  Widget build(BuildContext context) => HostGroups(
    section: 'hosts',
    header: false,
    emptyMessage: 'Add a host to get started.',
    onRefresh: invalidateHosts,
    hostBuilder: (s) => HostCard(record: s, mobile: false),
  );
}
