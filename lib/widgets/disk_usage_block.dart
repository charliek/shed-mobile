import 'package:flutter/material.dart';

import '../shed/format.dart';
import '../src/rust/api/dto.dart';
import '../theme/shed_colors.dart';
import '../theme/shed_theme.dart';

/// The four-column disk breakdown (`df.totals`): Images / Sheds / Snapshots /
/// Orphans, each an uppercase mono label over its physical-byte size. Extracted
/// from the former SystemCard so the merged Hosts card and any future disk view
/// share one layout. Pass [DiskTotals] (the per-category sizes); the bold total is
/// rendered by the caller (it sits in the card header beside the host name).
class DiskUsageBlock extends StatelessWidget {
  const DiskUsageBlock(this.totals, {super.key});

  final BridgeDiskTotals totals;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DiskCol('Images', totals.images),
        _DiskCol('Sheds', totals.sheds),
        _DiskCol('Snapshots', totals.snapshots),
        _DiskCol('Orphans', totals.orphans),
      ],
    );
  }
}

class _DiskCol extends StatelessWidget {
  const _DiskCol(this.label, this.size);

  final String label;
  final BridgeDiskSize size;

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
