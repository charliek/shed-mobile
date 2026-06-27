import 'package:dartssh2/dartssh2.dart';

import '../storage/secret_store.dart';
import 'key_manager.dart';

/// The device's in-app SSH identity (mobile). The private key PEM lives in secure
/// storage (Android Keystore-backed); the public `authorized_keys` line is kept
/// alongside it so the onboarding screen can re-show it without the private half.
/// Desktop doesn't use this — it reuses `~/.ssh/id_ed25519` directly.
class IdentityStore {
  IdentityStore(this._secrets);

  final SecretStore _secrets;

  static const _pemKey = 'ssh_identity_pem';
  static const _pubKey = 'ssh_identity_authorized_key';

  /// Whether a complete identity (both the private PEM and its public line) is
  /// stored. Requires BOTH so a half-written key never routes the user past
  /// onboarding with no public key to share. An undecryptable read (e.g. the
  /// Android Keystore key was invalidated by a new biometric enrollment) is reset
  /// to a clean state and treated as "no key" rather than crashing the gate.
  Future<bool> hasKey() async {
    try {
      final hasPem = (await _secrets.read(_pemKey)) != null;
      final hasPub = (await _secrets.read(_pubKey)) != null;
      return hasPem && hasPub;
    } catch (_) {
      await _safeReset();
      return false;
    }
  }

  /// Load the stored identity as dartssh2 keypairs. Throws [StateError] if no key
  /// has been generated yet (the onboarding flow generates one first).
  Future<List<SSHKeyPair>> load() async {
    final pem = await _secrets.read(_pemKey);
    if (pem == null) throw StateError('no device key generated yet');
    return SSHKeyPair.fromPem(pem);
  }

  /// The stored public `authorized_keys` line, or null if no key exists.
  Future<String?> authorizedKey() => _secrets.read(_pubKey);

  /// Generate a fresh ed25519 key and persist it, returning only the PUBLIC
  /// material for the user to paste into GitHub. The private PEM is scoped to this
  /// call (written to secure storage, never returned), so it doesn't linger in
  /// caller state. Overwrites any existing key.
  Future<PublicIdentity> generateAndStore({
    String comment = 'shed-mobile',
  }) async {
    final g = KeyManager.generateEd25519(comment: comment);
    // Write the private key first (so we never advertise a public key whose
    // private half wasn't saved), and roll back on any failure so a partial
    // write never leaves an inconsistent identity behind.
    try {
      await _secrets.write(_pemKey, g.privatePem);
      await _secrets.write(_pubKey, g.authorizedKey);
    } catch (_) {
      await _safeReset();
      rethrow;
    }
    return g.public;
  }

  Future<void> delete() async {
    await _secrets.delete(_pemKey);
    await _secrets.delete(_pubKey);
  }

  Future<void> _safeReset() async {
    try {
      await delete();
    } catch (_) {
      // best-effort cleanup; nothing more we can do
    }
  }
}
