import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'control/control_token_provider.dart';
import 'control/token_bundle.dart';
import 'keys/key_manager.dart';
import 'net/pinned_http_client.dart';
import 'rc/rc_models.dart';
import 'rc/rc_service.dart';
import 'servers/add_server_flow.dart';
import 'servers/server_record.dart';
import 'servers/server_store.dart';
import 'shed/shed_client.dart';
import 'shed/shed_dtos.dart';
import 'ssh/bootstrap_service.dart';
import 'ssh/host_key_store.dart';
import 'ssh/pty_session.dart';
import 'ssh/ssh_runner.dart';
import 'storage/secret_store.dart';

final secretStoreProvider = Provider<SecretStore>((ref) {
  // Mobile uses the OS keychain/keystore; desktop uses a 0600 file (the macOS
  // keychain entitlement needs a dev cert the ad-hoc local build lacks).
  if (Platform.isAndroid || Platform.isIOS) return FlutterSecureSecretStore();
  final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
  return FileSecretStore('$home/.shed-mobile');
});

final serverStoreProvider = Provider<ServerStore>(
  (ref) => ServerStore(ref.watch(secretStoreProvider)),
);

/// Desktop SSH identity — reuse `~/.ssh/id_ed25519`. M4 adds in-app keygen.
final identitiesProvider = FutureProvider<List<SSHKeyPair>>(
  (ref) async => KeyManager.defaultDesktopKey(),
);

/// TOFU host-key store used by the add-server flow (first contact).
final addHostKeysProvider = Provider<HostKeyStore>((ref) => HostKeyStore());

final addServerFlowProvider = FutureProvider<AddServerFlow>((ref) async {
  final identities = await ref.watch(identitiesProvider.future);
  final hostKeys = ref.watch(addHostKeysProvider);
  return AddServerFlow(
    ref.watch(serverStoreProvider),
    BootstrapService(identities, hostKeys),
    hostKeys,
  );
});

final serversProvider = FutureProvider<List<ServerRecord>>(
  (ref) async => ref.watch(serverStoreProvider).list(),
);

/// A host-key store pinned (non-TOFU) to a saved server's stored fingerprint —
/// the trust anchor shared by every SSH path to that server (mint, RC, PTY).
HostKeyStore pinnedHostKeysFor(ServerRecord rec) => HostKeyStore(
  pins: {'${rec.host}:${rec.sshPort}': rec.hostKeyPin},
  tofu: false,
);

/// Build a ShedClient for a saved server: pinned-TLS HTTP + a token provider
/// whose minter re-mints over SSH (host key verified against the stored pin).
ShedClient _buildShedClient(ServerRecord rec, List<SSHKeyPair> identities) {
  final hostKeys = pinnedHostKeysFor(rec);
  final bootstrap = BootstrapService(identities, hostKeys);
  final target = rec.toTarget();
  final http = PinnedHttpClient(
    host: rec.host,
    port: Uri.parse(rec.apiUrl).port,
    fingerprint: rec.tlsCertFingerprint,
  );
  final tokens = ControlTokenProvider(
    rec.name,
    resolve: () async => target,
    minter: (t) async {
      final b = await bootstrap.mint(t, expectedPin: t.tlsCertFingerprint);
      return MintedToken(b.token, b.expiresAt);
    },
  );
  return ShedClient(http, tokens);
}

final shedClientProvider = FutureProvider.autoDispose
    .family<ShedClient, String>((ref, serverName) async {
      final rec = await ref.watch(serverStoreProvider).get(serverName);
      if (rec == null) throw StateError('unknown server: $serverName');
      final identities = await ref.watch(identitiesProvider.future);
      final client = _buildShedClient(rec, identities);
      ref.onDispose(client.close); // release the pinned HTTP client/socket
      return client;
    });

final shedsProvider = FutureProvider.autoDispose.family<List<Shed>, String>((
  ref,
  serverName,
) async {
  final client = await ref.watch(shedClientProvider(serverName).future);
  return client.listSheds();
});

/// Build an RcService for a (server, shed): SSH as `<shed>@host` (host key pinned
/// to the stored fingerprint) and drive shed-ext-rc. The advisory target label
/// uses the server alias. The named-record key guards against swapping the two
/// same-typed strings (a positional `(String, String)` would not).
typedef ShedRef = ({String serverName, String shedName});

final rcServiceProvider = FutureProvider.autoDispose.family<RcService, ShedRef>(
  (ref, key) async {
    final rec = await ref.watch(serverStoreProvider).get(key.serverName);
    if (rec == null) throw StateError('unknown server: ${key.serverName}');
    final identities = await ref.watch(identitiesProvider.future);
    final runner = SshRunner(
      host: rec.host,
      port: rec.sshPort,
      user: key.shedName,
      identities: identities,
      hostKeys: pinnedHostKeysFor(rec),
    );
    return RcService(
      runner: runner.run,
      shedName: key.shedName,
      serverLabel: rec.name,
    );
  },
);

final rcSessionsProvider = FutureProvider.autoDispose
    .family<List<RcSession>, ShedRef>((ref, key) async {
      final svc = await ref.watch(rcServiceProvider(key).future);
      return svc.list();
    });

/// Build (but don't start) a [PtySession] for attaching a terminal to a shed's RC
/// session. A plain factory — NOT an autoDispose provider — so a one-shot read
/// can't dispose its Ref mid-connect; the terminal screen owns the returned
/// instance's lifecycle. Reads only the stable serverStore/identities providers.
/// Mirrors how [rcServiceProvider] assembles its SshRunner.
Future<PtySession> buildPtySession(
  WidgetRef ref, {
  required String serverName,
  required String shedName,
  required String slug,
}) async {
  final rec = await ref.read(serverStoreProvider).get(serverName);
  if (rec == null) throw StateError('unknown server: $serverName');
  final identities = await ref.read(identitiesProvider.future);
  return PtySession(
    host: rec.host,
    port: rec.sshPort,
    user: shedName,
    identities: identities,
    hostKeys: pinnedHostKeysFor(rec),
    slug: slug,
  );
}
