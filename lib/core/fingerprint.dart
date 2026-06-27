import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Canonical TLS pin form: `sha256:` + lowercase hex of SHA-256(DER leaf).
/// (The SSH host-key pin uses a different format — `SHA256:<base64>` — and is
/// kept in a separate store; never cross-compare the two. See PLAN §2.)
final RegExp kTlsFingerprintRe = RegExp(r'^sha256:[0-9a-f]{64}$');

/// Fingerprint of a leaf certificate's DER bytes as `sha256:<lowercase hex>`.
/// Matches the orchestrator's secureTransport.ts and shed's servertls.Fingerprint.
///
/// Compare pins with plain `==`: the pin is a public value, so a timing-safe
/// compare buys nothing (and the TS source compares with `!==`).
String certFingerprint(Uint8List der) => 'sha256:${sha256.convert(der)}';
