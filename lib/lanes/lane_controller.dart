import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/scheduler.dart';

import '../bridge/bridge_adapters.dart';
import '../core/app_error.dart';
import '../src/rust/api/dto_lane.dart';
import '../src/rust/api/dto_rc.dart';
import '../src/rust/api/lane.dart';
import '../ssh/lane_forward.dart';
import 'lane_settings.dart';
import 'lane_source.dart';
import 'lane_state.dart';

/// The first re-open wait after a lane ENDED (a terminal `Down`), doubling to
/// [laneRetryMax].
///
/// **Deliberately slower than Rust's 200 ms → 5 s resubscribe ladder.** Rust
/// retries a live adapter's stream — one HTTP request against a server it is
/// already connected to. Dart retries a WHOLE lane: a forward, a roster GET
/// and a subscription, each a round trip. A phone that hammers that every
/// 200 ms behind a sleeping machine spends its battery discovering the machine
/// is still asleep.
const laneRetryBase = Duration(seconds: 1);

/// The ceiling on the re-open ladder.
const laneRetryMax = Duration(seconds: 30);

/// The `Down` reason a lane ends with when the agent does not know this
/// session (opencode: a reseed answered 404; craze: `unknown_session` on
/// connect or attach). One of the three [laneDownIsFinal] reasons.
const laneUnknownSession = 'unknown_session';

/// The `Down` reason a craze lane ends with when its session CLOSED — craze's
/// end after a stop (`reset{session_closed}`). One of the three
/// [laneDownIsFinal] reasons.
const laneSessionClosed = 'session_closed';

/// The `Down` reason a craze lane ends with when its session never started —
/// `start_failed: <craze's cause>`. One of the three [laneDownIsFinal] reasons.
const laneStartFailed = 'start_failed';

/// **Whether a lane that ENDED with this `Down` reason is gone for good**, so
/// nothing re-opens it — the desktop's `down_is_final`, word for word, and
/// the phone's Rust pump says the same (`rust/src/api/lane.rs`).
///
/// `shed_core::lane`'s module doc (plan 025 §3.3.5) names three: the session
/// does not exist ([laneUnknownSession]), it was closed ([laneSessionClosed],
/// craze's end after a stop), or it never started ([laneStartFailed], with
/// craze's cause after a colon). No number of re-opens changes any of them: a
/// stopped session re-opened would only be told it is gone, and one that failed
/// to start would only repeat why. Every other `Down` is worth another attempt
/// (the agent restarted, the tunnel blipped, a bound ran out). Exact words, not
/// substrings: `session_closed_soon` is not a session that closed.
bool laneDownIsFinal(String reason) =>
    reason == laneUnknownSession ||
    reason == laneSessionClosed ||
    reason == laneStartFailed ||
    reason.startsWith('$laneStartFailed:');

/// What the composer says when a SEND's answer was lost (an
/// `LANE_OUTCOME_UNKNOWN`, plan 025 §3.3.4): the prompt may or may not have
/// started a turn, it is never resent, and the typed text stays in the box —
/// so the screen says plainly what to do before pressing Send again, and the
/// person decides. The desktop's `SEND_OUTCOME_UNKNOWN`, word for word.
const laneSendOutcomeUnknown =
    'outcome unknown: the connection to craze dropped; check the transcript '
    'before sending again';

/// The stamp kind of a CRAZE session's lane (plan 025 §3.7.2).
///
/// A craze row carries no stamp of roost's — its lane is the machine's craze
/// source's to open, by the row's hostId — so the controller is handed a
/// synthesized one (`kind` this, `sessionId` the hostId, no `serverUrl`), and
/// BRANCHES on this kind before anything else: no forward is ever
/// acquired for it (the lane reaches its session through the source's own
/// dial, the hub's splice), and it opens through [LaneSource.openCraze].
const crazeLaneKind = 'craze';

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
///   open()  ──acquireForward──▶ laneOpen ──▶ laneNudges
///                                                 │
///   nudge ──(one per frame)──▶ laneSnapshot(sinceSeq) ──▶ LaneState ──┘
/// ```
///
/// ## One reconnect owner, and it is Rust
///
/// The single rule that decides most of this class: **Rust owns reconnection.**
/// Its pump carries the whole resubscribe ladder, so Dart has exactly one
/// lifecycle job, and it exists only because it needs SSH: **a lane that
/// ENDED** (the snapshot's `ended`, set by a terminal `Down` and by nothing
/// else). Dart closes the handle, KEEPS the forward lease, and re-opens on the
/// ladder above.
///
/// Anything else that looks like a reconnect is not one. A dropped SSE stream,
/// a server reset, a reseed: all Rust's, all invisible here except as a new
/// generation in a snapshot. **And a `stale` that has not ended is not one
/// either** (plan 025 §3.2.4): an adapter that can resume from a cursor (craze)
/// marks the view stale when its transport drops and clears the mark with a
/// lone `Ready` once it has resumed — no reseed, the same generation. A
/// re-open there would tear down the very lane that is resuming and throw its
/// cursor away, so `stale` is the banner's and only `ended` is this class's.
///
/// ## The generation fence
///
/// Every open carries a generation, bumped by every teardown. A nudge, a
/// snapshot or a queued retry from an earlier generation is DROPPED. Without it
/// a lane that re-opened while its predecessor's open was still in flight would
/// install the old handle behind the new one's back, and the screen would
/// render a transcript from a transport nobody holds.
///
/// ## What this class deliberately does not do
///
/// It does not fold (Rust does), it does not own the SSH connection or the
/// forward (the machine's feed does), and it has no registry — "one lane per
/// row" is `laneControllerProvider`'s guarantee, because the bridge has no
/// registry either.
class LaneController {
  LaneController({
    required this.machine,
    required this.slug,
    required BridgeAgentLaneStamp stamp,
    required this.source,
    required this.reach,
    this.acquireForward,
    this.openCrazeLane,
    this.crazeSourceEpoch,
    Stream<int?>? crazeSources,
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
    // The same check for the craze branch: a craze stamp with no way to open
    // through the machine's craze source would fail on every retry instead of
    // here.
    if (stamp.kind == crazeLaneKind && openCrazeLane == null) {
      throw ArgumentError.value(
        openCrazeLane,
        'openCrazeLane',
        'a craze lane opens through its machine\'s craze source',
      );
    }
    // Full-stamp reconciliation. Subscribed in the constructor rather than in
    // `open()`: a row that disappears while the first open is still in flight
    // must still stop the retries.
    _stampSub = stamps?.listen(reconcile);
    // The craze source a craze lane rides is the FEED's, and a feed restart
    // replaces it — see [_syncCrazeSource].
    if (stamp.kind == crazeLaneKind) {
      _crazeSourceSub = crazeSources?.listen((_) => _syncCrazeSource());
    }
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
  final LaneReach reach;
  final ForwardAcquirer? acquireForward;

  /// How a CRAZE stamp's lane is opened — the machine feed's craze source
  /// (`MachineFeed.openCrazeLane`). Unused for every other kind.
  final CrazeLaneOpen? openCrazeLane;

  /// The epoch of the craze source a craze lane opens through NOW — the
  /// feed's live source (`MachineFeed.crazeLiveEpoch`), or null while it has
  /// none (a stopped or restarting feed, or a source not seeded yet). Read at
  /// every open, so this lane knows which source its handle belongs to.
  final int? Function()? crazeSourceEpoch;

  final LaneFramePull _schedulePull;
  final LaneDelay _delay;

  final _controller = StreamController<LaneState>.broadcast();
  LaneState _state = LaneState();

  /// Set in the constructor body and replaced only by [reconcile]. `late`
  /// rather than an initializing formal because the field is private and the
  /// parameter is not: a caller should name `stamp`.
  late BridgeAgentLaneStamp _stamp;
  StreamSubscription<BridgeAgentLaneStamp?>? _stampSub;

  /// The feed's craze-source transitions (`MachineFeed.crazeSources`): a
  /// trigger for [_syncCrazeSource], which reads [crazeSourceEpoch] for the
  /// truth.
  StreamSubscription<int?>? _crazeSourceSub;

  /// The epoch of the craze source this lane's handle was opened through —
  /// see [_syncCrazeSource].
  int? _openedEpoch;

  /// The epoch the latest craze open went through, set when it STARTS — so a
  /// failed open can tell "its source was retired under it" from an ordinary
  /// failure.
  int? _openingEpoch;

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

  /// The generation whose `ended` has already been acted on, so a second
  /// snapshot carrying the same `ended` does not start a second re-open.
  int? _endHandled;

  Duration _backoff = laneRetryBase;

  /// The `Settings` frames counted by the handles this lane has already let
  /// go of — what keeps [LaneState.settingsSeen] monotonic across re-opens,
  /// each handle counting from zero.
  int _framesBefore = 0;

  /// The current handle's count of `Settings` frames, as last taken from a
  /// LIVE read (see [_pull]).
  int _framesNow = 0;

  /// Each settings row's latest press, by [SettingsRow.key] — an answer
  /// settles its row only while its press is still the row's latest, so one
  /// that lands after a new stamp cleared the marks (and the row was pressed
  /// again) settles nothing.
  final Map<String, int> _presses = {};
  int _pressSeq = 0;

  /// The current view. Always available — a lane that has never opened still
  /// renders a header and, once it fails, a reason.
  LaneState get state => _state;

  Stream<LaneState> get updates => _controller.stream;

  /// The stamp this lane is open (or opening) against.
  BridgeAgentLaneStamp get stamp => _stamp;

  /// Whether a lane handle is currently held. Diagnostics and tests only.
  @visibleForTesting
  bool get isOpen => _handle != null;

  /// The lane handle held now, or null. Tests only: what a silent-resume cell
  /// compares across the outage — the SAME handle, never a re-open.
  @visibleForTesting
  LaneHandle? get handle => _handle;

  /// **Open the lane: forward, `lane_open`, subscribe.** Idempotent and safe to
  /// call on every frame — a second call with a handle already held, an open
  /// in flight, or after [close]/an abandon, returns immediately.
  ///
  /// The forward comes first because the dial url names its local port.
  /// Opening the lane before the forward exists would mean dialing a port
  /// nothing is listening on yet. A CRAZE lane has no forward at all: it opens
  /// through its machine's craze source ([crazeLaneKind]).
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
    if (failure == null) {
      // The machine's craze source may have been replaced while this open was
      // in flight; a handle through the retired one is moved now.
      _syncCrazeSource();
      return;
    }
    // A teardown that landed while the open was in flight has already decided
    // this lane's future; its failure is nobody's news.
    if (_closed || _abandoned || generation != _generation) return;
    final error = appErrorFrom(failure);
    final permanent = laneFailureIsPermanent(failure);
    // A craze open that failed because the source it went through was RETIRED
    // under it is the source's business, not the ladder's: the lane waits for
    // the replacement exactly as an open lane does ([_syncCrazeSource]).
    if (!permanent && _openedThroughRetiredSource()) {
      _sourceWait = true;
      _emit(_state.copyWith(retrying: true, stale: 'reconnecting'));
      _syncCrazeSource();
      return;
    }
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

    // **A craze lane branches BEFORE any forward** (plan 025 §3.7.2). Its
    // session sits behind the machine's craze hub, reached through the craze
    // source's own dial — there is no agent port to forward to and no URL to
    // re-point, so acquiring a lease here would hold an SSH channel to nothing.
    final LaneHandle handle;
    int? epoch;
    if (stamp.kind == crazeLaneKind) {
      final open = openCrazeLane;
      if (open == null) {
        throw StateError('no craze source to open ${stamp.sessionId} through');
      }
      // Read in the same synchronous run as the opener reads the feed's
      // source, so the two cannot name different sources.
      epoch = crazeSourceEpoch?.call();
      _openingEpoch = epoch;
      handle = await source.openCraze(open, stamp.sessionId);
    } else {
      final opened = await _openForwarded(stamp, generation);
      // Superseded while the forward was being acquired: nothing was opened.
      if (opened == null) return;
      handle = opened;
    }
    if (_superseded(generation)) {
      source.close(handle);
      return;
    }
    _handle = handle;
    _openedEpoch = epoch;
    _sourceWait = false;
    _cursor = null;
    _endHandled = null;
    _nudges = source
        .nudges(handle)
        .listen(
          (_) => _onNudge(generation),
          // A nudge stream that errors is still a "something changed" signal, and
          // the snapshot is the authority on what. It ends only on `lane_close`.
          onError: (Object _) => _onNudge(generation),
        );
    _emit(_state.copyWith(clearError: true, retrying: false, abandoned: false));
    // The roster row was fetched before the pump started, so there is already
    // something to read; waiting for the first nudge would leave the screen
    // blank for one round trip. It is also the first read of the session's
    // capabilities: there is no separate call to cache them at open (plan 025
    // §3.2.1) — they come with every snapshot, null until a seed carries them.
    _pull(generation);
  }

  /// A stamped lane's open: the forward first — the dial url names its local
  /// port, so opening the lane before the forward exists would dial a port
  /// nothing listens on yet — then `lane_open`.
  ///
  /// Null when a teardown superseded [generation] while the forward was being
  /// acquired (the lease is given back here). A handle opened after one is
  /// still returned: the caller's fence closes it.
  Future<LaneHandle?> _openForwarded(
    BridgeAgentLaneStamp stamp,
    int generation,
  ) async {
    if (reach == LaneReach.machine && _lease?.isValid != true) {
      // A lease from a previous generation whose forward died with the feed is
      // no use to the new one, and holding it would leak a refcount.
      await _releaseLease();
      final lease = await acquireForward!(laneRemotePort(stamp.serverUrl));
      if (_superseded(generation)) {
        await lease.release();
        return null;
      }
      _lease = lease;
    }

    final spec = BridgeLaneSpec(
      kind: stamp.kind,
      sessionId: stamp.sessionId,
      // The two are NEVER conflated: the dial goes to this phone's own
      // forward, never to the reported url.
      reportedUrl: stamp.serverUrl,
      dialUrl: reach == LaneReach.local
          ? stamp.serverUrl
          : laneDialUrl(stamp.serverUrl, _lease!.port),
    );
    return source.open(spec);
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

    // The settings clock (plan 025 §3.10) moves only with a LIVE read. A
    // `Settings` inside a reseed is counted when Rust folds it, a moment
    // before its seed's `Ready` shows it — and a lost answer means a drop,
    // which leaves `stale` set until that `Ready` (or a resume's): taking the
    // count then would let a "not confirmed" mark go before the value that
    // replaces it is on screen.
    if (snap.stale == null) _framesNow = snap.settingsFrames.toInt();

    _emit(
      _state.copyWith(
        rows: rows,
        activity: snap.activity,
        generation: snap.generation,
        approvals: snap.approvals.isEmpty && _state.approvals.isEmpty
            ? _state.approvals
            : List<BridgeLaneApproval>.unmodifiable(snap.approvals),
        stale: snap.stale,
        clearStale: snap.stale == null,
        ended: snap.ended,
        // Every snapshot, verbatim — including a null, which is "not seeded
        // yet" or "no settings", never "keep what you had".
        live: (
          session: snap.session,
          capabilities: snap.capabilities,
          settings: snap.settings,
        ),
        settingsSeen: _framesBefore + _framesNow,
      ),
    );

    // `ended`, never `stale`: see "One reconnect owner" above.
    if (snap.ended) _onEnded(generation, snap.stale ?? '');
  }

  /// The lane's subscription ENDED on a terminal `Down`. Dart re-opens — unless
  /// the reason says no re-open can ever succeed ([laneDownIsFinal]).
  void _onEnded(int generation, String reason) {
    if (_endHandled == generation) return;
    _endHandled = generation;
    if (laneDownIsFinal(reason)) {
      // The session is gone, closed, or never started. Re-opening would ask the
      // same question and get the same answer, forever. The transcript stays.
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
  /// the only place it means anything. A send whose answer was LOST is said in
  /// the desktop's words ([laneSendOutcomeUnknown]) — never resent, its text
  /// kept, the person decides.
  Future<void> send(
    String text, {
    BridgeSendMode mode = BridgeSendMode.queue,
  }) => _guardedVerb(
    (handle) => source.send(handle, text: text, mode: mode),
    clearError: () => _emit(_state.copyWith(clearComposerError: true)),
    setError: (error) => _emit(
      _state.copyWith(
        composerError: error.code == laneOutcomeUnknownCode
            ? AppError(laneOutcomeUnknownCode, laneSendOutcomeUnknown)
            : error,
      ),
    ),
  );

  /// Stop the turn in flight. `not_accepting` here means the turn ended between
  /// the render and the tap — an inline error next to the button, not a toast.
  Future<void> cancel() => _composerVerb(source.cancel);

  /// **End the SESSION** (plan 025 §3.7.3) — offered only when the snapshot's
  /// capabilities say `stop`, behind a confirm. Its `Ok` is the host's
  /// receipt, not the end: the session's close arrives on the stream as
  /// `Down{"session_closed"}`, which ends this lane for good
  /// ([laneDownIsFinal]) with the transcript kept. A refusal (or a lost
  /// receipt) lands on [LaneState.stopError], beside the control.
  Future<void> stop() => _guardedVerb(
    source.stop,
    clearError: () => _emit(_state.copyWith(clearStopError: true)),
    setError: (error) => _emit(_state.copyWith(stopError: error)),
  );

  /// Answer one approval. A refusal lands on THAT card
  /// ([LaneState.approvalErrors]), which is the only place it is legible: an
  /// adapter refuses a `Permission` whose decision matches no offered option,
  /// and refuses a second answer to one approval.
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

  /// **Change one setting** (plan 025 §3.10) — a press on the settings sheet:
  /// [value] on [row] as the sheet drew it, with [displayedModel] the model the
  /// sheet SHOWED, which an option is bound to (Amendment A13 — the adapter's
  /// fold may already be on a model the sheet has not drawn yet).
  ///
  /// The desktop's `useSettingChanges` press, rule for rule:
  ///
  /// * a press is sent only when [pressSends] says so — never while the row's
  ///   last change is pending, never a value the row does not offer or already
  ///   shows — and only on a session whose capabilities say `settings`;
  /// * the row is [RowPending] until craze answers, with NO optimistic value:
  ///   what it shows next is the session's own next `Settings`, which craze
  ///   sends ahead of its answer;
  /// * the answer settles the row ([settle]): nothing on success; a refusal
  ///   inline — "the model changed; try again" for an option craze refused
  ///   `stale_model`; "not confirmed" for an answer lost to a drop, unless the
  ///   row already shows the value asked for, until the next `Settings`
  ///   ([LaneState.settingsSeen]);
  /// * nothing is ever resent: a retry is the person's next press, a new
  ///   command.
  ///
  /// The marks live on the lane, not the sheet, so closing the sheet while a
  /// change is in flight loses nothing. Never throws: a refusal is the row's
  /// mark.
  Future<void> setSetting(
    SettingsRow row,
    String value, {
    required String? displayedModel,
  }) async {
    if (!settingsOffered(_state.capabilities)) return;
    final key = row.key;
    final mark = shownMark(_state.settingMarks[key], _state.settingsSeen);
    if (!pressSends(row, value, mark)) return;
    final press = ++_pressSeq;
    _presses[key] = press;
    _emit(_state.copyWith(settingMarks: _withMark(key, const RowPending())));
    final handle = _handle;
    AppError? error;
    if (handle == null) {
      error = _noLane();
    } else {
      try {
        await source.set(handle, changeFor(row, value, displayedModel));
      } catch (e) {
        error = appErrorFrom(e);
      }
    }
    // A newer press owns the row now, or a new stamp cleared it.
    if (_presses[key] != press) return;
    _presses.remove(key);
    // As of NOW: the settings on screen and the `Settings` seen so far, after
    // however many reads landed while the change was in flight.
    final shown = rowNow(_state.settings ?? noSettings, row);
    _emit(
      _state.copyWith(
        settingMarks: _withMark(
          key,
          settle(
            row.kind,
            error,
            _state.settingsSeen,
            confirmedOnScreen: shown?.current == value,
          ),
        ),
      ),
    );
  }

  /// The marks with [key]'s set to [mark] — or removed, for none.
  Map<String, RowMark> _withMark(String key, RowMark? mark) {
    final next = {..._state.settingMarks};
    if (mark == null) {
      next.remove(key);
    } else {
      next[key] = mark;
    }
    return Map<String, RowMark>.unmodifiable(next);
  }

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

  // ---- the craze source --------------------------------------------------

  /// **A craze lane follows its machine's craze SOURCE across a feed restart**
  /// (plan 025 §3.7.2; the desktop retires craze lanes by its source's fenced
  /// generation the same way).
  ///
  /// A craze lane reaches its session over the feed's craze tunnel, through
  /// the source handle it was opened by. A feed restart (`MachineFeed.stop` +
  /// `start` — a roost bootstrap completing does one) closes that tunnel and
  /// that handle and opens new ones on a new port, and nothing on the lane's
  /// own stream says so: its connection simply stops answering, and it would
  /// keep redialling the dead port until shed-craze's outage bound ended it,
  /// minutes later. The row never left, so the stamp stream says nothing
  /// either. So the lane follows the source instead:
  ///
  /// * **the source retired** — the handle opened through it is closed now,
  ///   and the lane WAITS (`retrying`): there is nothing to open through yet;
  /// * **a new source live** — the lane re-opens through it at once, with no
  ///   backoff: the same session, on the replacement source.
  ///
  /// Neither is the session's end. The row stays, the lane is not abandoned,
  /// and nothing is said back to craze: closing a lane is not a `Down`. Every
  /// OTHER re-open still waits for `ended` ([_onEnded]).
  ///
  /// **Who waits for a source, and who does not.** Only a lane that was OPEN,
  /// or OPENING, through the retired source moves to waiting for the next one
  /// ([_sourceWait]). A lane with no handle for any other reason — an `ended`
  /// lane out on its own backoff — keeps its own ladder: a retirement and a
  /// replacement say nothing about it, and its re-open goes through whichever
  /// source is live when its wait is over.
  ///
  /// **No notification can be missed.** The wait is recorded synchronously,
  /// before the handle's drop is awaited; and once the drop has landed the
  /// lane re-reads the CURRENT source ([crazeSourceEpoch]) rather than relying
  /// on a notification — a replacement that went live while the drop was
  /// pending has already sent its only one.
  void _syncCrazeSource() {
    if (_closed || _abandoned || _opening || _leaving) return;
    if (_stamp.kind != crazeLaneKind) return;
    final live = crazeSourceEpoch?.call();
    if (_handle != null) {
      if (_openedEpoch == live) return;
      // Open through a source that is no longer the live one: retired.
      _sourceWait = true;
      unawaited(_leaveRetiredSource());
      return;
    }
    if (_sourceWait && live != null) unawaited(_openThroughLiveSource());
  }

  /// The lane lost its source — it was open or opening through one that was
  /// retired — and opens the moment a new one is live. Never set for a lane
  /// that has no handle for any other reason.
  bool _sourceWait = false;

  /// A retired source's handle is being dropped: the re-check after the drop
  /// decides what happens next, not a notification that lands during it.
  bool _leaving = false;

  /// Whether the craze open that just failed went through a source that is no
  /// longer the live one.
  bool _openedThroughRetiredSource() =>
      _stamp.kind == crazeLaneKind &&
      _openingEpoch != null &&
      _openingEpoch != crazeSourceEpoch?.call();

  Future<void> _leaveRetiredSource() async {
    _leaving = true;
    final dropping = _dropHandle(releaseLease: true);
    // `_dropHandle` bumped the generation before its first await: anything
    // that moves it again (a close, a new stamp's re-open) owns the lane now.
    final token = _generation;
    _emit(_state.copyWith(retrying: true, stale: 'reconnecting'));
    try {
      await dropping;
    } finally {
      _leaving = false;
    }
    if (_closed || _abandoned || token != _generation) return;
    // The CURRENT source, re-read — see the method doc above.
    _syncCrazeSource();
  }

  Future<void> _openThroughLiveSource() async {
    _sourceWait = false;
    _backoff = laneRetryBase;
    await open();
  }

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
    // A change in flight on the old session settles nothing on the new one.
    _presses.clear();
    _emit(
      _state.copyWith(
        rows: const [],
        approvals: const [],
        approvalErrors: const {},
        settingMarks: const {},
        // A new stamp is a new session: nothing the old one's stream said
        // about itself — its row, what it can do, its settings — carries over.
        live: laneLiveUnknown,
        ended: false,
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
  /// `keepLease` is true for every re-open an ended lane provoked: the local
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
    await _crazeSourceSub?.cancel();
    _crazeSourceSub = null;
    await _dropHandle(releaseLease: true);
    await _controller.close();
  }

  Future<void> _dropHandle({required bool releaseLease}) async {
    _generation++;
    _pullPending = false;
    _endHandled = null;
    final nudges = _nudges;
    _nudges = null;
    final handle = _handle;
    _handle = null;
    _openedEpoch = null;
    _cursor = null;
    // The next handle counts its `Settings` from zero; the total carries on.
    _framesBefore += _framesNow;
    _framesNow = 0;
    // **`lane_close` FIRST, and the cancel awaited after it.**
    //
    // The reverse order — which this had, on the theory that a cancel racing
    // `lane_close`'s end of the stream could drop a teardown on the floor —
    // DEADLOCKS. Rust's `lane_nudges` sits parked on its wake notify for the
    // life of the lane, and a `StreamSubscription.cancel()` on an FRB stream
    // does not complete until that function returns. So awaiting the cancel
    // first meant `lane_close` was never reached, `close()` never completed,
    // and every teardown path — `close`, `_reopen`, `_reopenNow`, `_abandon` —
    // hung with the adapter, its pump and its HTTP connections still live.
    //
    // The race it was guarding against cannot happen in this order either:
    // `_generation` was bumped at the top of this method, so any nudge the
    // closing stream still delivers is dropped by [_onNudge]'s fence, and
    // `lane_close` is idempotent.
    //
    // Found by `integration_test/lane_test.dart`'s
    // `close_ends_the_pump_and_one_row_is_one_controller` — with a stubbed
    // `LaneSource` the cancel returns Dart's already-completed null future, so
    // no unit test could have seen it.
    if (handle != null) source.close(handle);
    await nudges?.cancel();
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

/// Whether a failed open can never succeed, so the ladder must not run.
///
/// The three permanent shapes, and each is a property of the ROW rather than of
/// the moment: this build has no adapter for the kind, the handle carries no
/// lane at all, or the agent does not know the session. Everything else — a
/// refused dial, an asleep machine, a forward that failed because the SSH link
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
