import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../rc/rc_ui.dart';
import '../src/rust/api/dto_rc.dart';
import '../src/rust/api/roost.dart';
import '../ssh/host_key_store.dart';
import '../ssh/lane_forward.dart';
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

  MachineFeedState copyWith({
    List<BridgeRcSession>? sessions,
    Map<String, MachinePatch>? overlay,
    bool? reachable,
    String? detail,
    bool? connectedOnce,
    BridgeRcCapabilities? capabilities,
    bool clearDetail = false,
  }) => MachineFeedState(
    machine: machine,
    sessions: sessions ?? this.sessions,
    overlay: overlay ?? this.overlay,
    reachable: reachable ?? this.reachable,
    detail: clearDetail ? null : (detail ?? this.detail),
    connectedOnce: connectedOnce ?? this.connectedOnce,
    capabilities: capabilities ?? this.capabilities,
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
///   running on mini3?" every time a phone changes networks.
///
/// [dialDetail] is the SSH dial's own failure, when there was one. It wins over
/// roost's reason because they describe the same outage at different distances:
/// the watcher can only report "connection refused" against the local port,
/// while the tunnel underneath knows the connection was refused *because this
/// device's key is not authorized*. Losing that was the transport swap's one
/// real regression, and this is where it is not lost.
@visibleForTesting
MachineFeedState foldRoostUpdate(
  MachineFeedState state,
  BridgeRoostUpdate update, {
  String? dialDetail,
}) => switch (update) {
  BridgeRoostUpdate_Snapshot(:final sessions) => state.copyWith(
    sessions: sessions,
    overlay: const {},
    reachable: true,
    connectedOnce: true,
    clearDetail: true,
  ),
  BridgeRoostUpdate_Down(:final reason) => state.copyWith(
    reachable: false,
    detail: dialDetail ?? reason,
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
  }) : _state = MachineFeedState(
         machine: machine,
         // Synchronous, and therefore present on the FIRST state the UI sees:
         // there is no host to ask, and making the gates wait on a round trip
         // that does not exist would leave the controls guessing.
         capabilities: roostCapabilities(),
       );

  final MachineRecord machine;
  final List<SSHKeyPair> identities;
  final HostKeyStore hostKeys;

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

  /// The current view. Always available — a machine that has never connected
  /// still has a row, because "mini3 is asleep" IS the information.
  MachineFeedState get state => _state;

  Stream<MachineFeedState> get updates => _controller.stream;

  bool get isRunning => _watcher != null;

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
      final watcher = await createRoostWatcher(
        machine: machine.name,
        localPort: tunnel.port,
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
      if (generation == _generation) _dialDetail = _describe(e);
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

  void _apply(BridgeRoostUpdate update) =>
      _emit(foldRoostUpdate(_state, update, dialDetail: _dialDetail));

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
