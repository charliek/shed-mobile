import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_section.dart';
import '../../core/url_launch.dart';
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
import '../sheds/shed_actions.dart';
import '../terminal/terminal_screen.dart';
import '../terminal/terminal_target.dart';
import 'session_watch_screen.dart';
import 'session_watch_source.dart';

/// A cross-host rc-session card: lifecycle badge, a live activity badge (when the
/// hub reports one and lifecycle permits it), an attention dot (roost's sticky
/// notification, plan 013 S3m — see [AttentionDot]), kind chip, a meta line
/// (shed · workdir · age), an optional one-line last-message preview, a "watch"
/// affordance (→ the codex message-feed view) for watch-capable kinds, a dark
/// "›_ open" pill (→ the in-app terminal) shown only when `attachKind ==
/// 'tmux'` (a shed row, always — see `lib/rc/rc_ui.dart`), and delete.
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
    this.originIsImplied = false,
    this.urlLauncher,
    super.key,
  });

  final String serverName;
  final String shedName;
  final BridgeRcSession session;
  final bool live;

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

  String get _base =>
      '${widget.serverName}-${widget.shedName}-${widget.session.slug}';

  ShedRef get _key =>
      (serverName: widget.serverName, shedName: widget.shedName);

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

  void _watch() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SessionWatchScreen(
        source: ShedWatchSource(
          serverName: widget.serverName,
          shedName: widget.shedName,
          session: widget.session,
        ),
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
        // rcServiceOneShot builds from the stable serverStore/identities, not the
        // autoDispose rcServiceProvider: nothing keeps the latter alive in the
        // cross-host view, so reading it here would dispose mid-load ("Cannot use
        // Ref after disposed") and the kill would never run.
        op: () async {
          final svc = await rcServiceOneShot(ref, _key);
          await svc.kill(widget.session.slug);
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

  /// Copy the session's claude.ai URL to the clipboard (the login/console link a
  /// claude-rc session advertises). Shown only when the session carries a URL.
  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    final s = widget.session;
    final desktop = isDesktopWidth(MediaQuery.sizeOf(context).width);

    // A claude-rc (or claude-broker) session advertises its login/console URL;
    // codex/cursor/shell leave it null, so the copy/open actions only render
    // when a non-empty URL is present.
    final url = (s.url != null && s.url!.isNotEmpty) ? s.url : null;

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
    final features = caps?.kindFeatures[s.kind.wire];
    final canWatch = features?.watch ?? false;
    // A shed row is `tmux` absent capabilities (the pre-v2 fallback) — the
    // xterm attach. A `native-remote`/other value has no shed-side affordance
    // (roost owns machine rows, never a shed's); this is the discriminator, so
    // a shed row can never silently lose its `>_ open` pill on an old server.
    final canOpen = attachKind(features) == 'tmux';

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
              ..._leadingActions(c, canWatch),
              if (canOpen) ...[
                OpenPill(
                  key: ValueKey('all-session-open-$_base'),
                  onTap: _open,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ],
              if (url != null) ...[
                const SizedBox(width: 8),
                SessionUrlActions(
                  url: url,
                  keyPrefix: 'all-session',
                  keySuffix: _base,
                  launcher: widget.urlLauncher,
                ),
              ],
              const SizedBox(width: 8),
              _deleteButton(c),
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
                  ..._leadingActions(c, canWatch),
                  if (canOpen) ...[
                    OpenPill(
                      key: ValueKey('all-session-open-$_base'),
                      onTap: _open,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                  ],
                  // The terminal first, then the link pair: `>_ open` is how
                  // you reach the session itself, and the URL is a second way
                  // in to the same one.
                  if (url != null) ...[
                    const SizedBox(width: 8),
                    SessionUrlActions(
                      url: url,
                      keyPrefix: 'all-session',
                      keySuffix: _base,
                      launcher: widget.urlLauncher,
                    ),
                  ],
                  // Delete sits at the far edge, away from everything you might
                  // actually be reaching for.
                  const Spacer(),
                  _deleteButton(c),
                ],
              ),
            ],
          );

    return CardShell(rail: sessionRailColor(c, state, activity), child: body);
  }

  /// What leads the action row: Watch, when the kind has a feed to watch.
  /// Shared by the desktop and mobile layouts so the gate lives in one place.
  ///
  /// Everything else follows the terminal — `>_ open` reaches the session
  /// itself, and the claude.ai link pair is a second way in to the same one.
  List<Widget> _leadingActions(ShedColors c, bool canWatch) => [
    if (canWatch) ...[_watchButton(c), const SizedBox(width: 8)],
  ];

  /// The PRIMARY action, and labelled: an unlabelled eye is a guess, and this is
  /// the one thing on the card most people want.
  Widget _watchButton(ShedColors c) => AccentPill(
    key: ValueKey('all-session-watch-$_base'),
    icon: Icons.visibility_outlined,
    label: 'Watch',
    onTap: _watch,
  );

  Widget _deleteButton(ShedColors c) => GhostIconButton(
    key: ValueKey('all-session-delete-$_base'),
    icon: Icons.delete_outline,
    tooltip: 'Delete',
    busy: _busy,
    onPressed: _delete,
  );
}
