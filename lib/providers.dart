import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app_section.dart';
import 'keys/identity_store.dart';
import 'keys/key_manager.dart';
import 'lanes/lane_controller.dart';
import 'lanes/lane_source.dart';
import 'lanes/lane_state.dart';
import 'servers/add_server_flow.dart';
import 'servers/server_record.dart';
import 'machines/machine_feed.dart';
import 'machines/machine_record.dart';
import 'machines/machine_store.dart';
import 'machines/roost_bootstrap_flow.dart';
import 'servers/server_store.dart';
import 'src/rust/api/client.dart';
import 'src/rust/api/dto.dart';
import 'src/rust/api/dto_lane.dart';
import 'src/rust/api/error.dart';
import 'ssh/host_key_store.dart';
import 'ssh/pty_session.dart';
import 'ssh/roost_entitlement.dart';
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

/// The add-server flow. Synchronous now: the SSH mint it drives runs through the
/// app-scoped mint sink (which resolves the identities itself), so the flow needs
/// only the store and the TOFU host-key store the preview's SSH leg pins into.
final addServerFlowProvider = Provider<AddServerFlow>(
  (ref) => AddServerFlow(
    ref.watch(serverStoreProvider),
    ref.watch(addHostKeysProvider),
  ),
);

/// Servers whose credential the Rust provider has ADOPTED in this app session,
/// fed by `CredentialSink`. Two consumers:
///
/// * the per-host overview timeout below — the FIRST authenticated call of a
///   session may have to run a whole SSH enrollment first, and must not lose to
///   a bound sized for the steady state;
/// * the "enrolling certificate" state on the host card (plan 002 §7 P8).
///
/// Monotonic and session-scoped: it never un-marks a server, and it is not
/// persisted (it answers "has this process minted yet?", not "what mode is this
/// server?" — that is `ServerRecord.authMode`).
final adoptedServersProvider =
    NotifierProvider<AdoptedServersNotifier, Set<String>>(
      AdoptedServersNotifier.new,
    );

class AdoptedServersNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void markAdopted(String server) {
    if (state.contains(server)) return;
    state = {...state, server};
  }
}

final serversProvider = FutureProvider<List<ServerRecord>>(
  (ref) async => ref.watch(serverStoreProvider).list(),
);

/// A host-key store pinned (non-TOFU) to a saved server's stored fingerprint —
/// the trust anchor shared by every SSH path to that server (mint, RC, PTY).
HostKeyStore pinnedHostKeysFor(ServerRecord rec) => HostKeyStore(
  pins: {'${rec.host}:${rec.sshPort}': rec.hostKeyPin},
  tofu: false,
);

/// Build a [BridgeClient] for a saved server: a pinned-TLS, provider-backed
/// shed-core HTTP client (FRB). The transport identity (base URL, pin, SSH
/// host/port) is immutable per client; the token FSM lives in Rust and mints via
/// the app-scoped mint sink (see `lib/bridge/mint_sink.dart`). The persisted
/// control token seeds the provider so the first request can skip a mint.
Future<BridgeClient> _buildBridgeClient(ServerRecord rec) {
  // A stored bearer is meaningless for a server the app believes issues
  // certificates, so it is not even handed across the bridge. Rust applies the
  // same rule to whatever it receives (`AuthMode::from_wire` + the seed gate);
  // this keeps the crossing itself minimal.
  final seed = rec.isMtls ? null : rec.controlToken;
  final seedExpiry = rec.controlTokenExpiresAt;
  return BridgeClient.connect(
    baseUrl: rec.apiUrl,
    serverName: rec.name,
    host: rec.host,
    sshPort: rec.sshPort,
    tlsPin: rec.tlsCertFingerprint,
    // A HINT, never a switch: whatever the server issues at the next mint wins,
    // and the credential-event stream writes the answer back to the record.
    authMode: rec.authMode,
    seedToken: seed,
    seedExpiryUnix: (seed != null && seedExpiry != null)
        ? BigInt.from(seedExpiry.millisecondsSinceEpoch ~/ 1000)
        : null,
  );
}

/// One [BridgeClient] per saved server, keyed by name (autoDispose.family). A
/// server-record change (host/port/pin) rebuilds it because a new client is
/// constructed from the freshly-read record. Disposed on last-listener-gone.
final shedClientProvider = FutureProvider.autoDispose
    .family<BridgeClient, String>((ref, serverName) async {
      final rec = await ref.watch(serverStoreProvider).get(serverName);
      if (rec == null) throw StateError('unknown server: $serverName');
      final client = await _buildBridgeClient(rec);
      // Explicitly drop the Rust-owned opaque on dispose (the finalizer is the
      // backstop). A double dispose is a no-op.
      ref.onDispose(() {
        if (!client.isDisposed) client.dispose();
      });
      return client;
    });

final shedsProvider = FutureProvider.autoDispose
    .family<List<BridgeShed>, String>((ref, serverName) async {
      final client = await ref.watch(shedClientProvider(serverName).future);
      return client.listSheds();
    });

/// Image variants available on a server (`GET /api/images`), for the create-shed
/// Image picker. Never blocks creation — the picker falls back to "(server
/// default)" if this errors.
final imagesProvider = FutureProvider.autoDispose
    .family<List<BridgeShedImage>, String>((ref, serverName) async {
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

/// The bound for a host's FIRST authenticated call of the session (plan 002
/// §7 P8's budget alignment).
///
/// 12 s is a steady-state bound: it assumes a credential is already held, so the
/// call is one HTTPS round-trip. The first call of a session may instead have to
/// run a full enrollment first — a `_bootstrap` SSH dial + remote exec, which
/// Dart bounds at 15 s (`BootstrapService.timeout`) — and then the real request.
/// A valid-but-slow mtls enrollment would lose to a 12 s outer bound every time,
/// which would present a HEALTHY server as unreachable.
///
/// So the first call gets a bound that strictly dominates the SSH leg that
/// actually gates it (15 s + the request + margin), and the steady state keeps
/// its fast 12 s failure so an offline host still degrades quickly. This is
/// mode-independent on purpose: a token-mode host with an expired seed mints on
/// its first call too, and had exactly the same latent problem.
///
/// Rust's own 45 s mint timeout stays a pure backstop above both — it can only
/// fire if the Dart sink never answers at all, and cancelling this call aborts
/// the Rust request (and frees its parked mint) via the abort-on-drop guard.
const _enrollingFanoutTimeout = Duration(seconds: 30);

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
  final BridgeOverview overview;
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
      // read, not watch: the bound is decided once per call. Watching would make
      // every host's first adoption invalidate every other host's overview.
      final enrolled = ref.read(adoptedServersProvider).contains(serverName);
      final bound = enrolled ? _hostFanoutTimeout : _enrollingFanoutTimeout;
      try {
        return OverviewData(await client.overview().timeout(bound));
      } on BridgeError_BadStatus catch (e) {
        // A top-level 404 can only mean the /api/overview route doesn't exist
        // (server too old) — the terminal upgrade-required value, never retried.
        if (e.code == 404) return const OverviewUnsupported();
        rethrow;
      }
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

/// One shed on one host — the key every per-shed provider families on. A named
/// record, so the family key compares structurally and the two same-typed
/// strings cannot be swapped by accident (a positional `(String, String)`
/// would not catch it).
typedef ShedRef = ({String serverName, String shedName});

/// Build (but don't start) a [PtySession] for attaching a terminal to a shed's RC
/// session. A plain factory — NOT an autoDispose provider — so a one-shot read
/// can't dispose its Ref mid-connect; the terminal screen owns the returned
/// instance's lifecycle. Reads only the stable serverStore/identities providers.
/// Mirrors how [roostDialFor] assembles a feed's SSH identity.
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

// ---------------------------------------------------------------------------
// Machines (plan 012, roadmap R4)
// ---------------------------------------------------------------------------

/// The device's configured machines — native hosts reached over SSH, each
/// running a `roost-session` the phone reads through the shared Rust client.
final machineStoreProvider = Provider<MachineStore>(
  (ref) => MachineStore(ref.watch(secretStoreProvider)),
);

final machinesProvider = FutureProvider<List<MachineRecord>>(
  (ref) async => ref.watch(machineStoreProvider).list(),
);

/// The ONE trust-on-first-use host-key store every machine connection shares —
/// the feed's tunnel, its one-shot execs, and the terminal's PTY.
///
/// A machine is an ordinary SSH host with no endpoint that publishes a
/// fingerprint (a shed server has `/api/ssh-host-key`; a machine has nothing),
/// so first use is the only moment a key can be learned. Sharing ONE store is
/// what makes that mean anything: a per-connection store starts empty every
/// time, accepts whatever answers, and pins it somewhere nobody reads — TOFU
/// with no memory, which is just "trust anything" wearing a better name.
///
/// Not `autoDispose`, for the same reason. Still in-memory only, so the trust
/// resets when the app does; persisting it is a separate change (it wants a
/// user-visible "this machine's key changed" story, not a silent upgrade).
final machineHostKeysProvider = Provider<HostKeyStore>(
  (ref) => HostKeyStore(tofu: true),
);

/// **Which machines THIS APP RUN bootstrapped** — the one claim that decides
/// whether a machine's watcher keeps its agent hooks wired (plan 020 §3.3).
///
/// Not `autoDispose`, and for a sharper reason than the store above: every
/// reader IS `autoDispose`. A `MachineFeed` dies when the user leaves the
/// screen and the phone tears one down on every background, so a claim kept
/// anywhere nearer the feed would be forgotten by the next foreground — and the
/// install that earned it would never be honoured again.
///
/// In memory only, and deliberately never persisted: see
/// [RoostBootstrapEntitlements].
final roostEntitlementsProvider = Provider<RoostBootstrapEntitlements>(
  (ref) => RoostBootstrapEntitlements(),
);

/// **The ORIGIN key** every per-feed provider families on — a configured
/// machine, or a shed on a saved host (plan 022 S6).
///
/// A bare string is a MACHINE NAME, which is what the key has always meant;
/// `shed:<server>/<shed>` is a shed. Two reasons the shed case rides the same
/// key rather than a second family:
///
/// * **It is the same feed.** After S6 a shed's agent sessions are roost tabs
///   read over an SSH tunnel — the identical mechanism a machine's rows come
///   from, with a different login and a pinned host key. The object, the
///   watcher, the tunnel and the state are unchanged.
/// * **Everything keyed on "which feed" works for both for free.** The lane
///   (`LaneRef.machine`) and the read-only peek (`RoostPeekScreen.machineName`)
///   both address a feed by this string, so a shed row gets a transcript and a
///   peek with no second code path.
///
/// A configured machine literally named `shed:…` would collide. Machine names
/// come from the add-machine form, the prefix is stated here, and the
/// alternative (a sealed key type) would change `LaneRef` and every override in
/// the test suite for a collision nobody can hit by accident.
const String shedOriginPrefix = 'shed:';

/// Why a machine may not be called [name], or null when it may.
///
/// A machine's name IS its feed origin, and `shed:<server>/<shed>` is a shed's
/// ([shedFeedKey]). Nothing else separates the two namespaces, so a machine
/// named `shed:h/proj` resolves to that shed: same provider key, same feed,
/// same controls — and the machine's own host and user are never dialled.
/// Ending a session from the machine's list would end the shed's.
///
/// Pure and exported so the rule is testable without driving the form, and so
/// any future entry point for a machine name has one place to ask.
String? machineNameError(String name) {
  if (name.startsWith(shedOriginPrefix)) {
    return 'A machine name cannot start with "$shedOriginPrefix" — '
        'that prefix names a shed.';
  }
  return null;
}

/// The feed origin for one shed. See [shedOriginPrefix].
String shedFeedKey(String serverName, String shedName) =>
    '$shedOriginPrefix$serverName/$shedName';

/// The shed a feed origin names, or null when it names a machine.
///
/// Splits on the LAST `/`. A shed name cannot contain one — shed validates it
/// as `^[a-z][a-z0-9-]*[a-z0-9]$` (`internal/config/types.go:84`) — while a
/// server alias is free-form and unconstrained (shed says so in as many words
/// at `internal/config/clientcreds_test.go:248`, which is why it escapes the
/// name before putting it in a path). So in `shed:a/b/c` the only parse that
/// can be real is the server `a/b` and the shed `c`: `b/c` is not a name any
/// shed could have. A left-split reads the server as `a`, which either fails
/// closed on an unknown server or — if a server really is named `a` — dials
/// THE WRONG SERVER.
ShedRef? parseShedFeedKey(String origin) {
  if (!origin.startsWith(shedOriginPrefix)) return null;
  final rest = origin.substring(shedOriginPrefix.length);
  final slash = rest.lastIndexOf('/');
  if (slash <= 0 || slash == rest.length - 1) return null;
  return (
    serverName: rest.substring(0, slash),
    shedName: rest.substring(slash + 1),
  );
}

/// **What one feed origin dials** — the record and the host-key store, as a
/// pure function of the saved hosts (plan 022 S6).
///
/// Pure, and extracted for the reason `foldRoostUpdate` and `roostOfferFor`
/// are: it is the whole of the difference between a shed feed and a machine
/// feed, it breaks silently in production when it is wrong (a wrong user or
/// port is a connection that lands somewhere else entirely), and inside the
/// provider it could only be checked by building a [MachineFeed] — which calls
/// `roostCapabilities()` and therefore needs the native library. Here it is a
/// table.
///
/// The two arms:
///
/// * **A shed** is reached as `<shed>@<server host>` on the SERVER's sshd —
///   that is how shed-server routes a connection into the right VM (the same
///   login [buildPtySession] uses). Its host key is PINNED to the fingerprint
///   the add-host flow stored, never TOFU: a shed server publishes its key over
///   `/api/ssh-host-key`, so there is nothing to trust on first use. An UNKNOWN
///   server yields no pins and `tofu: false`, so the dial fails closed with a
///   host-key error rather than trusting whatever answers.
/// * **A machine** keeps the record the user configured and the SHARED TOFU
///   store — see [machineHostKeysProvider] for why a per-feed store would be
///   TOFU in name only.
({MachineRecord record, HostKeyStore hostKeys}) roostDialFor({
  required String origin,
  required List<ServerRecord> servers,
  required List<MachineRecord> machines,
  required HostKeyStore machineHostKeys,
}) {
  final shed = parseShedFeedKey(origin);
  if (shed == null) {
    return (
      record: machines.firstWhere(
        (m) => m.name == origin,
        orElse: () => MachineRecord(name: origin, host: origin),
      ),
      hostKeys: machineHostKeys,
    );
  }
  final rec = servers.where((s) => s.name == shed.serverName).firstOrNull;
  return (
    record: MachineRecord(
      // The ORIGIN, not the shed name: this string labels the tunnel, the
      // watcher and every error the feed raises, and two servers may well both
      // have a shed called `proj`.
      name: origin,
      host: rec?.host ?? shed.serverName,
      user: shed.shedName,
      sshPort: rec?.sshPort ?? 22,
    ),
    hostKeys: rec == null ? HostKeyStore(tofu: false) : pinnedHostKeysFor(rec),
  );
}

/// One origin's live feed — the SSH tunnel plus the shared Rust roost watcher.
///
/// Split in two on purpose: this provider owns the FEED OBJECT (so `create` and
/// `kill` have something to call), and [machineFeedProvider] exposes its state
/// stream (so the UI rebuilds). One provider returning a stream could not offer
/// those verbs without the UI reaching around it.
///
/// `autoDispose` with an explicit `onDispose` teardown, deliberately: the feed
/// owns an SSH connection and a poll loop, and leaving those alive behind a
/// screen the user has left is what drains a phone's battery. Losing them costs
/// nothing — roost's `tab.list` is authoritative, so reconnecting is a complete
/// resync.
final machineFeedControllerProvider = Provider.autoDispose
    .family<MachineFeed, String>((ref, origin) {
      // Read the already-resolved values: this provider is only reached from a
      // widget that has a live feed, which means the futures have completed.
      final dial = roostDialFor(
        origin: origin,
        servers: ref.watch(serversProvider).value ?? const <ServerRecord>[],
        machines: ref.watch(machinesProvider).value ?? const <MachineRecord>[],
        machineHostKeys: ref.watch(machineHostKeysProvider),
      );
      final feed = MachineFeed(
        machine: dial.record,
        identities: ref.watch(identitiesProvider).value ?? const <SSHKeyPair>[],
        hostKeys: dial.hostKeys,
        // Shared because this feed is `autoDispose` and the claim is the app
        // run's, not this object's.
        entitlements: ref.watch(roostEntitlementsProvider),
      );
      ref.onDispose(feed.dispose);
      return feed;
    });

/// One origin's live state stream.
final machineFeedProvider = StreamProvider.autoDispose
    .family<MachineFeedState, String>((ref, origin) async* {
      // Ensure the record source + identity are loaded before building the
      // feed, so the controller reads resolved values rather than empty
      // defaults.
      if (parseShedFeedKey(origin) != null) {
        await ref.watch(serversProvider.future);
      } else {
        await ref.watch(machinesProvider.future);
      }
      await ref.watch(identitiesProvider.future);
      final feed = ref.watch(machineFeedControllerProvider(origin));
      unawaited(feed.start());
      yield feed.state;
      yield* feed.updates;
    });

/// **One machine's bootstrap flow** — the probe and install verbs the machine
/// card's install/start affordance drives (plan 020 §3.8, commit C-M4).
///
/// **This wiring is the commit's load-bearing line.** `drive` is a tear-off of
/// [MachineFeed.runBootstrap] and must stay one: a completed install is the
/// only thing that entitles this app run to keep the machine's agent hooks
/// wired, and `runBootstrap` is where that claim is recorded and the machine's
/// watcher re-spawned to honour it. Assembling a `RoostBootstrapRunner` here
/// instead would drive exactly the same install and silently lose the hook
/// re-send on the one machine that just earned it — plan 019's defect, one
/// level up. `integration_test/roost_bootstrap_drive_test.dart` fails if this
/// line stops going through the feed.
///
/// `autoDispose.family`, like every other per-machine provider: it holds the
/// feed controller alive while a card is offering to bootstrap, and lets both
/// go when the screen does.
final roostBootstrapFlowProvider = Provider.autoDispose
    .family<RoostBootstrapFlow, String>((ref, name) {
      final feed = ref.watch(machineFeedControllerProvider(name));
      return RoostBootstrapFlow(
        target: name,
        // Read at CALL time, not captured: the tunnel comes and goes with the
        // feed, and a port read when this object was built may since have been
        // closed and rebound.
        localPort: () => feed.tunnelPort,
        drive: feed.runBootstrap,
      );
    });

// ---------------------------------------------------------------------------
// Agent lanes (plan 018 §3.11, roost pivot S4m)
// ---------------------------------------------------------------------------

/// One lane's address: the machine, and the ROW's slug (roost's tab id).
///
/// **The slug, not the agent session id.** The session id is part of the stamp
/// being reconciled — a tab that restarts comes back with a new one — so it
/// cannot also be the key that has to survive a change to it. A record, so the
/// family key compares structurally (the [ShedRef] convention).
typedef LaneRef = ({String machine, String slug});

/// One row's agent-lane stamp, or null when the machine's rows no longer carry
/// this session at all.
@visibleForTesting
BridgeAgentLaneStamp? laneStampFor(MachineFeedState state, String slug) {
  for (final s in state.sessions) {
    if (s.slug == slug) return s.agentLane;
  }
  return null;
}

/// The stamp stream [LaneController.reconcile] consumes.
///
/// **Only AUTHORITATIVE states count.** A feed that has never connected carries
/// no rows at all, and mapping that to "the row is gone" would abandon every
/// lane during the first second of a cold start. `foldRoostUpdate` keeps the
/// rows across a `Down`, so once `connectedOnce` is true an absent row is a
/// real absence — which is exactly when a lane should stop retrying.
@visibleForTesting
Stream<BridgeAgentLaneStamp?> laneStamps(
  Stream<MachineFeedState> updates,
  String slug,
) => updates
    .where((s) => s.connectedOnce)
    .map((s) => laneStampFor(s, slug))
    .distinct();

/// How a lane reaches its agent server. **Production is always
/// [LaneReach.machine]**; [LaneReach.local] exists for one overriding caller,
/// the hermetic integration harness.
///
/// **Never infer this from the machine's host.** An earlier version of this
/// seam was a `laneReachFor(MachineRecord)` that answered [LaneReach.local] for
/// `localhost`/`127.0.0.1`/`::1`, reasoning that a machine dialled at a
/// loopback address is this device, so its `127.0.0.1:<port>` IS our
/// `127.0.0.1:<port>`. That inference is false whenever SSH on loopback leads
/// somewhere else, and the canonical case is the one a shed developer hits
/// first: a **shed VM** is reached at `localhost:2222`, which is the shed
/// *server's* sshd on this host, and it routes into a Firecracker/VZ microVM
/// that has a loopback of its own. The agent's `127.0.0.1:2421` inside that VM
/// is emphatically not this device's `127.0.0.1:2421`. A container, a published
/// Docker port and a jump port all break the same way.
///
/// Proven live, not argued: one shed VM — same gx session, same everything —
/// registered twice under two host spellings. As `localhost` the lane took the
/// local branch, made no forward, and sat at `generation=0` forever with
/// "Reconnecting: the gx lane at http://127.0.0.1:2421 is closed". As
/// `192.168.86.42` — the same sshd, the same VM — it forwarded, reached
/// `generation=1`, and send/approve/interject/cancel all worked. A hostname
/// cannot tell those two apart, so nothing here tries.
///
/// Defaulting to [LaneReach.machine] is wrong nowhere: a forward to a genuinely
/// local agent still works, at the cost of one extra hop through the machine's
/// own SSH connection, which the feed is already holding open.
final laneReachProvider = Provider<LaneReach>((ref) => LaneReach.machine);

/// The lane bridge, as one overridable seam.
///
/// A provider rather than a bare `const BridgeLaneSource()` inside the
/// controller provider, for the [rcWatcherBridgeProvider] reason: the whole
/// point of [LaneSource] is that a widget test can stub the bridge, and it can
/// only do that if there is somewhere to hand the stub in.
final laneSourceProvider = Provider<LaneSource>(
  (ref) => const BridgeLaneSource(),
);

/// **One lane per row** — the guarantee that lives HERE and nowhere else.
///
/// The bridge has no registry: two `lane_open` calls are two lanes, two
/// subscriptions and two adapters against one agent. So the de-duplication is
/// the provider's, and `autoDispose.family` is the whole mechanism — two
/// screens watching one [LaneRef] share one [LaneController], and the last
/// listener leaving closes it.
///
/// It watches [machineFeedControllerProvider] so a live lane keeps the machine's
/// feed, its one SSH client and its forwards alive, and *listens* to
/// [machineFeedProvider] rather than watching it: the state stream is what
/// starts the feed (a lane's forward needs the tunnel up), but watching it would
/// rebuild this provider — and therefore the controller — on every roost poll,
/// which is precisely the guarantee above, broken.
///
/// Throws when the row carries no lane. Unreachable from the UI, which offers
/// the transcript affordance only for a row whose `agentLane` is non-null, and
/// an honest error rather than a controller that silently never opens.
final laneControllerProvider = Provider.autoDispose
    .family<LaneController, LaneRef>((ref, key) {
      final feed = ref.watch(machineFeedControllerProvider(key.machine));
      ref.listen(machineFeedProvider(key.machine), (_, _) {});
      final stamp = laneStampFor(feed.state, key.slug);
      if (stamp == null) {
        throw StateError('no agent lane on ${key.machine}/${key.slug}');
      }
      final controller = LaneController(
        machine: key.machine,
        slug: key.slug,
        stamp: stamp,
        source: ref.watch(laneSourceProvider),
        // The feed owns the SSH connection every lane call rides — the probe
        // and the forward both go through it, so a lane costs no second link.
        probe: feed.probe,
        reach: ref.watch(laneReachProvider),
        acquireForward: feed.acquireForward,
        stamps: laneStamps(feed.updates, key.slug),
      );
      ref.onDispose(controller.close);
      return controller;
    });

/// One lane's live state stream.
///
/// Split from [laneControllerProvider] for the reason
/// [machineFeedControllerProvider] is split from [machineFeedProvider]: the
/// verbs need an object to call, the UI needs a stream to rebuild on, and one
/// provider returning a stream could not offer both without the UI reaching
/// around it.
final laneStateProvider = StreamProvider.autoDispose.family<LaneState, LaneRef>(
  (ref, key) async* {
    // Resolved before the controller is built, so the feed it reads is
    // holding the real machine record and identity rather than the empty
    // defaults.
    await ref.watch(machinesProvider.future);
    await ref.watch(identitiesProvider.future);
    final controller = ref.watch(laneControllerProvider(key));
    // **Subscribed before `open()` can emit.** `controller.updates` is a
    // BROADCAST stream and buffers nothing, and an `async*` body pauses at
    // `yield controller.state` before it ever reaches `yield*`'s own subscribe
    // — so an emission landing in that gap was dropped and the screen kept the
    // pre-open state until something else changed. This relay is a
    // single-subscription controller, which DOES buffer before its listener
    // attaches, so the window closes with nothing but `dart:async`.
    final relay = StreamController<LaneState>();
    final sub = controller.updates.listen(
      relay.add,
      onError: relay.addError,
      onDone: relay.close,
      cancelOnError: false,
    );
    ref.onDispose(() {
      sub.cancel();
      relay.close();
    });
    unawaited(controller.open());
    yield controller.state;
    yield* relay.stream;
  },
);
