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

  /// Connect over the host-key-pinned SSH channel and run the mint command,
  /// returning the RAW bundle stdout (one JSON line) WITHOUT parsing. This is the
  /// FRB mint-inversion path (plan §3.2): the bridge's `BridgeClient` emits a
  /// need-token request, Dart runs this exec, and the raw stdout is submitted
  /// back to Rust where `parse_control_bundle` parses it. Never surfaces
  /// stdout/stderr on failure (could echo token bytes): [SshRunner] doesn't log,
  /// and on empty output we throw without echoing it.
  Future<String> mintRaw(ServerTarget target) async {
    final runner = SshRunner(
      host: target.host,
      port: target.sshPort,
      user: _user,
      identities: identities,
      hostKeys: hostKeys,
    );
    final res = await runner.run(['control', _clientKind], timeout: _timeout);
    if (res.stdout.trim().isEmpty) throw AppError.authExpired();
    return res.stdout;
  }

  /// Connect over the host-key-pinned SSH channel, run the mint command, and
  /// parse the bundle locally. Used by the ADD-SERVER (TOFU) flow, which must
  /// learn the TLS pin + https port from the SSH-delivered bundle before it can
  /// pin TLS — a distinct concern from the provider-mint inversion (that path
  /// parses in Rust via [mintRaw]). [expectedPin] (when known) must equal the
  /// bundle's TLS pin.
  Future<ControlBundle> mint(ServerTarget target, {String? expectedPin}) async {
    final stdout = await mintRaw(target);
    return parseControlBundle(stdout, expectedPin: expectedPin);
  }
}
