import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_section.dart';
import '../../bridge/bridge_adapters.dart';
import '../../providers.dart';
import '../../shed/cloud.dart';
import '../../shed/format.dart';
import '../../shed/shed_status.dart';
import '../../src/rust/api/client.dart';
import '../../src/rust/api/dto.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';
import '../../widgets/card_shell.dart';
import '../../widgets/runtime_badge.dart';
import '../../widgets/square_icon_button.dart';
import '../../widgets/status_badge.dart';
import '../rc/shed_detail_screen.dart';
import 'extend_sheet.dart';
import 'shed_actions.dart';

/// The single shed-row widget, shared by the cross-host Sheds tab and the
/// per-host [ShedListScreen]: status dot, name, runtime badge, image chip, a
/// textual status label, and a meta line (repo · vCPU · mem · uptime). Both
/// widths carry the state-appropriate lifecycle actions (open sessions,
/// restart+stop when running / start when stopped, delete-with-confirm). On
/// mobile the whole card still drills into the shed's sessions (the action
/// buttons sit below the tappable content and win the gesture, so tapping one
/// acts without also navigating). Restart is a client-side stop→start; on
/// failure the card reflects the now-stopped state and surfaces it.
///
/// A cloud shed (plan 041) also wears a `Cloud` badge, its meta line ends with
/// the lease's time left (amber under its warning time, red once ended), and its
/// actions follow the cloud rules ([cloudActions]): no restart, and an Extend
/// that opens [showExtendSheet] and sends through [runShedExtend].
class ShedCard extends ConsumerStatefulWidget {
  const ShedCard({required this.serverName, required this.shed, super.key});

  final String serverName;
  final BridgeShed shed;

  @override
  ConsumerState<ShedCard> createState() => _ShedCardState();
}

class _ShedCardState extends ConsumerState<ShedCard> {
  bool _busy = false;

  // Set BEFORE the confirm dialog await so a rapid second tap on the delete
  // button can't stack a second dialog; cleared once the dialog resolves.
  bool _confirming = false;

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
    Future<void> Function(BridgeClient c) op,
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
          await c.start(name: widget.shed.name);
        } else {
          await c.stop(name: widget.shed.name);
        }
      });

  // Restart = stop then start (shed-core has no atomic restart). A start that
  // fails after a successful stop leaves the shed stopped; the invalidate
  // refetches the real state.
  Future<void> _restart() => _run('shed-restart', (c) async {
    await c.stop(name: widget.shed.name);
    await c.start(name: widget.shed.name);
  });

  // Delete-with-confirm. The _confirming guard (set before the dialog await)
  // stops a rapid second tap from stacking a second dialog; after the await we
  // re-check mounted (a BuildContext async gap) before mutating, and only
  // proceed when the user actually confirmed.
  Future<void> _delete() async {
    if (_busy || _confirming) return;
    setState(() => _confirming = true);
    final ok = await confirmShedDelete(
      context,
      widget.shed.name,
      cloud: widget.shed.cloud != null,
    );
    if (!mounted) return;
    setState(() => _confirming = false);
    if (ok) {
      await _run('shed-delete', (c) => c.delete(name: widget.shed.name));
    }
  }

  // Extend a cloud shed's lease: the sheet picks the hours, the shared helper
  // sends the extend and refreshes both shed views.
  Future<void> _extend(BridgeShedLease lease) async {
    if (_busy) return;
    final hours = await showExtendSheet(
      context,
      name: widget.shed.name,
      lease: lease,
    );
    if (hours == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await runShedExtend(
        ref,
        context,
        serverName: widget.serverName,
        name: widget.shed.name,
        hours: hours,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    final desktop = isDesktopWidth(MediaQuery.sizeOf(context).width);
    final wire = bridgeShedStatusWire(widget.shed.status);
    final st = shedStatusTone(wire);

    // Desktop: header on the left, the action row trailing on the same line.
    if (desktop) {
      return CardShell(
        child: Row(
          children: [
            Expanded(child: _headerRow(c, st, wire)),
            const SizedBox(width: 12),
            _actions(c),
          ],
        ),
      );
    }

    // Mobile: the whole card still drills into the shed's sessions (keeping the
    // per-host list's tap-to-open), with the lifecycle action row below the
    // tappable content. The action buttons — nested InkWells — win the gesture
    // arena, so a tap on one acts without also navigating.
    return InkWell(
      onTap: _open,
      borderRadius: BorderRadius.circular(13),
      child: CardShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _headerRow(c, st, wire),
            const SizedBox(height: 12),
            _actions(c),
          ],
        ),
      ),
    );
  }

  /// The status dot + header, shared by both layouts (the only difference
  /// between desktop and mobile is what wraps this row: a trailing actions
  /// row on the same line vs. actions below in a Column).
  Widget _headerRow(ShedColors c, StatusDisplay st, String wire) => Row(
    children: [
      StatusDot(tone: st.tone, animate: st.pulse, size: 10),
      const SizedBox(width: 14),
      Expanded(child: _header(c, st, wire)),
    ],
  );

  /// The name + runtime/image badges, a textual status label (so the per-host
  /// list keeps the readable status the old `_ShedTile` showed), and the meta
  /// line. [wire] is the status already resolved by [build] — passed down so
  /// it isn't recomputed here.
  Widget _header(ShedColors c, StatusDisplay st, String wire) {
    final s = widget.shed;
    final meta = shedMetaLine(s);
    final cloud = s.cloud;
    final lease = cloud == null
        ? null
        : cloudLease(cloud, ref.watch(cloudNowProvider));
    final metaStyle = monoStyle(fontSize: 12, color: c.fg3);
    final unknownHours = s.extendUnknownHours;
    return Column(
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
            if (cloud != null) ...[
              const SizedBox(width: 8),
              CloudBadge(key: ValueKey('all-shed-cloud-$_base')),
            ],
            if (s.image != null) ...[
              const SizedBox(width: 8),
              Flexible(child: _ImageChip(image: s.image!)),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          wire,
          key: ValueKey('all-shed-status-$_base'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: monoStyle(fontSize: 11.5, color: c.toneFg(st.tone)),
        ),
        if (meta.isNotEmpty || lease != null) ...[
          const SizedBox(height: 5),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: meta),
                if (lease != null) ...[
                  if (meta.isNotEmpty) const TextSpan(text: ' · '),
                  TextSpan(
                    text: lease.words,
                    style: metaStyle.copyWith(
                      color: switch (lease.state) {
                        LeaseState.soon => c.warnFg,
                        LeaseState.ended => c.errFg,
                        LeaseState.ok || LeaseState.unknown => c.fg3,
                      },
                    ),
                  ),
                ],
              ],
            ),
            key: ValueKey('all-shed-meta-$_base'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: metaStyle,
          ),
        ],
        if (unknownHours != null) ...[
          const SizedBox(height: 5),
          Text(
            unresolvedExtendWords(unknownHours),
            key: ValueKey('all-shed-extend-unknown-$_base'),
            style: sansStyle(fontSize: 12, color: c.warnFg),
          ),
        ],
      ],
    );
  }

  /// The state-appropriate lifecycle actions, identical on both widths: open,
  /// then restart+stop (running) / start (stopped), then delete. While a
  /// mutation is in flight the row collapses to a single spinner.
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
    final cloud = s.cloud;
    if (cloud != null) {
      return _cloudActions(
        c,
        cloudActions(s, cloud, ref.watch(cloudNowProvider)),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _openButton(),
        if (bridgeShedIsRunning(s)) ...[
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
          _stopButton(c),
        ] else ...[
          const SizedBox(width: 8),
          _startButton(c),
        ],
        const SizedBox(width: 8),
        _deleteButton(c),
      ],
    );
  }

  /// A cloud shed's actions (the desktop's rules): no restart; start and stop
  /// only before its lease ends; delete only once it is not running; Extend
  /// while the server offers it and no earlier extend's outcome is unknown.
  Widget _cloudActions(ShedColors c, CloudActions a) {
    final lease = widget.shed.cloud?.lease;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _openButton(),
        if (a.extend && lease != null) ...[
          const SizedBox(width: 8),
          SquareIconButton(
            key: ValueKey('all-shed-extend-$_base'),
            icon: Icons.more_time,
            size: 36,
            tooltip: 'Extend',
            onPressed: () => _extend(lease),
          ),
        ],
        if (a.stop) ...[const SizedBox(width: 8), _stopButton(c)],
        if (a.start) ...[const SizedBox(width: 8), _startButton(c)],
        if (a.delete) ...[const SizedBox(width: 8), _deleteButton(c)],
      ],
    );
  }

  Widget _openButton() => SquareIconButton(
    key: ValueKey('all-shed-open-$_base'),
    icon: Icons.chevron_right,
    size: 36,
    tooltip: 'Sessions',
    onPressed: _open,
  );

  Widget _stopButton(ShedColors c) => SquareIconButton(
    key: ValueKey('all-shed-stop-$_base'),
    icon: Icons.stop,
    size: 36,
    background: c.errBg,
    iconColor: c.errFg,
    tooltip: 'Stop',
    onPressed: () => _toggle(start: false),
  );

  Widget _startButton(ShedColors c) => SquareIconButton(
    key: ValueKey('all-shed-start-$_base'),
    icon: Icons.play_arrow,
    size: 36,
    background: c.okBg,
    iconColor: c.okFg,
    tooltip: 'Start',
    onPressed: () => _toggle(start: true),
  );

  Widget _deleteButton(ShedColors c) => SquareIconButton(
    key: ValueKey('all-shed-delete-$_base'),
    icon: Icons.delete_outline,
    size: 36,
    tooltip: 'Delete',
    iconColor: c.fg3,
    onPressed: _delete,
  );
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
