import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app_section.dart';
import 'keys/identity_store.dart';
import 'keys/key_manager.dart';
import 'rc/activity_overlay.dart';
import 'rc/rc_service.dart';
import 'servers/add_server_flow.dart';
import 'servers/server_record.dart';
import 'servers/server_store.dart';
import 'src/rust/api/client.dart';
import 'src/rust/api/dto.dart';
import 'src/rust/api/dto_rc.dart';
import 'src/rust/api/error.dart';
import 'src/rust/api/watcher.dart';
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

/// Build a [BridgeClient] for a saved server: a pinned-TLS, provider-backed
/// shed-core HTTP client (FRB). The transport identity (base URL, pin, SSH
/// host/port) is immutable per client; the token FSM lives in Rust and mints via
/// the app-scoped mint sink (see `lib/bridge/mint_sink.dart`). The persisted
/// control token seeds the provider so the first request can skip a mint.
Future<BridgeClient> _buildBridgeClient(ServerRecord rec) {
  final seed = rec.controlToken;
  final seedExpiry = rec.controlTokenExpiresAt;
  return BridgeClient.connect(
    baseUrl: rec.apiUrl,
    serverName: rec.name,
    host: rec.host,
    sshPort: rec.sshPort,
    tlsPin: rec.tlsCertFingerprint,
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
      try {
        return OverviewData(
          await client.overview().timeout(_hostFanoutTimeout),
        );
      } on BridgeError_BadStatus catch (e) {
        // A top-level 404 can only mean the /api/overview route doesn't exist
        // (server too old) — the terminal upgrade-required value, never retried.
        if (e.code == 404) return const OverviewUnsupported();
        rethrow;
      }
    });

/// The injectable seam over the two-call FRB watcher (`createRcWatcher` +
/// `rcWatcherEvents` + the sync `stopRcEvents` + the opaque `dispose`). The
/// default impl calls the generated FRB functions; [liveActivityProvider] drives
/// it, and a test overrides [rcWatcherBridgeProvider] with a fake so the
/// Riverpod wiring is unit-testable without the native library.
abstract class RcWatcherBridge {
  const RcWatcherBridge();

  /// Spawn a watcher for [serverName] against [client], returning its opaque
  /// handle (step 1 of the two-call shape).
  Future<BridgeWatcherHandle> create({
    required BridgeClient client,
    required String serverName,
  });

  /// Drain the handle's watcher into a Dart `Stream` (step 2).
  Stream<BridgeWatcherUpdate> events(BridgeWatcherHandle handle);

  /// Synchronous, idempotent stop (the co-primary teardown Riverpod `onDispose`
  /// calls); aborts a parked forwarder immediately.
  void stop(BridgeWatcherHandle handle);

  /// Drop the Rust-owned opaque (guarded against double-dispose).
  void dispose(BridgeWatcherHandle handle);
}

class _FrbRcWatcherBridge extends RcWatcherBridge {
  const _FrbRcWatcherBridge();

  @override
  Future<BridgeWatcherHandle> create({
    required BridgeClient client,
    required String serverName,
  }) => createRcWatcher(client: client, serverName: serverName);

  @override
  Stream<BridgeWatcherUpdate> events(BridgeWatcherHandle handle) =>
      rcWatcherEvents(handle: handle);

  @override
  void stop(BridgeWatcherHandle handle) => stopRcEvents(handle: handle);

  @override
  void dispose(BridgeWatcherHandle handle) {
    if (!handle.isDisposed) handle.dispose();
  }
}

final rcWatcherBridgeProvider = Provider<RcWatcherBridge>(
  (ref) => const _FrbRcWatcherBridge(),
);

/// Debounce for the unknown-slug overview refetch: a session created outside the
/// app (e.g. via the CLI) announces itself on the rc-events stream, but the
/// overlay can only patch EXISTING cards — the overview must be refetched once
/// for the new card to appear at all. At most one such refetch per window, so a
/// burst of events for a new session costs a single fetch. This stays
/// consumer-side because it needs overview knowledge the watcher lacks.
///
/// A top-level `var` (not `const`) purely so tests can shrink the window via
/// [setRcUnknownSlugDebounceForTest] and assert the debounce re-enables without a
/// real 5s wait; production never mutates it.
Duration _rcUnknownSlugDebounce = const Duration(seconds: 5);

/// Test seam: override (or reset, with `null`) the unknown-slug debounce window so
/// the "debounce re-enables after the window" behavior is assertable in a unit
/// test. Restore to the 5s default in `tearDown`.
@visibleForTesting
void setRcUnknownSlugDebounceForTest(Duration? window) =>
    _rcUnknownSlugDebounce = window ?? const Duration(seconds: 5);

/// The live rc-activity overlay for one host, folded by the Rust
/// `RcEventsWatcher` and streamed over the bridge (`createRcWatcher` +
/// `rcWatcherEvents`). A StreamProvider so the sessions view (and per-card
/// `.select`s) react to each folded snapshot without re-fetching the overview.
///
/// Lifecycle: autoDispose — the watcher runs only while something watches this
/// (the Sessions view / a watch screen for the host is visible). `onDispose`
/// cancels the Dart subscription, calls the SYNCHRONOUS `stopRcEvents` (which
/// aborts the Rust forwarder even while parked), then drops the opaque handle.
///
/// Reconnect is Rust-owned: the `RcEventsWatcher` backs off + reconnects, clears
/// its held overlay on resync, and re-mints on a 401. A `Down` update is NOT
/// destructive here — the subscription and the last overlay are kept. A resync
/// arrives folded onto the next `Event` as `resync: true`, which triggers exactly
/// one `overviewProvider` invalidation (so a coalesced/dropped intermediate can't
/// lose the signal). The consumer-side unknown-slug debounce (below) is retained
/// because it surfaces an out-of-band session on a HEALTHY connection, which the
/// resync-on-reconnect path alone does not.
final liveActivityProvider = StreamProvider.autoDispose
    .family<ActivityOverlay, String>((ref, serverName) {
      final bridge = ref.watch(rcWatcherBridgeProvider);
      final controller = StreamController<ActivityOverlay>();
      var disposed = false;
      BridgeWatcherHandle? handle;
      StreamSubscription<BridgeWatcherUpdate>? sub;

      void teardown() {
        final h = handle;
        if (h != null) {
          bridge.stop(h);
          bridge.dispose(h);
        }
      }

      ref.onDispose(() {
        disposed = true;
        unawaited(sub?.cancel());
        teardown();
        unawaited(controller.close());
      });

      // Emit an initial empty overlay immediately so consumers render before the
      // first event (pre-B3 behavior).
      var overlay = ActivityOverlay.empty;
      controller.add(overlay);

      // Unknown-slug refetch (debounced): an event for a session the current
      // overview snapshot doesn't hold means there's no card for the patch to
      // land on — refetch the overview once so the new card appears. ref.read
      // (not watch): the overview must never be a dependency, or its own
      // invalidation would rebuild this provider and tear down the watcher.
      var lastUnknownRefetch = DateTime.fromMillisecondsSinceEpoch(0);
      bool overviewHasSession(String shed, String slug) {
        final r = ref.read(overviewProvider(serverName)).value;
        // No snapshot to compare against — don't churn (treat as known).
        if (r is! OverviewData) return true;
        for (final s in r.overview.sheds) {
          if (s.shed.name == shed) {
            return s.sessions.any((sess) => sess.slug == slug);
          }
        }
        return false; // whole shed unknown → the snapshot is stale too
      }

      void maybeRefetchUnknown(String shed, String slug) {
        if (overviewHasSession(shed, slug)) return;
        final now = DateTime.now();
        if (now.difference(lastUnknownRefetch) < _rcUnknownSlugDebounce) return;
        lastUnknownRefetch = now;
        ref.invalidate(overviewProvider(serverName));
      }

      void onUpdate(BridgeWatcherUpdate update) {
        if (disposed) return;
        switch (update) {
          case BridgeWatcherUpdate_Event(
            :final event,
            overlay: final entries,
            :final resync,
          ):
            // A resync (reconnect cleared the held overlay) → refetch the base
            // overview once (Rust already cleared its snapshot; this restores
            // the Event.resync → invalidate ordering). A resync already
            // invalidates the overview, so skip the unknown-slug check for this
            // same update — it would only ever cost a redundant second refetch
            // (and burn the debounce window). The next non-resync event picks up
            // any still-unknown slug.
            if (resync) {
              ref.invalidate(overviewProvider(serverName));
            } else {
              // A live event for a session the overview doesn't know about → one
              // debounced overview refetch so the new card materializes. Match
              // the pre-B3 set: session.updated (not removed) + activity.changed.
              switch (event) {
                case BridgeRcEvent_SessionUpdated(
                  :final shed,
                  :final slug,
                  :final removed,
                ):
                  if (!removed) maybeRefetchUnknown(shed, slug);
                case BridgeRcEvent_ActivityChanged(:final shed, :final slug):
                  maybeRefetchUnknown(shed, slug);
                case _:
                  break;
              }
            }
            overlay = ActivityOverlay(entries);
            controller.add(overlay);
          case BridgeWatcherUpdate_Down():
            // Do NOTHING destructive — the Rust watcher owns reconnect/backoff.
            // Keep the subscription and the last overlay (Rust clears it via a
            // resync on reconnect).
            break;
        }
      }

      ref
          .watch(shedClientProvider(serverName).future)
          .then((client) async {
            // Disposed before the client resolved → never create the watcher.
            if (disposed) return;
            final h = await bridge.create(
              client: client,
              serverName: serverName,
            );
            // Disposed between create and listen → stop + drop immediately.
            if (disposed) {
              bridge.stop(h);
              bridge.dispose(h);
              return;
            }
            handle = h;
            sub = bridge.events(h).listen(onUpdate);
          })
          .catchError((Object e, StackTrace st) {
            // Client build failed (unknown server / keychain error): surface it
            // as the provider's error state rather than silently idling.
            if (!disposed) controller.addError(e, st);
          });

      return controller.stream;
    });

/// One (shed, rc session) pair on a host — the cross-host Sessions view's unit.
typedef ShedSession = ({String shedName, BridgeRcSession session});

/// Flatten an overview into the Sessions view's (shed, session) pairs — the
/// server rc-enriches the sessions, and a stopped shed contributes none. The
/// embedded bridge sessions are rendered directly (B4: consumers are on the
/// bridge RC types), so the shared session card renders identically whether the
/// data came from the overview (here) or the per-shed SSH `rc list` fan-out.
List<ShedSession> shedSessionPairs(BridgeOverview overview) => [
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
    .family<BridgeRcCapabilities?, ShedRef>((ref, key) async {
      final result = await ref.watch(overviewProvider(key.serverName).future);
      if (result is! OverviewData) return null; // old server → absent caps
      for (final s in result.overview.sheds) {
        if (s.shed.name == key.shedName) {
          return s.capabilities;
        }
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

/// One-shot [RcService] for a widget action (create/kill fired from a screen
/// that doesn't otherwise watch [rcServiceProvider]). Reads only the STABLE
/// serverStore/identities providers: a one-shot
/// `ref.read(rcServiceProvider(key).future)` races autoDispose — nothing keeps
/// the provider alive through its own async build, so its body's later read
/// throws "Cannot use the Ref after it has been disposed" and the action never
/// runs. Mirrors [buildRcService] for [WidgetRef] callers (and the session
/// card's delete action, which already assembles the service this way).
Future<RcService> rcServiceOneShot(WidgetRef ref, ShedRef key) async {
  // Capture both dependencies BEFORE the first await: a WidgetRef must not be
  // read after an async gap (the widget can dispose mid-flight, and
  // `ref.read` then throws "Cannot use a WidgetRef after dispose"). Reading the
  // store synchronously and the identities Future up front means no `ref` usage
  // survives an await.
  final store = ref.read(serverStoreProvider);
  final identitiesFuture = ref.read(identitiesProvider.future);
  final rec = await store.get(key.serverName);
  if (rec == null) throw StateError('unknown server: ${key.serverName}');
  final identities = await identitiesFuture;
  return rcServiceFor(rec, identities, key.shedName);
}

final rcServiceProvider = FutureProvider.autoDispose.family<RcService, ShedRef>(
  (ref, key) => buildRcService(ref, key),
);

final rcSessionsProvider = FutureProvider.autoDispose
    .family<List<BridgeRcSession>, ShedRef>((ref, key) async {
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
