import '../control/token_bundle.dart';
import '../ssh/bootstrap_service.dart';
import '../ssh/host_key_store.dart';
import 'server_record.dart';
import 'server_store.dart';
import 'server_target.dart';

/// What the user confirms before a server is trusted: the SSH host-key
/// fingerprint and the TLS pin (the latter delivered over the host-key-pinned
/// SSH channel by the mint bundle).
class ServerPreview {
  const ServerPreview({
    required this.host,
    required this.sshPort,
    required this.hostKeyFingerprint,
    required this.bundle,
  });

  final String host;
  final int sshPort;
  final String hostKeyFingerprint;
  final ControlBundle bundle;

  String get apiUrl => 'https://$host:${bundle.httpsPort}';
  String get tlsCertFingerprint => bundle.tlsCertFingerprint;
}

/// Add-server flow. SSH-mints to learn the TLS pin + token (the SSH channel is
/// host-key-pinned), surfaces both fingerprints for the user to confirm, then
/// persists. Trust root = the SSH host key (TOFU on first contact); the TLS pin
/// rides that trusted channel (PLAN §13 S2/S3, adapted for the fat client).
class AddServerFlow {
  AddServerFlow(this.store, this.bootstrap, this.hostKeys);

  final ServerStore store;
  final BootstrapService bootstrap;
  final HostKeyStore hostKeys;

  Future<ServerPreview> preview({
    required String host,
    required int sshPort,
  }) async {
    final bundle = await bootstrap.mint(
      ServerTarget(
        name: host,
        host: host,
        sshPort: sshPort,
        secure: true,
        baseUrl: 'https://$host',
      ),
    );
    final hostKeyFp = hostKeys.pinFor('$host:$sshPort') ?? '(unknown)';
    return ServerPreview(
      host: host,
      sshPort: sshPort,
      hostKeyFingerprint: hostKeyFp,
      bundle: bundle,
    );
  }

  Future<ServerRecord> commit({
    required String name,
    required ServerPreview preview,
  }) async {
    final record = ServerRecord(
      name: name,
      host: preview.host,
      sshPort: preview.sshPort,
      apiUrl: preview.apiUrl,
      tlsCertFingerprint: preview.tlsCertFingerprint,
      hostKeyPin: preview.hostKeyFingerprint,
      controlToken: preview.bundle.token,
      controlTokenExpiresAt: preview.bundle.expiresAt,
    );
    await store.add(record);
    return record;
  }
}
