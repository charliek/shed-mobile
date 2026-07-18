import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../servers/server_record.dart';
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
  /// stdout. The saved [ServerRecord] supplies the pinned SSH host key; a request
  /// with no matching saved server fails (the production mint path always has
  /// one — the client was built from it).
  Future<String> _mint(BridgeMintRequest req) async {
    final servers = await _container.read(serverStoreProvider).list();
    ServerRecord? rec;
    for (final r in servers) {
      if (r.host == req.host && r.sshPort == req.sshPort) {
        rec = r;
        break;
      }
    }
    if (rec == null) {
      throw StateError('no saved server for ${req.host}:${req.sshPort}');
    }
    final identities = await _container.read(identitiesProvider.future);
    final HostKeyStore hostKeys = pinnedHostKeysFor(rec);
    final bootstrap = BootstrapService(identities, hostKeys);
    final target = ServerTarget(
      name: rec.name,
      host: req.host,
      sshPort: req.sshPort,
      secure: true,
      baseUrl: req.baseUrl,
      tlsCertFingerprint: req.expectedTlsPin,
    );
    return bootstrap.mintRaw(target);
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
