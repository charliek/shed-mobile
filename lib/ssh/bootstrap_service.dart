import 'package:dartssh2/dartssh2.dart';

import '../core/app_error.dart';
import '../core/shell_quote.dart';
import '../servers/server_target.dart';
import 'host_key_store.dart';
import 'ssh_runner.dart';

/// Mints a credential over the reserved `_bootstrap` SSH user, the same
/// authority the shed CLI uses (`ssh _bootstrap@host control shed-mobile`).
/// Port of controlToken.ts `mintViaSSH` + the Go SDK `Bootstrap`.
///
/// Parsing is NOT here: the bundle is parsed in Rust (`parse_control_bundle`)
/// for both the running-server mint (the `BridgeClient` inversion) and the
/// add-server preview (`previewAddServer`). Dart owns the SSH transport, the
/// host-key trust decision, and the request line — nothing else.
class BootstrapService {
  /// [runWire] is a test seam: injected, it stands in for the live SSH exec so
  /// the composed request line can be asserted byte-for-byte without a server.
  BootstrapService(this.identities, this.hostKeys, {this.runWire});

  final List<SSHKeyPair> identities;
  final HostKeyStore hostKeys;

  /// Test seam (see the constructor); null in production, where each mint opens
  /// its own [SshRunner] against the target.
  final SshRunWire? runWire;

  static const _user = '_bootstrap';
  static const clientKind = 'shed-mobile';

  /// Bound on one `_bootstrap` round-trip. The Rust side's own mint timeouts
  /// (45 s for a background mint, 20 s for the add-server preview) are
  /// deliberately LONGER, so a slow SSH dial surfaces as this typed failure
  /// rather than as an opaque Rust-side timeout (plan 002 §7 P8).
  static const timeout = Duration(seconds: 15);

  /// Compose the `_bootstrap` request line: the quoted `control <kind>` prefix
  /// plus [extraArgs] appended **VERBATIM**.
  ///
  /// The verbatim part is load-bearing, not stylistic. The server's grammar is
  /// `<scope> [<kind>] [csr=<std base64 DER>]`, read from `sess.RawCommand()`
  /// and split on whitespace — there is no shell on that path
  /// (`internal/sshd/bootstrap.go`). Standard base64 contains `+`, `/` and `=`
  /// padding, none of which [shellQuote] considers bare-safe, so routing a
  /// `csr=…` argument through [wireCmd] would emit `'csr=…'` WITH the quotes,
  /// the server's `csr=` prefix match would miss, and an `auth.mode: mtls`
  /// server would answer "this server requires auth.mode: mtls; upgrade shed".
  ///
  /// The extra args come from Rust (`BridgeMintRequest.extraArgs`), which
  /// guarantees at most one whitespace-free `csr=` token; the check below is
  /// defence in depth that keeps this method's contract true whatever it is
  /// handed, since nothing downstream quotes (or can escape) a bad token.
  static String requestLine(List<String> extraArgs) {
    for (final a in extraArgs) {
      if (a.isEmpty || a.contains(RegExp(r'\s'))) {
        throw AppError(
          'BOOTSTRAP_BAD_ARG',
          'A _bootstrap argument must be one non-empty, whitespace-free token.',
        );
      }
    }
    // The `control <kind>` prefix is bare-safe, so quoting it is a no-op today —
    // but keep it quoted so the ONE unquoted thing on this line is the part
    // documented above as deliberately unquoted.
    return [
      wireCmd(const ['control', clientKind]),
      ...extraArgs,
    ].join(' ');
  }

  /// Connect over the host-key-verified SSH channel and run the mint command,
  /// returning the RAW bundle stdout (one JSON line) WITHOUT parsing. This is
  /// the FRB mint-inversion path (plan §3.2): Rust emits a need-credential
  /// request, Dart runs this exec, and the raw stdout goes back to Rust where
  /// `parse_control_bundle` parses it.
  ///
  /// [extraArgs] are appended to the request line verbatim (see [requestLine]) —
  /// today exactly one `csr=<base64>` for an mtls enrollment, or nothing, which
  /// leaves the line byte-identical to the pre-mtls client's (plan 001 D4).
  ///
  /// Never surfaces stdout/stderr on failure (could echo credential bytes):
  /// [SshRunner] doesn't log, and on empty output we throw without echoing it.
  Future<String> mintRaw(
    ServerTarget target, {
    List<String> extraArgs = const [],
  }) async {
    final run =
        runWire ??
        SshRunner(
          host: target.host,
          port: target.sshPort,
          user: _user,
          identities: identities,
          hostKeys: hostKeys,
        ).runWire;
    final res = await run(requestLine(extraArgs), timeout: timeout);
    if (res.stdout.trim().isEmpty) throw AppError.authExpired();
    return res.stdout;
  }
}
