import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../src/rust/api/client.dart';

/// The Rust credential-event stream, as an injectable pair of seams (open +
/// shut down). The real ones need the native library, so tests drive a plain
/// `StreamController`.
typedef CredentialEventSource = Stream<BridgeCredentialEvent> Function();

/// The app-scoped credential-event listener (plan 002 §7 P1): ONE listener for
/// the whole process, mirroring `MintSink`.
///
/// Rust emits `Adopted` after EVERY successful mint (post-lock, non-blocking)
/// and a derived `ModeChanged` when the adopted shape differs from the last
/// announced one. Mobile is the client that PERSISTS the answer: writing
/// `ServerRecord.authMode` here is what makes a live `auth.mode` flip survive an
/// app restart (AC5).
///
/// Since plan 023 §3.5 it persists the SEED too. An `Adopted` in token mode
/// carries the freshly minted bearer and its expiry, and both are written, as
/// one record, through `ServerStore.adoptCredential`. The seed used to be
/// written once at add time and never again — which meant it went stale about
/// 22h later (a 2h5m refresh window against a 24h TTL) and every cold launch
/// after that paid the mint it was supposed to skip. No certificate or key
/// material exists on the DTO to store, in either mode.
///
/// A `ModeChanged` carries no credential material at all, so it is forwarded
/// WITHOUT a token: it changes the learned mode and touches nothing else.
///
/// Ordering is load-bearing the same way the mint sink's is: register BEFORE any
/// `BridgeClient` is constructed. A client built before the sink exists simply
/// drops the events it would have delivered, and the app would then only learn
/// the mode on the NEXT launch.
///
/// Writes are SERIALIZED through a single future chain: `Adopted` and the
/// derived `ModeChanged` arrive back-to-back and each write is a
/// read-modify-write of one secure-storage blob, so concurrent handlers could
/// otherwise clobber each other. `ServerStore.adoptCredential` is additionally a
/// no-op when nothing changed, so an event that re-announces what is already
/// stored costs no storage write at all.
class CredentialSink {
  CredentialSink._(this._container, this._sub, this._close);

  final ProviderContainer _container;
  StreamSubscription<BridgeCredentialEvent>? _sub;
  final void Function() _close;
  Future<void> _writes = Future<void>.value();
  bool _shutdown = false;

  /// Register the single app-scoped credential listener on [container]'s
  /// provider graph. Call once at startup, before the first `BridgeClient`.
  static CredentialSink register(
    ProviderContainer container, {
    CredentialEventSource? open,
    void Function()? close,
  }) {
    late final CredentialSink sink;
    final sub = (open ?? setCredentialEventSink)().listen((event) {
      sink._handle(event);
    });
    sink = CredentialSink._(
      container,
      sub,
      close ?? shutdownCredentialEventSink,
    );
    return sink;
  }

  void _handle(BridgeCredentialEvent event) {
    final (
      String server,
      String authMode,
      String? token,
      DateTime? expiresAt,
    ) = switch (event) {
      BridgeCredentialEvent_Adopted(
        :final server,
        :final authMode,
        :final token,
        :final expiresAtUnix,
      ) =>
        (server, authMode, token, _utcFromUnix(expiresAtUnix)),
      // No credential material on this one, by construction — pass none, so
      // the store keeps whatever the adoption before it wrote.
      BridgeCredentialEvent_ModeChanged(:final server, :final authMode) => (
        server,
        authMode,
        null,
        null,
      ),
    };
    // In-session state first (synchronous, and what the "enrolling certificate"
    // UI + the first-call timeout budget key off), then the durable write.
    _container.read(adoptedServersProvider.notifier).markAdopted(server);
    _writes = _writes.then((_) async {
      try {
        await _container
            .read(serverStoreProvider)
            .adoptCredential(
              server,
              authMode,
              token: token,
              expiresAt: expiresAt,
            );
      } catch (_) {
        // A secure-storage failure must never kill the stream: the credential
        // itself is live in Rust and the session keeps working — only the
        // next-launch seed/hint is lost, which costs one silent re-mint (D5).
        // The store itself does NOT swallow the error; containing it is this
        // listener's decision, made here where the consequence is known.
      }
    });
  }

  /// Pending persistence, for tests and for an orderly teardown.
  @visibleForTesting
  Future<void> get settled => _writes;

  /// The bridge reports expiries as unix SECONDS (`BigInt?`); `ServerRecord`
  /// stores a UTC [DateTime]. Same conversion `AddServerFlow.preview` does for
  /// the add-time seed, so the two writers agree on the stored shape.
  static DateTime? _utcFromUnix(BigInt? unixSeconds) => unixSeconds == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(
          unixSeconds.toInt() * 1000,
          isUtc: true,
        );

  /// Idempotent teardown: end the Rust-side stream, then unsubscribe.
  Future<void> dispose() async {
    if (_shutdown) return;
    _shutdown = true;
    _close();
    await _sub?.cancel();
    _sub = null;
    await _writes;
  }
}
