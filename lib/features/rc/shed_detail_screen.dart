import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../marionette/drive_state.dart';
import '../../providers.dart';
import '../../rc/rc_models.dart';
import '../../shed/shed_status.dart';
import '../../theme/shed_colors.dart';
import '../../theme/shed_theme.dart';
import '../../widgets/app_bar_count_title.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_retry.dart';
import '../../widgets/kind_chip.dart';
import '../../widgets/open_pill.dart';
import '../../widgets/square_icon_button.dart';
import '../../widgets/status_badge.dart';
import '../terminal/terminal_screen.dart';
import 'create_rc_screen.dart';

/// Tone + label for an RC session's derived state. The tone comes from the shared
/// [shedStatusTone] table (keyed by the wire string) so it matches the cross-host
/// Sessions view; the label stays here (a few states read nicer with a space).
(ShedStatusTone, String) rcStateTone(RcState state) => (
  shedStatusTone(state.wire).tone,
  switch (state) {
    RcState.ready => 'ready',
    RcState.starting => 'starting',
    RcState.reconnecting => 'reconnecting',
    RcState.needsTrust => 'needs trust',
    RcState.needsAuth => 'needs auth',
    RcState.dead => 'dead',
  },
);

/// One shed's remote-control sessions: list with derived state, copy/open the
/// claude.ai URL, kill, and create. Driven by shed-ext-rc over SSH.
class ShedDetailScreen extends ConsumerWidget {
  const ShedDetailScreen({
    required this.serverName,
    required this.shedName,
    super.key,
  });

  final String serverName;
  final String shedName;

  ({String serverName, String shedName}) get _key =>
      (serverName: serverName, shedName: shedName);

  Future<void> _kill(BuildContext context, WidgetRef ref, String slug) async {
    try {
      final svc = await ref.read(rcServiceProvider(_key).future);
      await svc.kill(slug);
      logDriveResult('rc-kill', ok: true);
      // Refresh only on success: a failed kill is a transport/server error, so
      // re-listing would just pay another doomed SSH round-trip.
      ref.invalidate(rcSessionsProvider(_key));
      ref.invalidate(hostSessionsProvider(serverName));
    } catch (e) {
      logDriveResult('rc-kill', ok: false, error: e);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('kill failed: $e')));
      }
    }
  }

  Future<void> _copy(BuildContext context, String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    logDriveResult('rc-copy', ok: true);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('URL copied')));
    }
  }

  void _openTerminal(BuildContext context, RcSession s) {
    logDriveResult('terminal-open', ok: true);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TerminalScreen(
          serverName: serverName,
          shedName: shedName,
          slug: s.slug,
          title: '$shedName/${s.slug}',
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    logDriveResult('rc-open', ok: ok);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open URL')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(rcSessionsProvider(_key));
    return Scaffold(
      key: const ValueKey('rc-screen'),
      appBar: AppBar(
        title: AppBarCountTitle(
          title: shedName,
          count: sessions.asData?.value.length,
          noun: 'session',
        ),
        actions: [
          IconButton(
            key: const ValueKey('rc-refresh'),
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(rcSessionsProvider(_key)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('rc-create'),
        onPressed: () async {
          final created = await Navigator.of(context).push<RcSession>(
            MaterialPageRoute<RcSession>(
              builder: (_) =>
                  CreateRcScreen(serverName: serverName, shedName: shedName),
            ),
          );
          // Skip a wasted SSH re-list when the user cancelled (popped null).
          if (created != null) {
            ref.invalidate(rcSessionsProvider(_key));
            ref.invalidate(hostSessionsProvider(serverName));
          }
        },
        icon: const Icon(Icons.add, size: 20),
        label: const Text('New session'),
      ),
      body: sessions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetry(
          error: e,
          messageKey: const ValueKey('rc-error'),
          onRetry: () => ref.invalidate(rcSessionsProvider(_key)),
        ),
        data: (list) {
          logDriveState(
            'screen=rc server=$serverName shed=$shedName count=${list.length}',
          );
          if (list.isEmpty) {
            return const EmptyState(
              key: ValueKey('rc-empty'),
              title: 'No sessions',
              message: 'Start an agent — Claude, Codex, or a plain shell.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(rcSessionsProvider(_key)),
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: list.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: context.shed.line),
              itemBuilder: (_, i) {
                final s = list[i];
                return _SessionCard(
                  key: ValueKey('rc-session-${s.slug}'),
                  session: s,
                  onTerminal: () => _openTerminal(context, s),
                  onCopy: () => _copy(context, s.url!),
                  onOpen: () => _open(context, s.url!),
                  onKill: () => _kill(context, ref, s.slug),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    super.key,
    required this.session,
    required this.onTerminal,
    required this.onCopy,
    required this.onOpen,
    required this.onKill,
  });

  final RcSession session;
  final VoidCallback onTerminal;
  final VoidCallback onCopy;
  final VoidCallback onOpen;
  final VoidCallback onKill;

  @override
  Widget build(BuildContext context) {
    final shed = context.shed;
    final s = session;
    final (tone, label) = rcStateTone(s.state);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: sansStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: shed.fg,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(
                key: ValueKey('rc-state-${s.state.wire}'),
                tone: tone,
                label: label,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              KindChip(s.kind.wire),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  s.slug,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle(fontSize: 11, color: shed.fg3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OpenPill(
                  key: ValueKey('rc-terminal-${s.slug}'),
                  onTap: onTerminal,
                ),
              ),
              if (s.hasUrl) ...[
                const SizedBox(width: 8),
                SquareIconButton(
                  key: ValueKey('rc-copy-${s.slug}'),
                  icon: Icons.copy,
                  tooltip: 'Copy URL',
                  size: 40,
                  onPressed: onCopy,
                ),
                const SizedBox(width: 8),
                SquareIconButton(
                  key: ValueKey('rc-open-${s.slug}'),
                  icon: Icons.open_in_new,
                  tooltip: 'Open in browser',
                  size: 40,
                  onPressed: onOpen,
                ),
              ],
              const SizedBox(width: 8),
              SquareIconButton(
                key: ValueKey('rc-kill-${s.slug}'),
                icon: Icons.delete_outline,
                tooltip: 'Kill',
                iconColor: shed.errFg,
                size: 40,
                onPressed: onKill,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The dark "›_ open" pill that launches the in-app terminal.
