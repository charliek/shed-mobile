import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../../machines/machine_feed.dart';
import '../../machines/machine_record.dart';
import '../../providers.dart';
import '../../rc/rc_ui.dart';
import '../../shed/shed_status.dart';
import '../../src/rust/api/dto_rc.dart';
import '../../theme/shed_colors.dart';
import '../../widgets/card_shell.dart';
import '../../widgets/kind_chip.dart';
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
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MachineHeader(machine: machine, state: state),
          const SizedBox(height: 8),
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

class _MachineHeader extends StatelessWidget {
  const _MachineHeader({required this.machine, required this.state});

  final MachineRecord machine;
  final MachineFeedState? state;

  @override
  Widget build(BuildContext context) {
    final reachable = state?.reachable ?? false;
    return Row(
      children: [
        Expanded(
          child: Text(
            machine.origin.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: context.shed.fg3,
            ),
          ),
        ),
        if (!reachable)
          StatusBadge(
            key: ValueKey('machine-unreachable-${machine.name}'),
            label: (state?.connectedOnce ?? false)
                ? 'unreachable'
                : 'connecting',
            tone: ShedStatusTone.warn,
          ),
      ],
    );
  }
}

class _MachineNote extends StatelessWidget {
  const _MachineNote({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusBadge(
                  tone: shedStatusTone(lifecycle.wire).tone,
                  label: lifecycle.wire.replaceAll('-', ' '),
                ),
                const SizedBox(width: 8),
                if (display != null) ...[
                  StatusBadge(
                    tone: display.tone,
                    label: display.label,
                    pulse: display.pulse,
                  ),
                  const SizedBox(width: 8),
                ],
                KindChip(session.kind.wire),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              session.displayName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 2),
            Text(
              [
                'tmux ${session.tmuxSession}',
                if (session.workdir != null) session.workdir!,
                if (!state.reachable) 'last known',
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.fg3),
            ),
            // **Controls render off `kind_features`, never off the kind.**
            // A session whose `approvals` is "tui" reports them for information
            // only — they are answered in its terminal — so offering a button
            // would produce a 409 the user cannot act on. Unknown capabilities
            // (an older binary) mean observe-only, which is the safe default.
            if (state.reachable)
              _MachineControls(session: session, state: state),
          ],
        ),
      ),
    );
  }
}

/// The per-session control row.
///
/// Every affordance is gated on the machine's advertised `kind_features`, so
/// this row is EMPTY for a kind that supports none — which is the honest
/// rendering, not a degraded one. A `shell` session, for instance, accepts no
/// structured turn and resolves no approvals remotely; it simply has nothing to
/// offer here beyond ending it.
class _MachineControls extends ConsumerStatefulWidget {
  const _MachineControls({required this.session, required this.state});

  final BridgeRcSession session;
  final MachineFeedState state;

  @override
  ConsumerState<_MachineControls> createState() => _MachineControlsState();
}

class _MachineControlsState extends ConsumerState<_MachineControls> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function(MachineFeed feed) op) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final feed = ref.read(
        machineFeedControllerProvider(widget.state.machine.name),
      );
      await op(feed);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final st = widget.state;
    final canSteer = st.canSteer(s);
    final canInterrupt = st.canInterrupt(s);
    // Nothing to offer beyond ending it — render nothing rather than a row of
    // disabled buttons that implies the feature is merely unavailable.
    final anything = canSteer || canInterrupt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Row(
          children: [
            if (canSteer)
              TextButton.icon(
                key: ValueKey('machine-steer-${s.slug}'),
                onPressed: _busy ? null : () => _promptSteer(s),
                icon: const Icon(Icons.send, size: 16),
                label: const Text('Steer'),
              ),
            if (canInterrupt)
              TextButton.icon(
                key: ValueKey('machine-interrupt-${s.slug}'),
                onPressed: _busy
                    ? null
                    : () => _run((f) async => f.interrupt(s.slug)),
                icon: const Icon(Icons.stop_circle_outlined, size: 16),
                label: const Text('Interrupt'),
              ),
            if (anything) const Spacer(),
            TextButton.icon(
              key: ValueKey('machine-kill-${s.slug}'),
              onPressed: _busy ? null : () => _run((f) => f.kill(s.slug)),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('End'),
              style: TextButton.styleFrom(foregroundColor: context.shed.errFg),
            ),
          ],
        ),
        if (_error != null)
          Text(
            _error!,
            key: ValueKey('machine-control-error-${s.slug}'),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.shed.errFg),
          ),
      ],
    );
  }

  Future<void> _promptSteer(BridgeRcSession s) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Steer ${s.displayName}'),
        content: TextField(
          key: const ValueKey('machine-steer-text'),
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'What should it do next?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('machine-steer-send'),
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = text?.trim() ?? '';
    if (trimmed.isEmpty) return;
    await _run((f) async => f.steer(s.slug, trimmed));
  }
}
