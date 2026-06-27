import 'package:dartssh2/dartssh2.dart';

import '../core/app_error.dart';
import '../control/token_bundle.dart';
import '../servers/server_target.dart';
import 'host_key_store.dart';
import 'ssh_runner.dart';

/// Mints a control token over the reserved `_bootstrap` SSH user, the same
/// authority the shed CLI uses (`ssh _bootstrap@host control shed-mobile`).
/// Port of controlToken.ts `mintViaSSH` + the Go SDK `Bootstrap`.
class BootstrapService {
  BootstrapService(this.identities, this.hostKeys);

  final List<SSHKeyPair> identities;
  final HostKeyStore hostKeys;

  static const _user = '_bootstrap';
  static const _clientKind = 'shed-mobile';
  static const _timeout = Duration(seconds: 15);

  /// Connect over the host-key-pinned SSH channel, run the mint command, and
  /// parse the bundle. [expectedPin] (when known) must equal the bundle's TLS
  /// pin. Never surfaces SSH stdout/stderr on failure (could echo token bytes):
  /// [SshRunner] doesn't log, and on empty/unparseable output we throw without
  /// echoing it. The bundle on stdout is the real success signal — SshRunner
  /// already treats a non-empty stdout as success even when dartssh2 drops a late
  /// exit code — so this only needs the empty-stdout guard.
  Future<ControlBundle> mint(ServerTarget target, {String? expectedPin}) async {
    final runner = SshRunner(
      host: target.host,
      port: target.sshPort,
      user: _user,
      identities: identities,
      hostKeys: hostKeys,
    );
    final res = await runner.run(['control', _clientKind], timeout: _timeout);
    if (res.stdout.trim().isEmpty) throw AppError.authExpired();
    return parseControlBundle(res.stdout, expectedPin: expectedPin);
  }
}
