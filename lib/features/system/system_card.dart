import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../marionette/drive_state.dart';
import '../../providers.dart';
import '../../shed/shed_dtos.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';
import '../../widgets/card_shell.dart';
import '../../widgets/runtime_badge.dart';

/// A per-host disk-usage card (`GET /api/system/df`): host name + runtime badge +
/// bold total, then the Images / Sheds / Snapshots / Orphans breakdown (physical
/// bytes). Best-effort: a host whose agent lacks the endpoint shows "unavailable".
class SystemCard extends ConsumerWidget {
  const SystemCard({required this.serverName, super.key});

  final String serverName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.shed;
    final df = ref.watch(hostSystemDfProvider(serverName));

    Widget shell({required Key key, required Widget child}) => CardShell(
      key: key,
      padding: const EdgeInsets.fromLTRB(15, 14, 17, 16),
      child: child,
    );

    Widget header(Widget trailing, {String? backend}) => Row(
      children: [
        Icon(Icons.storage_outlined, size: 18, color: c.fg2),
        const SizedBox(width: 9),
        Flexible(
          child: Text(
            serverName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sansStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: c.fg,
            ),
          ),
        ),
        if (backend != null) ...[
          const SizedBox(width: 8),
          RuntimeBadge(backend),
        ],
        const Spacer(),
        trailing,
      ],
    );

    return df.when(
      loading: () => shell(
        key: ValueKey('system-host-$serverName'),
        child: header(
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (e, _) {
        logDriveState('system host=$serverName ok=false');
        return shell(
          key: ValueKey('system-host-error-$serverName'),
          child: header(
            Text(
              'unavailable',
              style: monoStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: c.errFg,
              ),
            ),
          ),
        );
      },
      data: (usage) {
        logDriveState('system host=$serverName ok=true');
        final t = usage.totals;
        return shell(
          key: ValueKey('system-host-$serverName'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header(
                Text(
                  formatBytes(t.all.physicalBytes),
                  style: monoStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: c.fg,
                  ),
                ),
                backend: usage.backend,
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DiskCol('Images', t.images),
                  _DiskCol('Sheds', t.sheds),
                  _DiskCol('Snapshots', t.snapshots),
                  _DiskCol('Orphans', t.orphans),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DiskCol extends StatelessWidget {
  const _DiskCol(this.label, this.size);

  final String label;
  final DiskSize size;

  @override
  Widget build(BuildContext context) {
    final c = context.shed;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: monoStyle(fontSize: 9.5, color: c.fg3, letterSpacing: 0.4),
          ),
          const SizedBox(height: 4),
          Text(
            formatBytes(size.physicalBytes),
            style: monoStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: c.fg,
            ),
          ),
        ],
      ),
    );
  }
}
