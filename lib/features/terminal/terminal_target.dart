import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../ssh/pty_session.dart';

/// Where a terminal attaches.
///
/// **Machines no longer have a tmux attach** (plan 013 S3m): a machine's
/// sessions come from a `roost-session` now, which owns its own terminal —
/// `MachineTerminalTarget` is gone, and a `native-remote` row's attach
/// affordance is the read-only `RoostPeekScreen` peek instead (see
/// `attachKind` in `lib/rc/rc_ui.dart`, and `machine_sessions_view.dart` for
/// the routing). `ShedTerminalTarget` is unaffected — a shed's rc sessions
/// still attach to their tmux pane exactly as before.
///
/// Sealed, so adding a second kind of target is a compile error at every site
/// that has to care rather than a silently-unhandled branch.
sealed class TerminalTarget {
  const TerminalTarget({required this.slug, required this.title});

  /// The RC session's slug — the tmux pane is `rc-<slug>`.
  final String slug;

  /// What the app bar reads.
  final String title;

  /// Resolve the connection parameters and build an UNSTARTED session.
  ///
  /// Unstarted on purpose: the caller owns start/teardown, so a screen disposed
  /// while this future was in flight can drop the session without ever having
  /// opened a connection.
  Future<PtySession> connect(WidgetRef ref);
}

/// A session inside a shed, reached through its server's SSH daemon.
final class ShedTerminalTarget extends TerminalTarget {
  const ShedTerminalTarget({
    required this.serverName,
    required this.shedName,
    required super.slug,
    required super.title,
  });

  final String serverName;
  final String shedName;

  @override
  Future<PtySession> connect(WidgetRef ref) async {
    final rec = await ref.read(serverStoreProvider).get(serverName);
    if (rec == null) throw StateError('unknown server: $serverName');
    final identities = await ref.read(identitiesProvider.future);
    return PtySession(
      host: rec.host,
      port: rec.sshPort,
      // A shed's login user IS the shed name — that is how the server's SSH
      // daemon routes a connection to the right VM.
      user: shedName,
      identities: identities,
      hostKeys: pinnedHostKeysFor(rec),
      slug: slug,
    );
  }
}
