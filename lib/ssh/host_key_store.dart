import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

/// Stores pinned SSH host keys (`SHA256:<base64>`) keyed by `host:port` and
/// builds dartssh2 host-key verify handlers.
///
/// dartssh2 hands the handler the UTF-8 bytes of `SHA256:<base64nopad>` — the
/// same format as `ssh-keyscan`, Go `FingerprintSHA256`, and shed's
/// `/api/ssh-host-key`. In [tofu] mode an unknown host is pinned on first use;
/// otherwise an unknown host is rejected. A changed key is always rejected.
/// Production add-server seeds the pin from `/api/ssh-host-key` (confirmed by
/// the user) and runs with `tofu: false`; blind TOFU is a debug/test shortcut
/// (PLAN §13 S3).
class HostKeyStore {
  HostKeyStore({Map<String, String>? pins, this.tofu = true})
    : _pins = {...?pins};

  final Map<String, String> _pins;
  final bool tofu;

  String? pinFor(String key) => _pins[key];
  void setPin(String key, String fingerprint) => _pins[key] = fingerprint;

  SSHHostkeyVerifyHandler verifier(String key) {
    return (String type, Uint8List fingerprint) {
      final fp = utf8.decode(fingerprint);
      final known = _pins[key];
      if (known == null) {
        if (!tofu) return false;
        _pins[key] = fp;
        return true;
      }
      return known == fp;
    };
  }
}
