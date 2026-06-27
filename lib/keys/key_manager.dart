import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

/// Loads the device's SSH identity. On desktop we reuse an existing on-disk key
/// (no in-app keygen needed); M4 adds in-app ed25519 generation for mobile.
class KeyManager {
  /// Parse a private-key PEM file into dartssh2 identities. Accepts OpenSSH
  /// (incl. passphrase-encrypted ed25519/RSA), PKCS#1 RSA, and SEC1 EC; throws
  /// on PKCS#8 or an encrypted legacy EC key (dartssh2 limitations).
  static List<SSHKeyPair> importFromFile(String path, {String? passphrase}) {
    final pem = File(path).readAsStringSync();
    return SSHKeyPair.fromPem(pem, passphrase);
  }

  /// The conventional desktop key at `~/.ssh/id_ed25519`.
  static List<SSHKeyPair> defaultDesktopKey() {
    final home = Platform.environment['HOME'] ?? '';
    return importFromFile('$home/.ssh/id_ed25519');
  }
}
