import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/scheduler.dart';

import '../bridge/bridge_adapters.dart';
import '../core/app_error.dart';
import '../src/rust/api/dto_lane.dart';
import '../src/rust/api/dto_rc.dart';
import '../src/rust/api/lane.dart';
import '../ssh/lane_forward.dart';
import 'lane_source.dart';
import 'lane_state.dart';
import 'probe_runner.dart';

/// The first re-open wait after a terminal `Down`, doubling to [laneRetryMax].
///
/// **Deliberately slower than Rust's 200 ms → 5 s resubscribe ladder.** Rust
/// retries a live adapter's stream — one HTTP request against a server it is
/// already connected to. Dart retries a WHOLE lane: an SSH probe, a forward, a
/// roster GET and a subscription, each a round trip. A phone that hammers that
/// every 200 ms behind a sleeping machine spends its battery discovering the
/// machine is still asleep.
const laneRetryBase = Duration(seconds: 1);

/// The ceiling on the re-open ladder.
const laneRetryMax = Duration(seconds: 30);

/// The `Down` reason that ends the retries: the agent does not know this
/// session, so no number of re-opens will find it. The desktop's
/// `DOWN_UNKNOWN_SESSION` rule.
const laneUnknownSession = 'unknown_session';

/// How the lane reaches its agent server, and therefore whether it needs a
/// forward at all.
///
/// The desktop's `ReachKind`, minus the SSH config entry (the phone's forward
/// comes from the machine's own feed, which already holds the connection).
enum LaneReach {
  /// The agent server is on THIS device's loopback: its ports are our ports,
  /// so the dial url is the reported url and there is nothing to forward. The
  /// hermetic harness (§3.13) runs here.
  local,

  /// The agent server is on the machine's loopback, reachable only through a
  /// forward on the feed's SSH connection.
  machine,
}

/// Borrow the forward to a far-side port. Production is
/// `MachineFeed.acquireForward`; the returned [LaneLease] is the lane's whole
/// obligation.
typedef ForwardAcquirer = Future<LaneLease> Function(int remotePort);

/// Run `pull` once, on the next animation frame. See [scheduleOnNextFrame].
typedef LaneFramePull = void Function(void Function() pull);

/// Wait, then continue. Injected so the backoff ladder is asserted on recorded
/// durations instead of on a test that sleeps for 39 seconds.
typedef LaneDelay = Future<void> Function(Duration wait);

/// Production batching: **at most one snapshot pull per animation frame**,
/// which is what the desktop's rAF batch does.
///
/// A burst of frames is already one nudge (Rust's dirty bit), so this bounds
/// the remaining case: nudges arriving faster than the UI paints. With the pull
/// synchronous and atomic under one lock, the desktop's `newestWins` guard is
/// not needed here — two pulls cannot interleave and produce a torn view.
void scheduleOnNextFrame(void Function() pull) {
  final binding = SchedulerBinding.instance;
  binding.addPostFrameCallback((_) => pull());
  // `addPostFrameCallback` does not itself ask for a frame, and a nudge lands
  // outside build — with nothing else dirtying the tree, the callback would sit
  // there until something unrelated repainted.
  binding.ensureVisualUpdate();
}

/// **One agent lane's logic, outside every widget** (plan 018 §3.11).
///
/// ```text
///   open()  ──probe (gx only)──▶ acquireForward ──▶ laneOpen ──▶ laneNudges
///                                                                    │
///   nudge ──(one per frame)──▶ laneSnapshot(sinceSeq) ──▶ LaneState ──┘
/// ```
///
/// ## One reconnect owner, and it is Rust
///
/// The single rule that decides most of this class: **Rust owns reconnection.**
/// Its pump carries the whole resubscribe ladder, so Dart has exactly two
/// lifecycle jobs, and both exist only because they need SSH:
///
/// * **`needsCredentials`** — gx's leader restarted mid-pin and wants a fresh
///   discovery. Dart re-runs the probe and calls `laneRefreshCredentials`.
///   **No re-open**: the pin resumes in place, generation and ring intact.
/// * **A terminal `Down`** (the snapshot's `stale`) — Rust has stopped. Dart
///   closes the handle, KEEPS the forward lease, and re-opens on the ladder
///   above.
///
/// Anything else that looks like a reconnect is not one. A dropped SSE stream,
/// a silent resume, a server reset, a reseed: all Rust's, all invisible here
/// except as a new generation in a snapshot.
///
/// ## The generation fence
///
/// Every open carries a generation, bumped by every teardown. A nudge, a
/// snapshot, a probe result or a queued retry from an earlier generation is
/// DROPPED. Without it a lane that re-opened while its predecessor's probe was
/// in flight would install the old handle behind the new one's back, and the
/// screen would render a transcript from a transport nobody holds.
///
/// ## What this class deliberately does not do
///
/// It does not fold (Rust does), it does not decode the probe (Rust does), it
/// does not own the SSH connection or the forward (the machine's feed does),
/// and it has no registry — "one lane per row" is `laneControllerProvider`'s
/// guarantee, because the bridge has no registry either.
class LaneController {
  LaneController({
    required this.machine,
    required this.slug,
    required BridgeAgentLaneStamp stamp,
    required this.source,
    required this.probe,
    required this.reach,
    this.acquireForward,
    Stream<BridgeAgentLaneStamp?>? stamps,
    LaneFramePull? schedulePull,
    LaneDelay? delay,
  }) : _schedulePull = schedulePull ?? scheduleOnNextFrame,
       _delay = delay ?? ((d) => Future<void>.delayed(d)) {
    _stamp = stamp;
    // A real check, not `assert`: this invariant must hold in release builds
    // too, or a machine-reach lane with no forward fails later and confusingly
    // (a bare `!` on a null `acquireForward`) instead of at construction.
    if (reach == LaneReach.machine && acquireForward == null) {
      throw ArgumentError.value(
        acquireForward,
        'acquireForward',
        'a lane on a machine needs a forward to reach it',
      );
    }
    // Full-stamp reconciliation. Subscribed in the constructor rather than in
    // `open()`: a row that disappears while the first open is still in flight
    // must still stop the retries.
    _stampSub = stamps?.listen(reconcile);
  }

  /// The machine this lane's agent runs on — for diagnostics and the provider
  /// key, never for transport (the feed owns that).
  final String machine;

  /// The ROW's slug (roost's tab id). The lane's identity on the phone, and
  /// deliberately not the agent session id: the session id is part of the stamp
  /// being reconciled, so it cannot also be the key that survives a change to
  /// it.
  final String slug;

  final LaneSource source;
  final ProbeRunner probe;
  final LaneReach reach;
  final ForwardAcquirer? acquireForward;

  final LaneFramePull _schedulePull;
  final LaneDelay _delay;

  final _controller = StreamController<LaneState>.broadcast();
  LaneState _state = LaneState();

  /// Set in the constructor body and replaced only by [reconcile]. `late`
  /// rather than an initializing formal because the field is private and the
  /// parameter is not: a caller should name `stamp`.
  late BridgeAgentLaneStamp _stamp;
  StreamSubscription<BridgeAgentLaneStamp?>? _stampSub;

  LaneHandle? _handle;
  StreamSubscription<bool>? _nudges;
  LaneLease? _lease;

  /// The cursor for the next snapshot: the highest seq Dart holds. Null asks
  /// for the whole generation, which is what a fresh open wants.
  BigInt? _cursor;

  /// Bumped by every teardown — see "the generation fence" above.
  int _generation = 0;

  bool _opening = false;
  bool _closed = false;
  bool _abandoned = false;
  bool _pullPending = false;
  bool _refreshing = false;

  /// The generation whose `stale` has already been acted on, so a second
  /// snapshot carrying the same `stale` does not start a second re-open.
  int? _staleHandled;

  Duration _backoff = laneRetryBase;

  /// The current view. Always available — a lane that has never opened still
  /// renders a header and, once it fails, a reason.
  LaneState get state => _state;

  Stream<LaneState> get updates => _controller.stream;

  /// The stamp this lane is open (or opening) against.
  BridgeAgentLaneStamp get stamp => _stamp;

  /// Whether a lane handle is currently held. Diagnostics and tests only.
  @visibleForTesting
  bool get isOpen => _handle != null;

  /// **Open the lane: probe, forward, `lane_open`, subscribe.** Idempotent and
  /// safe to call on every frame — a second call with a handle already held, an
  /// open in flight, or after [close]/an abandon, returns immediately.
  ///
  /// The ORDER is the contract. The gx probe comes first because its bytes are
  /// an argument to `lane_open` (Rust parses them into the discovery it pins
  /// the epoch with); the forward comes next because the dial url names its
  /// local port. Reversing either would mean opening a lane that cannot dial or
  /// cannot authenticate, and discovering it a round trip later.
  Future<void> open() async {
    if (_closed || _abandoned || _handle != null || _opening) return;
    _opening = true;
    final generation = ++_generation;
    Object? failure;
    try {
      await _openOnce(generation);
    } catch (e) {
      failure = e;
    }
    _opening = false;
    if (failure == null) return;
    // A teardown that landed while the open was in flight has already decided
    // this lane's future; its failure is nobody's news.
    if (_closed || _abandoned || generation != _generation) return;
    final error = appErrorFrom(failure);
    final permanent = laneFailureIsPermanent(failure);
    _abandoned = permanent;
    _emit(
      _state.copyWith(error: error, retrying: !permanent, abandoned: permanent),
    );
    // A transient failure — an asleep machine, a refused dial — is exactly what
    // the ladder is for. A permanent one (no adapter for this kind, no such
    // session) would be a hot loop against an answer that cannot change.
    if (!permanent) unawaited(_reopen(keepLease: true));
  }

  /// Whether a teardown or a newer open has moved on since [generation] was
  /// captured — see "the generation fence" above. Checked at every await point
  /// in [_openOnce] that could otherwise install a stale handle behind a newer
  /// open's back.
  bool _superseded(int generation) => generation != _generation;

  Future<void> _openOnce(int generation) async {
    final stamp = _stamp;

    Uint8List? probeStdout;
    if (stamp.kind == _gxKind) {
      // Verbatim, unquoted, unread. See [ProbeRunner].
      probeStdout = await probe(source.gxProbeCommand());
      if (_superseded(generation)) return;
    }

    if (reach == LaneReach.machine && _lease?.isValid != true) {
      // A lease from a previous generation whose forward died with the feed is
      // no use to the new one, and holding it would leak a refcount.
      await _releaseLease();
      final lease = await acquireForward!(laneRemotePort(stamp.serverUrl));
      if (_superseded(generation)) {
        await lease.release();
        return;
      }
      _lease = lease;
    }

    final spec = BridgeLaneSpec(
      kind: stamp.kind,
      sessionId: stamp.sessionId,
      // The two are NEVER conflated: a gx discovery record is matched against
      // the reported url, while the dial goes to this phone's own forward.
      reportedUrl: stamp.serverUrl,
      dialUrl: reach == LaneReach.local
          ? stamp.serverUrl
          : laneDialUrl(stamp.serverUrl, _lease!.port),
      gxProbeStdout: probeStdout,
    );

    final handle = await source.open(spec);
    if (_superseded(generation)) {
      source.close(handle);
      return;
    }
    _handle = handle;
    _cursor = null;
    _staleHandled = null;
    _nudges = source
        .nudges(handle)
        .listen(
          (_) => _onNudge(generation),
          // A nudge stream that errors is still a "something changed" signal, and
          // the snapshot is the authority on what. It ends only on `lane_close`.
          onError: (Object _) => _onNudge(generation),
        );
    _emit(
      _state.copyWith(
        capabilities: source.capabilities(handle),
        clearError: true,
        retrying: false,
        abandoned: false,
      ),
    );
    // The roster row was fetched before the pump started, so there is already
    // something to read; waiting for the first nudge would leave the screen
    // blank for one round trip.
    _pull(generation);
  }

  // ---- the read side ------------------------------------------------------

  void _onNudge(int generation) {
    if (generation != _generation || _pullPending) return;
    _pullPending = true;
    _schedulePull(() {
      _pullPending = false;
      _pull(generation);
    });
  }

  void _pull(int generation) {
    if (generation != _generation) return;
    final handle = _handle;
    if (handle == null) return;

    final snap = source.snapshot(handle, _cursor);

    // The ONE merge this side does. `full` means "replace what you hold" —
    // which is also how a generation change, a resubscription and a cursor
    // evicted by the row cap all arrive, so there is no delta with a hole in
    // it to reason about. A non-full snapshot with no new rows (a nudge that
    // was only new activity or approvals) keeps the existing list rather than
    // reallocating a copy of it every such pull.
    final rows = snap.full
        ? List<BridgeRcFeedMessage>.unmodifiable(snap.messages)
        : snap.messages.isEmpty
        ? _state.rows
        : List<BridgeRcFeedMessage>.unmodifiable([
            ..._state.rows,
            ...snap.messages,
          ]);
    if (snap.messages.isNotEmpty) {
      _cursor = snap.messages.last.seq;
    } else if (snap.full) {
      // A full answer with no rows is a generation with no rows: the cursor
      // Dart held names a seq in a window that no longer exists.
      _cursor = null;
    }

    // The ladder resets only on a HEALTHY generation, not on a successful
    // open: an agent that accepts a connection and dies inside it would
    // otherwise be retried every second forever.
    if (snap.stale == null && snap.generation > BigInt.zero) {
      _backoff = laneRetryBase;
    }

    _emit(
      _state.copyWith(
        rows: rows,
        activity: snap.activity,
        generation: snap.generation,
        approvals: snap.approvals.isEmpty && _state.approvals.isEmpty
            ? _state.approvals
            : List<BridgeLaneApproval>.unmodifiable(snap.approvals),
        needsCredentials: snap.needsCredentials,
        stale: snap.stale,
        clearStale: snap.stale == null,
      ),
    );

    if (snap.needsCredentials) unawaited(_refreshCredentials(generation));
    final stale = snap.stale;
    if (stale != null) _onStale(generation, stale);
  }

  /// gx asked for a fresh discovery: probe again and hand the bytes over.
  /// **No re-open** — that is the whole point of the ask (§3.9).
  Future<void> _refreshCredentials(int generation) async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final stdout = await probe(source.gxProbeCommand());
      if (generation != _generation) return;
      final handle = _handle;
      if (handle == null) return;
      await source.refreshCredentials(handle, stdout);
    } catch (e) {
      if (generation == _generation) {
        _emit(_state.copyWith(error: appErrorFrom(e)));
      }
    } finally {
      _refreshing = false;
    }
  }

  /// The pump ended on a terminal `Down`. Rust has stopped; Dart re-opens.
  void _onStale(int generation, String reason) {
    if (_staleHandled == generation) return;
    _staleHandled = generation;
    if (reason.contains(laneUnknownSession)) {
      // The agent does not know this session. Re-opening would ask the same
      // question and get the same answer, forever.
      unawaited(_abandon());
      return;
    }
    unawaited(_reopen(keepLease: true));
  }

  // ---- the verbs ----------------------------------------------------------

  /// Send `text` to the session. `Interject` needs
  /// [BridgeLaneCapabilities.interject]; an adapter that cannot do it answers
  /// `not_accepting`, which lands on the composer as an inline error.
  ///
  /// Never throws: a refusal is state, because the control that raised it is
  /// the only place it means anything.
  Future<void> send(
    String text, {
    BridgeSendMode mode = BridgeSendMode.queue,
  }) => _composerVerb((handle) => source.send(handle, text: text, mode: mode));

  /// Stop the turn in flight. `not_accepting` here means the turn ended between
  /// the render and the tap — an inline error next to the button, not a toast.
  Future<void> cancel() => _composerVerb(source.cancel);

  /// Answer one approval. A refusal lands on THAT card
  /// ([LaneState.approvalErrors]), which is the only place it is legible: gx
  /// refuses a `Permission` whose decision matches no offered option, and
  /// either adapter refuses a second answer to one approval.
  Future<void> answer(String approvalId, BridgeLaneAnswer answer) =>
      _guardedVerb(
        (handle) =>
            source.answer(handle, approvalId: approvalId, answer: answer),
        clearError: () => _emit(
          _state.copyWith(approvalErrors: _withoutApprovalError(approvalId)),
        ),
        setError: (error) => _emit(
          _state.copyWith(
            approvalErrors: _withApprovalError(approvalId, error),
          ),
        ),
      );

  Future<void> _composerVerb(Future<void> Function(LaneHandle) verb) =>
      _guardedVerb(
        verb,
        clearError: () => _emit(_state.copyWith(clearComposerError: true)),
        setError: (error) => _emit(_state.copyWith(composerError: error)),
      );

  /// The shape every verb shares: no handle is a `_noLane()` refusal, a
  /// refusal from a since-superseded generation is nobody's news, and
  /// everything else never throws past here — a refusal is state, landed by
  /// [setError] on whichever card raised it.
  Future<void> _guardedVerb(
    Future<void> Function(LaneHandle) verb, {
    required void Function() clearError,
    required void Function(AppError error) setError,
  }) async {
    final handle = _handle;
    if (handle == null) {
      setError(_noLane());
      return;
    }
    final generation = _generation;
    clearError();
    try {
      await verb(handle);
    } catch (e) {
      if (generation != _generation) return;
      setError(appErrorFrom(e));
    }
  }

  Map<String, AppError> _withApprovalError(String id, AppError error) =>
      Map<String, AppError>.unmodifiable({..._state.approvalErrors, id: error});

  Map<String, AppError> _withoutApprovalError(String id) =>
      Map<String, AppError>.unmodifiable(
        {..._state.approvalErrors}..remove(id),
      );

  AppError _noLane() =>
      AppError('LANE_NOT_OPEN', 'the lane is not open right now');

  // ---- reconciliation -----------------------------------------------------

  /// **Full-stamp reconciliation** against the machine feed's rows.
  ///
  /// Row-presence is not enough, and the difference is a real bug rather than a
  /// nicety: a tab that restarted is present with a NEW port, and a lane that
  /// only checked presence would keep talking to a forward that reaches nothing
  /// while the screen showed a live-looking transcript. So the whole
  /// `{kind, sessionId, serverUrl}` stamp is compared:
  ///
  /// * **gone** → close and stop retrying;
  /// * **changed** → close, give the forward back (the port may have moved) and
  ///   re-open against the new stamp, immediately — a new stamp is news, not a
  ///   failure, so it does not wait out a backoff.
  void reconcile(BridgeAgentLaneStamp? stamp) {
    if (_closed) return;
    if (stamp == null) {
      if (_abandoned) return;
      unawaited(_abandon());
      return;
    }
    if (stamp == _stamp) return;
    _stamp = stamp;
    // A new stamp revives a lane that was given up on: whatever was permanent
    // about the old one was a property of the old one.
    _abandoned = false;
    _backoff = laneRetryBase;
    unawaited(_reopenNow());
  }

  Future<void> _reopenNow() async {
    await _dropHandle(releaseLease: true);
    _emit(
      _state.copyWith(
        rows: const [],
        approvals: const [],
        approvalErrors: const {},
        needsCredentials: false,
        clearStale: true,
        clearError: true,
        clearComposerError: true,
        retrying: false,
        abandoned: false,
      ),
    );
    await open();
  }

  /// Drop the handle, wait out the ladder, open again.
  ///
  /// `keepLease` is true for every re-open Rust's `Down` provoked: the local
  /// port is fixed for the forward's life and the forward re-dials the SSH
  /// channel underneath it, so giving the lease back would close a forward the
  /// next open needs and cost an extra SSH channel to rebuild.
  Future<void> _reopen({required bool keepLease}) async {
    await _dropHandle(releaseLease: !keepLease);
    // Captured AFTER the drop, which bumped the generation: any later teardown
    // (a close, a stamp change, another re-open) bumps it again and this queued
    // retry drops itself instead of racing the newer one.
    final token = _generation;
    final wait = _backoff;
    _backoff = wait * 2 > laneRetryMax ? laneRetryMax : wait * 2;
    _emit(_state.copyWith(retrying: true));
    await _delay(wait);
    if (_closed || _abandoned || token != _generation) return;
    await open();
  }

  Future<void> _abandon() async {
    _abandoned = true;
    await _dropHandle(releaseLease: true);
    _emit(_state.copyWith(abandoned: true, retrying: false));
  }

  // ---- teardown -----------------------------------------------------------

  /// **End the lane.** Closes the handle, gives the forward back, cancels the
  /// nudge subscription and bumps the generation. Idempotent — the provider's
  /// `onDispose` calls it, and so may a screen that is done.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _stampSub?.cancel();
    _stampSub = null;
    await _dropHandle(releaseLease: true);
    await _controller.close();
  }

  Future<void> _dropHandle({required bool releaseLease}) async {
    _generation++;
    _pullPending = false;
    _staleHandled = null;
    final nudges = _nudges;
    _nudges = null;
    await nudges?.cancel();
    final handle = _handle;
    _handle = null;
    _cursor = null;
    // AFTER the subscription is cancelled: `lane_close` ends the nudge stream,
    // and a cancel racing that end is the one ordering that can drop a
    // teardown on the floor.
    if (handle != null) source.close(handle);
    if (releaseLease) await _releaseLease();
  }

  Future<void> _releaseLease() async {
    final lease = _lease;
    _lease = null;
    // Nulled first, so a second release cannot reach the registry — the
    // refcount is what closes the forward, and giving one lease back twice
    // closes a forward somebody else is using.
    await lease?.release();
  }

  void _emit(LaneState next) {
    _state = next;
    if (!_controller.isClosed) _controller.add(next);
  }
}

const _gxKind = 'gx';

/// Whether a failed open can never succeed, so the ladder must not run.
///
/// The three permanent shapes, and each is a property of the ROW rather than of
/// the moment: this build has no adapter for the kind, the handle carries no
/// lane at all, or the agent does not know the session. Everything else — a
/// refused dial, an asleep machine, a probe that failed because the SSH link
/// was down — is exactly what a retry is for.
@visibleForTesting
bool laneFailureIsPermanent(Object failure) => switch (failure) {
  BridgeLaneError_UnsupportedLane() => true,
  BridgeLaneError_NoLane() => true,
  BridgeLaneError_UnknownSession() => true,
  _ => false,
};

/// The far-side port a lane's forward must reach, from the REPORTED url.
///
/// Throws a typed [AppError] rather than a `FormatException`: an agent that
/// announced an unusable url is a row the user can see, and "not usable" with
/// the url in it is the only actionable thing to say about it.
@visibleForTesting
int laneRemotePort(String serverUrl) {
  final uri = Uri.tryParse(serverUrl);
  // `Uri.port` answers the scheme's default when none was given, and 0 for a
  // scheme it has no default for — which is the one answer no forward can use.
  final port = uri == null ? 0 : uri.port;
  if (port == 0) {
    throw AppError(
      'LANE_BAD_SERVER_URL',
      'the agent server url $serverUrl names no port to reach',
    );
  }
  return port;
}

/// The reported url, re-pointed at this phone's own forward.
///
/// `replace` rather than string-building: it keeps the scheme and any path the
/// agent announced, and only the authority — which is exactly what a forward
/// changes — moves.
@visibleForTesting
String laneDialUrl(String serverUrl, int localPort) =>
    Uri.parse(serverUrl).replace(host: '127.0.0.1', port: localPort).toString();
