import 'dart:async';
import 'dart:convert';

import '../core/app_error.dart';
import '../storage/secret_store.dart';
import 'server_record.dart';
import 'server_target.dart';

/// Persists the device's configured servers (with their pins + token seeds) as
/// one JSON blob in secure storage.
class ServerStore {
  ServerStore(this._secret);

  final SecretStore _secret;
  static const _key = 'servers.v1';

  /// Tail of the mutation queue. Every read-modify-write ([add], [remove],
  /// [adoptCredential]) rewrites the WHOLE `servers.v1` blob, so two of them
  /// interleaving loses one update entirely: both read the same list, each
  /// mutates its own copy, and the second write clobbers the first.
  /// [SecretStore] cannot help — it makes the individual write atomic, not the
  /// surrounding read-modify-write.
  ///
  /// That is not hypothetical here: `adoptCredential` is driven by the Rust
  /// credential-event stream and fires on its own schedule, so it can land
  /// mid-`add` while the user is adding a server.
  ///
  /// Reads ([list]/[get]/[resolveTarget]) deliberately stay OFF this queue —
  /// the mutations call [list] internally, so serializing reads on the same
  /// queue would deadlock. A read racing a mutation may observe the pre- or
  /// post-state, which is fine; only the write sequence needs ordering.
  Future<void> _tail = Future<void>.value();

  /// Run [op] after every previously queued mutation has finished.
  ///
  /// The queue tail never carries a failure: [op]'s error is forwarded to the
  /// caller's future, while `_tail` completes normally so one failed mutation
  /// cannot wedge every later one.
  Future<T> _serialized<T>(Future<T> Function() op) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await op());
      } catch (e, s) {
        result.completeError(e, s);
      }
    });
    return result.future;
  }

  Future<List<ServerRecord>> list() async {
    final raw = await _secret.read(_key);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map<String, Object?>>()
        .map(ServerRecord.fromJson)
        .toList();
  }

  Future<ServerRecord?> get(String name) async {
    for (final r in await list()) {
      if (r.name == name) return r;
    }
    return null;
  }

  Future<void> add(ServerRecord record) => _serialized(() async {
    final all = await list();
    if (all.any((r) => r.name == record.name)) {
      throw AppError(
        'SERVER_EXISTS',
        'A server named "${record.name}" already exists.',
      );
    }
    all.add(record);
    await _save(all);
  });

  /// Persist, ATOMICALLY, everything [name]'s server just issued: the credential
  /// shape AND — in token mode — the freshly minted bearer with its expiry
  /// (plan 002 §7 P1, as amended by plan 023 §3.5).
  ///
  /// One method rather than a mode setter plus a token setter, because these
  /// three fields are one fact. Two writes could interleave with a third
  /// mutation and leave a bearer paired with someone else's expiry, or an mtls
  /// record still holding a dead seed; one read-modify-write on the mutation
  /// queue cannot.
  ///
  /// The rules, matching the events `lib/bridge/credential_sink.dart` feeds in:
  ///
  ///  * **mtls** — both credential fields are CLEARED, whatever was passed. A
  ///    bearer cannot authenticate against a server that issues certificates, so
  ///    keeping it is pure liability.
  ///  * **token with [token] present** (an `Adopted`) — the pair is REPLACED,
  ///    both halves together. [expiresAt] is taken as given, `null` included: a
  ///    token the minter reported no expiry for stores none.
  ///  * **token with [token] absent** (a bare `ModeChanged`, which carries no
  ///    credential material) — the stored pair is left exactly as it is. The
  ///    event neither invents nor erases a credential.
  ///
  /// Driven by a stream that fires on EVERY successful mint, so it is idempotent
  /// and writes NOTHING when the stored record already says all of this. An
  /// unknown [name] (the record was removed while a mint was in flight) is a
  /// no-op. A storage failure is NOT swallowed here — it propagates to the
  /// caller, which decides what a lost hint costs.
  ///
  /// Returns whether anything was written.
  Future<bool> adoptCredential(
    String name,
    String authMode, {
    String? token,
    DateTime? expiresAt,
  }) => _serialized(() async {
    final mode = normalizeAuthMode(authMode);
    final all = await list();
    final i = all.indexWhere((r) => r.name == name);
    if (i < 0) return false;
    final cur = all[i];

    final mtls = mode == kAuthModeMtls;
    final nextToken = mtls ? null : (token ?? cur.controlToken);
    final nextExpiry = mtls
        ? null
        : (token == null ? cur.controlTokenExpiresAt : expiresAt);

    if (cur.authMode == mode &&
        cur.controlToken == nextToken &&
        cur.controlTokenExpiresAt == nextExpiry) {
      return false;
    }
    all[i] = cur.copyWith(
      authMode: mode,
      controlToken: nextToken,
      controlTokenExpiresAt: nextExpiry,
    );
    await _save(all);
    return true;
  });

  Future<void> remove(String name) => _serialized(() async {
    final all = await list();
    all.removeWhere((r) => r.name == name);
    await _save(all);
  });

  Future<ServerTarget?> resolveTarget(String name) async =>
      (await get(name))?.toTarget();

  Future<void> _save(List<ServerRecord> all) =>
      _secret.write(_key, jsonEncode(all.map((r) => r.toJson()).toList()));
}
