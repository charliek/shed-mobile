import 'dart:async';

import 'package:dartssh2/dartssh2.dart';

import '../src/rust/api/dto_rc.dart';
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

  MachineFeedState copyWith({
    List<BridgeRcSession>? sessions,
    Map<String, MachinePatch>? overlay,
    bool? reachable,
    String? detail,
    bool? connectedOnce,
    bool clearDetail = false,
  }) => MachineFeedState(
    machine: machine,
    sessions: sessions ?? this.sessions,
    overlay: overlay ?? this.overlay,
    reachable: reachable ?? this.reachable,
    detail: clearDetail ? null : (detail ?? this.detail),
    connectedOnce: connectedOnce ?? this.connectedOnce,
  );

  /// A session's activity, with the live patch applied.
  BridgeRcActivity? activityOf(BridgeRcSession s) =>
      overlay[s.slug]?.activity ?? s.activity;

  /// A session's lifecycle state, with the live patch applied.
  BridgeRcState stateOf(BridgeRcSession s) => overlay[s.slug]?.state ?? s.state;
}

/// One session's live patch — the activity dimension only.
class MachinePatch {
  const MachinePatch({this.activity, this.state});

  final BridgeRcActivity? activity;
  final BridgeRcState? state;

  MachinePatch merge(MachinePatch other) => MachinePatch(
    activity: other.activity ?? activity,
    state: other.state ?? state,
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
