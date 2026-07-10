import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app_section.dart';
import 'control/control_token_provider.dart';
import 'control/token_bundle.dart';
import 'core/app_error.dart';
import 'keys/identity_store.dart';
import 'keys/key_manager.dart';
import 'net/pinned_http_client.dart';
import 'rc/rc_capabilities.dart';
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

/// Mobile (Android/iOS) vs desktop — the two platforms diverge on secret storage
/// and identity source. One definition so the branch can't drift.
bool get _isMobile => Platform.isAndroid || Platform.isIOS;

final secretStoreProvider = Provider<SecretStore>((ref) {
  // Mobile uses the OS keychain/keystore; desktop uses a 0600 file (the macOS
  // keychain entitlement needs a dev cert the ad-hoc local build lacks).
  if (_isMobile) return FlutterSecureSecretStore();
  final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
  return FileSecretStore('$home/.shed-mobile');
});

final serverStoreProvider = Provider<ServerStore>(
  (ref) => ServerStore(ref.watch(secretStoreProvider)),
);

/// The device's in-app identity store (mobile keygen). Backed by secure storage.
final identityStoreProvider = Provider<IdentityStore>(
  (ref) => IdentityStore(ref.watch(secretStoreProvider)),
);

/// SSH identity. Desktop reuses `~/.ssh/id_ed25519`; mobile loads the in-app
/// generated key from secure storage (the onboarding flow generates it first, so
/// this throws a StateError on mobile until then — gated by
/// [needsOnboardingProvider]).
final identitiesProvider = FutureProvider<List<SSHKeyPair>>((ref) async {
  if (_isMobile) return ref.watch(identityStoreProvider).load();
  return KeyManager.defaultDesktopKey();
});

/// Whether to route to the keygen onboarding screen. Mobile-only: true until an
/// in-app key has been generated. Desktop reuses `~/.ssh/id_ed25519` (a missing
/// key there surfaces as a connection error, not an onboarding loop — desktop
/// onboarding would write to the wrong place), so this is always false on desktop.
final needsOnboardingProvider = FutureProvider<bool>((ref) async {
  if (!_isMobile) return false;
  return !await ref.watch(identityStoreProvider).hasKey();
});

/// Whether the device key can be (re)generated in-app — mobile only (desktop
/// reuses `~/.ssh`). Exposed as a provider so the platform branch stays out of
/// widget build methods (and is overridable in tests).
final canRegenerateKeyProvider = Provider<bool>((ref) => _isMobile);

/// The device's PUBLIC identity (authorized_keys line + `SHA256:` fingerprint),
/// for the identity screen. Public material only — never the private key. Mobile
/// reads the stored public line; desktop derives the public half of the first
/// `~/.ssh` identity. Null when no key is available or the stored line is
/// unparseable.
final publicIdentityProvider = FutureProvider.autoDispose<PublicIdentity?>((
  ref,
) async {
  if (_isMobile) {
    final line = await ref.watch(identityStoreProvider).authorizedKey();
    if (line == null) return null;
    try {
      return PublicIdentity.fromAuthorizedKeyLine(line);
    } on FormatException {
      return null;
    }
  }
  final identities = await ref.watch(identitiesProvider.future);
  if (identities.isEmpty) return null;
  return PublicIdentity.fromBlob(
    identities.first.toPublicKey().encode(),
    comment: 'desktop (~/.ssh)',
  );
});

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

/// Image variants available on a server (`GET /api/images`), for the create-shed
/// Image picker. Never blocks creation — the picker falls back to "(server
/// default)" if this errors.
final imagesProvider = FutureProvider.autoDispose
    .family<List<ImageInfo>, String>((ref, serverName) async {
      final client = await ref.watch(shedClientProvider(serverName).future);
      return client.listImages();
    });

/// The selected top-level section. Shared by both layouts (mobile bottom tabs /
/// desktop sidebar), which each render all three sections directly. Both land on
/// Hosts.
final appSectionProvider = NotifierProvider<AppSectionNotifier, AppSection>(
  AppSectionNotifier.new,
);

class AppSectionNotifier extends Notifier<AppSection> {
  @override
  AppSection build() => AppSection.hosts;

  void select(AppSection section) => state = section;
}

/// Bound on a single host's overview call so one slow/offline host (e.g. a hung
/// TLS handshake) can't pin its group in a perpetual spinner — the per-host
/// [AsyncValue] fails to an "unreachable" card instead. The cross-host views
/// render one group per host, each watching its own per-host provider, so hosts
/// fill in independently rather than all-or-nothing.
const _hostFanoutTimeout = Duration(seconds: 12);

/// The outcome of one host's overview fetch. Sealed so the old-server case is a
/// terminal VALUE the views render as a "needs upgrade" card, not a retryable
/// error: Riverpod 3 auto-retries thrown `Exception`s, and a server that
/// predates GET /api/overview will never start serving it mid-session — leaving
/// it an error would flicker the card and re-poll a server that can't change.
/// Genuine transport errors still throw (retry stays useful for those).
sealed class OverviewResult {
  const OverviewResult();
}

/// A served overview snapshot.
class OverviewData extends OverviewResult {
  const OverviewData(this.overview);
  final Overview overview;
}

/// The server predates GET /api/overview (404 on the route) — the Hosts and
/// Sessions views hard-require an upgraded server (the breaking posture) and
/// render a clear upgrade card, never silent emptiness.
class OverviewUnsupported extends OverviewResult {
  const OverviewUnsupported();
}

/// One host's whole snapshot in a single `GET /api/overview`: server features +
/// disk usage + every shed with its rc-enriched sessions and capabilities. This
/// replaces the former `shedsProvider` + `hostSystemDfProvider` +
/// per-shed-SSH-`shed-ext-rc-list` fan-out that drove the Hosts and Sessions
/// views. A server too old to serve the route responds 404, which resolves to
/// the TERMINAL [OverviewUnsupported] value (the route is top-level, so a 404
/// can only mean the endpoint doesn't exist); transport errors throw.
final overviewProvider = FutureProvider.autoDispose
    .family<OverviewResult, String>((ref, serverName) async {
      final client = await ref.watch(shedClientProvider(serverName).future);
      try {
        return OverviewData(
          await client.fetchOverview().timeout(_hostFanoutTimeout),
        );
      } on AppError catch (e) {
        if (e.statusCode == 404) return const OverviewUnsupported();
        rethrow;
      }
    });

/// One (shed, rc session) pair on a host — the cross-host Sessions view's unit.
typedef ShedSession = ({String shedName, RcSession session});

/// Flatten an overview into the Sessions view's (shed, session) pairs — the
/// server rc-enriches the sessions, and a stopped shed contributes none. The
/// pure core of what replaced the per-shed SSH fan-out (SSH now stays only for
/// terminal attach, RcService create/kill/prompt, and token mint).
List<ShedSession> shedSessionPairs(Overview overview) => [
  for (final s in overview.sheds)
    for (final sess in s.sessions) (shedName: s.shed.name, session: sess),
];

/// The rc capabilities of one shed, read from the host overview (a single call
/// shared with the Hosts/Sessions views). Null when the shed is absent/stopped,
/// the server reported no caps, or the server predates /api/overview
/// ([OverviewUnsupported]) — the create form treats all of those as "absent" and
/// falls back to its safe base (claude + shell). A real transport error bubbles
/// so the form can degrade to the base too.
final shedCapabilitiesProvider = FutureProvider.autoDispose
    .family<RcCapabilities?, ShedRef>((ref, key) async {
      final result = await ref.watch(overviewProvider(key.serverName).future);
      if (result is! OverviewData) return null; // old server → absent caps
      for (final s in result.overview.sheds) {
        if (s.shed.name == key.shedName) return s.capabilities;
      }
      return null;
    });

/// Refresh everything the Hosts section renders: the saved-host list plus each
/// host's overview (reachability + shed summary + disk usage + sessions). Shared
/// by the mobile Hosts screen and the desktop Hosts pane so "what a Hosts refresh
/// means" lives in one place.
void invalidateHosts(WidgetRef ref) {
  ref.invalidate(serversProvider);
  ref.invalidate(overviewProvider);
}

/// Refetch everything that renders one host's sheds after a shed mutation
/// (create/start/stop/restart/delete) or an explicit refresh: the per-host shed
/// list AND the host overview (the Hosts and Sessions views render from
/// [overviewProvider] now, so invalidating only [shedsProvider] would leave them
/// stale). The single home for "a shed changed on this server" — use it
/// everywhere [shedsProvider] used to be invalidated alone.
void invalidateShedViews(WidgetRef ref, String serverName) {
  ref.invalidate(shedsProvider(serverName));
  ref.invalidate(overviewProvider(serverName));
}

/// Build an RcService for a (server, shed): SSH as `<shed>@host` (host key pinned
/// to the stored fingerprint) and drive shed-ext-rc. The advisory target label
/// uses the server alias. The named-record key guards against swapping the two
/// same-typed strings (a positional `(String, String)` would not).
typedef ShedRef = ({String serverName, String shedName});

/// Build an RcService for a (server, shed): SSH as `<shed>@host` (host key pinned
/// to the stored fingerprint) and drive shed-ext-rc. A plain factory reading only
/// the stable serverStore/identities providers (like [buildPtySession]) so the
/// cross-host fan-out can call it directly without the autoDispose-disposed-during
/// -load race a one-shot `ref.read(rcServiceProvider.future)` would hit.
/// Assemble an RcService from an already-resolved server record + identities, so
/// the cross-host fan-out can resolve those once and reuse them across a host's
/// sheds (rather than re-reading the keychain/server list per shed).
RcService rcServiceFor(
  ServerRecord rec,
  List<SSHKeyPair> identities,
  String shedName,
) {
  final runner = SshRunner(
    host: rec.host,
    port: rec.sshPort,
    user: shedName,
    identities: identities,
    hostKeys: pinnedHostKeysFor(rec),
  );
  return RcService(
    runner: runner.run,
    shedName: shedName,
    serverLabel: rec.name,
  );
}

Future<RcService> buildRcService(Ref ref, ShedRef key) async {
  final rec = await ref.read(serverStoreProvider).get(key.serverName);
  if (rec == null) throw StateError('unknown server: ${key.serverName}');
  final identities = await ref.read(identitiesProvider.future);
  return rcServiceFor(rec, identities, key.shedName);
}

final rcServiceProvider = FutureProvider.autoDispose.family<RcService, ShedRef>(
  (ref, key) => buildRcService(ref, key),
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
