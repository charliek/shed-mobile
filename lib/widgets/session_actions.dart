/// **The session card's action row, one treatment for every card.**
///
/// A shed row and a machine row offer the same things and must look the same
/// offering them — the difference between the two is how they are reached, and
/// that is not something a person should be able to see.
///
/// The weighting is deliberate, and reads left to right by how often you want
/// it: **Watch** is the primary and carries the accent; `>_ open` is the
/// secondary and is dark but COMPACT — it earns its width from its label, not
/// by expanding to fill the row, because a full-width button reads as the
/// primary one; the per-kind extras are quiet outlined squares; and **delete**
/// is a bare glyph pushed to the far edge, with no fill at all. A tinted box
/// around a destructive action makes it the loudest thing on a card you are
/// only reading.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../core/url_launch.dart';
import '../theme/shed_colors.dart';
import '../theme/shed_theme.dart';
import 'square_icon_button.dart';

/// The PRIMARY action — accent-tinted, labelled, and the widest thing that is
/// not the terminal.
class AccentPill extends StatelessWidget {
  const AccentPill({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: c.accentSoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: c.accent),
            const SizedBox(width: 6),
            Text(
              label,
              style: sansStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A destructive action as a BARE glyph — no fill, no border.
///
/// Deleting a session is not something a card should advertise. It needs to be
/// reachable and unmistakable, not prominent; a filled red box makes it the
/// first thing the eye lands on, on a card you are usually only reading.
class GhostIconButton extends StatelessWidget {
  const GhostIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.busy = false,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    if (busy) {
      return const SizedBox(
        width: 36,
        height: 36,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 36,
        height: 36,
        child: Tooltip(
          message: tooltip ?? '',
          child: Icon(icon, size: 16, color: color ?? c.errFg),
        ),
      ),
    );
  }
}

/// **The two things a session's claude.ai URL is for: copying it, and opening
/// it.**
///
/// Shared by the shed row and the machine row so the pair cannot drift — a
/// claude session that shows a link on one and not the other is the same
/// session described two ways. Quiet outlined squares: a second way in is not a
/// better one than the terminal, and should not out-shout it.
///
/// Renders nothing when [url] is null, which is every non-claude kind.
class SessionUrlActions extends StatelessWidget {
  const SessionUrlActions({
    required this.url,
    required this.keyPrefix,
    required this.keySuffix,
    this.launcher,
    super.key,
  });

  final String? url;

  /// Names the two button keys `<prefix>-url-copy-<suffix>` /
  /// `<prefix>-url-open-<suffix>`, the shape the rest of each row's keys
  /// already use, so a drive harness reaches them the same way.
  final String keyPrefix;
  final String keySuffix;

  /// Injectable for tests; production uses the default external launcher.
  final UrlLauncher? launcher;

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Clipboard.setData(ClipboardData(text: url!));
    } catch (e) {
      logDriveResult('session-url-copy', ok: false, error: e);
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not copy URL')),
      );
      return;
    }
    logDriveResult('session-url-copy', ok: true);
    messenger.showSnackBar(const SnackBar(content: Text('URL copied')));
  }

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await launchExternalUrl(url!, launcher: launcher);
    logDriveResult('session-url-open', ok: outcome == UrlLaunchOutcome.success);
    if (outcome == UrlLaunchOutcome.success) return;
    messenger.showSnackBar(const SnackBar(content: Text('Could not open URL')));
  }

  @override
  Widget build(BuildContext context) {
    if (url == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SquareIconButton(
          key: ValueKey('$keyPrefix-url-copy-$keySuffix'),
          icon: Icons.copy,
          size: 36,
          tooltip: 'Copy URL',
          onPressed: () => _copy(context),
        ),
        const SizedBox(width: 8),
        SquareIconButton(
          key: ValueKey('$keyPrefix-url-open-$keySuffix'),
          icon: Icons.open_in_new,
          size: 36,
          tooltip: 'Open in browser',
          onPressed: () => _open(context),
        ),
      ],
    );
  }
}
