import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

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
    this.urlLauncher,
    super.key,
  });

  final String serverName;
  final String shedName;
  final BridgeRcSession session;
  final bool live;

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
  Future<void> _copyUrl(String url) async {
    // Match _openUrl: a platform-channel failure snackbars instead of escaping
    // the button callback as an unhandled async error.
    try {
      await Clipboard.setData(ClipboardData(text: url));
    } catch (e) {
      logDriveResult('session-url-copy', ok: false, error: e);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not copy URL')));
      }
      return;
    }
    logDriveResult('session-url-copy', ok: true);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('URL copied')));
    }
  }

  /// Open the session's URL in an external browser via the shared safe-launch
  /// helper (http/https only; a rejected/failed launch snackbars instead of
  /// throwing).
  Future<void> _openUrl(String url) async {
    final outcome = await launchExternalUrl(url, launcher: widget.urlLauncher);
    logDriveResult('session-url-open', ok: outcome == UrlLaunchOutcome.success);
    if (!mounted || outcome == UrlLaunchOutcome.success) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Could not open URL')));
  }

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
              ..._leadingActions(c, canWatch, url),
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
                  ..._leadingActions(c, canWatch, url),
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

  /// The watch/copy/open action buttons shown ahead of the terminal pill —
  /// shared by the desktop and mobile layouts so the `canWatch`/`url` gating
  /// lives in one place instead of two hand-kept copies.
  List<Widget> _leadingActions(ShedColors c, bool canWatch, String? url) => [
    if (canWatch) ...[_watchButton(c), const SizedBox(width: 8)],
    if (url != null) ...[
      _urlCopyButton(url),
      const SizedBox(width: 8),
      _urlOpenButton(url),
      const SizedBox(width: 8),
    ],
  ];

  Widget _watchButton(ShedColors c) => SquareIconButton(
    key: ValueKey('all-session-watch-$_base'),
    icon: Icons.visibility_outlined,
    size: 40,
    tooltip: 'Watch',
    onPressed: _watch,
  );

  Widget _urlCopyButton(String url) => SquareIconButton(
    key: ValueKey('all-session-url-copy-$_base'),
    icon: Icons.copy,
    size: 40,
    tooltip: 'Copy URL',
    onPressed: () => _copyUrl(url),
  );

  Widget _urlOpenButton(String url) => SquareIconButton(
    key: ValueKey('all-session-url-open-$_base'),
    icon: Icons.open_in_new,
    size: 40,
    tooltip: 'Open in browser',
    onPressed: () => _openUrl(url),
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
