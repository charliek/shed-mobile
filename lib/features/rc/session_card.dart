import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_section.dart';
import '../../core/url_launch.dart';
import '../../machines/machine_feed.dart';
import '../../providers.dart';
import '../../rc/rc_ui.dart';
import '../../shed/format.dart';
import '../../src/rust/api/dto_rc.dart';
import '../../shed/shed_status.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';
import '../../widgets/card_shell.dart';
import '../../widgets/kind_chip.dart';
import '../../widgets/open_pill.dart';
import '../../widgets/session_actions.dart';
import '../../widgets/status_badge.dart';
import '../lanes/lane_screen.dart';
import '../terminal/roost_peek_screen.dart';
import '../terminal/terminal_screen.dart';
import '../terminal/terminal_target.dart';

/// One shed session — **a roost tab** (plan 022 S6, shed#328).
///
/// The RC hub is gone: a shed's agent sessions come from the `roost-session`
/// running on it, read over the phone's own SSH tunnel, exactly as a machine's
/// do. So the whole card is a function of the feed's state — the live
/// activity/lifecycle patch, the per-kind affordances, and the tab id a kill
/// closes — and nothing here calls the server's HTTP API any more.
///
/// What the card shows: lifecycle badge, live activity badge (when the
/// lifecycle permits it), an attention dot (roost's sticky notification), kind
/// chip, a meta line (shed · workdir · age), and the actions below.
///
/// **The Transcript pill is gated on the ROW, never on the kind.** A row whose
/// tab reported an agent lane carries [BridgeRcSession.agentLane]; the
/// capability block's `feed: "messages"` is a per-KIND ceiling and is allowed to
/// disagree with it (`roost_kind_features`' doc says so in as many words). The
/// attach affordance reads [attachKind]: `native-remote` — every roost row — is
/// the read-only peek, and `tmux` is the xterm attach, which is what a
/// capability block from an older, non-roost producer would still ask for.
class SessionCard extends ConsumerStatefulWidget {
  const SessionCard({
    required this.serverName,
    required this.shedName,
    required this.session,
    required this.state,
    this.originIsImplied = false,
    this.urlLauncher,
    super.key,
  });

  final String serverName;
  final String shedName;
  final BridgeRcSession session;

  /// The shed feed's current state — the live patch, the per-kind affordances,
  /// and whether the shed is answering at all.
  final MachineFeedState state;

  /// Whether the surrounding view already says which shed this session is in.
  ///
  /// True on a shed's own detail screen, whose app bar names it — repeating it
  /// on every card wastes a line that truncates. FALSE in the cross-host list,
  /// which groups by SERVER: two sheds on one server would otherwise leave
  /// their sessions with nothing on the card saying which is which.
  final bool originIsImplied;

  /// Test seam for the URL "open" action: an injected launcher passed straight
  /// through to [launchExternalUrl]. Production leaves this null (the real
  /// url_launcher is used); tests inject a fake to assert the launched [Uri]
  /// and to simulate success / false / throw.
  final UrlLauncher? urlLauncher;

  @override
  ConsumerState<SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends ConsumerState<SessionCard> {
  bool _busy = false;
  String? _error;

  String get _base =>
      '${widget.serverName}-${widget.shedName}-${widget.session.slug}';

  /// The feed this row belongs to — the shed's, addressed by its origin.
  String get _origin => shedFeedKey(widget.serverName, widget.shedName);

  /// The xterm attach, for a capability block that still asks for tmux.
  void _open() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TerminalScreen(
        target: ShedTerminalTarget(
          serverName: widget.serverName,
          shedName: widget.shedName,
          slug: widget.session.slug,
          title: '${widget.shedName}/${widget.session.slug}',
        ),
      ),
    ),
  );

  /// The read-only roost peek (`tab.dump`, polled) — the attach affordance for
  /// a `native-remote` row, which is every roost row. `tabId` is non-null there
  /// by construction: only a roost-sourced row carries one, and only a roost
  /// row advertises `native-remote`.
  void _peek() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => RoostPeekScreen(
        machineName: _origin,
        tabId: widget.session.tabId!,
        title: widget.session.displayName,
      ),
    ),
  );

  /// The row's agent lane. Gated on the row carrying a stamp:
  /// `laneControllerProvider` THROWS for a row with none, so the affordance and
  /// the provider's precondition are the same condition.
  void _openLane() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LaneScreen(
        machine: _origin,
        // The ROW's slug (roost's tab id), not the stamp's session id — the
        // session id is the thing being reconciled.
        slug: widget.session.slug,
        title: widget.session.displayName,
      ),
    ),
  );

  /// End the session — roost's `tab.close`, through the feed that holds the
  /// tunnel. The feed folds the row out optimistically, so the card goes at
  /// once rather than at the next push.
  Future<void> _delete() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(machineFeedControllerProvider(_origin))
          .kill(widget.session.slug);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    final s = widget.session;
    final st = widget.state;
    final desktop = isDesktopWidth(MediaQuery.sizeOf(context).width);

    // A claude-rc (or claude-broker) session advertises its login/console URL;
    // codex/cursor/shell leave it null, so the copy/open actions only render
    // when a non-empty URL is present.
    final url = (s.url != null && s.url!.isNotEmpty) ? s.url : null;

    // The live patch the feed folded, applied over the last snapshot.
    final state = st.stateOf(s);
    final activity = st.activityOf(s);
    // Lifecycle-trumps covers the WHOLE activity dimension: a blocking state
    // (needs-*/dead) suppresses the last-message line too — a stale preview on
    // a dead/gated row would present pre-death context as current.
    final lastMessage = rcStatePermitsActivity(state) ? s.lastMessage : null;

    final attach = attachKind(st.featuresFor(s));
    // `native-remote` only ever routes to the peek, and the peek addresses the
    // tab by roost's own id — a row without one could not be peeked at all.
    final canPeek = attach == 'native-remote' && s.tabId != null;
    final canOpen = attach == 'tmux';
    final canTranscribe = s.agentLane != null;

    final badge = StatusBadge(
      tone: shedStatusTone(state.wire).tone,
      label: state.wire.replaceAll('-', ' '),
    );

    // Lifecycle trumps activity: show the activity badge only when the
    // lifecycle permits it AND the feed reported a renderable one.
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
      sessionMetaLine(
        widget.shedName,
        s.createdAt,
        workdir: s.workdir,
        originIsImplied: widget.originIsImplied,
      ),
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

    final actions = <Widget>[
      // The PRIMARY action when there is one, and the accent says so: reading
      // the conversation is what you came for, and the pane is the fallback.
      if (canTranscribe) ...[
        AccentPill(
          key: ValueKey('all-session-lane-$_base'),
          icon: Icons.forum_outlined,
          label: 'Transcript',
          onTap: _openLane,
        ),
        const SizedBox(width: 8),
      ],
      if (canPeek)
        OpenPill(
          key: ValueKey('all-session-peek-$_base'),
          onTap: _peek,
          padding: EdgeInsets.symmetric(horizontal: desktop ? 16 : 14),
          tooltip: 'Peek',
        ),
      if (canOpen)
        OpenPill(
          key: ValueKey('all-session-open-$_base'),
          onTap: _open,
          padding: EdgeInsets.symmetric(horizontal: desktop ? 16 : 14),
        ),
      // A claude session advertises a claude.ai URL — a second way in to the
      // same session, so it follows the attach affordance.
      if (url != null) ...[
        const SizedBox(width: 8),
        SessionUrlActions(
          url: url,
          keyPrefix: 'all-session',
          keySuffix: _base,
          launcher: widget.urlLauncher,
        ),
      ],
    ];

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
                        if (s.attention) ...[
                          const SizedBox(width: 8),
                          AttentionDot(
                            key: ValueKey('all-session-attention-$_base'),
                          ),
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
              ...actions,
              const SizedBox(width: 8),
              _deleteButton(),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Both badges beside the name: lifecycle and activity are read
              // together, in one glance, instead of on separate lines.
              Row(
                children: [
                  Expanded(child: nameText),
                  const SizedBox(width: 10),
                  badge,
                  if (activityBadge != null) ...[
                    const SizedBox(width: 6),
                    activityBadge,
                  ],
                  if (s.attention) ...[
                    const SizedBox(width: 6),
                    AttentionDot(key: ValueKey('all-session-attention-$_base')),
                  ],
                ],
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  kindChip,
                  const SizedBox(width: 9),
                  Flexible(child: metaText),
                ],
              ),
              if (lastMessageText != null) ...[
                const SizedBox(height: 8),
                lastMessageText,
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  ...actions,
                  // Delete sits at the far edge, away from everything you might
                  // actually be reaching for.
                  const Spacer(),
                  _deleteButton(),
                ],
              ),
            ],
          );

    return Opacity(
      // A stale row is the last KNOWN state of a shed we cannot currently
      // reach — dimmed rather than hidden, because it is still the best
      // available answer to "what is running in there?".
      opacity: st.reachable ? 1 : 0.55,
      child: CardShell(
        rail: sessionRailColor(c, state, activity, stale: !st.reachable),
        child: _error == null
            ? body
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  body,
                  const SizedBox(height: 6),
                  Text(
                    _error!,
                    key: ValueKey('all-session-control-error-$_base'),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: c.errFg),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _deleteButton() => GhostIconButton(
    key: ValueKey('all-session-delete-$_base'),
    icon: Icons.delete_outline,
    tooltip: 'Delete',
    busy: _busy,
    onPressed: _delete,
  );
}
