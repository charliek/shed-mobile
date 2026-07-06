import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../marionette/drive_state.dart';
import '../../providers.dart';
import '../../servers/server_record.dart';
import '../../shed/shed_dtos.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';
import '../../widgets/card_shell.dart';
import '../../widgets/disk_usage_block.dart';
import '../../widgets/runtime_badge.dart';
import '../../widgets/square_icon_button.dart';
import '../../widgets/status_badge.dart';

/// The merged Hosts-section card: one host's status **and** disk usage (the former
/// Hosts tile + System card, combined). Identity (name/URL) renders synchronously
/// from the [ServerRecord]; the status dot + shed summary come from
/// [shedsProvider] (the reachability gate) and the disk breakdown from
/// [hostSystemDfProvider] (best-effort) — both per-host `autoDispose.family`
/// providers, so each card loads and degrades independently (an unreachable host
/// never stalls the others).
///
/// Mobile is tappable ([onOpen] → the host's sheds) with a chevron; desktop is not.
/// Removing the saved host (delete) is available in **every** async state — parity
/// with the old server tile, keyed `server-remove-<name>` (mobile) /
/// `desktop-server-remove-<name>` (desktop).
class HostCard extends ConsumerWidget {
  const HostCard({
    required this.record,
    this.onOpen,
    this.mobile = true,
    super.key,
  });

  final ServerRecord record;

  /// Mobile drill-in to the host's sheds. Null on desktop (not tappable).
  final VoidCallback? onOpen;

  final bool mobile;

  Future<void> _remove(WidgetRef ref, BuildContext context) async {
    // Capture the container before the async gap: removing a host disposes this
    // card, so a WidgetRef used after the await could hit "Cannot use Ref after
    // disposed" (the ccaf70e class of bug). The app-level container outlives the
    // widget, so the invalidate always lands. Same pattern as IdentityScreen.
    final store = ref.read(serverStoreProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    await store.remove(record.name);
    logDriveResult('server-remove', ok: true);
    container.invalidate(serversProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.shed;
    final serverName = record.name;
    final sheds = ref.watch(shedsProvider(serverName));
    final df = ref.watch(hostSystemDfProvider(serverName));

    // Reachability gate: sheds is the primary HTTP call. Data → ok/summary;
    // error → unreachable (warn); loading → neutral.
    final (ShedStatusTone dotTone, String summary) = sheds.when(
      data: (list) {
        final running = list.where((s) => s.isRunning).length;
        final n = list.length;
        final label = n == 0
            ? 'No sheds'
            : '$n ${n == 1 ? 'shed' : 'sheds'}'
                  '${running > 0 ? ' · $running running' : ''}';
        return (ShedStatusTone.ok, label);
      },
      error: (_, _) => (ShedStatusTone.warn, 'Unreachable'),
      loading: () => (ShedStatusTone.idle, 'Loading…'),
    );

    // Runtime badge: prefer df's backend; fall back to a shed's backend (so an
    // old agent without df still shows vz/firecracker); else no badge.
    final dfBackend = df.asData?.value.backend;
    final backend = (dfBackend != null && dfBackend != 'none')
        ? dfBackend
        : sheds.asData?.value
              .map((s) => s.backend)
              .firstWhere((b) => b != null, orElse: () => null);

    final reachable = sheds.hasError
        ? 'f'
        : sheds.hasValue
        ? 't'
        : '-';
    final dfState = df.hasError
        ? 'error'
        : df.hasValue
        ? 'ok'
        : 'loading';
    logDriveState(
      'host-card host=$serverName reachable=$reachable df=$dfState '
      'sheds=${sheds.asData?.value.length ?? '-'}',
    );

    final key = ValueKey(
      sheds.hasError ? 'host-card-error-$serverName' : 'host-card-$serverName',
    );
    final total = _total(df);
    final delete = _delete(c, () => _remove(ref, context));

    return mobile
        ? _mobile(
            c: c,
            cardKey: key,
            dotTone: dotTone,
            summary: summary,
            backend: backend,
            df: df,
            total: total,
            delete: delete,
          )
        : _desktop(
            c: c,
            cardKey: key,
            dotTone: dotTone,
            summary: summary,
            backend: backend,
            df: df,
            total: total,
            delete: delete,
          );
  }

  Widget _delete(ShedColors c, Future<void> Function() onDelete) =>
      SquareIconButton(
        key: ValueKey(
          mobile
              ? 'server-remove-${record.name}'
              : 'desktop-server-remove-${record.name}',
        ),
        icon: Icons.delete_outline,
        size: mobile ? 34 : 36,
        iconColor: c.fg3,
        tooltip: 'Remove',
        onPressed: onDelete,
      );

  Widget _nameRow(ShedColors c, ShedStatusTone dotTone, String? backend) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      StatusDot(tone: dotTone),
      const SizedBox(width: 10),
      Flexible(
        child: Text(
          record.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: sansStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            color: c.fg,
          ),
        ),
      ),
      if (backend != null) ...[const SizedBox(width: 8), RuntimeBadge(backend)],
    ],
  );

  /// The bold total for the header trailing slot (df physical bytes), or null.
  String? _total(AsyncValue<SystemDiskUsage> df) {
    final usage = df.asData?.value;
    return usage == null ? null : formatBytes(usage.totals.all.physicalBytes);
  }

  /// The disk area under the header: the four-column breakdown when df has data,
  /// "unavailable" when it errors, a spinner while loading.
  Widget _disk(ShedColors c, AsyncValue<SystemDiskUsage> df) => df.when(
    loading: () => const SizedBox(
      height: 16,
      width: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
    error: (_, _) => Text(
      'unavailable',
      style: monoStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: c.errFg,
      ),
    ),
    data: (usage) => DiskUsageBlock(usage.totals),
  );

  /// The bold df total, sized per layout (13 mobile, 16 desktop).
  Widget _totalText(ShedColors c, String total, double size) => Text(
    total,
    style: monoStyle(fontSize: size, fontWeight: FontWeight.w700, color: c.fg),
  );

  Widget _mobile({
    required ShedColors c,
    required Key cardKey,
    required ShedStatusTone dotTone,
    required String summary,
    required String? backend,
    required AsyncValue<SystemDiskUsage> df,
    required String? total,
    required Widget delete,
  }) {
    return CardShell(
      key: cardKey,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _nameRow(c, dotTone, backend)),
                if (onOpen != null)
                  Icon(Icons.chevron_right, size: 18, color: c.fg3),
                const SizedBox(width: 4),
                delete,
              ],
            ),
            const SizedBox(height: 7),
            Text(
              record.apiUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: monoStyle(fontSize: 11.5, color: c.fg3),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    summary,
                    style: monoStyle(fontSize: 11.5, color: c.fg2),
                  ),
                ),
                if (total != null) _totalText(c, total, 13),
              ],
            ),
            const SizedBox(height: 12),
            _disk(c, df),
          ],
        ),
      ),
    );
  }

  Widget _desktop({
    required ShedColors c,
    required Key cardKey,
    required ShedStatusTone dotTone,
    required String summary,
    required String? backend,
    required AsyncValue<SystemDiskUsage> df,
    required String? total,
    required Widget delete,
  }) {
    return CardShell(
      key: cardKey,
      padding: const EdgeInsets.fromLTRB(17, 15, 15, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(child: _nameRow(c, dotTone, backend)),
              const SizedBox(width: 12),
              Text(summary, style: monoStyle(fontSize: 11.5, color: c.fg2)),
              const Spacer(),
              if (total != null) _totalText(c, total, 16),
              const SizedBox(width: 10),
              delete,
            ],
          ),
          const SizedBox(height: 14),
          _disk(c, df),
        ],
      ),
    );
  }
}
