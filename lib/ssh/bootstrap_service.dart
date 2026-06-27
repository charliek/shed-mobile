import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import '../core/app_error.dart';
import '../core/shell_quote.dart';
import '../control/token_bundle.dart';
import '../servers/server_target.dart';
import 'host_key_store.dart';

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
  /// pin. Never surfaces SSH stdout/stderr on failure (could echo token bytes).
  Future<ControlBundle> mint(ServerTarget target, {String? expectedPin}) async {
    final socket = await SSHSocket.connect(
      target.host,
      target.sshPort,
      timeout: _timeout,
    );
    SSHClient? client;
    try {
      client = SSHClient(
        socket,
        username: _user,
        identities: identities,
        onVerifyHostKey: hostKeys.verifier('${target.host}:${target.sshPort}'),
      );
      final res = await client.runWithResult(wireCmd(['control', _clientKind]));
      // dartssh2 can report a null/late exit code even on success, so the bundle
      // on stdout is the real success signal; only an empty stdout is a failure.
      // Never surface stdout/stderr on failure (could echo token material).
      final out = utf8.decode(res.stdout);
      if (out.trim().isEmpty) throw AppError.authExpired();
      return parseControlBundle(out, expectedPin: expectedPin);
    } finally {
      // SSHClient.close() owns the socket; if construction threw, close it directly.
      if (client != null) {
        client.close();
      } else {
        socket.destroy();
      }
    }
  }
}
