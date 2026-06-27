import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:pinenacl/ed25519.dart' as ed;

/// A freshly generated ed25519 identity. [authorizedKey] is the one-line
/// `ssh-ed25519 AAAA… <comment>` string the user pastes into GitHub (or a shed's
/// authorized_keys); [fingerprint] is the `SHA256:…` form `ssh-keygen -l` prints,
/// shown so the user can confirm what they pasted.
class GeneratedKey {
  const GeneratedKey({
    required this.privatePem,
    required this.authorizedKey,
    required this.fingerprint,
  });

  final String privatePem;
  final String authorizedKey;
  final String fingerprint;

  /// Public-only view — the material safe to show/copy/return past the keygen
  /// call, so the private PEM doesn't linger in long-lived UI state.
  PublicIdentity get public =>
      PublicIdentity(authorizedKey: authorizedKey, fingerprint: fingerprint);
}

/// The public half of an identity: the `authorized_keys` line and its `SHA256:…`
/// fingerprint. Carries no private material.
class PublicIdentity {
  const PublicIdentity({
    required this.authorizedKey,
    required this.fingerprint,
  });

  final String authorizedKey;
  final String fingerprint;
}

/// Loads — and on mobile, generates — the device's SSH identity. Desktop reuses
/// an existing on-disk key; mobile generates an ed25519 key in-app and the user
/// pastes its public half into GitHub (verified against `ssh-keygen`).
class KeyManager {
  /// Parse a private-key PEM into dartssh2 identities. Accepts OpenSSH (incl.
  /// passphrase-encrypted ed25519/RSA), PKCS#1 RSA, and SEC1 EC; throws on PKCS#8
  /// or an encrypted legacy EC key (dartssh2 limitations).
  static List<SSHKeyPair> importFromFile(String path, {String? passphrase}) {
    final pem = File(path).readAsStringSync();
    return SSHKeyPair.fromPem(pem, passphrase);
  }

  /// The conventional desktop key at `~/.ssh/id_ed25519`.
  static List<SSHKeyPair> defaultDesktopKey() {
    final home = Platform.environment['HOME'] ?? '';
    return importFromFile('$home/.ssh/id_ed25519');
  }

  /// Generate a new unencrypted ed25519 key in-app (pinenacl CSPRNG → dartssh2's
  /// OpenSSH serialization). The resulting PEM round-trips through
  /// [SSHKeyPair.fromPem], and the [GeneratedKey.authorizedKey] /
  /// [GeneratedKey.fingerprint] match `ssh-keygen -y` / `-l` byte-for-byte
  /// (asserted by the key_manager test against the real `ssh-keygen`).
  static GeneratedKey generateEd25519({String comment = 'shed-mobile'}) {
    final sk = ed.SigningKey.generate();
    final publicKey = Uint8List.fromList(sk.verifyKey); // 32-byte public
    final privateKey = Uint8List.fromList(sk); // 64-byte secret (seed+public)
    final kp = OpenSSHEd25519KeyPair(publicKey, privateKey, comment);

    final blob = kp.toPublicKey().encode(); // SSH wire public-key blob
    final authorizedKey = 'ssh-ed25519 ${base64.encode(blob)} $comment';
    final digest = base64
        .encode(sha256.convert(blob).bytes)
        .replaceAll('=', '');
    return GeneratedKey(
      privatePem: kp.toPem(),
      authorizedKey: authorizedKey,
      fingerprint: 'SHA256:$digest',
    );
  }
}
