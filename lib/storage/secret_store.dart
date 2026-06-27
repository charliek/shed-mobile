import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Key/value secret persistence. Abstracted so the data layer is unit-testable
/// with an in-memory fake (flutter_secure_storage needs a platform channel).
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Production store backed by the OS keychain/keystore (macOS Keychain, Android
/// Keystore-backed AES, Linux libsecret).
class FlutterSecureSecretStore implements SecretStore {
  FlutterSecureSecretStore([FlutterSecureStorage? storage])
    : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

/// In-memory store for tests and dev.
class InMemorySecretStore implements SecretStore {
  final Map<String, String> _m = {};

  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
  @override
  Future<void> delete(String key) async => _m.remove(key);
}

/// Desktop store: one 0600 file per key under [dirPath]. Used on macOS/Linux
/// where the keychain entitlement requires a dev signing cert the ad-hoc local
/// build can't provide. The device already holds the SSH private key on disk
/// (~/.ssh) and the shed CLI keeps its own token in plaintext ~/.shed/config.yaml,
/// so a 0600 file is a consistent trust model for a personal desktop tool.
class FileSecretStore implements SecretStore {
  FileSecretStore(this.dirPath);

  final String dirPath;

  File _file(String key) => File('$dirPath/${Uri.encodeComponent(key)}');

  @override
  Future<String?> read(String key) async {
    final f = _file(key);
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<void> write(String key, String value) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) await dir.create(recursive: true);
    await _chmod('700', dirPath); // enforce on every write, not just creation
    // Write to a temp file, lock it down, then atomically rename over the target
    // so a crash can't leave a truncated token/pin blob.
    final f = _file(key);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(value);
    await _chmod('600', tmp.path);
    await tmp.rename(f.path);
  }

  @override
  Future<void> delete(String key) async {
    final f = _file(key);
    if (await f.exists()) await f.delete();
  }

  Future<void> _chmod(String mode, String path) async {
    try {
      await Process.run('chmod', [mode, path]);
    } catch (_) {
      // best-effort; non-POSIX or chmod missing
    }
  }
}
