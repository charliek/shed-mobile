import '../src/rust/api/preview.dart';
import '../ssh/host_key_store.dart';
import 'server_record.dart';
import 'server_store.dart';

/// Bound on the whole add-server round-trip, passed to the Rust preview.
///
/// Sits deliberately ABOVE `BootstrapService.timeout` (15 s), which bounds the
/// SSH leg this drives: the Dart side always answers the emitted mint request,
/// so a slow/dead server surfaces as the typed SSH failure rather than as this
/// outer timer. Well below the background mint's 45 s, because add-server is an
/// interactive screen the user is watching (plan 002 §7 P8).
const kAddServerPreviewTimeout = Duration(seconds: 20);

/// The Rust preview call, as an injectable seam. The real `previewAddServer`
/// needs the native library AND a registered mint sink, so unit tests inject a
/// stand-in and assert what the flow does with the DTO.
typedef PreviewAddServerFn =
    Future<BridgeAddServerPreview> Function({
      required String host,
      required int sshPort,
      required BigInt timeoutMs,
    });

/// What the user confirms before a server is trusted: the SSH host-key
/// fingerprint and the TLS pin (the latter delivered over the host-key-verified
/// SSH channel by the mint bundle), plus the credential shape the server issued.
class ServerPreview {
  const ServerPreview({
    required this.host,
    required this.sshPort,
    required this.hostKeyFingerprint,
    required this.authMode,
    required this.tlsCertFingerprint,
    required this.httpsPort,
    this.token,
    this.tokenExpiresAt,
  });

  final String host;
  final int sshPort;
  final String hostKeyFingerprint;

  /// [kAuthModeToken] or [kAuthModeMtls], normalized by Rust.
  final String authMode;
  final String tlsCertFingerprint;
  final int httpsPort;

  /// The seed bearer token — **token mode only** (null in mtls, where the
  /// preview's ephemeral certificate and key were dropped in Rust).
  final String? token;
  final DateTime? tokenExpiresAt;

  String get apiUrl => 'https://$host:$httpsPort';
  bool get isMtls => authMode == kAuthModeMtls;
}

/// Add-server flow. Drives the RUST preview op (`previewAddServer`), which
/// generates an ephemeral keypair, sends the CSR out over the mint inversion —
/// Dart runs the `_bootstrap` SSH round-trip with the app's TOFU host-key store —
/// parses the returned bundle, and hands back a sanitized DTO. The user confirms
/// both fingerprints, then this persists them.
///
/// Why Rust owns the request: an `auth.mode: mtls` server REJECTS a CSR-less
/// bootstrap before it returns any JSON, so the side that composes the request
/// has to be the side that can generate a keypair (plan 002 §D8-mobile). The
/// trust root is unchanged — the SSH host key (TOFU on first contact); the TLS
/// pin rides that trusted channel.
class AddServerFlow {
  AddServerFlow(this.store, this.hostKeys, {PreviewAddServerFn? previewFn})
    : _previewFn = previewFn ?? previewAddServer;

  final ServerStore store;

  /// The TOFU host-key store the preview's SSH leg pins into — the SAME instance
  /// `MintSink` hands the `addServerPreview` mint, which is what lets [preview]
  /// read back the fingerprint that connection actually saw.
  final HostKeyStore hostKeys;

  final PreviewAddServerFn _previewFn;

  Future<ServerPreview> preview({
    required String host,
    required int sshPort,
  }) async {
    final p = await _previewFn(
      host: host,
      sshPort: sshPort,
      timeoutMs: BigInt.from(kAddServerPreviewTimeout.inMilliseconds),
    );
    final hostKeyFp = hostKeys.pinFor('$host:$sshPort') ?? '(unknown)';
    final expiry = p.tokenExpiresAtUnix;
    return ServerPreview(
      host: host,
      sshPort: sshPort,
      hostKeyFingerprint: hostKeyFp,
      authMode: normalizeAuthMode(p.authMode),
      tlsCertFingerprint: p.tlsCertFingerprint,
      httpsPort: p.httpsPort,
      token: p.token,
      tokenExpiresAt: expiry == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              expiry.toInt() * 1000,
              isUtc: true,
            ),
    );
  }

  Future<ServerRecord> commit({
    required String name,
    required ServerPreview preview,
  }) async {
    final record = ServerRecord(
      name: name,
      host: preview.host,
      sshPort: preview.sshPort,
      apiUrl: preview.apiUrl,
      tlsCertFingerprint: preview.tlsCertFingerprint,
      hostKeyPin: preview.hostKeyFingerprint,
      authMode: preview.authMode,
      // §7 P7: the seed token is the ONE credential crossing at add time, and it
      // exists only in token mode — persisting it is what keeps a token-mode
      // cold launch mint-free. Rust already nulls it in mtls mode; the branch
      // here states the rule, it is not a second gate.
      controlToken: preview.isMtls ? null : preview.token,
      controlTokenExpiresAt: preview.isMtls ? null : preview.tokenExpiresAt,
    );
    await store.add(record);
    return record;
  }
}
