import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_section.dart';
import '../../shed/shed_client.dart';
import '../../shed/shed_dtos.dart';
import '../../shed/shed_status.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';
import '../../widgets/runtime_badge.dart';
import '../../widgets/square_icon_button.dart';
import '../../widgets/status_badge.dart';
import '../rc/shed_detail_screen.dart';
import 'shed_actions.dart';

/// A cross-host shed card: status dot, name, runtime badge, image chip, and a
/// meta line (repo · vCPU · mem · uptime). On desktop it carries inline actions
/// (open sessions, restart, stop/start); on mobile the whole card drills into the
/// shed's sessions (actions live in the per-host screen). Restart is a client-side
/// stop→start; on failure the card reflects the now-stopped state and surfaces it.
class ShedCard extends ConsumerStatefulWidget {
  const ShedCard({required this.serverName, required this.shed, super.key});

  final String serverName;
  final Shed shed;

  @override
  ConsumerState<ShedCard> createState() => _ShedCardState();
}

class _ShedCardState extends ConsumerState<ShedCard> {
  bool _busy = false;

  String get _base => '${widget.serverName}-${widget.shed.name}';

  void _open() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ShedDetailScreen(
        serverName: widget.serverName,
        shedName: widget.shed.name,
      ),
    ),
  );

  Future<void> _run(
    String action,
    Future<void> Function(ShedClient c) op,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // The shared kernel resolves the client, logs, surfaces failures, and
      // refetches shedsProvider (so e.g. a restart whose start failed shows
      // stopped). The card layers its busy state on top.
      await runShedAction(
        ref,
        context,
        serverName: widget.serverName,
        action: action,
        op: op,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle({required bool start}) =>
      _run(start ? 'shed-start' : 'shed-stop', (c) async {
        if (start) {
          await c.startShed(widget.shed.name);
        } else {
          await c.stopShed(widget.shed.name);
        }
      });

  Future<void> _restart() =>
      _run('shed-restart', (c) => c.restartShed(widget.shed.name));

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    final s = widget.shed;
    final desktop = isDesktopWidth(MediaQuery.sizeOf(context).width);
    final st = shedStatusTone(s.status);
    final meta = shedMetaLine(s);

    final body = Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          StatusDot(tone: st.tone, animate: st.pulse, size: 10),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sansStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: c.fg,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    RuntimeBadge(s.backend),
                    if (s.image != null) ...[
                      const SizedBox(width: 8),
                      Flexible(child: _ImageChip(image: s.image!)),
                    ],
                  ],
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle(fontSize: 12, color: c.fg3),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (desktop)
            _actions(c)
          else
            Icon(Icons.chevron_right, size: 20, color: c.fg3),
        ],
      ),
    );

    // The card's identity key (drive target + stable `_busy` State across list
    // refetches) is supplied by the parent on the ShedCard element itself.
    return desktop
        ? body
        : InkWell(
            onTap: _open,
            borderRadius: BorderRadius.circular(13),
            child: body,
          );
  }

  Widget _actions(ShedColors c) {
    if (_busy) {
      return const SizedBox(
        width: 36,
        height: 36,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final s = widget.shed;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SquareIconButton(
          key: ValueKey('all-shed-open-$_base'),
          icon: Icons.chevron_right,
          size: 36,
          tooltip: 'Sessions',
          onPressed: _open,
        ),
        if (s.isRunning) ...[
          const SizedBox(width: 8),
          SquareIconButton(
            key: ValueKey('all-shed-restart-$_base'),
            icon: Icons.refresh,
            size: 36,
            background: c.warnBg,
            iconColor: c.warnFg,
            tooltip: 'Restart',
            onPressed: _restart,
          ),
          const SizedBox(width: 8),
          SquareIconButton(
            key: ValueKey('all-shed-stop-$_base'),
            icon: Icons.stop,
            size: 36,
            background: c.errBg,
            iconColor: c.errFg,
            tooltip: 'Stop',
            onPressed: () => _toggle(start: false),
          ),
        ] else ...[
          const SizedBox(width: 8),
          SquareIconButton(
            key: ValueKey('all-shed-start-$_base'),
            icon: Icons.play_arrow,
            size: 36,
            background: c.okBg,
            iconColor: c.okFg,
            tooltip: 'Start',
            onPressed: () => _toggle(start: true),
          ),
        ],
      ],
    );
  }
}

class _ImageChip extends StatelessWidget {
  const _ImageChip({required this.image});

  final String image;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 11, color: c.fg2),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              image,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: monoStyle(fontSize: 11, color: c.fg2),
            ),
          ),
        ],
      ),
    );
  }
}
