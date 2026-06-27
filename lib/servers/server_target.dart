/// In-memory view of a configured shed server: how to reach it plus the secret
/// material to authenticate. Mirrors the orchestrator's ServerTarget
/// (apps/api/src/lib/shedConfig.ts). Secret fields never leave the device.
class ServerTarget {
  const ServerTarget({
    required this.name,
    required this.host,
    required this.sshPort,
    required this.secure,
    required this.baseUrl,
    this.tlsCertFingerprint,
    this.controlToken,
    this.controlTokenExpiresAt,
  });

  final String name;
  final String host;
  final int sshPort;

  /// A secure server (the modern shed default) uses pinned-TLS HTTPS + a bearer
  /// control token. Non-secure (legacy plain-HTTP) servers carry no token.
  final bool secure;

  /// Base URL for the shed HTTP API: `https://host:httpsPort` when secure.
  final String baseUrl;

  /// Normalized `sha256:<hex>` pin for the self-signed leaf (secure only).
  final String? tlsCertFingerprint;

  /// Control-token seed (the persisted minted token); may be stale/expired.
  final String? controlToken;
  final DateTime? controlTokenExpiresAt;
}
