import 'server_target.dart';

/// The bearer-token credential shape (`auth.mode: token`, its permanent legacy
/// alias `secure`, and every pre-mtls server). The DEFAULT for anything the app
/// has not learned otherwise.
const kAuthModeToken = 'token';

/// The client-certificate credential shape (`auth.mode: mtls`). The certificate
/// IS the credential; no bearer token exists (plan 001 D2).
const kAuthModeMtls = 'mtls';

/// Decode a stored/received auth mode, TOLERANTLY.
///
/// `null`, `""`, the legacy `"secure"` spelling and any unrecognized (future)
/// value all read as [kAuthModeToken] — the same rule as
/// `shed_core::token::AuthMode::from_wire`, which the Rust side applies to BOTH
/// the wire value and the stored hint this function decodes. Treating an unknown
/// mode as mtls would put the client on the branch that expects a certificate it
/// cannot have; treating it as token puts it on the branch whose fields are
/// actually populated, and the next mint corrects it either way (plan 001 D5).
///
/// There is deliberately NO schema-version field on the record (plan 002 §D6):
/// tolerance is the migration. A record written before mtls existed simply has
/// no `auth_mode` key and reads as token, which is what it was.
String normalizeAuthMode(Object? raw) =>
    raw is String && raw.trim() == kAuthModeMtls
    ? kAuthModeMtls
    : kAuthModeToken;

/// A persisted server entry (the on-device equivalent of one `~/.shed/config.yaml`
/// server). Holds the pinned TLS fingerprint, the pinned SSH host key, the
/// learned auth mode, and — in token mode only — the last minted control token
/// (the seed). Stored in secure storage.
class ServerRecord {
  const ServerRecord({
    required this.name,
    required this.host,
    required this.sshPort,
    required this.apiUrl,
    required this.tlsCertFingerprint,
    required this.hostKeyPin,
    this.authMode = kAuthModeToken,
    this.controlToken,
    this.controlTokenExpiresAt,
  });

  final String name;
  final String host;
  final int sshPort;
  final String apiUrl;
  final String tlsCertFingerprint;
  final String hostKeyPin;

  /// The credential shape this server last issued: [kAuthModeToken] or
  /// [kAuthModeMtls]. LEARNED, never configured — the server decides at every
  /// mint, and the Rust credential-event stream writes the answer back here
  /// (see `lib/bridge/credential_sink.dart`), which is what makes a live
  /// `auth.mode` flip survive an app restart (plan 002 §7 P1 / AC5).
  ///
  /// It is only ever a HINT on the next launch: it decides whether a stored seed
  /// token is worth planting (a bearer authenticates nothing against an mtls
  /// server), and nothing else.
  final String authMode;

  /// The seed bearer token — token mode only. First persisted at add time
  /// (plan 002 §7 P7's sanctioned add-time crossing) and then REFRESHED on every
  /// adoption the Rust credential-event stream announces (plan 023 §3.5), so a
  /// token-mode cold launch skips a mint however long ago the server was added.
  /// A write-once seed could not: the mint refresh window is 2h5m against a 24h
  /// TTL, so a seed stops being plantable about 22h after it was minted.
  ///
  /// In mtls mode this is always null: the certificate and its private key live
  /// in Rust for the process lifetime and are never persisted (plan 001 D6).
  final String? controlToken;

  /// When [controlToken] stops being plantable. Written and cleared ONLY
  /// alongside it — a fresh bearer beside a stale expiry would make the app
  /// treat a live credential as expired, or an expired one as live.
  final DateTime? controlTokenExpiresAt;

  /// Whether this server is believed to issue client certificates.
  bool get isMtls => authMode == kAuthModeMtls;

  /// Distinguishes "argument omitted" from "argument passed as null" for the
  /// two nullable credential fields. `null` is a MEANINGFUL value for both
  /// (clear it), so a plain `String?` parameter could only ever set, never
  /// clear — the bug that made the seed write-once.
  static const Object _unset = Object();

  /// A copy with a new learned [authMode] and/or new credential material.
  ///
  /// [controlToken] and [controlTokenExpiresAt] are set-or-clear: OMIT one to
  /// keep what is stored, pass a value to set it, pass `null` to clear it. The
  /// three cases the credential sink drives are exactly these — adopting mtls
  /// clears both (a bearer for a server that no longer accepts one is dead
  /// weight in secure storage), adopting a token sets both, and a bare
  /// `ModeChanged` (which carries no credential material at all) passes neither,
  /// so it can neither invent nor erase one.
  ///
  /// The two always travel together; see [controlTokenExpiresAt].
  ServerRecord copyWith({
    String? authMode,
    Object? controlToken = _unset,
    Object? controlTokenExpiresAt = _unset,
  }) => ServerRecord(
    name: name,
    host: host,
    sshPort: sshPort,
    apiUrl: apiUrl,
    tlsCertFingerprint: tlsCertFingerprint,
    hostKeyPin: hostKeyPin,
    authMode: authMode ?? this.authMode,
    controlToken: identical(controlToken, _unset)
        ? this.controlToken
        : controlToken as String?,
    controlTokenExpiresAt: identical(controlTokenExpiresAt, _unset)
        ? this.controlTokenExpiresAt
        : controlTokenExpiresAt as DateTime?,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'host': host,
    'ssh_port': sshPort,
    'api_url': apiUrl,
    'tls_cert_fingerprint': tlsCertFingerprint,
    'host_key_pin': hostKeyPin,
    'auth_mode': authMode,
    if (controlToken != null) 'control_token': controlToken,
    if (controlTokenExpiresAt != null)
      'control_token_expires_at': controlTokenExpiresAt!.toIso8601String(),
  };

  factory ServerRecord.fromJson(Map<String, Object?> j) => ServerRecord(
    name: j['name'] as String,
    host: j['host'] as String,
    sshPort: (j['ssh_port'] as num).toInt(),
    apiUrl: j['api_url'] as String,
    tlsCertFingerprint: j['tls_cert_fingerprint'] as String,
    hostKeyPin: j['host_key_pin'] as String,
    authMode: normalizeAuthMode(j['auth_mode']),
    controlToken: j['control_token'] as String?,
    controlTokenExpiresAt: j['control_token_expires_at'] is String
        ? DateTime.tryParse(j['control_token_expires_at'] as String)
        : null,
  );

  ServerTarget toTarget() => ServerTarget(
    name: name,
    host: host,
    sshPort: sshPort,
    secure: true,
    baseUrl: apiUrl,
    tlsCertFingerprint: tlsCertFingerprint,
    controlToken: controlToken,
    controlTokenExpiresAt: controlTokenExpiresAt,
  );
}
