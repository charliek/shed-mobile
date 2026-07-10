import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_section.dart';
import '../../providers.dart';
import '../../rc/rc_models.dart';
import '../../shed/shed_dtos.dart';
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

/// A cross-host rc-session card: status badge, kind chip, a meta line
/// (shed · tmux · age), a dark "›_ open" pill (→ the in-app terminal), and delete.
/// Fed by the SSH `shed-ext-rc list` ([RcSession]), so the slug/kind/state are
/// authoritative (no derivation). Delete kills the session over SSH (managed
/// teardown), consistent with how the list is gathered.
class SessionCard extends ConsumerStatefulWidget {
  const SessionCard({
    required this.serverName,
    required this.shedName,
    required this.session,
    super.key,
  });

  final String serverName;
  final String shedName;
  final RcSession session;

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
    final tone = shedStatusTone(s.state.wire).tone;

    final badge = StatusBadge(
      tone: tone,
      label: s.state.wire.replaceAll('-', ' '),
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
                      ],
                    ),
                    const SizedBox(height: 5),
                    metaText,
                  ],
                ),
              ),
              const SizedBox(width: 12),
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
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
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
