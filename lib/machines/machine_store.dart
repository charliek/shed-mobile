import 'dart:async';
import 'dart:convert';

import '../storage/secret_store.dart';
import 'machine_record.dart';

/// Persists the device's configured machines as one JSON blob.
///
/// Mirrors [ServerStore]'s shape deliberately — including the mutation queue —
/// because it has the same read-modify-write hazard: every mutation rewrites
/// the WHOLE blob, so two interleaving would lose one entirely.
///
/// A machine record holds no secret (host, user, port — the SSH identity is the
/// device key, stored separately), so this could have been plain preferences.
/// It uses the same secure store as servers anyway: one storage layer to reason
/// about, and a machine list is a map of what a person can reach, which is not
/// obviously public either.
class MachineStore {
  MachineStore(this._secret);

  final SecretStore _secret;
  static const _key = 'machines.v1';

  Future<void> _tail = Future<void>.value();

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

  /// Every configured machine, in stored order.
  ///
  /// A malformed blob yields an EMPTY list rather than throwing: the machines
  /// section is additive, and a bad decode must not take down a sessions view
  /// that also shows sheds.
  Future<List<MachineRecord>> list() async {
    final raw = await _secret.read(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, Object?>>()
          .map(MachineRecord.fromJson)
          .where((m) => m.name.isNotEmpty && m.host.isNotEmpty)
          .toList();
    } on FormatException {
      return [];
    }
  }

  /// Add or replace a machine by name. Names are unique — the name IS the
  /// origin handle, so two rows sharing one would be indistinguishable in the
  /// sessions view.
  Future<void> put(MachineRecord machine) => _serialized(() async {
    final all = await list();
    final next = [...all.where((m) => m.name != machine.name), machine]
      ..sort((a, b) => a.name.compareTo(b.name));
    await _write(next);
  });

  Future<void> remove(String name) => _serialized(() async {
    final all = await list();
    await _write(all.where((m) => m.name != name).toList());
  });

  Future<void> _write(List<MachineRecord> machines) async {
    await _secret.write(
      _key,
      jsonEncode(machines.map((m) => m.toJson()).toList()),
    );
  }
}
