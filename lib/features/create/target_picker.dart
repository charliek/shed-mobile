import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../../bridge/bridge_adapters.dart';
import '../../machines/machine_record.dart';
import '../../providers.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';
import '../../widgets/status_badge.dart';
import '../rc/create_rc_screen.dart';
import 'create_rc_target.dart';
import '../servers/add_server_screen.dart';
import '../sheds/create_shed_screen.dart';

/// Create-from-tab entry points: the cross-host Sheds/Sessions views can't assume
/// a target, so these pick one (a host for a new shed, a running shed for a new
/// session) and then push the *existing* create screen unchanged. A single saved
/// host auto-skips the host picker (it's local/instant); the shed picker always
/// opens (its candidates need a per-host fan-out) and loads each host's running
/// sheds progressively + tolerantly. Zero candidates is never a silent no-op.

/// Which cross-host create flow a FAB / header button triggers. Shared by both
/// layouts so the mobile FAB and desktop button dispatch identically.
enum CreateTarget { shed, session }

/// The button/FAB label for [target] — one source so both layouts stay in sync.
String createLabel(CreateTarget target) => switch (target) {
  CreateTarget.shed => 'New shed',
  CreateTarget.session => 'New session',
};

/// Run the create flow for [target] from the current context.
Future<void> startCreate(
  BuildContext context,
  WidgetRef ref,
  CreateTarget target,
) => switch (target) {
  CreateTarget.shed => newShedFromTab(context, ref),
  CreateTarget.session => newSessionFromTab(context, ref),
};

/// Open the add-host flow (push AddServerScreen, then refresh the host list).
/// The single home for "add a host", shared by the mobile Hosts FAB, the desktop
/// sidebar "+ Add" link, and the desktop Hosts-pane header button.
Future<void> openAddHost(BuildContext context, WidgetRef ref) async {
  logDriveResult('add-open', ok: true);
  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const AddServerScreen()));
  if (!context.mounted) return;
  ref.invalidate(serversProvider);
}

/// New shed: pick a host (auto-skip when there's one), then CreateShedScreen.
/// CreateShedScreen self-invalidates shedsProvider on a successful create, so the
/// cross-host Sheds view refreshes without a caller-side invalidate here.
Future<void> newShedFromTab(BuildContext context, WidgetRef ref) async {
  final serverName = await pickHost(context, ref);
  if (serverName == null || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CreateShedScreen(serverName: serverName),
    ),
  );
}

/// New session: pick where it runs — a running shed on any host, or a machine —
/// then CreateRcScreen. A machine is offered on exactly the same footing as a
/// shed: an agent on a machine is a session like any other, and making it a
/// separate flow would be the first place that stopped being true.
///
/// On a created session, refresh what lists it. CreateRcScreen pops the created
/// session but self-invalidates nothing, so this is load-bearing for a shed; a
/// machine's hub reconcile brings its own row in, but invalidating is still what
/// makes it appear at once rather than at the next tick.
Future<void> newSessionFromTab(BuildContext context, WidgetRef ref) async {
  final target = await pickRunTarget(context, ref);
  if (target == null || !context.mounted) return;
  final created = await Navigator.of(context).push<Object?>(
    MaterialPageRoute<Object?>(builder: (_) => CreateRcScreen(target: target)),
  );
  if (created == null) return;
  switch (target) {
    case ShedRcTarget(:final serverName, :final shedName):
      ref.invalidate(overviewProvider(serverName));
      ref.invalidate(
        rcSessionsProvider((serverName: serverName, shedName: shedName)),
      );
    case MachineRcTarget(:final machineName):
      ref.invalidate(machineFeedProvider(machineName));
  }
}

/// Pick a saved host. One host → returned immediately (no sheet); many → a bottom
/// sheet keyed `pick-host-<name>`. Null on cancel / no hosts.
Future<String?> pickHost(BuildContext context, WidgetRef ref) async {
  final hosts = await ref.read(serversProvider.future);
  if (!context.mounted) return null;
  if (hosts.isEmpty) {
    _toast(context, 'Add a host first.');
    logDriveResult('pick-host', ok: false);
    return null;
  }
  if (hosts.length == 1) {
    logDriveResult('pick-host', ok: true);
    return hosts.first.name;
  }
  final chosen = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: context.shed.surface,
    showDragHandle: true,
    builder: (_) => _Sheet(
      title: 'Pick a host',
      children: [
        for (final h in hosts)
          _PickRow(
            key: ValueKey('pick-host-${h.name}'),
            label: h.name,
            sub: h.apiUrl,
            onTap: () => Navigator.of(context).pop(h.name),
          ),
      ],
    ),
  );
  logDriveResult('pick-host', ok: chosen != null);
  return chosen;
}

/// Pick where a new session runs: a running shed on any host, or a machine.
/// Opens immediately and loads each host's sheds progressively (one slow or
/// offline host never stalls it); only running sheds are offered, because a
/// session needs one. Machines are offered unconditionally — a machine has no
/// lifecycle to be in the wrong part of, and whether it is reachable right now
/// is a question the create screen answers honestly rather than one the picker
/// silently pre-empts by hiding the row.
///
/// Rows keyed `pick-shed-<server>-<shed>` and `pick-machine-<name>`. Null on
/// cancel / none.
Future<CreateRcTarget?> pickRunTarget(
  BuildContext context,
  WidgetRef ref,
) async {
  final result = await showModalBottomSheet<CreateRcTarget>(
    context: context,
    backgroundColor: context.shed.surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _RunTargetPickerSheet(),
  );
  logDriveResult('pick-shed', ok: result != null);
  return result;
}

void _toast(BuildContext context, String message) {
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

const _shedPickerTitle = 'Where should it run?';

/// The picker body: running sheds (one section per host, each loading its own
/// sheds independently), then machines. Shows the "nothing to run on" hint only
/// once every host has resolved with no running shed AND there are no machines.
class _RunTargetPickerSheet extends ConsumerWidget {
  const _RunTargetPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    return servers.when(
      loading: () => const _Sheet(
        title: _shedPickerTitle,
        children: [
          Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
      error: (e, _) => _Sheet(
        title: _shedPickerTitle,
        children: [_Note('Could not load hosts: $e')],
      ),
      data: (hosts) {
        final shedRows = <Widget>[];
        var allResolved = true;
        for (final h in hosts) {
          final sheds = ref.watch(shedsProvider(h.name));
          sheds.when(
            data: (list) {
              for (final s in list.where(bridgeShedIsRunning)) {
                shedRows.add(
                  _PickRow(
                    key: ValueKey('pick-shed-${h.name}-${s.name}'),
                    label: s.name,
                    sub: h.name,
                    onTap: () => Navigator.of(
                      context,
                    ).pop(ShedRcTarget(serverName: h.name, shedName: s.name)),
                  ),
                );
              }
            },
            loading: () => allResolved = false,
            error: (_, _) {},
          );
        }
        final machines =
            ref.watch(machinesProvider).value ?? const <MachineRecord>[];
        final machineRows = [
          for (final m in machines)
            _PickRow(
              key: ValueKey('pick-machine-${m.name}'),
              label: m.name,
              sub: m.host,
              onTap: () => Navigator.of(
                context,
              ).pop(MachineRcTarget(machineName: m.name)),
            ),
        ];
        if (allResolved && shedRows.isEmpty && machineRows.isEmpty) {
          return const _Sheet(
            title: _shedPickerTitle,
            children: [
              _Note('Nothing to run on yet — start a shed, or add a machine.'),
            ],
          );
        }
        // Headers earn their place only when there is more than one kind of
        // place to run: a list of sheds under a "Sheds" header, with no
        // machines anywhere, is a label explaining itself.
        final headed = shedRows.isNotEmpty && machineRows.isNotEmpty;
        return _Sheet(
          title: _shedPickerTitle,
          children: [
            if (headed && shedRows.isNotEmpty) const _GroupLabel('Sheds'),
            ...shedRows,
            if (!allResolved)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            if (headed && machineRows.isNotEmpty) const _GroupLabel('Machines'),
            ...machineRows,
          ],
        );
      },
    );
  }
}

/// A section label inside the sheet — same treatment as a list header
/// elsewhere, quieter than the sheet title.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
    child: Text(
      text.toUpperCase(),
      style: monoStyle(
        fontSize: 10.5,
        color: context.shed.fg3,
      ).copyWith(letterSpacing: 1.1),
    ),
  );
}

/// The shared sheet chrome: a title over a scrollable child list (safe-area
/// padded). The drag handle is provided by showModalBottomSheet.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              title,
              style: sansStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: c.fg,
              ),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 8),
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.label,
    required this.sub,
    required this.onTap,
    super.key,
  });

  final String label;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            const StatusDot(tone: ShedStatusTone.ok),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: sansStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.fg,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(sub, style: monoStyle(fontSize: 11, color: c.fg3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Text(
        text,
        key: const ValueKey('pick-empty'),
        style: monoStyle(fontSize: 12.5, color: context.shed.fg2),
      ),
    );
  }
}
