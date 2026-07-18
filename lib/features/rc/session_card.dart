import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_section.dart';
import '../../providers.dart';
import '../../rc/rc_models.dart';
import '../../shed/format.dart';
import '../../shed/shed_status.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';
import '../../widgets/card_shell.dart';
import '../../widgets/kind_chip.dart';
import '../../widgets/open_pill.dart';
import '../../widgets/square_icon_button.dart';
import '../../widgets/status_badge.dart';
import '../sheds/shed_actions.dart';
import '../terminal/terminal_screen.dart';
import 'codex_watch_screen.dart';

/// A cross-host rc-session card: lifecycle badge, a live activity badge (when the
/// hub reports one and lifecycle permits it), kind chip, a meta line
/// (shed · tmux · age), an optional one-line last-message preview, a "watch"
/// affordance (→ the codex message-feed view) for watch-capable kinds, a dark
/// "›_ open" pill (→ the in-app terminal), and delete.
///
/// When [live] is true the card overlays the host's `GET /api/rc/events` stream
/// (via [liveActivityProvider]) onto the base overview snapshot, so its activity
/// badge and last-message line update without a refetch. [live] should be set
/// only when the server advertises `rc-events`.
class SessionCard extends ConsumerStatefulWidget {
  const SessionCard({
    required this.serverName,
    required this.shedName,
    required this.session,
    this.live = false,
    super.key,
  });

  final String serverName;
  final String shedName;
  final RcSession session;
  final bool live;

  @override
  ConsumerState<SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends ConsumerState<SessionCard> {
  bool _busy = false;

  String get _base =>
      '${widget.serverName}-${widget.shedName}-${widget.session.slug}';

  ShedRef get _key =>
      (serverName: widget.serverName, shedName: widget.shedName);

  void _open() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TerminalScreen(
        serverName: widget.serverName,
        shedName: widget.shedName,
        slug: widget.session.slug,
        title: '${widget.shedName}/${widget.session.slug}',
      ),
    ),
  );

  void _watch() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CodexWatchScreen(
        serverName: widget.serverName,
        shedName: widget.shedName,
        session: widget.session,
      ),
    ),
  );

  Future<void> _delete() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await runAction(
        ref,
        context,
        action: 'session-delete',
        // Build the RcService from the stable serverStore/identities, not the
        // autoDispose rcServiceProvider: nothing keeps the latter alive in the
        // cross-host view, so reading it here would dispose mid-load ("Cannot use
        // Ref after disposed") and the kill would never run.
        op: () async {
          final rec = await ref
              .read(serverStoreProvider)
              .get(widget.serverName);
          if (rec == null) {
            throw StateError('unknown server: ${widget.serverName}');
          }
          final identities = await ref.read(identitiesProvider.future);
          await rcServiceFor(
            rec,
            identities,
            widget.shedName,
          ).kill(widget.session.slug);
        },
        invalidate: () {
          ref.invalidate(overviewProvider(widget.serverName));
          ref.invalidate(rcSessionsProvider(_key));
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    final s = widget.session;
    final desktop = isDesktopWidth(MediaQuery.sizeOf(context).width);

    // Overlay the live SSE patch (if watching) onto the base snapshot.
    final patch = widget.live
        ? ref.watch(
            liveActivityProvider(
              widget.serverName,
            ).select((a) => a.value?.lookup(widget.shedName, s.slug)),
          )
        : null;
    final state = patch?.state ?? s.state;
    final activity = patch?.activity ?? s.activity;
    // Lifecycle-trumps covers the WHOLE activity dimension: a blocking state
    // (needs-*/dead) suppresses the last-message line too — a stale preview on
    // a dead/gated row would present pre-death context as current (mirrors the
    // Go server's DisplayActivity + toSessionRC suppression).
    final lastMessage = rcStatePermitsActivity(state)
        ? (patch?.lastMessage ?? s.lastMessage)
        : null;

    // Watch affordance: only for a kind whose capabilities advertise the feed.
    final caps = ref.watch(shedCapabilitiesProvider(_key)).value;
    final canWatch = caps?.kindFeatures[s.kind.wire]?.watch ?? false;

    final badge = StatusBadge(
      tone: shedStatusTone(state.wire).tone,
      label: state.wire.replaceAll('-', ' '),
    );

    // Lifecycle trumps activity: show the activity badge only when the lifecycle
    // permits it (needs-*/dead hide it) AND the hub reported a renderable one.
    final actDisplay = rcActivityBadge(state, activity);
    final activityBadge = actDisplay == null
        ? null
        : StatusBadge(
            key: ValueKey('all-session-activity-$_base'),
            tone: actDisplay.tone,
            label: actDisplay.label,
            pulse: actDisplay.pulse,
          );

    final kindChip = KindChip(s.kind.wire);
    final nameText = Text(
      s.displayName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: sansStyle(
        fontSize: 15.5,
        fontWeight: FontWeight.w600,
        color: c.fg,
      ),
    );
    final metaText = Text(
      sessionMetaLine(widget.shedName, s.tmuxSession, s.createdAt),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: monoStyle(fontSize: 11.5, color: c.fg3),
    );
    final lastMessageText = (lastMessage == null)
        ? null
        : Text(
            lastMessage,
            key: ValueKey('all-session-lastmsg-$_base'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sansStyle(fontSize: 12.5, color: c.fg2),
          );

    final body = desktop
        ? Row(
            children: [
              badge,
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(child: nameText),
                        const SizedBox(width: 10),
                        kindChip,
                        if (activityBadge != null) ...[
                          const SizedBox(width: 8),
                          activityBadge,
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    metaText,
                    if (lastMessageText != null) ...[
                      const SizedBox(height: 4),
                      lastMessageText,
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (canWatch) ...[_watchButton(c), const SizedBox(width: 8)],
              OpenPill(
                key: ValueKey('all-session-open-$_base'),
                onTap: _open,
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              const SizedBox(width: 8),
              _deleteButton(c),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: nameText),
                  const SizedBox(width: 10),
                  badge,
                ],
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  kindChip,
                  const SizedBox(width: 9),
                  Flexible(child: metaText),
                  if (activityBadge != null) ...[
                    const SizedBox(width: 9),
                    activityBadge,
                  ],
                ],
              ),
              if (lastMessageText != null) ...[
                const SizedBox(height: 8),
                lastMessageText,
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  if (canWatch) ...[_watchButton(c), const SizedBox(width: 8)],
                  Expanded(
                    child: OpenPill(
                      key: ValueKey('all-session-open-$_base'),
                      onTap: _open,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _deleteButton(c),
                ],
              ),
            ],
          );

    return CardShell(child: body);
  }

  Widget _watchButton(ShedColors c) => SquareIconButton(
    key: ValueKey('all-session-watch-$_base'),
    icon: Icons.visibility_outlined,
    size: 40,
    tooltip: 'Watch',
    onPressed: _watch,
  );

  Widget _deleteButton(ShedColors c) {
    if (_busy) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return SquareIconButton(
      key: ValueKey('all-session-delete-$_base'),
      icon: Icons.delete_outline,
      size: 40,
      background: c.errBg,
      iconColor: c.errFg,
      tooltip: 'Delete',
      onPressed: _delete,
    );
  }
}
