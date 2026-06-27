import 'dart:convert';

import '../core/app_error.dart';
import '../core/fingerprint.dart';
import '../servers/server_target.dart';

/// A minted (or seeded) control token. `expiresAt == null` means no known expiry.
class MintedToken {
  const MintedToken(this.token, this.expiresAt);

  final String token;
  final DateTime? expiresAt;
}

/// Mints a fresh control token for [target] (over SSH `_bootstrap`).
typedef Minter = Future<MintedToken> Function(ServerTarget target);

/// Validate an SSH bootstrap bundle (one JSON line) into a [MintedToken],
/// failing closed. Port of controlToken.ts `parseTokenBundle`:
///   - bad JSON, non-`control` scope, empty/whitespace token, or a
///     missing/unparseable `expires_at` -> [AppError.authExpired]
///   - a minted `tls_cert_fingerprint` that doesn't match an already-configured
///     pin (a trust-model change we refuse to make silently) -> tlsPinMismatch
///
/// Note: when a pin IS configured, a present bundle fingerprint must match; an
/// absent one is tolerated (the bundle still arrived over a host-key-pinned SSH
/// channel). The full add-server flow additionally requires the bundle pin to be
/// present and equal to the user-confirmed TLS pin (PLAN §13 S2/P6).
MintedToken parseTokenBundle(String stdout, ServerTarget target) {
  Object? raw;
  try {
    raw = jsonDecode(stdout);
  } on FormatException {
    throw AppError.authExpired();
  }
  if (raw is! Map<String, Object?>) throw AppError.authExpired();

  if (raw['scope'] != 'control') throw AppError.authExpired();

  final tokenRaw = raw['token'];
  if (tokenRaw is! String) throw AppError.authExpired();
  final token = tokenRaw.trim();
  if (token.isEmpty) throw AppError.authExpired();

  final pin = target.tlsCertFingerprint;
  final mintedFp = raw['tls_cert_fingerprint'];
  if (pin != null && mintedFp is String) {
    final minted = mintedFp.trim().toLowerCase();
    if (!kTlsFingerprintRe.hasMatch(minted) || minted != pin) {
      throw AppError.tlsPinMismatch();
    }
  }

  final expiresRaw = raw['expires_at'];
  if (expiresRaw is! String) throw AppError.authExpired();
  final expiresAt = DateTime.tryParse(expiresRaw);
  if (expiresAt == null) throw AppError.authExpired();

  return MintedToken(token, expiresAt);
}

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
