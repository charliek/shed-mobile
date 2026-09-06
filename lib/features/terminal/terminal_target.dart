import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../ssh/pty_session.dart';

/// Where a terminal attaches — a shed, or a machine.
///
/// The two differ only in the SSH COORDINATES: a shed is reached through its
/// server's SSH daemon with a pinned host key and the shed's name as the login
/// user; a machine is an ordinary SSH host the operator already manages. Once a
/// connection exists the remote command is identical (`tmux attach -t rc-<slug>`,
/// see [rcAttachCommand]), which is why [PtySession] needs no notion of either
/// and this seam is the whole of the difference.
///
/// Sealed, so adding a third kind of target is a compile error at every site
/// that has to care rather than a silently-unhandled branch.
sealed class TerminalTarget {
  const TerminalTarget({required this.slug, required this.title});

  /// The RC session's slug — the tmux pane is `rc-<slug>` on both kinds.
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

/// A session on a machine — a native host reached over ordinary SSH.
final class MachineTerminalTarget extends TerminalTarget {
  const MachineTerminalTarget({
    required this.machineName,
    required super.slug,
    required super.title,
  });

  final String machineName;

  @override
  Future<PtySession> connect(WidgetRef ref) async {
    final machines = await ref.read(machinesProvider.future);
    final m = machines.where((m) => m.name == machineName).firstOrNull;
    if (m == null) throw StateError('unknown machine: $machineName');
    final identities = await ref.read(identitiesProvider.future);
    return PtySession(
      host: m.host,
      port: m.sshPort,
      // `root` matches the rest of the machine path's default (see MachineFeed):
      // a machine with no configured user lets the far side decide, which on a
      // phone means dartssh2's default rather than an ssh_config lookup.
      user: m.user ?? 'root',
      identities: identities,
      // A machine is an ordinary SSH host with no published host key to pin
      // against, so the phone pins on FIRST USE — the same posture the feed's
      // tunnel takes, and the same store, so the two agree about the machine.
      hostKeys: ref.read(machineHostKeysProvider),
      slug: slug,
    );
  }
}
