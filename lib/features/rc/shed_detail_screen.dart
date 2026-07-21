import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../../providers.dart';
import '../../src/rust/api/dto_rc.dart';
import '../../theme/shed_colors.dart';
import '../../widgets/app_bar_count_title.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_retry.dart';
import 'create_rc_screen.dart';
import 'session_card.dart';

/// One shed's remote-control sessions: the SSH-backed session list (via
/// [rcSessionsProvider]) rendered with the shared [SessionCard] — watch eye,
/// terminal open pill, claude URL copy/open, and delete — plus create. Driven by
/// shed-ext-rc over SSH; each card additionally reads the host overview (for its
/// watch capability), but an overview error must never blank this list.
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
          final created = await Navigator.of(context).push<BridgeRcSession>(
            MaterialPageRoute<BridgeRcSession>(
              builder: (_) =>
                  CreateRcScreen(serverName: serverName, shedName: shedName),
            ),
          );
          // Skip a wasted SSH re-list when the user cancelled (popped null).
          if (created != null) {
            ref.invalidate(rcSessionsProvider(_key));
            ref.invalidate(overviewProvider(serverName));
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
                // Identity key (server-shed-slug) so each row's SessionCard keeps
                // its own `_busy` state across list rebuilds — matches the
                // cross-host Sessions view's scheme (all_sessions_view.dart).
                return SessionCard(
                  key: ValueKey('all-session-$serverName-$shedName-${s.slug}'),
                  serverName: serverName,
                  shedName: shedName,
                  session: s,
                  live: false,
                );
              },
            ),
          );
        },
      ),
    );
  }
}
