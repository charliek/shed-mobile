import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../../machines/machine_record.dart';
import '../../providers.dart';
import '../../theme/shed_colors.dart';
import '../../widgets/card_shell.dart';
import '../../widgets/host_groups.dart';
import '../../widgets/status_badge.dart';
import 'add_machine_screen.dart';

/// **Machines on the Hosts tab**, below the shed hosts.
///
/// A machine and a shed host are the same KIND of thing to a person — somewhere
/// your sessions run — so they are configured in the same place and rendered
/// with the same card vocabulary. What differs is only how they are reached: a
/// host is an HTTP API with a TLS pin and a control token; a machine is an
/// ordinary SSH host with an activity hub on loopback. That difference belongs
/// in the plumbing, not in the navigation.
class MachinesSection extends ConsumerWidget {
  const MachinesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final machines = ref.watch(machinesProvider);
    final list = machines.value ?? const <MachineRecord>[];
    logDriveState('machines-section count=${list.length}');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          label: 'MACHINES',
          count: list.isEmpty ? null : list.length,
          action: TextButton.icon(
            key: const ValueKey('machines-add'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AddMachineScreen()),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add machine'),
          ),
        ),
        if (list.isEmpty)
          const HostNote(
            key: ValueKey('machines-empty'),
            'A machine is a computer you reach over SSH that runs the shed '
            'activity hub.',
          )
        else
          for (final m in _healthyFirst(ref, list))
            _MachineCard(machine: m),
      ],
    );
  }
}

/// Reachable machines first, then still-connecting, then offline — alphabetical
/// inside each band.
///
/// A status list whose order changes under you is one you stop trusting at a
/// glance, so the bands are stable and only a real health change moves a row.
/// Watching each feed here is not incidental: it is what keeps the tunnels alive
/// while this tab is up, which is what makes the badges mean anything.
List<MachineRecord> _healthyFirst(WidgetRef ref, List<MachineRecord> list) {
  int rank(MachineRecord m) {
    final st = ref.watch(machineFeedProvider(m.name)).value;
    if (st == null) return 1;
    if (st.reachable) return 0;
    return st.connectedOnce ? 2 : 1;
  }

  final ranked = [for (final m in list) (rank(m), m)];
  ranked.sort((a, b) => a.$1 - b.$1 != 0 ? a.$1 - b.$1 : a.$2.name.compareTo(b.$2.name));
  return [for (final r in ranked) r.$2];
}

/// One configured machine: its reachability and how many sessions it is
/// carrying — the same at-a-glance shape a host card gives.
class _MachineCard extends ConsumerWidget {
  const _MachineCard({required this.machine});

  final MachineRecord machine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.shed;
    // Watching the feed here keeps the tunnel alive while the Hosts tab is up,
    // which is what makes the status meaningful rather than a stale guess.
    final feed = ref.watch(machineFeedProvider(machine.name));
    final state = feed.value;
    final reachable = state?.reachable ?? false;
    final count = state?.sessions.length ?? 0;

    return CardShell(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      machine.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(width: 8),
                    StatusBadge(
                      key: ValueKey('machine-card-status-${machine.name}'),
                      tone: reachable ? ShedStatusTone.ok : ShedStatusTone.warn,
                      label: reachable
                          ? '$count ${count == 1 ? 'session' : 'sessions'}'
                          : ((state?.connectedOnce ?? false)
                                ? 'unreachable'
                                : 'connecting'),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (machine.user != null)
                      '${machine.user}@${machine.host}'
                    else
                      machine.host,
                    if (machine.sshPort != 22) 'port ${machine.sshPort}',
                    // The reason, when there is one — "no route to host" and
                    // "nothing is listening on 1029" need different fixes.
                    if (!reachable && state?.detail != null) state!.detail!,
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: c.fg3),
                ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('machine-remove-${machine.name}'),
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove machine',
            onPressed: () async {
              await ref.read(machineStoreProvider).remove(machine.name);
              ref.invalidate(machinesProvider);
              logDriveResult('machine-remove', ok: true);
            },
          ),
        ],
      ),
    );
  }
}
