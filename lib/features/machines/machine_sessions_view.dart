import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../../machines/machine_feed.dart';
import '../../machines/machine_record.dart';
import '../../providers.dart';
import '../rc/session_watch_screen.dart';
import '../rc/session_watch_source.dart';
import '../../rc/rc_ui.dart';
import '../../shed/shed_status.dart';
import '../../src/rust/api/dto_rc.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';
import '../../widgets/card_shell.dart';
import '../../widgets/kind_chip.dart';
import '../../widgets/host_groups.dart';
import '../../widgets/status_badge.dart';

/// **Machine sessions, beside shed sessions** (plan 012, roadmap R4).
///
/// A machine is a native host reached over SSH, running the RC activity hub
/// directly — no shed server in the path. The rows look like shed rows on
/// purpose: a session is a session, and the only thing a person needs to know is
/// WHERE it is running, which the group header says once.
///
/// Two things the shed sections do not have to handle:
///
/// * **Unreachable is a normal state.** A machine that is asleep or off-network
///   keeps its last-known rows, dimmed, with the reason shown — never an error,
///   and never a silently empty list.
/// * **Rows key on the MACHINE, not on a shed.** A directly-read hub reports an
///   empty `shed` for every session, so keying on it would collide two machines
///   that happen to share a slug.
class MachineSessionsView extends ConsumerWidget {
  const MachineSessionsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final machines = ref.watch(machinesProvider);
    return machines.when(
      loading: () => const SizedBox.shrink(),
      // A machine list that cannot be read must not take down the sessions
      // screen: sheds are still perfectly usable.
      error: (_, _) => const SizedBox.shrink(),
      data: (list) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // No add-affordance here: machines are configured on the Hosts tab,
          // beside shed hosts, so a session view stays a session view. With
          // none configured this renders nothing at all rather than an empty
          // section competing with the shed list.
          for (final m in list) _MachineGroup(machine: m),
        ],
      ),
    );
  }
}

class _MachineGroup extends ConsumerWidget {
  const _MachineGroup({required this.machine});

  final MachineRecord machine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(machineFeedProvider(machine.name));
    final state = feed.value;
    final sessions = state?.sessions ?? const <BridgeRcSession>[];
    final reachable = state?.reachable ?? false;

    logDriveState(
      'machine-sessions machine=${machine.name} reachable=$reachable '
      'count=${sessions.length}',
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MachineHeader(machine: machine, state: state),
          if (sessions.isEmpty)
            _MachineNote(
              key: ValueKey('machine-empty-${machine.name}'),
              text: _emptyText(state),
            )
          else
            for (final s in sessions)
              _MachineSessionCard(
                // Keyed by ORIGIN + slug, never by shed (which is empty here).
                key: ValueKey('${machine.origin}/${s.slug}'),
                machine: machine,
                session: s,
                state: state!,
              ),
        ],
      ),
    );
  }

  /// What an empty list MEANS depends on whether we ever connected — "no
  /// sessions" and "we have never reached this machine" are different facts and
  /// showing the wrong one is actively misleading.
  static String _emptyText(MachineFeedState? state) {
    if (state == null) return 'connecting…';
    if (state.reachable) return 'No sessions';
    if (!state.connectedOnce) {
      return state.detail ?? 'connecting…';
    }
    return state.detail ?? 'unreachable';
  }
}

/// A machine's group heading in the sessions list.
///
/// The SHARED [SectionHeader], not a hand-rolled Row: a machine group and a
/// shed group sit in the same list, so any difference in indent or weight reads
/// as a mistake. It was one — this header carried no padding of its own and
/// relied on a wrapper that went away when the tab became a single scroll view,
/// leaving `MACHINE:MINI3` jammed against the edge while the shed headings kept
/// their indent.
class _MachineHeader extends StatelessWidget {
  const _MachineHeader({required this.machine, required this.state});

  final MachineRecord machine;
  final MachineFeedState? state;

  @override
  Widget build(BuildContext context) {
    final reachable = state?.reachable ?? false;
    return SectionHeader(
      label: machine.origin.toUpperCase(),
      action: reachable
          ? null
          : Padding(
              padding: const EdgeInsets.only(right: 12),
              child: StatusBadge(
                key: ValueKey('machine-unreachable-${machine.name}'),
                label: (state?.connectedOnce ?? false)
                    ? 'unreachable'
                    : 'connecting',
                tone: ShedStatusTone.warn,
              ),
            ),
    );
  }
}

class _MachineNote extends StatelessWidget {
  const _MachineNote({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    // 20 left to sit under the section heading, matching HostNote.
    padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: context.shed.fg3),
    ),
  );
}

/// One machine session.
///
/// Deliberately NOT the shed [SessionCard]: that card resolves a shed's SSH
/// endpoint through a server for its terminal and delete actions, none of which
/// a machine session has. Offering those affordances and having them fail would
/// be worse than not offering them.
class _MachineSessionCard extends StatelessWidget {
  const _MachineSessionCard({
    required this.machine,
    required this.session,
    required this.state,
    super.key,
  });

  final MachineRecord machine;
  final BridgeRcSession session;
  final MachineFeedState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.shed;
    // The live patch applied over the snapshot.
    final activity = state.activityOf(session);
    final lifecycle = state.stateOf(session);
    // The SAME helper the shed card uses, so a machine row and a shed row can
    // never disagree about what "working" looks like. It already applies the
    // lifecycle-trumps-activity rule.
    final display = rcActivityBadge(lifecycle, activity);

    return Opacity(
      // A stale row is the last KNOWN state of a machine we cannot currently
      // reach — dimmed rather than hidden, because it is still the best
      // available answer to "what is running on mini3?".
      opacity: state.reachable ? 1 : 0.55,
      child: CardShell(
        // The SAME rule the shed card uses, so a column of both kinds reads as
        // one column. A row we cannot currently reach gets no edge — colouring
        // it would assert something present about a machine we cannot see.
        rail: sessionRailColor(
          colors,
          lifecycle,
          activity,
          stale: !state.reachable,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name first, both badges beside it — identical to the shed card,
            // because where a session runs should not change how it is read.
            Row(
              children: [
                Expanded(
                  child: Text(
                    session.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sansStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: colors.fg,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                StatusBadge(
                  tone: shedStatusTone(lifecycle.wire).tone,
                  label: lifecycle.wire.replaceAll('-', ' '),
                ),
                if (display != null) ...[
                  const SizedBox(width: 6),
                  StatusBadge(
                    tone: display.tone,
                    label: display.label,
                    pulse: display.pulse,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                KindChip(session.kind.wire),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    // Workdir first — see `sessionMetaLine`. The machine is not
                    // repeated: the list is grouped by it.
                    [
                      if (session.workdir != null) session.workdir!,
                      session.tmuxSession,
                      if (!state.reachable) 'last known',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle(fontSize: 11.5, color: colors.fg3),
                  ),
                ),
              ],
            ),
            // Watch, and end. Steering and interrupting live INSIDE the watch
            // view, beside the output: nobody directs an agent they cannot see,
            // and a control on a list row is a decision made blind. What a
            // session accepts is still gated on `kind_features` — that gate
            // just belongs where the acting happens.
            if (state.reachable)
              _MachineActions(
                machineName: state.machine.name,
                session: session,
                state: state,
              ),
          ],
        ),
      ),
    );
  }
}

/// Watch and End — the two things worth doing from a LIST.
///
/// Everything that steers a session (a turn, a keystroke, an interrupt) is on
/// the watch screen instead, because acting on an agent without reading its
/// output first is guesswork. End stays here because it is not direction: it is
/// removal, and it needs no context to mean what it says.
class _MachineActions extends ConsumerStatefulWidget {
  const _MachineActions({
    required this.machineName,
    required this.session,
    required this.state,
  });

  final String machineName;
  final BridgeRcSession session;
  final MachineFeedState state;

  @override
  ConsumerState<_MachineActions> createState() => _MachineActionsState();
}

class _MachineActionsState extends ConsumerState<_MachineActions> {
  bool _busy = false;
  String? _error;

  void _watch() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SessionWatchScreen(
        source: MachineWatchSource(
          machineName: widget.machineName,
          session: widget.session,
        ),
      ),
    ),
  );

  Future<void> _end() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(machineFeedControllerProvider(widget.machineName))
          .kill(widget.session.slug);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final slug = widget.session.slug;
    // **Gated on the kind's own capability, exactly as the shed card is.**
    // A kind with no feed opens a watch screen that can only fail against the
    // messages endpoint — and a machine session offering Watch where the same
    // kind in a shed does not is precisely the inconsistency this block exists
    // to remove. Unknown capabilities mean no, which is the safe direction.
    final canWatch =
        widget.state.featuresFor(widget.session)?.watch ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Row(
          children: [
            if (canWatch)
              TextButton.icon(
                key: ValueKey('machine-watch-$slug'),
                onPressed: _busy ? null : _watch,
                icon: const Icon(Icons.visibility_outlined, size: 16),
                label: const Text('Watch'),
              ),
            const Spacer(),
            TextButton.icon(
              key: ValueKey('machine-kill-$slug'),
              onPressed: _busy ? null : _end,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('End'),
              style: TextButton.styleFrom(
                foregroundColor: context.shed.errFg,
              ),
            ),
          ],
        ),
        if (_error != null)
          Text(
            _error!,
            key: ValueKey('machine-control-error-$slug'),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.shed.errFg),
          ),
      ],
    );
  }
}
