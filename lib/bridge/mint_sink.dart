import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../servers/server_target.dart';
import '../src/rust/api/mint.dart';
import '../ssh/bootstrap_service.dart';
import '../ssh/host_key_store.dart';

/// The app-scoped mint sink (plan §3.2, D3): ONE listener, routed by
/// `request_id`. The control-token FSM lives in Rust; when a `BridgeClient`
/// needs a fresh token it emits a [BridgeMintRequest] on this StreamSink, Dart
/// runs the `_bootstrap` SSH mint over dartssh2 (UNCHANGED exec), and submits the
/// RAW stdout back — the bundle is parsed IN RUST (`parse_control_bundle`).
///
/// Ordering is load-bearing: [registerMintSink] must run BEFORE any
/// `BridgeClient` is constructed (listener-before-client), so a mint emitted at
/// first request always has a listener. [MintSink.dispose] fires
/// [shutdownMintSink] (resolving every parked mint) then cancels the
/// subscription — Riverpod/app-lifecycle teardown calls it.
class MintSink {
  MintSink._(this._container, this._sub);

  final ProviderContainer _container;
  StreamSubscription<BridgeMintRequest>? _sub;
  bool _shutdown = false;

  /// Register the single app-scoped mint listener on [container]'s provider
  /// graph (serverStore + identities + pinned host keys). Call once at startup,
  /// before the first `BridgeClient`.
  static MintSink register(ProviderContainer container) {
    late final MintSink sink;
    final sub = setMintSink().listen((req) {
      // Never let an exception escape the listener (that would kill the sink
      // stream). Every path submits exactly one outcome.
      unawaited(sink._handle(req));
    });
    sink = MintSink._(container, sub);
    return sink;
  }

  Future<void> _handle(BridgeMintRequest req) async {
    try {
      final raw = await _mint(req);
      await submitMintResult(
        requestId: req.requestId,
        outcome: BridgeMintOutcome.success(rawStdout: raw),
      );
    } catch (e) {
      // Never surface stdout/stderr or exception detail (could echo token
      // bytes) — a short, stable code only.
      await submitMintResult(
        requestId: req.requestId,
        outcome: BridgeMintOutcome.failure(code: _code(e)),
      );
    }
  }

  /// Run the `_bootstrap` SSH mint for the server identified by the request's
  /// immutable transport identity (host + ssh port), returning the raw bundle
  /// stdout.
  ///
  /// The request's `extraArgs` (an mtls CSR, or nothing) ride the request line
  /// **verbatim** — see [BootstrapService.requestLine] for why quoting them
  /// would break an mtls enrollment.
  Future<String> _mint(BridgeMintRequest req) async {
    final trust = await resolveMintTrust(_container, req);
    final identities = await _container.read(identitiesProvider.future);
    final bootstrap = BootstrapService(identities, trust.hostKeys);
    final target = ServerTarget(
      name: trust.serverName,
      host: req.host,
      sshPort: req.sshPort,
      secure: true,
      baseUrl: req.baseUrl,
      tlsCertFingerprint: req.expectedTlsPin,
    );
    return bootstrap.mintRaw(target, extraArgs: req.extraArgs);
  }

  static String _code(Object e) => 'MINT_FAILED';

  /// Idempotent teardown: resolve every parked mint (fires the Rust-side
  /// shutdown) then cancel the Dart subscription.
  Future<void> dispose() async {
    if (_shutdown) return;
    _shutdown = true;
    shutdownMintSink();
    await _sub?.cancel();
    _sub = null;
  }
}

/// The SSH trust anchor for one mint round-trip, plus the server identity the
/// mint runs under.
class MintTrust {
  const MintTrust({required this.serverName, required this.hostKeys});

  final String serverName;
  final HostKeyStore hostKeys;
}

/// Choose the SSH host-key anchor for [req] — the whole of what
/// [BridgeMintPurpose] decides, and the one half of the flow Rust cannot decide
/// for itself (plan 002 §7 P7).
///
/// * [BridgeMintPurpose.controlMint] — a SAVED server: the host key is PINNED to
///   the stored `ServerRecord.hostKeyPin`. A request with no matching saved
///   server fails; the production mint path always has one (the client was built
///   from it).
/// * [BridgeMintPurpose.addServerPreview] — FIRST CONTACT: there is no saved
///   record yet (learning what to save is the point), so the anchor is the app's
///   TOFU store — the same instance `AddServerFlow` reads the learned
///   fingerprint back from, so the user confirms the key this mint actually saw.
@visibleForTesting
Future<MintTrust> resolveMintTrust(
  ProviderContainer container,
  BridgeMintRequest req,
) async {
  switch (req.purpose) {
    case BridgeMintPurpose.addServerPreview:
      return MintTrust(
        serverName: req.host,
        hostKeys: container.read(addHostKeysProvider),
      );
    case BridgeMintPurpose.controlMint:
      final servers = await container.read(serverStoreProvider).list();
      for (final r in servers) {
        if (r.host == req.host && r.sshPort == req.sshPort) {
          return MintTrust(serverName: r.name, hostKeys: pinnedHostKeysFor(r));
        }
      }
      throw StateError('no saved server for ${req.host}:${req.sshPort}');
  }
}
