import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../marionette/drive_state.dart';
import '../../providers.dart';
import '../../rc/rc_models.dart';
import 'create_rc_screen.dart';

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
        title: Text('$shedName · sessions'),
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
          if (created != null) ref.invalidate(rcSessionsProvider(_key));
        },
        icon: const Icon(Icons.add),
        label: const Text('New session'),
      ),
      body: sessions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$e', key: const ValueKey('rc-error')),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.invalidate(rcSessionsProvider(_key)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (list) {
          logDriveState(
            'screen=rc server=$serverName shed=$shedName count=${list.length}',
          );
          if (list.isEmpty) {
            return const Center(
              key: ValueKey('rc-empty'),
              child: Text('No sessions. Tap "New session".'),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(rcSessionsProvider(_key)),
            child: ListView(
              children: [
                for (final s in list)
                  _RcTile(
                    session: s,
                    onCopy: () => _copy(context, s.url!),
                    onOpen: () => _open(context, s.url!),
                    onKill: () => _kill(context, ref, s.slug),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RcTile extends StatelessWidget {
  const _RcTile({
    required this.session,
    required this.onCopy,
    required this.onOpen,
    required this.onKill,
  });

  final RcSession session;
  final VoidCallback onCopy;
  final VoidCallback onOpen;
  final VoidCallback onKill;

  @override
  Widget build(BuildContext context) {
    final s = session;
    return ListTile(
      key: ValueKey('rc-session-${s.slug}'),
      title: Text(s.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${s.kind.wire} · ${s.slug}'),
          const SizedBox(height: 4),
          _StateChip(state: s.state),
        ],
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (s.hasUrl) ...[
            IconButton(
              key: ValueKey('rc-copy-${s.slug}'),
              icon: const Icon(Icons.copy),
              tooltip: 'Copy URL',
              onPressed: onCopy,
            ),
            IconButton(
              key: ValueKey('rc-open-${s.slug}'),
              icon: const Icon(Icons.open_in_new),
              tooltip: 'Open in browser',
              onPressed: onOpen,
            ),
          ],
          IconButton(
            key: ValueKey('rc-kill-${s.slug}'),
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Kill',
            onPressed: onKill,
          ),
        ],
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});
  final RcState state;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (state) {
      RcState.ready => (Colors.green, 'ready'),
      RcState.starting => (Colors.blueGrey, 'starting'),
      RcState.reconnecting => (Colors.orange, 'reconnecting'),
      RcState.needsTrust => (Colors.amber, 'needs trust'),
      RcState.needsAuth => (Colors.amber, 'needs auth'),
      RcState.dead => (Colors.red, 'dead'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        key: ValueKey('rc-state-${state.wire}'),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}
