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
  /// [setAuthMode]) rewrites the WHOLE `servers.v1` blob, so two of them
  /// interleaving loses one update entirely: both read the same list, each
  /// mutates its own copy, and the second write clobbers the first.
  /// [SecretStore] cannot help — it makes the individual write atomic, not the
  /// surrounding read-modify-write.
  ///
  /// That is not hypothetical here: `setAuthMode` is driven by the Rust
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

  /// Persist the credential shape [name]'s server just issued (plan 002 §7 P1).
  ///
  /// Driven by the Rust credential-event stream, which fires on EVERY successful
  /// mint — so this is idempotent and writes NOTHING when the stored value
  /// already matches (a rotation must not cost a secure-storage write). A flip
  /// to mtls also drops the stored seed token: it can no longer authenticate
  /// anything, so keeping it is pure liability. An unknown [name] (the record was
  /// removed while a mint was in flight) is a no-op.
  ///
  /// Returns whether anything was written.
  Future<bool> setAuthMode(String name, String authMode) =>
      _serialized(() async {
        final mode = normalizeAuthMode(authMode);
        final all = await list();
        final i = all.indexWhere((r) => r.name == name);
        if (i < 0) return false;
        final cur = all[i];
        final dropSeed = mode == kAuthModeMtls && cur.controlToken != null;
        if (cur.authMode == mode && !dropSeed) return false;
        all[i] = cur.copyWith(authMode: mode, dropControlToken: dropSeed);
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
