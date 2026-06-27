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

  Future<void> add(ServerRecord record) async {
    final all = await list();
    if (all.any((r) => r.name == record.name)) {
      throw AppError(
        'SERVER_EXISTS',
        'A server named "${record.name}" already exists.',
      );
    }
    all.add(record);
    await _save(all);
  }

  Future<void> remove(String name) async {
    final all = await list();
    all.removeWhere((r) => r.name == name);
    await _save(all);
  }

  Future<ServerTarget?> resolveTarget(String name) async =>
      (await get(name))?.toTarget();

  Future<void> _save(List<ServerRecord> all) =>
      _secret.write(_key, jsonEncode(all.map((r) => r.toJson()).toList()));
}
