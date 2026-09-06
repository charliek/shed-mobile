import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../providers.dart';
import '../servers/server_record.dart';
import '../theme/shed_colors.dart';
import '../theme/shed_theme.dart';
import 'empty_state.dart';
import 'error_retry.dart';

/// A cross-host section body: one group per saved host — a host header followed by
/// [hostBuilder]'s widget for that host. Each host body is its own ConsumerWidget
/// watching its own per-host provider, so hosts load and error **independently**
/// (no all-or-nothing spinner). The shared cross-host iteration for the Hosts,
/// Sheds, and Sessions sections in both layouts.
class HostGroups extends ConsumerWidget {
  const HostGroups({
    required this.section,
    required this.emptyMessage,
    required this.hostBuilder,
    this.header = true,
    this.onRefresh,
    this.bottomInset = 40,
    this.leading,
    this.trailing,
    super.key,
  });

  /// Section id for ValueKeys / drive state (e.g. 'all-sheds').
  final String section;
  final String emptyMessage;
  final Widget Function(ServerRecord server) hostBuilder;

  /// Whether to render the uppercase host header above each group. Off for the
  /// Hosts section, whose per-host card carries the host name itself.
  final bool header;

  /// Pull-to-refresh hook. Defaults to re-listing the servers; sections pass one
  /// that also invalidates their per-host family (so refresh re-fetches the data,
  /// not just the host list).
  final void Function(WidgetRef ref)? onRefresh;

  /// Bottom list padding — raised (e.g. 96) on sections that float a FAB over the
  /// list so the last card clears it.
  final double bottomInset;

  /// Widgets above the first host group and below the last, INSIDE the scroll
  /// view — so a second section (machines) scrolls with the hosts rather than
  /// being pinned to the bottom of the screen, and shares the pull-to-refresh.
  ///
  /// They render even when there are NO hosts: a person with zero hosts and two
  /// machines must still see their machines, and the trailing section is exactly
  /// where the affordance to add one lives.
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    return servers.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          ErrorRetry(error: e, onRetry: () => ref.invalidate(serversProvider)),
      data: (list) {
        logDriveState('screen=$section hosts=${list.length}');
        // With nothing to put beside it, an empty host list is the whole screen.
        if (list.isEmpty && leading == null && trailing == null) {
          return EmptyState(
            key: ValueKey('$section-empty'),
            title: 'No hosts yet',
            message: emptyMessage,
          );
        }
        return RefreshIndicator(
          onRefresh: () async => onRefresh != null
              ? onRefresh!(ref)
              : ref.invalidate(serversProvider),
          child: ListView(
            padding: EdgeInsets.only(top: 6, bottom: bottomInset),
            children: [
              ?leading,
              // Alongside another section the empty host list is ONE quiet line
              // under its own header, not a full-page owl — the page still has
              // content, and a page-sized empty state would deny it.
              if (list.isEmpty)
                HostNote(key: ValueKey('$section-empty'), emptyMessage)
              else
                for (final s in list) ...[
                  if (header) HostGroupHeader(name: s.name),
                  hostBuilder(s),
                ],
              ?trailing,
            ],
          ),
        );
      },
    );
  }
}

/// The uppercase mono host label above each group.
class HostGroupHeader extends StatelessWidget {
  const HostGroupHeader({required this.name, super.key});

  final String name;

  @override
  Widget build(BuildContext context) {
    final shed = context.shed;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Text(
        name.toUpperCase(),
        style: monoStyle(
          fontSize: 10.5,
          color: shed.fg3,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.9,
        ),
      ),
    );
  }
}

/// A tab section heading (SHED SERVERS / MACHINES), with an optional trailing
/// action. Shared so the two sections of the Hosts tab read as siblings — which
/// is the point: a shed host and a machine are the same kind of thing to a
/// person, differing only in how they are reached.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.label,
    this.count,
    this.action,
    super.key,
  });

  final String label;
  final int? count;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final shed = context.shed;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, action == null ? 20 : 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              count == null ? label : '$label ($count)',
              style: monoStyle(
                fontSize: 10.5,
                color: shed.fg3,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.9,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// A thin indented per-host line — the per-host loading state and minimal
/// summaries.
class HostNote extends StatelessWidget {
  const HostNote(this.text, {this.color, super.key});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final shed = context.shed;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
      child: Text(
        text,
        style: monoStyle(fontSize: 12, color: color ?? shed.fg2),
      ),
    );
  }
}

/// A tinted per-host status banner (e.g. an unreachable host in the warn tone, or
/// an old-agent "unavailable" host in the err tone). Shared by the Sheds,
/// Sessions, and System sections.
class HostBanner extends StatelessWidget {
  const HostBanner({
    required this.text,
    required this.tone,
    this.icon = Icons.warning_amber_rounded,
    super.key,
  });

  final String text;
  final ShedStatusTone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final shed = context.shed;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: shed.toneBg(tone),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: shed.toneFg(tone)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: monoStyle(
                fontSize: 12,
                color: shed.toneFg(tone),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
