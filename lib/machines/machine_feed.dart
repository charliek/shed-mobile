import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../rc/rc_ui.dart';
import '../src/rust/api/dto_rc.dart';
import '../src/rust/api/roost.dart';
import '../src/rust/api/roost_bootstrap.dart';
import '../ssh/exec_bytes.dart';
import '../ssh/host_key_store.dart';
import '../ssh/lane_forward.dart';
import '../ssh/roost_bootstrap_runner.dart';
import '../ssh/roost_entitlement.dart';
import '../ssh/roost_reach.dart';
import '../ssh/roost_tunnel.dart';
import '../ssh/ssh_connection.dart';
import '../ssh/ssh_runner.dart';
import 'machine_record.dart';

/// One machine's live view, as the UI renders it.
class MachineFeedState {
  const MachineFeedState({
    required this.machine,
    this.sessions = const [],
    this.overlay = const {},
    this.reachable = false,
    this.detail,
    this.connectedOnce = false,
    this.capabilities,
    this.downKind,
  });

  final MachineRecord machine;

  /// The last snapshot the machine's `roost-session` reported. Kept across a
  /// disconnect on purpose: the UI shows the last known sessions (dimmed, with
  /// a reason) rather than blanking the machine, which is what a brief network
  /// blip deserves.
  final List<BridgeRcSession> sessions;

  /// Live patches from the feed, keyed by SLUG, applied over [sessions] at
  /// render time.
  ///
  /// **Empty on the roost path**, and kept anyway: roost's watcher folds its
  /// event batches into a whole inventory before republishing, so there is no
  /// patch stream to fold — a `Snapshot` is the entire truth about a machine.
  /// The overlay stays because it is what the render sites read through
  /// ([activityOf] / [stateOf]), and because roost's R1 live push lands events
  /// again; deleting it would mean re-deriving the same seam a milestone later.
  final Map<String, MachinePatch> overlay;

  final bool reachable;

  /// Why it is unreachable, verbatim. Shown to the user because "no route to
  /// host" and "nothing is listening on that socket" are different problems
  /// with different fixes, and flattening them to "offline" throws away the
  /// only actionable part.
  final String? detail;

  /// Whether a snapshot has EVER arrived — distinguishes "still connecting"
  /// from "connected, and this machine genuinely has no sessions".
  final bool connectedOnce;

  /// The machine's per-kind affordances.
  ///
  /// **Controls render off THIS, never off the kind.** On the roost path they
  /// are [roostCapabilities] — synthesized, not probed, because roost is a
  /// terminal multiplexer with agent adapters rather than shed's guest agent,
  /// so there is nothing to ask. Every steering feature the RC hub used to
  /// advertise for a machine reads `false`/empty there, which is what makes the
  /// existing per-feature gates hide those controls with no new conditionals.
  final BridgeRcCapabilities? capabilities;

  /// What kind of unreachable this is, from the last `Down`.
  ///
  /// Null means **unclassified**, not "reachable": a snapshot clears it, but so
  /// does never having had one — a feed error or a pause marks the machine
  /// unreachable without any `Down` to classify it. A caller reads this to
  /// decide what to OFFER, and null is the honest "offer nothing".
  ///
  /// The branch a caller acts on; [detail] is the sentence it shows. Only
  /// [BridgeReachKind.notInstalled] and [BridgeReachKind.noSession] name
  /// something the phone could offer to do about it — the other two are
  /// reported and nothing more.
  ///
  /// **Cleared by the next `Snapshot`**, which is the whole reason it is on the
  /// state rather than read off the last update: a machine that came back must
  /// not keep offering to install roost on it.
  ///
  /// **A `Snapshot` is the only thing that clears it, and deliberately so.** A
  /// feed error, a failed watcher start and [stop] all set `reachable: false`
  /// and leave the kind standing, because none of them is evidence about the
  /// far side: only a snapshot proves a `roost-session` is answering. Clearing
  /// on those paths would drop a still-true "roost is not installed here" over
  /// a dropped connection — the same mistake as blanking [sessions] on a
  /// `Down`, which this module already declines to make.
  ///
  /// The consequence a renderer must handle: [detail] and this field can
  /// describe different things at once ("paused", plus a kind from the last
  /// real `Down`). The kind says what could be OFFERED; [detail] says what is
  /// happening now.
  final BridgeReachKind? downKind;

  MachineFeedState copyWith({
    List<BridgeRcSession>? sessions,
    Map<String, MachinePatch>? overlay,
    bool? reachable,
    String? detail,
    bool? connectedOnce,
    BridgeRcCapabilities? capabilities,
    BridgeReachKind? downKind,
    bool clearDetail = false,
    bool clearDownKind = false,
  }) => MachineFeedState(
    machine: machine,
    sessions: sessions ?? this.sessions,
    overlay: overlay ?? this.overlay,
    reachable: reachable ?? this.reachable,
    detail: clearDetail ? null : (detail ?? this.detail),
    connectedOnce: connectedOnce ?? this.connectedOnce,
    capabilities: capabilities ?? this.capabilities,
    downKind: clearDownKind ? null : (downKind ?? this.downKind),
  );

  /// The affordances for a session's kind, or null when unknown.
  BridgeRcKindFeatures? featuresFor(BridgeRcSession s) =>
      capabilities?.kindFeatures[s.kind.wire];

  /// Whether this session can be STEERED from here — a structured turn.
  /// `input: "turn"` is the only mode that accepts one.
  ///
  /// False for every roost row (`input` is empty there): a roost tab is a
  /// terminal, and typing into one is roost's `tab.write`, which the phone does
  /// not offer in this milestone.
  bool canSteer(BridgeRcSession s) => featuresFor(s)?.input == 'turn';

  /// Whether a running turn can be interrupted from here.
  bool canInterrupt(BridgeRcSession s) => featuresFor(s)?.interrupt ?? false;

  /// Whether an approval can be ANSWERED from here.
  ///
  /// `"remote"` means the far side can resolve it; `"tui"` means the rows are
  /// informational and the decision must be made in the session's terminal.
  /// roost advertises `"none"`.
  bool canApprove(BridgeRcSession s) => featuresFor(s)?.approvals == 'remote';

  /// A session's activity, with the live patch applied.
  BridgeRcActivity? activityOf(BridgeRcSession s) =>
      overlay[s.slug]?.activity ?? s.activity;

  /// A session's lifecycle state, with the live patch applied.
  BridgeRcState stateOf(BridgeRcSession s) => overlay[s.slug]?.state ?? s.state;
}

/// One session's live patch — the activity dimension only.
class MachinePatch {
  const MachinePatch({this.activity, this.state, this.lastSeq});

  final BridgeRcActivity? activity;
  final BridgeRcState? state;

  /// A feed's high-water mark for this session.
  ///
  /// A NOTIFICATION, not content: the event says "there is something new past
  /// seq N", and the body comes from a follow-up fetch.
  final BigInt? lastSeq;

  /// Later wins per FIELD, so one dimension cannot erase another that arrived
  /// first — the dimensions travel on separate events and must not clobber
  /// each other.
  MachinePatch merge(MachinePatch other) => MachinePatch(
    activity: other.activity ?? activity,
    state: other.state ?? state,
    lastSeq: other.lastSeq ?? lastSeq,
  );
}

/// Fold one roost update into the feed's state — **the whole reconciliation,
/// as a pure function** (plan 013 S3m).
///
/// Pure so it can be tested without a bridge, a socket, or a machine: the two
/// rules below are the entire contract between roost and what the cards show,
/// and they are exactly the rules that break silently in production.
///
/// * A `Snapshot` **replaces** the row set — it is roost's whole agent-owned
///   tab list as of that push, so merging would resurrect tabs that were
///   closed. It also clears the overlay, because the snapshot already carries
///   every dimension a patch could hold.
/// * A `Down` **keeps** the rows and marks them stale with a reason. Blanking
///   the machine would throw away the best available answer to "what is
///   running on mini3?" every time a phone changes networks. It also records
///   the `kind`, which is the branch a caller acts on — and the next `Snapshot`
///   clears it, so a machine that came back never keeps offering an install.
///
/// [dialDetail] is the SSH dial's own failure, when there was one. It wins over
/// roost's reason because they describe the same outage at different distances:
/// the watcher can only report "connection refused" against the local port,
/// while the tunnel underneath knows the connection was refused *because this
/// device's key is not authorized*. Losing that was the transport swap's one
/// real regression, and this is where it is not lost.
///
/// [observedKind] is the same argument for the same outage, one field over, and
/// it is what makes `downKind` mean anything at all on a phone (plan 020
/// amendment A2). The reach Rust holds here is a `LabelledPort` — a loopback
/// port Dart owns — which takes `RoostReach::last_error`'s `None` default, so
/// **every `Down` this watcher publishes carries `kind: Other`**, whatever the
/// real cause. Dart owns the transport, so Dart is the only layer that ever
/// sees the far end's `exit 127` or its `client-bridge: no session`, and its
/// classification wins for exactly the reason [dialDetail] does. Where Dart
/// observed nothing the update's own kind stands, so a transport that one day
/// does classify needs no change here.
@visibleForTesting
MachineFeedState foldRoostUpdate(
  MachineFeedState state,
  BridgeRoostUpdate update, {
  String? dialDetail,
  BridgeReachKind? observedKind,
}) => switch (update) {
  BridgeRoostUpdate_Snapshot(:final sessions) => state.copyWith(
    sessions: sessions,
    overlay: const {},
    reachable: true,
    connectedOnce: true,
    clearDetail: true,
    clearDownKind: true,
  ),
  BridgeRoostUpdate_Down(:final reason, :final kind) => state.copyWith(
    reachable: false,
    detail: dialDetail ?? reason,
    downKind: observedKind ?? kind,
  ),
};

/// Apply the row a `tab.open` returned, optimistically.
///
/// Keyed on the slug (roost's tab id as a string), so a re-open of a row the
/// last snapshot already carried replaces it rather than doubling it. The next
/// push from the watcher is authoritative either way — this only exists so the
/// card appears in the gap before that push arrives, which is the difference
/// between "it worked" and "did that button do anything?".
@visibleForTesting
MachineFeedState foldOpenedRow(MachineFeedState state, BridgeRcSession row) =>
    state.copyWith(
      sessions: [...state.sessions.where((s) => s.slug != row.slug), row],
    );

/// Drop a row that has just been closed, optimistically.
///
/// Same reasoning inverted: `tab.close` removes the tab from `tab.list`
/// entirely, so the next push agrees — but a killed session lingering until
/// that push lands reads as "the kill didn't work".
@visibleForTesting
MachineFeedState foldClosedRow(MachineFeedState state, String slug) =>
    state.copyWith(
      sessions: state.sessions.where((s) => s.slug != slug).toList(),
      overlay: {...state.overlay}..remove(slug),
    );

/// The in-flight-dial bookkeeping [MachineFeed._connect] uses to dedupe
/// concurrent connects within one generation, without adopting a pending dial
/// that belongs to an earlier one.
///
/// Generation-agnostic over the dialed type on purpose: [MachineFeed._connect]
/// dials a real [SSHClient], which needs a live socket to construct and so
/// cannot be unit tested directly, but the bookkeeping bug this fixes (a
/// stop/start cycle adopting the previous generation's dial) has nothing to do
/// with what is being dialed. Pulling it out lets the decision be tested with a
/// dummy type instead — see `test/machines/machine_feed_test.dart`.
@visibleForTesting
class DialDedupe<T> {
  Future<T>? _pending;
  int? _pendingGeneration;

  /// The pending dial for [generation], or null when there is none — either
  /// nothing is in flight, or what's in flight belongs to an earlier
  /// generation and must not be adopted: it is left alone, not awaited, because
  /// its own completion handler already closes what it produces once it
  /// notices the generation has moved on (see [MachineFeed._connect]).
  Future<T>? pendingFor(int generation) {
    final pending = _pending;
    return (pending != null && _pendingGeneration == generation)
        ? pending
        : null;
  }

  /// Record [future] as the pending dial for [generation].
  void start(int generation, Future<T> future) {
    _pending = future;
    _pendingGeneration = generation;
  }

  /// Clear the pending dial if it is still [future] — a later [start] may
  /// already have replaced it (the stale-generation case above), and that
  /// newer entry must survive this call's `finally`.
  void clear(Future<T> future) {
    if (identical(_pending, future)) {
      _pending = null;
      _pendingGeneration = null;
    }
  }
}

/// The fence [MachineFeed.start] puts after each of its awaits: did a
/// [MachineFeed.stop] land while this resource was being built?
///
/// If it did, the resource belongs to nobody — [MachineFeed._teardown] has
/// already nulled and released whatever it could see — so it is released HERE
/// and the caller is told to give up rather than install it behind the feed's
/// back. Returns true when it was released (caller must return), false when the
/// generation still holds and the caller may install it.
///
/// Extracted, generic, and `@visibleForTesting` for exactly the reasons
/// [DialDedupe] is: `start()` builds a real [RoostTunnel] (a live
/// `ServerSocket`) and a real [BridgeRoostWatcher] (an FRB opaque handle, not
/// constructible in a unit test at all), but the decision has nothing to do
/// with what was built. With a dummy resource the race is testable — see
/// `test/machines/machine_feed_test.dart`.
@visibleForTesting
Future<bool> releaseIfStopped<T>({
  required int startedAt,
  required int current,
  required T resource,
  required Future<void> Function(T) release,
}) async {
  if (startedAt == current) return false;
  await release(resource);
  return true;
}

/// Spawning one machine's roost watcher — `createRoostWatcher`'s own signature.
///
/// Named as a type so a drift between it and the bridge call is a compile error
/// in this file, exactly as [BootstrapExec] is. See [MachineFeed]'s
/// `_spawnWatcher` for why the seam exists at all.
typedef WatcherSpawn =
    Future<BridgeRoostWatcher> Function({
      required String machine,
      required int localPort,
      required bool bootstrapped,
    });

/// **One machine's feed: the tunnel, the watcher, and the state they produce.**
///
/// Owns the phone-specific half of the lifecycle. Everything above the local
/// port is shared Rust (see `rust/src/api/roost.rs` and `shed_app::roost`), so
/// what lives here is exactly what a phone must decide: when to hold an SSH
/// connection open, and when to let it go.
///
/// ## What changed under it, and what did not
///
/// The machine's sessions come from its `roost-session` now, not from the RC
/// activity hub (plan 013, the Roost Pivot's first milestone). That is a
/// re-point of the transport, not a re-architecture: the tunnel still publishes
/// one stable loopback port, Rust is still handed nothing but an `int`, and the
/// state this class produces has the same shape the cards already render.
///
/// Two consequences worth naming:
///
/// * **The SSH connection is this class's to own.** [RoostTunnel] execs on it
///   per accepted connection but never closes it — a PTY may be sharing it —
///   so [_teardown] is the one place it dies.
/// * **Capabilities are synthesized, not probed.** There is no second SSH exec
///   at start-up any more; [roostCapabilities] is a constant, so the controls
///   are gated correctly from the very first frame rather than after a round
///   trip that could fail.
///
/// ## Backgrounding is a STOP, not a stall
///
/// [stop] tears the tunnel and the watcher down; [start] rebuilds both. That is
/// deliberate rather than lazy: holding an SSH connection and a parked watcher
/// open behind a backgrounded phone is what drains a battery and gets an app
/// killed by the OS.
///
/// Resuming loses nothing, and that falls out of the WIRE rather than needing a
/// replay protocol: `tab.list` is an authoritative snapshot, so a fresh
/// connection is a complete resync by construction.
class MachineFeed {
  MachineFeed({
    required this.machine,
    required this.identities,
    required this.hostKeys,
    required this.entitlements,
    WatcherSpawn? spawnWatcher,
  }) : _spawnWatcher = spawnWatcher ?? createRoostWatcher,
       _state = MachineFeedState(
         machine: machine,
         // Synchronous, and therefore present on the FIRST state the UI sees:
         // there is no host to ask, and making the gates wait on a round trip
         // that does not exist would leave the controls guessing.
         capabilities: roostCapabilities(),
       );

  final MachineRecord machine;
  final List<SSHKeyPair> identities;
  final HostKeyStore hostKeys;

  /// **What this app run bootstrapped** — shared with every other feed, because
  /// the claim belongs to the app rather than to this object.
  ///
  /// A feed is `autoDispose` and the phone tears one down on every background,
  /// so a per-feed set would forget the install the moment the user left the
  /// screen — and the machine's hooks would then never be re-sent again for the
  /// rest of the run. See [RoostBootstrapEntitlements].
  final RoostBootstrapEntitlements entitlements;

  /// How [start] spawns the watcher — `createRoostWatcher` in production.
  ///
  /// **The seam exists because a watcher handle answers nothing.** What [start]
  /// tells the bridge about this machine's entitlement is the one thing this
  /// class decides and the one thing nothing can read back: `BridgeRoostWatcher`
  /// is opaque, and the effect of the bool is on a wire only a fake roost sees
  /// (it is pinned there, in Rust). A pass-through recorder is therefore the
  /// only way a harness can assert that a feed asks for the claim it holds —
  /// including across the re-spawn [_entitle] performs, which is the case this
  /// whole commit exists for.
  final WatcherSpawn _spawnWatcher;

  final _controller = StreamController<MachineFeedState>.broadcast();
  MachineFeedState _state;

  RoostTunnel? _tunnel;
  BridgeRoostWatcher? _watcher;
  StreamSubscription<BridgeRoostUpdate>? _sub;
  bool _starting = false;

  /// The SSH connection every exec on this machine rides. Owned HERE, because
  /// [RoostTunnel] deliberately does not close what it did not open.
  SSHClient? _client;

  /// The dial in flight, so two connections accepted at once do not open two
  /// SSH links and leak one — deduped per [_generation]. See [DialDedupe].
  final _dialDedupe = DialDedupe<SSHClient>();

  /// The agent-lane port forwards riding this machine's one SSH connection,
  /// refcounted per remote port. See [ForwardRegistry] and [acquireForward].
  late final ForwardRegistry _forwards = ForwardRegistry(
    // Forwards ride the SAME connection, through the same `_connect` the roost
    // tunnel uses — so they inherit its dedupe and its generation fencing, and
    // a lane costs no second SSH link.
    openForward: (remotePort) =>
        LaneForward.open(connect: _connect, remotePort: remotePort),
  );

  /// Bumped by every [_teardown], so a dial that completes after a stop closes
  /// its client instead of installing it behind the feed's back.
  int _generation = 0;

  /// Why the last SSH dial failed, if it did. See [foldRoostUpdate].
  String? _dialDetail;

  /// **What Dart's own transport has learned about this machine's roost
  /// reach**, and the only source of a meaningful `downKind` on a phone (plan
  /// 020 amendment A2).
  ///
  /// Two things record into it, and they are the only two that ever see the
  /// answer: the tunnel's exec stderr (`roost-session: command not found`,
  /// `client-bridge: no session`), and a dial that never got onto the box at
  /// all. Two things read it: [foldRoostUpdate], so a card can offer an install
  /// or a start; and a [RoostBootstrapRunner], so the probe's one
  /// `session.identify` comes back as a *state of the far side* rather than as
  /// "the probe could not be completed".
  ///
  /// Exposed so the bootstrap runner reads the same observation the card does.
  /// Two of them would be two answers to one question.
  final RoostReachObserver reach = RoostReachObserver();

  /// The current view. Always available — a machine that has never connected
  /// still has a row, because "mini3 is asleep" IS the information.
  MachineFeedState get state => _state;

  Stream<MachineFeedState> get updates => _controller.stream;

  bool get isRunning => _watcher != null;

  /// **Did THIS APP RUN bootstrap this machine?** — what [start] hands
  /// `createRoostWatcher`, and the whole of what decides whether this machine's
  /// watcher keeps its agent hooks wired (plan 020 §3.3).
  ///
  /// A getter over [entitlements] rather than a field of its own: the answer
  /// changes during a feed's life (an install is what changes it) and every
  /// reader must see the change, not a copy taken at construction.
  bool get bootstrappedThisRun => entitlements.holds(machine.name);

  /// The local port the machine's `roost-session` is reachable on, or null when
  /// the tunnel is down.
  ///
  /// Exposed so a screen can address the same session over the SAME tunnel the
  /// feed holds — a second connection per screen would double the SSH cost of
  /// simply looking at a session.
  int? get tunnelPort => _tunnel?.port;

  /// Open the tunnel and start watching. Idempotent, and safe to call on every
  /// foreground.
  Future<void> start() async {
    if (_watcher != null || _starting) return;
    _starting = true;
    // The same fence `_connect` uses: a `stop()` during either await below has
    // already run `_teardown()`, so installing what this call built would put a
    // tunnel or a watcher back behind the feed's back. Nothing owns them at that
    // point, so this call closes what it made rather than leaking it.
    final generation = _generation;
    try {
      final tunnel = await RoostTunnel.open(
        connect: _connect,
        // Opaque, and composed by roost itself — the phone is out of the
        // argv business entirely (see `roostRemoteCommand`).
        remoteCommand: roostRemoteCommand(),
        machine: machine.name,
        onStderr: _observeStderr,
      );
      if (await releaseIfStopped(
        startedAt: generation,
        current: _generation,
        resource: tunnel,
        release: (t) => t.close(),
      )) {
        return;
      }
      _tunnel = tunnel;

      // Rust is handed the PORT and nothing else — no host, no key, no SSH.
      final watcher = await _spawnWatcher(
        machine: machine.name,
        localPort: tunnel.port,
        // **Asked afresh at every spawn**, which is the whole reason the answer
        // lives outside this object: a phone spawns a watcher on every
        // foreground, and an entitlement read once at app start would be read
        // before the install that earns it. A bool, never a label — Rust
        // substitutes its own (plan 020 §3.3, amendment A8).
        bootstrapped: bootstrappedThisRun,
      );
      // The worst of the two: `_watcher` non-null with `_tunnel` already nulled
      // by the teardown makes `isRunning` true and `tunnelPort` null, and every
      // later `start()` then returns early on that stale `_watcher` — the feed
      // never comes back.
      if (await releaseIfStopped(
        startedAt: generation,
        current: _generation,
        resource: watcher,
        release: (w) => stopRoostWatcher(handle: w),
      )) {
        return;
      }
      _watcher = watcher;
      _sub = roostWatcherEvents(handle: watcher).listen(
        _apply,
        onError: (Object e) =>
            _emit(_state.copyWith(reachable: false, detail: 'feed error: $e')),
      );
    } catch (e) {
      // Binding the port failed — the machine itself is not dialled here at
      // all (the tunnel execs per accepted connection), so an asleep or
      // unauthorized machine arrives as the watcher's `Down` instead.
      await _teardown();
      _emit(_state.copyWith(reachable: false, detail: _describe(e)));
    } finally {
      _starting = false;
    }
  }

  /// Open (or reuse) the machine's SSH connection. Handed to [RoostTunnel],
  /// which calls it once per accepted connection so a dropped link is
  /// re-established on the next use rather than tearing the tunnel down.
  Future<SSHClient> _connect() async {
    final existing = _client;
    if (existing != null && !existing.isClosed) return existing;
    final generation = _generation;
    // Only adopt a pending dial from THIS generation — see [DialDedupe].
    final pending = _dialDedupe.pendingFor(generation);
    if (pending != null) return pending;
    final future = openSshClient(
      host: machine.host,
      port: machine.sshPort,
      user: machine.user ?? 'root',
      identities: identities,
      hostKeys: hostKeys,
    );
    _dialDedupe.start(generation, future);
    try {
      final client = await future;
      if (generation != _generation) {
        // A stop won the race. Nothing owns this client, so close it here or
        // it outlives the feed that asked for it.
        client.close();
        throw StateError('the machine feed was stopped');
      }
      _client = client;
      _dialDetail = null;
      return client;
    } catch (e) {
      // Record WHY: the watcher only ever sees "the local port refused", and
      // "this device's key is not authorized" is the one thing the user can
      // actually act on. See [foldRoostUpdate].
      if (generation == _generation) {
        final detail = _describe(e);
        _dialDetail = detail;
        // Every dial failure is `Unreachable` by roost's own definition of it —
        // "shed never got as far as asking: the handshake failed, the key did
        // not verify, the login was refused". It is deliberately NOT `Other`:
        // `Other` is what a failure that never ran an exec at all reports, and
        // this one is about the box.
        reach.record(RoostReachNote(BridgeReachKind.unreachable, detail));
      }
      rethrow;
    } finally {
      _dialDedupe.clear(future);
    }
  }

  /// **Borrow a forward to `127.0.0.1:<remotePort>` on this machine** — how an
  /// agent lane reaches a server bound to the machine's own loopback.
  ///
  /// Refcounted per remote port and single-flight, so two lanes against one
  /// agent server share one forward and one SSH channel; the returned lease is
  /// the caller's whole obligation, and releasing the last one closes the
  /// forward.
  ///
  /// Typed as the [LaneLease] INTERFACE rather than the concrete
  /// [LaneForwardLease] it always is: a lease is all a lane needs (a local
  /// port, a validity bit and a give-back), and narrowing it here is what lets
  /// `LaneController`'s whole lifecycle be tested without an sshd.
  ///
  /// Requires a started feed: [dispose] closes every forward and invalidates
  /// every lease, so acquiring against a torn-down feed would hand out a port
  /// that reaches nothing. The same [StateError] [create] and [kill] raise.
  Future<LaneLease> acquireForward(int remotePort) async {
    if (_tunnel == null) throw StateError('the machine is not connected');
    return _forwards.acquire(remotePort);
  }

  /// **Run one already-composed command on this machine and return its raw
  /// stdout** — the production [ProbeRunner] for an agent lane's gx credential
  /// probe (plan 018 §3.11).
  ///
  /// Rides the feed's ONE `SSHClient`, the same connection the roost tunnel and
  /// every lane forward use, so a probe costs no second SSH link and inherits
  /// the dial's dedupe and generation fencing.
  ///
  /// **Bytes, never a string.** The gx probe's stdout carries a bearer token.
  /// It is handed straight across the bridge, parsed by Rust and dropped there;
  /// nothing here decodes it, logs it, keeps it, or puts any part of it in the
  /// error below — which is why the failure message is a fixed sentence with
  /// only the exit code in it, and why stderr is discarded rather than
  /// surfaced.
  ///
  /// A null exit code is "unknown", not "failed": dartssh2 occasionally drops
  /// the `exit-status` request even on success. So the only refusal is the one
  /// that is unambiguous — a non-zero status with nothing on stdout, which is a
  /// probe that did not run (no `gx`, no `$GROK_HOME`) rather than one whose
  /// output Rust can judge for itself.
  Future<Uint8List> probe(String wireCommand) async {
    final client = await _connect();
    final result = await execOn(client, wireCommand);
    final code = result.exitCode;
    if (code != null && code != 0 && result.stdout.isEmpty) {
      throw StateError(
        'the discovery probe on ${machine.name} exited $code with no output',
      );
    }
    return result.stdout;
  }

  /// Start a session on this machine — roost's `tab.open`.
  ///
  /// Minimal by design (plan 013 §4): the agent's binary and a working
  /// directory, nothing else. A kickoff prompt and a permission mode need a
  /// provider script on the far side, which is a later slice; the create form
  /// therefore does not offer them for a machine rather than dropping them
  /// silently here.
  ///
  /// A blank [workdir] is passed through as empty, which is roost's own "use
  /// the project's directory, else `$HOME`" default — the same thing the form's
  /// helper text promises.
  ///
  /// Returns the created session's slug (roost's tab id, as a string).
  Future<String> create({required BridgeRcKind kind, String? workdir}) async {
    final port = _tunnel?.port;
    if (port == null) throw StateError('the machine is not connected');
    final row = await roostTabOpen(
      localPort: port,
      machine: machine.name,
      kind: kind.wire,
      workdir: workdir ?? '',
    );
    _emit(foldOpenedRow(_state, row));
    return row.slug;
  }

  /// End a session — roost's `tab.close`.
  ///
  /// [slug] is the row's slug, which IS roost's tab id rendered as a string;
  /// the typed id travels on the row so nothing has to parse one back out.
  Future<void> kill(String slug) async {
    final port = _tunnel?.port;
    if (port == null) throw StateError('the machine is not connected');
    final tabId = _rowFor(slug)?.tabId;
    if (tabId == null) {
      // Not a roost row (or a row this feed no longer holds): closing the wrong
      // tab id is worse than refusing.
      throw StateError('no roost tab for $slug');
    }
    await roostTabClose(localPort: port, tabId: tabId);
    _emit(foldClosedRow(_state, slug));
  }

  BridgeRcSession? _rowFor(String slug) {
    for (final s in _state.sessions) {
      if (s.slug == slug) return s;
    }
    return null;
  }

  /// Stop watching and close the tunnel, leaving the feed restartable.
  ///
  /// **Nothing in the app calls this today** — the only thing that reaches the
  /// teardown is [dispose], from `machineFeedControllerProvider`'s `onDispose`
  /// (`providers.dart`). Kept because the "backgrounding is a STOP" story above
  /// is what a foreground/background hook will use, and because it is the
  /// `_teardown` + "paused" pair every restart path needs. Adding a caller is a
  /// deliberate decision, not a tidy-up: a lane holding a
  /// [LaneForwardLease] has its forward closed and its lease invalidated here.
  Future<void> stop() async {
    await _teardown();
    _emit(_state.copyWith(reachable: false, detail: 'paused'));
  }

  Future<void> dispose() async {
    await _teardown();
    await _controller.close();
  }

  Future<void> _teardown() async {
    _generation++;
    await _sub?.cancel();
    _sub = null;
    final watcher = _watcher;
    _watcher = null;
    if (watcher != null) {
      // The SYNCHRONOUS stop, not just a drop: it aborts the watcher and the
      // forwarder even while they are parked.
      await stopRoostWatcher(handle: watcher);
    }
    await _tunnel?.close();
    _tunnel = null;
    // Every lane forward on this connection goes with it, and every lease is
    // invalidated: a lane holding one must re-acquire rather than keep writing
    // into a local port that no longer reaches the machine.
    await _forwards.closeAll();
    // The tunnel and the forwards free their ports and their channels but never
    // the connection — this is the one place it dies.
    _client?.close();
    _client = null;
    _dialDetail = null;
  }

  void _apply(BridgeRoostUpdate update) {
    // **A `Snapshot` is the only thing that clears the observation**, exactly
    // as it is the only thing that clears `downKind` — and for the same reason.
    // A feed error, a failed watcher start and a [stop] all mark the machine
    // unreachable without being evidence about the far side; only a snapshot
    // proves a `roost-session` is answering, and clearing on any of the others
    // would drop a still-true "roost is not installed here" over a dropped
    // connection.
    if (update is BridgeRoostUpdate_Snapshot) reach.clear();
    _emit(
      foldRoostUpdate(
        _state,
        update,
        dialDetail: _dialDetail,
        observedKind: reach.last?.kind,
      ),
    );
  }

  /// The tunnel exec's stderr, as the pump's ACCUMULATED tail — the only place
  /// the phone ever learns *why* this machine's roost reach is refusing.
  ///
  /// A tail rather than a chunk because SSH frame boundaries are arbitrary and
  /// `client-bridge: no session` can arrive as two of them; see
  /// [DuplexPump.onStderr]. See [noteForExecStderr] for what is recorded and
  /// what deliberately is not.
  void _observeStderr(String text) {
    final note = noteForExecStderr(text);
    if (note != null) reach.record(note);
  }

  /// **Run one bootstrap `Step::Exec` on this machine** — the production
  /// [BootstrapExec] for a [RoostBootstrapRunner] (plan 020 §3.8).
  ///
  /// Rides the feed's ONE `SSHClient`, the same connection the roost tunnel and
  /// every lane forward use, exactly as [probe] and [acquireForward] do: a
  /// bootstrap costs no second SSH link and inherits the dial's dedupe and
  /// generation fencing.
  ///
  /// Every cap comes from the step; nothing here invents one. The command is
  /// roost's own composition and is passed verbatim — see `exec_bytes.dart`.
  ///
  /// Held as a field of the seam's own type rather than declared as a plain
  /// method: that is what makes a drift between this signature and
  /// [BootstrapExec] a compile error HERE, in the file that owns the
  /// connection, rather than a surprise at the one call site that wires them
  /// together.
  late final BootstrapExec bootstrapExec = _bootstrapExec;

  /// **Drive one bootstrap of this machine to its answer** — a probe or an
  /// install, over this feed's one `SSHClient` (plan 020 §3.8).
  ///
  /// The runner is assembled HERE rather than by the caller, and that is the
  /// point. A completed install is the ONLY thing that entitles this app run to
  /// keep this machine's agent hooks wired, and a caller free to assemble its
  /// own runner is a caller free to drive an install that records nothing —
  /// which is plan 019's defect exactly: a hook seam built, unit-tested, and
  /// then constructed by no production caller. The recording is not the UI's to
  /// remember.
  ///
  /// [handle] is the bridge handle for the drive (`roostBootstrapProbe` /
  /// `roostBootstrapInstall`, wrapped in a [LiveBootstrapHandle]). A cancelled
  /// drive is re-run by calling this again — see [RoostBootstrapRunner.run].
  Future<BridgeBootstrapStep> runBootstrap(BootstrapHandle handle) async {
    final step = await RoostBootstrapRunner(
      handle: handle,
      exec: bootstrapExec,
      // The same observation the machine card branches on. Two of them would be
      // two answers to one question — see [reach].
      reach: reach,
    ).run();
    if (step is BridgeBootstrapStep_Installed) await _entitle();
    return step;
  }

  /// Record that this app run bootstrapped this machine, and re-spawn the
  /// watcher so the claim takes effect now rather than whenever the feed next
  /// restarts.
  ///
  /// **The re-spawn is not a nicety.** A watcher decides at SPAWN whether it
  /// wires hooks (`createRoostWatcher`'s `bootstrapped`), and this machine has
  /// had one since the screen opened — the one that has been reporting it as
  /// unreachable all the while roost was missing. Leaving it would mean the one
  /// machine that just earned the entitlement is the one machine that never
  /// exercises it, until the user happens to leave the screen and come back.
  /// The desktop hits the same trap from the other side and solves it with a
  /// shared flag; a phone, which rebuilds its watcher constantly anyway, can
  /// simply rebuild it once more.
  ///
  /// [stop] + [start] is the documented restart pair. It costs one reconnect on
  /// a machine shed has just put a NEW `roost-session` on, where the old
  /// connection is stale by construction.
  Future<void> _entitle() async {
    entitlements.record(machine.name);
    if (isRunning) {
      await stop();
      await start();
    }
  }

  Future<ExecBytesOutcome> _bootstrapExec(
    String command,
    Stream<Uint8List> stdin, {
    required Duration budget,
    required int stdoutCap,
    required bool captureStdout,
    required int stderrCap,
  }) async {
    final client = await _connect();
    return execBytesOn(
      client,
      command,
      stdin,
      budget: budget,
      stdoutCap: stdoutCap,
      captureStdout: captureStdout,
      stderrCap: stderrCap,
      label: machine.name,
    );
  }

  void _emit(MachineFeedState next) {
    _state = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  /// A transport failure as a short, human reason — never the raw exception,
  /// which can carry detail not worth putting on a card.
  static String _describe(Object e) {
    if (e is SSHAuthAbortError || e is SSHAuthFailError) {
      return 'this device\'s key is not authorized on the machine';
    }
    if (e is SSHStateError) return 'the SSH connection failed';
    return 'cannot reach the machine';
  }
}
