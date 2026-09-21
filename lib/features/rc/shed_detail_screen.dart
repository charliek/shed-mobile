import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stridelabs_drive/stridelabs_drive.dart';

import '../../machines/machine_feed.dart';
import '../../providers.dart';
import '../../src/rust/api/dto_rc.dart';
import '../../theme/shed_colors.dart';
import '../../widgets/app_bar_count_title.dart';
import '../../widgets/empty_state.dart';
import '../create/create_rc_target.dart';
import 'create_rc_screen.dart';
import 'session_card.dart';
import 'shed_session_group.dart';
import 'feed_start_failure.dart';

/// One shed's agent sessions — **its roost tabs** (plan 022 S6, shed#328).
///
/// The shed's `roost-session` is read over the phone's own SSH tunnel, exactly
/// as a machine's is, so this screen renders from the feed rather than from a
/// one-shot list: rows arrive, change and vanish as roost publishes them, and
/// there is nothing to "refresh".
///
/// **Unreachable is not an error here.** A shed with no `roost-session` keeps
/// whatever rows it last had, dimmed, and says why — the same posture the
/// machine list takes, and the reason this screen has no error branch at all.
class ShedDetailScreen extends ConsumerWidget {
  const ShedDetailScreen({
    required this.serverName,
    required this.shedName,
    super.key,
  });

  final String serverName;
  final String shedName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final origin = shedFeedKey(serverName, shedName);
    final feed = ref.watch(machineFeedProvider(origin));
    // `.value` alone swallows an AsyncError into `null`, which `_body` renders
    // as a spinner that never resolves. The failures that land here happen
    // BEFORE `MachineFeed.start()` can turn them into an unreachable row — a
    // missing or unreadable SSH identity, a server store that will not open —
    // so there is nothing else to show them.
    final error = feed.hasError ? feed.error : null;
    final state = feed.value;
    final sessions = state?.sessions ?? const <BridgeRcSession>[];
    return Scaffold(
      key: const ValueKey('rc-screen'),
      appBar: AppBar(
        title: AppBarCountTitle(
          title: shedName,
          count: state == null ? null : sessions.length,
          noun: 'session',
        ),
        actions: [
          // A reconnect, not a refetch: roost pushes, so the only thing a
          // person can usefully ask for is a fresh tunnel — which is what
          // invalidating the feed does (the controller's `onDispose` tears the
          // old one down and the next watch rebuilds it).
          IconButton(
            key: const ValueKey('rc-refresh'),
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(machineFeedProvider(origin)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('rc-create'),
        onPressed: () async {
          await Navigator.of(context).push<Object?>(
            MaterialPageRoute<Object?>(
              builder: (_) => CreateRcScreen(
                target: ShedRcTarget(
                  serverName: serverName,
                  shedName: shedName,
                ),
              ),
            ),
          );
          // Nothing to invalidate: `tab.open` folds the new row onto the feed
          // optimistically and roost's next push is authoritative.
        },
        icon: const Icon(Icons.add, size: 20),
        label: const Text('New session'),
      ),
      body: _body(context, state, sessions, error),
    );
  }

  Widget _body(
    BuildContext context,
    MachineFeedState? state,
    List<BridgeRcSession> sessions,
    Object? error,
  ) {
    if (error != null) {
      return FeedStartFailure(origin: '$serverName/$shedName', error: error);
    }
    if (state == null) {
      return const Center(child: CircularProgressIndicator());
    }
    logDriveState(
      'screen=rc server=$serverName shed=$shedName count=${sessions.length} '
      'reachable=${state.reachable}',
    );
    if (sessions.isEmpty) {
      return EmptyState(
        key: const ValueKey('rc-empty'),
        title: state.reachable ? 'No sessions' : 'No sessions to show',
        message: state.reachable
            ? 'Start an agent — Claude, Codex, or a plain shell.'
            : shedSessionsEmptyText(state),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: sessions.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: context.shed.line),
      itemBuilder: (_, i) {
        final s = sessions[i];
        // Identity key (server-shed-slug) so each row's SessionCard keeps its
        // own busy state across list rebuilds — matches the cross-host
        // Sessions view's scheme (all_sessions_view.dart).
        return SessionCard(
          key: ValueKey('all-session-$serverName-$shedName-${s.slug}'),
          serverName: serverName,
          shedName: shedName,
          session: s,
          state: state,
          // This screen's app bar already names the shed.
          originIsImplied: true,
        );
      },
    );
  }
}
