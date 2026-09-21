import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../../machines/machine_feed.dart';
import '../../providers.dart';
import '../../src/rust/api/dto_rc.dart';
import '../../theme/shed_colors.dart';
import '../../widgets/host_groups.dart';
import '../../widgets/status_badge.dart';
import 'session_card.dart';

/// **One shed's roost tabs, in the cross-host sessions list** (plan 022 S6).
///
/// A shed's agent sessions are roost tabs read over the phone's own SSH tunnel
/// now — the same feed a machine's rows come from, addressed by
/// [shedFeedKey]. So this group is the shed-shaped sibling of
/// `_MachineGroup` and behaves the same way in the two places it matters:
///
/// * **Unreachable is a normal state.** A shed with no `roost-session` (or one
///   the phone cannot dial right now) keeps its last-known rows, dimmed, with
///   the reason shown — never an error, and never a silently empty list.
/// * **Rows key on the shed's ORIGIN**, not on a slug: a slug is roost's tab
///   id, per-daemon, so two sheds can both have a tab `4`.
class ShedSessionGroup extends ConsumerWidget {
  const ShedSessionGroup({
    required this.serverName,
    required this.shedName,
    this.serverPredatesRoost = false,
    super.key,
  });

  final String serverName;
  final String shedName;

  /// This shed's server still enriches its overview rows with RC sessions,
  /// which only a pre-0.9.0 server does.
  ///
  /// It changes what an empty list MEANS. "No roost session on this shed" is
  /// the right advice against a 0.9.0 server and the wrong advice here: the
  /// hub those sessions came from is gone on this side, so the fix is to
  /// upgrade the server, not to start a daemon on the shed. Pointing a user at
  /// the wrong repair is the failure mode S6 already fixed once in the desktop
  /// Agents pane.
  final bool serverPredatesRoost;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final origin = shedFeedKey(serverName, shedName);
    final feed = ref.watch(machineFeedProvider(origin));
    // See `shed_detail_screen.dart`: `.value` turns an AsyncError into `null`,
    // and `null` reads as "connecting…" forever. A feed that could not START
    // has a cause worth naming — this row is small, so it names it in place of
    // the badge's optimistic "connecting".
    final startError = feed.hasError ? feed.error : null;
    final state = feed.value;
    final sessions = state?.sessions ?? const <BridgeRcSession>[];
    final reachable = state?.reachable ?? false;
    logDriveState(
      'shed-sessions server=$serverName shed=$shedName '
      'reachable=$reachable count=${sessions.length} source=roost',
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            label: shedName.toUpperCase(),
            action: reachable
                ? null
                : Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: StatusBadge(
                      key: ValueKey('shed-unreachable-$serverName-$shedName'),
                      label: startError != null
                          ? 'failed'
                          : (state?.connectedOnce ?? false)
                          ? 'unreachable'
                          : 'connecting',
                      tone: ShedStatusTone.warn,
                    ),
                  ),
          ),
          if (sessions.isEmpty)
            _ShedNote(
              key: ValueKey('shed-empty-$serverName-$shedName'),
              text: shedSessionsEmptyText(
                state,
                startError: startError,
                serverPredatesRoost: serverPredatesRoost,
              ),
            )
          else
            for (final s in sessions)
              SessionCard(
                key: ValueKey('all-session-$serverName-$shedName-${s.slug}'),
                serverName: serverName,
                shedName: shedName,
                session: s,
                state: state!,
                // The group heading names the shed.
                originIsImplied: true,
              ),
        ],
      ),
    );
  }
}

/// What an empty list MEANS depends on whether we ever connected — "no
/// sessions" and "this shed is not running a roost-session" are different facts
/// and showing the wrong one is actively misleading.
///
/// The no-session case is the one a 0.9.0 shed lands in by default: the roost
/// daemon is not in the image yet (plan 022 D5 puts it in 023), so a shed has
/// one only where something put it there. The reason string the feed carries is
/// roost's own, and it says exactly that.
String shedSessionsEmptyText(
  MachineFeedState? state, {
  Object? startError,
  bool serverPredatesRoost = false,
}) {
  // Outranks the roost reasons below: they all assume the server speaks 0.9.0,
  // and against an older one they name a repair that cannot help.
  if (serverPredatesRoost) {
    return 'This server predates 0.9.0 — its agent sessions came from the RC '
        'hub, which is retired. Upgrade the server to see sessions here.';
  }
  // A feed that never started outranks every other message: the states below
  // all describe a connection that got somewhere, and saying "connecting…" for
  // a missing SSH identity points the user at the wrong thing entirely.
  if (startError != null) return '$startError';
  if (state == null) return 'connecting…';
  if (state.reachable) return 'No sessions';
  if (!state.connectedOnce) return state.detail ?? 'connecting…';
  return state.detail ?? 'no roost session on this shed';
}

/// A thin indented per-shed line — the same treatment [HostNote] gives a host.
class _ShedNote extends StatelessWidget {
  const _ShedNote({required this.text, super.key});

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
