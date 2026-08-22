import 'dart:async';

import 'package:dartssh2/dartssh2.dart';

import '../rc/rc_ui.dart';
import '../src/rust/api/dto_rc.dart';
import '../src/rust/api/rc_runner.dart';
import '../ssh/ssh_runner.dart';
import '../src/rust/api/machine.dart';
import '../ssh/host_key_store.dart';
import '../ssh/hub_tunnel.dart';
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

  /// The last snapshot the hub reported. Kept across a disconnect on purpose:
  /// the UI shows the last known sessions (dimmed, with a reason) rather than
  /// blanking the machine, which is what a brief network blip deserves.
  final List<BridgeRcSession> sessions;

  /// Live patches from the feed, keyed by SLUG, applied over [sessions] at
  /// render time.
  ///
  /// An overlay rather than mutated rows, for two reasons: the FRB-generated
  /// DTO has no `copyWith` (rebuilding it field-by-field would silently drop a
  /// field the day the contract grows one), and it mirrors the shape the app
  /// already uses for the shed feed — one overlay per feed, never merged across
  /// machines, since a directly-read hub reports an EMPTY shed and `(shed,slug)`
  /// would collide.
  final Map<String, MachinePatch> overlay;

  final bool reachable;

  /// Why it is unreachable, verbatim. Shown to the user because "no route to
  /// host" and "nothing is listening on 1029" are different problems with
  /// different fixes, and flattening them to "offline" throws away the only
  /// actionable part.
  final String? detail;

  /// Whether a snapshot has EVER arrived — distinguishes "still connecting"
  /// from "connected, and this machine genuinely has no sessions".
  final bool connectedOnce;

  /// The machine's per-kind affordances, from the one-shot `rc list` envelope.
  ///
  /// **Controls render off THIS, never off the kind.** A session whose
  /// `approvals` is `"tui"` reports approvals for information only — they are
  /// answered in its terminal — so offering an approve button would produce a
  /// `409 not_supported` the user cannot act on. `null` means the machine's
  /// binary predates capability discovery: degrade to observe-only rather than
  /// guessing.
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
  bool canSteer(BridgeRcSession s) => featuresFor(s)?.input == 'turn';

  /// Whether a running turn can be interrupted from here.
  bool canInterrupt(BridgeRcSession s) => featuresFor(s)?.interrupt ?? false;

  /// Whether an approval can be ANSWERED from here.
  ///
  /// `"remote"` means the hub can resolve it; `"tui"` means the rows are
  /// informational and the decision must be made in the session's terminal.
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

  /// The feed's high-water mark for this session, from `message.appended`.
  ///
  /// A NOTIFICATION, not content: the event says "there is something new past
  /// seq N", and the body comes from a follow-up `/messages` fetch. A watcher
  /// keyed on this is what makes the rich view live without polling.
  final BigInt? lastSeq;

  /// Later wins per FIELD, so an `activity.changed` cannot erase a seq bump
  /// that arrived first (and vice versa) — the two dimensions travel on
  /// separate events and must not clobber each other.
  MachinePatch merge(MachinePatch other) => MachinePatch(
    activity: other.activity ?? activity,
    state: other.state ?? state,
    lastSeq: other.lastSeq ?? lastSeq,
  );
}

/// **One machine's feed: the tunnel, the watcher, and the state they produce.**
///
/// Owns the phone-specific half of the lifecycle. Everything above the local
/// port is shared Rust (see `rust/src/api/machine.dart` and
/// `shed_app::machine`), so what lives here is exactly what a phone must decide:
/// when to hold an SSH connection open, and when to let it go.
///
/// ## Backgrounding is a STOP, not a stall
///
/// [stop] tears the tunnel and the watcher down; [start] rebuilds both. That is
/// deliberate rather than lazy: holding an SSH connection and an SSE stream open
/// behind a backgrounded phone is what drains a battery and gets an app killed
/// by the OS.
///
/// Resuming loses nothing, and that falls out of the WIRE rather than needing a
/// replay protocol: `/v1/sessions` is an authoritative snapshot, so a fresh
/// connection is a complete resync by construction.
class MachineFeed {
  MachineFeed({
    required this.machine,
    required this.identities,
    required this.hostKeys,
  }) : _state = MachineFeedState(machine: machine);

  final MachineRecord machine;
  final List<SSHKeyPair> identities;
  final HostKeyStore hostKeys;

  final _controller = StreamController<MachineFeedState>.broadcast();
  MachineFeedState _state;

  HubTunnel? _tunnel;
  BridgeMachineWatcher? _watcher;
  StreamSubscription<BridgeMachineUpdate>? _sub;
  bool _starting = false;

  /// The current view. Always available — a machine that has never connected
  /// still has a row, because "mini3 is asleep" IS the information.
  MachineFeedState get state => _state;

  Stream<MachineFeedState> get updates => _controller.stream;

  bool get isRunning => _watcher != null;

  /// The local port the hub is forwarded to, or null when the tunnel is down.
  ///
  /// Exposed so the rich session view can read the message cursor and post
  /// control verbs over the SAME tunnel the feed holds — a second connection
  /// per screen would double the SSH cost of simply looking at a session.
  int? get tunnelPort => _tunnel?.port;

  /// Open the tunnel and start watching. Idempotent, and safe to call on every
  /// foreground.
  Future<void> start() async {
    if (_watcher != null || _starting) return;
    _starting = true;
    try {
      final tunnel = await HubTunnel.open(
        machine: machine.name,
        host: machine.host,
        sshPort: machine.sshPort,
        user: machine.user ?? 'root',
        identities: identities,
        hostKeys: hostKeys,
      );
      _tunnel = tunnel;

      // Rust is handed the PORT and nothing else — no host, no key, no SSH.
      final watcher = await createMachineWatcher(
        machine: machine.name,
        localPort: tunnel.port,
      );
      _watcher = watcher;
      _sub = machineWatcherEvents(handle: watcher).listen(
        _apply,
        onError: (Object e) =>
            _emit(_state.copyWith(reachable: false, detail: 'feed error: $e')),
      );
      // Capabilities ride in the one-shot `list` envelope, not on the hub wire,
      // so this is a separate SSH round trip — done ONCE per start and not
      // awaited, because the feed must not be held up by it. Until it lands the
      // UI offers no controls, which is the correct degraded posture.
      unawaited(_loadCapabilities());
    } catch (e) {
      // Opening the tunnel failed (no route, auth refused). That is the
      // everyday asleep/unauthorized case, so it becomes a REASON on the row
      // rather than an exception the caller has to handle.
      await _teardown();
      _emit(_state.copyWith(reachable: false, detail: _describe(e)));
    } finally {
      _starting = false;
    }
  }

  /// Fetch the machine's per-kind affordances.
  ///
  /// A failure is deliberately SILENT: capabilities are what gate the controls,
  /// so not having them means observe-only — a correct, safe degradation that
  /// does not deserve an error banner on top of a working feed.
  Future<void> _loadCapabilities() async {
    try {
      // The MACHINE argv (`<rc_bin> rc list`), not the guest builder: a machine
      // has no `shed-ext-rc`, so the bare builder exits non-zero and this method
      // degrades to observe-only — silently, since a failed probe is not an
      // error. That silence hid the mistake until a live machine had a
      // steerable session on it.
      final argv = await machineListArgv(rcBin: machine.rcBin ?? 'sx');
      final res = await _ssh(argv, const Duration(seconds: 15));
      if (res.code != 0) return;
      final caps = await rcDecodeCapabilities(stdout: res.stdout);
      if (caps != null) _emit(_state.copyWith(capabilities: caps));
    } catch (_) {
      // observe-only
    }
  }

  /// Run one command on the machine over SSH — the one-shot path, distinct from
  /// the hub tunnel. Used for capabilities and for `kill`, which the hub does
  /// not serve (it observes and steers; it does not remove).
  Future<SshResult> _ssh(List<String> argv, Duration timeout) {
    final runner = SshRunner(
      host: machine.host,
      port: machine.sshPort,
      user: machine.user ?? 'root',
      identities: identities,
      hostKeys: hostKeys,
    );
    return runner.run(argv, timeout: timeout);
  }

  // -------------------------------------------------------------------------
  // Control verbs — every one gated by the CALLER on `kind_features`
  // -------------------------------------------------------------------------

  /// Start a turn. Only for a kind whose `input` is `turn`
  /// ([MachineFeedState.canSteer]).
  Future<void> steer(String slug, String text) async {
    final port = _tunnel?.port;
    if (port == null) throw StateError('the machine is not connected');
    await machineTurn(localPort: port, slug: slug, text: text);
  }

  /// Interrupt a running turn ([MachineFeedState.canInterrupt]).
  Future<bool> interrupt(String slug) async {
    final port = _tunnel?.port;
    if (port == null) throw StateError('the machine is not connected');
    return machineInterrupt(localPort: port, slug: slug);
  }

  /// Answer a pending approval ([MachineFeedState.canApprove]).
  Future<String> approve(String slug, String id, String decision) async {
    final port = _tunnel?.port;
    if (port == null) throw StateError('the machine is not connected');
    return machineApprove(
      localPort: port,
      slug: slug,
      id: id,
      decision: decision,
    );
  }

  /// Kill a session.
  ///
  /// Over SSH rather than the hub: the hub observes and steers, it does not
  /// remove. The row is dropped optimistically because the hub reconciles on a
  /// 2s active / 10s idle cadence, and a killed session lingering for ten
  /// seconds reads as "the kill didn't work"; the next snapshot is
  /// authoritative and restores it if the kill somehow failed.
  Future<void> kill(String slug) async {
    final argv = await machineKillArgv(
      rcBin: machine.rcBin ?? 'sx',
      slug: slug,
    );
    final res = await _ssh(argv, const Duration(seconds: 15));
    if (res.code != 0) {
      throw StateError(
        res.stderr.trim().isEmpty ? 'kill failed' : res.stderr.trim(),
      );
    }
    _emit(
      _state.copyWith(
        sessions: _state.sessions.where((s) => s.slug != slug).toList(),
      ),
    );
  }

  /// Stop watching and close the tunnel. Called on background and on dispose.
  Future<void> stop() async {
    await _teardown();
    _emit(_state.copyWith(reachable: false, detail: 'paused'));
  }

  Future<void> dispose() async {
    await _teardown();
    await _controller.close();
  }

  Future<void> _teardown() async {
    await _sub?.cancel();
    _sub = null;
    final watcher = _watcher;
    _watcher = null;
    if (watcher != null) {
      // The SYNCHRONOUS stop, not just a drop: it aborts the forwarder even
      // while it is parked waiting for the next update.
      await stopMachineWatcher(handle: watcher);
    }
    await _tunnel?.close();
    _tunnel = null;
  }

  void _apply(BridgeMachineUpdate update) {
    switch (update) {
      case BridgeMachineUpdate_Snapshot(:final sessions):
        // Authoritative: REPLACES rather than merges, and clears the overlay —
        // the snapshot already carries the activity dimension, so keeping old
        // patches would let a stale one win over fresh truth. This is what makes
        // a reconnect a complete resync.
        _emit(
          _state.copyWith(
            sessions: sessions,
            overlay: const {},
            reachable: true,
            connectedOnce: true,
            clearDetail: true,
          ),
        );
      case BridgeMachineUpdate_Event(:final event):
        _applyEvent(event);
      case BridgeMachineUpdate_Down(:final reason):
        // Sessions are deliberately NOT cleared — the last snapshot stays on
        // screen, marked stale, until the next connect resyncs it.
        _emit(_state.copyWith(reachable: false, detail: reason));
    }
  }

  /// Apply one feed event.
  ///
  /// Narrow on purpose: the activity dimension only. A session the snapshot does
  /// not know is left alone — the Rust watcher re-snapshots on an unknown slug,
  /// so the full row arrives that way rather than being synthesized from an
  /// event body that carries only a display subset.
  void _applyEvent(BridgeRcEvent event) {
    switch (event) {
      case BridgeRcEvent_ActivityChanged(
        :final slug,
        :final activity,
        :final state,
      ):
        _emit(
          _state.copyWith(
            overlay: _withPatch(
              slug,
              MachinePatch(activity: activity, state: state),
            ),
          ),
        );
      case BridgeRcEvent_SessionUpdated(
        :final slug,
        :final removed,
        :final state,
      ):
        if (removed) {
          _emit(
            _state.copyWith(
              sessions: _state.sessions.where((s) => s.slug != slug).toList(),
              overlay: {..._state.overlay}..remove(slug),
            ),
          );
          return;
        }
        _emit(
          _state.copyWith(
            overlay: _withPatch(slug, MachinePatch(state: state)),
          ),
        );
      case BridgeRcEvent_MessageAppended(:final slug, :final seq):
        // The seq only ever moves FORWARD within a hub run. A lower value means
        // the hub restarted (seq resets to 1), and the reader treats that as
        // "refetch from scratch" rather than a targeted drain — so it is passed
        // through unfiltered and interpreted there, where the cursor lives.
        _emit(
          _state.copyWith(
            overlay: _withPatch(slug, MachinePatch(lastSeq: seq)),
          ),
        );
      default:
        break;
    }
  }

  Map<String, MachinePatch> _withPatch(String slug, MachinePatch patch) {
    final next = {..._state.overlay};
    next[slug] = next[slug]?.merge(patch) ?? patch;
    return next;
  }

  void _emit(MachineFeedState next) {
    _state = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  /// A transport failure as a short, human reason — never the raw exception,
  /// which can carry detail not worth putting on a card.
  static String _describe(Object e) {
    if (e is SSHAuthAbortError || e is SSHAuthFailError) {
      return 'this device\'s key is not authorized on ${'the machine'}';
    }
    if (e is SSHStateError) return 'the SSH connection failed';
    return 'cannot reach the machine';
  }
}
