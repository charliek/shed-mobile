import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:pinenacl/ed25519.dart' as ed;

/// The `SHA256:<unpadded-base64>` fingerprint of an SSH public-key wire blob —
/// the form `ssh-keygen -l` prints. The single source of truth for fingerprints
/// (used by keygen and by [PublicIdentity]) so the two paths can't drift.
String fingerprintOfBlob(Uint8List blob) =>
    'SHA256:${base64.encode(sha256.convert(blob).bytes).replaceAll('=', '')}';

/// A freshly generated ed25519 identity. [authorizedKey] is the one-line
/// `ssh-ed25519 AAAA… <comment>` string the user pastes into GitHub (or a shed's
/// authorized_keys); [fingerprint] is the `SHA256:…` form `ssh-keygen -l` prints.
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

/// The public half of an identity: the `authorized_keys` line and its `SHA256:`
/// fingerprint. Carries no private material.
class PublicIdentity {
  const PublicIdentity({
    required this.authorizedKey,
    required this.fingerprint,
  });

  final String authorizedKey;
  final String fingerprint;

  /// Build from a raw SSH public-key wire blob (e.g. `SSHHostKey.encode()`),
  /// reading the embedded key-type for the authorized_keys line. [comment] is
  /// appended to the line when non-empty.
  factory PublicIdentity.fromBlob(Uint8List blob, {String comment = ''}) {
    final type = _keyTypeFromBlob(blob);
    final b64 = base64.encode(blob);
    final line = comment.isEmpty ? '$type $b64' : '$type $b64 $comment';
    return PublicIdentity(
      authorizedKey: line,
      fingerprint: fingerprintOfBlob(blob),
    );
  }

  /// Parse an `authorized_keys` line — `[options] <type> <base64> [comment…]` —
  /// keeping the original line verbatim for display/copy and deriving the
  /// fingerprint from the decoded blob. Throws [FormatException] on a malformed
  /// line so callers can show an error instead of crashing.
  factory PublicIdentity.fromAuthorizedKeyLine(String line) {
    final parts = line.trim().split(RegExp(r'\s+'));
    // The key-type token may be preceded by an options field; find it by prefix.
    final i = parts.indexWhere(
      (p) =>
          p.startsWith('ssh-') || p.startsWith('ecdsa-') || p.startsWith('sk-'),
    );
    if (i < 0 || i + 1 >= parts.length) {
      throw const FormatException('not an authorized_keys line');
    }
    final Uint8List blob;
    try {
      blob = base64.decode(parts[i + 1]);
    } on FormatException {
      throw const FormatException('invalid base64 key blob');
    }
    // The blob must be a real public key whose embedded type matches the token,
    // so a stray base64 word (e.g. `ssh-ed25519 AAAA`) isn't accepted as a key.
    // (_keyTypeFromBlob throws FormatException on a short/garbage blob.)
    if (_keyTypeFromBlob(blob) != parts[i]) {
      throw const FormatException('key blob does not match its type');
    }
    return PublicIdentity(
      authorizedKey: line.trim(),
      fingerprint: fingerprintOfBlob(blob),
    );
  }
}

/// Read the key-type name from the start of an SSH public-key wire blob
/// (`uint32 length` + that many bytes).
String _keyTypeFromBlob(Uint8List b) {
  if (b.length < 4) throw const FormatException('blob too short');
  final len = (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
  if (len <= 0 || 4 + len > b.length) {
    throw const FormatException('malformed key blob');
  }
  return ascii.decode(b.sublist(4, 4 + len));
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

    // One source of truth for the authorized_keys line + fingerprint format.
    final pub = PublicIdentity.fromBlob(
      kp.toPublicKey().encode(),
      comment: comment,
    );
    return GeneratedKey(
      privatePem: kp.toPem(),
      authorizedKey: pub.authorizedKey,
      fingerprint: pub.fingerprint,
    );
  }
}
