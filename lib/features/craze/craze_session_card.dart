import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../lanes/lane_controller.dart';
import '../../machines/machine_feed.dart';
import '../../providers.dart';
import '../../shed/shed_status.dart';
import '../../src/rust/api/dto_rc.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';
import '../../widgets/card_shell.dart';
import '../../widgets/kind_chip.dart';
import '../../widgets/open_pill.dart';
import '../../widgets/session_actions.dart';
import '../../widgets/status_badge.dart';
import '../lanes/lane_screen.dart';
import '../terminal/roost_peek_screen.dart';

/// **One craze session, in a machine's (or a shed's) sessions list** (plan
/// 025 §3.7.2, D4).
///
/// For a craze session the status is craze's: this card renders the hub's row
/// — the provider and model, what the session is doing (or, idle, the head of
/// its last reply), what it is blocked on, who is attached, why it failed to
/// start — never roost's tab. A roost tab the session runs in (a craze TUI) has
/// already been folded into this row by the machine's merge
/// (`MachineFeedState.rows`), and arrives here only as [CrazeMachineRow.tabId]:
/// the terminal actions — Peek and End tab — act on THAT tab, by its typed id,
/// never on the row's key (a hostId is not a tab id).
///
/// **The Transcript pill is always offered**: every craze session has one, and
/// it opens through the machine's craze source (no forward). A row the feed
/// holds while its craze source is not live is the LAST KNOWN row — dimmed and
/// saying so, its edge uncoloured — exactly as a roost row of an unreachable
/// machine is.
class CrazeSessionCard extends ConsumerStatefulWidget {
  const CrazeSessionCard({
    required this.origin,
    required this.row,
    required this.keySuffix,
    super.key,
  });

  /// The feed this row belongs to — a machine's name, or a shed's origin
  /// (`shed:<server>/<shed>`). The lane and the tab actions address the feed
  /// by it.
  final String origin;

  final CrazeMachineRow row;

  /// What scopes this card's keys — the machine name, or `<server>-<shed>`:
  /// a hostId is unique per hub, and two machines' hubs are two hubs.
  final String keySuffix;

  @override
  ConsumerState<CrazeSessionCard> createState() => _CrazeSessionCardState();
}

class _CrazeSessionCardState extends ConsumerState<CrazeSessionCard> {
  bool _busy = false;
  String? _error;

  String get _key => '${widget.keySuffix}-${widget.row.session.id}';

  /// The session's transcript — keyed by the row's hostId, which is what the
  /// lane provider resolves a craze row by.
  void _openLane() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LaneScreen(
        machine: widget.origin,
        kind: crazeLaneKind,
        slug: widget.row.session.id,
        title: widget.row.session.title,
      ),
    ),
  );

  /// The read-only peek of the roost tab the session runs in.
  void _peek(int tabId) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => RoostPeekScreen(
        machineName: widget.origin,
        tabId: tabId,
        title: widget.row.session.title,
      ),
    ),
  );

  /// End the roost TAB — by its id, which is also roost's row slug, so the
  /// feed's own `kill` finds it (an absorbed tab is still one of the feed's
  /// roost sessions; the merge only stopped SHOWING it). Closing a TUI's tab
  /// detaches it; the craze session itself outlives it (craze's own rule).
  Future<void> _endTab(int tabId) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(machineFeedControllerProvider(widget.origin))
          .kill('$tabId');
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    final row = widget.row;
    final s = row.session;
    final display = rcActivityBadge(BridgeRcState.ready, s.activity);
    final tabId = row.tabId;

    // Provider and model first (what the session IS), then where it runs, who
    // is attached, and — when it is — that this is the last known state.
    final meta = [
      ?s.provider,
      ?s.model,
      if (s.cwd.isNotEmpty) s.cwd,
      if ((s.attached ?? 0) > 0) '${s.attached} attached',
      if (row.stale) 'last known',
    ].join(' · ');

    // "Doing" while it works; the head of its last reply, dimmed, once idle.
    final doing = s.doing;
    final lastReply = s.lastReply;
    final needsYou = s.pendingApprovals > 0;

    return Opacity(
      opacity: row.stale ? 0.55 : 1,
      child: CardShell(
        rail: sessionRailColor(
          c,
          BridgeRcState.ready,
          s.activity,
          stale: row.stale,
        ),
        child: Column(
          key: ValueKey('craze-row-$_key'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sansStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: c.fg,
                    ),
                  ),
                ),
                if (display != null) ...[
                  const SizedBox(width: 10),
                  StatusBadge(
                    key: ValueKey('craze-activity-$_key'),
                    tone: display.tone,
                    label: display.label,
                    pulse: display.pulse && !row.stale,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                const KindChip('craze'),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    meta,
                    key: ValueKey('craze-meta-$_key'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle(fontSize: 11.5, color: c.fg3),
                  ),
                ),
              ],
            ),
            if (needsYou) ...[
              const SizedBox(height: 8),
              Text(
                [
                  'needs you (${s.pendingApprovals})',
                  ?s.headAskSummary,
                ].join(': '),
                key: ValueKey('craze-needs-$_key'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: sansStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: c.fg,
                ),
              ),
            ],
            if (doing != null) ...[
              const SizedBox(height: 6),
              Text(
                doing,
                key: ValueKey('craze-doing-$_key'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sansStyle(fontSize: 12.5, color: c.fg2),
              ),
            ] else if (lastReply != null) ...[
              const SizedBox(height: 6),
              Text(
                lastReply,
                key: ValueKey('craze-reply-$_key'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sansStyle(fontSize: 12.5, color: c.fg3),
              ),
            ],
            if (s.startError case final startError?) ...[
              const SizedBox(height: 6),
              Text(
                startError,
                key: ValueKey('craze-start-error-$_key'),
                style: monoStyle(fontSize: 11.5, color: c.errFg),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                AccentPill(
                  key: ValueKey('craze-lane-$_key'),
                  icon: Icons.forum_outlined,
                  label: 'Transcript',
                  onTap: _openLane,
                ),
                if (tabId != null) ...[
                  const SizedBox(width: 8),
                  OpenPill(
                    key: ValueKey('craze-peek-$_key'),
                    onTap: () => _peek(tabId),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    tooltip: 'Peek',
                  ),
                ],
                const Spacer(),
                if (tabId != null)
                  GhostIconButton(
                    key: ValueKey('craze-end-tab-$_key'),
                    icon: Icons.delete_outline,
                    tooltip: 'End tab',
                    busy: _busy,
                    onPressed: () => _endTab(tabId),
                  ),
              ],
            ),
            if (_error != null)
              Text(
                _error!,
                key: ValueKey('craze-control-error-$_key'),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: c.errFg),
              ),
          ],
        ),
      ),
    );
  }
}
