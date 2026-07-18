import 'dart:convert';

import '../core/app_error.dart';
import '../core/fingerprint.dart';

/// The provider-mint path (`MintedToken`/`Minter`/`parseTokenBundle`) was
/// retired in B3/B4: the running-server control-token FSM now lives in Rust
/// (`ControlTokenProvider`), which parses the SSH-delivered bundle via
/// `parse_control_bundle`. What remains here is the ADD-SERVER (TOFU) bundle
/// parse below, which Dart still owns because the add-server flow must learn the
/// TLS pin + https port from the SSH-delivered bundle before it can pin TLS.

/// The full `_bootstrap control` bundle (token + TLS pin + https port). Used by
/// the add-server flow, which bootstraps the TLS pin from this SSH-delivered
/// value (the SSH channel is host-key-pinned). Stricter than [parseTokenBundle]:
/// the TLS fingerprint and a positive https_port are REQUIRED (PLAN §13 S2/P6).
class ControlBundle {
  const ControlBundle({
    required this.token,
    required this.expiresAt,
    required this.tlsCertFingerprint,
    required this.httpsPort,
  });

  final String token;
  final DateTime expiresAt;
  final String tlsCertFingerprint;
  final int httpsPort;
}

ControlBundle parseControlBundle(String stdout, {String? expectedPin}) {
  Object? raw;
  try {
    raw = jsonDecode(stdout);
  } on FormatException {
    throw AppError.authExpired();
  }
  if (raw is! Map<String, Object?>) throw AppError.authExpired();
  if (raw['scope'] != 'control') throw AppError.authExpired();

  final tokenRaw = raw['token'];
  if (tokenRaw is! String || tokenRaw.trim().isEmpty) {
    throw AppError.authExpired();
  }

  final fpRaw = raw['tls_cert_fingerprint'];
  if (fpRaw is! String) throw AppError.tlsPinMissing();
  final fp = fpRaw.trim().toLowerCase();
  if (!kTlsFingerprintRe.hasMatch(fp)) throw AppError.tlsPinMissing();
  if (expectedPin != null && fp != expectedPin) throw AppError.tlsPinMismatch();

  final portRaw = raw['https_port'];
  if (portRaw is! int || portRaw < 1 || portRaw > 65535) {
    throw AppError.authExpired();
  }
  final httpsPort = portRaw;

  final expRaw = raw['expires_at'];
  if (expRaw is! String) throw AppError.authExpired();
  final exp = DateTime.tryParse(expRaw);
  if (exp == null) throw AppError.authExpired();

  return ControlBundle(
    token: tokenRaw.trim(),
    expiresAt: exp,
    tlsCertFingerprint: fp,
    httpsPort: httpsPort,
  );
}
