import 'server_target.dart';

/// A persisted server entry (the on-device equivalent of one `~/.shed/config.yaml`
/// server). Holds the pinned TLS fingerprint, the pinned SSH host key, and the
/// last minted control token (the seed). Stored in secure storage.
class ServerRecord {
  const ServerRecord({
    required this.name,
    required this.host,
    required this.sshPort,
    required this.apiUrl,
    required this.tlsCertFingerprint,
    required this.hostKeyPin,
    this.controlToken,
    this.controlTokenExpiresAt,
  });

  final String name;
  final String host;
  final int sshPort;
  final String apiUrl;
  final String tlsCertFingerprint;
  final String hostKeyPin;
  final String? controlToken;
  final DateTime? controlTokenExpiresAt;

  Map<String, Object?> toJson() => {
    'name': name,
    'host': host,
    'ssh_port': sshPort,
    'api_url': apiUrl,
    'tls_cert_fingerprint': tlsCertFingerprint,
    'host_key_pin': hostKeyPin,
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
