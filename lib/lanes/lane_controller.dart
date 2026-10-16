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

/// **How long a craze lane outlives its row** (plan 032 §3.1) — the
/// desktop's `CRAZE_DEPART_GRACE`.
///
/// craze 0.2.0 drops a stopping session from its roster AT ONCE, ahead of the
/// session's last events (its closing records, then `session_closed`), so a
/// row that leaves is not yet a lane that ended. The lane keeps its own
/// connection this long for them ([LaneController.reconcile]). The hub's
/// round is 1 s and a stop's tool teardown takes seconds; a host that died
/// with no final event hands the lane a final `unknown_session` on its redial
/// anyway, so this only bounds the worst case — and an offline source, which
/// emits no stamps to cancel it, is bounded by it too.
const crazeDepartGrace = Duration(seconds: 10);

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

/// What the composer says when a `/` COMMAND's answer was lost (plan 029
/// §3.5's draft-lifecycle table) — a rename, a mode, a prompt row, `/exit`'s
/// stop: it may have run, nothing resends it, the draft stays, and the person
/// checks the session before trying again. The desktop's `MAY_HAVE_APPLIED`,
/// word for word. A plain send keeps [laneSendOutcomeUnknown].
const laneCommandOutcomeUnknown = 'may have applied — check the session';

/// **What ONE call of a composer verb came to** (plan 029 §3.5, P8) — the
/// call's own answer, handed back to whoever made it, which is what a caller
/// settles its draft from: [LaneVerbDone] clears it, every other outcome
/// keeps it.
///
/// Never inferred from [LaneState] read back after the await. The lane lands
/// a refusal on its state only while the call's generation is still its own
/// (the generation fence, [LaneController._guardedVerb]); a call the lane
/// moved on from — a re-open, a new stamp, a close because the lane's
/// provider rebuilt — lands nothing, and "nothing on the state" is not "it
/// took". That call answers [LaneVerbSuperseded], and only the caller is left
/// to say it.
sealed class LaneVerbOutcome {
  const LaneVerbOutcome();

  /// What to say for it — null exactly when it took ([LaneVerbDone]).
  AppError? get error;
}

/// It took. [warning]: it took with a caveat — a rename craze applied but
/// could not record (`index_write`, P19) — which the caller shows beside the
/// cleared draft; never a rollback, never a retry.
final class LaneVerbDone extends LaneVerbOutcome {
  const LaneVerbDone({this.warning});

  final String? warning;

  @override
  AppError? get error => null;
}

/// A definite refusal — craze's words, or no lane to send it on: it did not
/// run. Also on [LaneState.composerError] (or the verb's own card).
final class LaneVerbRefused extends LaneVerbOutcome {
  const LaneVerbRefused(this.error);

  @override
  final AppError error;
}

/// The answer was lost to a drop (`LANE_OUTCOME_UNKNOWN`): it may have run,
/// and nothing resends it. [error] says so in the verb's own wording
/// ([laneSendOutcomeUnknown], [laneCommandOutcomeUnknown]) — as the lane's
/// state does too.
final class LaneVerbUnknown extends LaneVerbOutcome {
  const LaneVerbUnknown(this.error);

  @override
  final AppError error;
}

/// **The lane moved on while the call was out** — its generation changed
/// (a re-open, a new stamp, the controller closed by its provider's
/// rebuild) — so its answer, WHATEVER it was, landed nothing on the lane's
/// state. The request may have reached craze, so this is never a success:
/// the draft stays, and [error] says the verb's "may have run" wording, which
/// the CALLER shows — the lane that would have said it has let the answer go.
final class LaneVerbSuperseded extends LaneVerbOutcome {
  const LaneVerbSuperseded(this.error);

  @override
  final AppError error;
}

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

/// Start a one-shot timer that runs `fire` after `wait` — the departure grace
/// ([crazeDepartGrace]). Injected, as [LaneDelay] is, so a test fires the
/// grace instead of sleeping through it (and can fire one that was
/// cancelled, to prove the fence rather than the cancel).
typedef LaneTimer = Timer Function(Duration wait, void Function() fire);

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
/// ## A row that leaves before its lane ends
///
/// A craze session's row can leave its roster ahead of the session's last
/// events (craze 0.2.0's Stop), so an open craze lane outlives its row by a
/// grace ([crazeDepartGrace]) on its own connection before it is given up on
/// — see [reconcile]. The grace is fenced like everything else: by its
/// handle generation, and by its own identity.
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
    LaneTimer? timer,
  }) : _schedulePull = schedulePull ?? scheduleOnNextFrame,
       _delay = delay ?? ((d) => Future<void>.delayed(d)),
       _timer = timer ?? Timer.new {
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
  final LaneTimer _timer;

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

  /// The departure grace a craze lane is waiting out, or null — see
  /// [reconcile]. At most one: a repeated `null` neither stacks another nor
  /// extends this one.
  _Departure? _departure;

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
          // Verbatim too — a null is "no menu" — but the SAME instance while
          // the menu is the same by value (LaneState.slashMenu's doc).
          slashMenu: sameSlashMenu(_state.slashMenu, snap.slashMenu)
              ? _state.slashMenu
              : snap.slashMenu,
          effortOption: snap.effortOption,
        ),
        settingsSeen: _framesBefore + _framesNow,
      ),
    );

    // `ended`, never `stale`: see "One reconnect owner" above.
    if (snap.ended) _onEnded(generation, snap.stale ?? '');
  }

  /// The lane's subscription ENDED on a terminal `Down`. Dart re-opens — unless
  /// the reason says no re-open can ever succeed ([laneDownIsFinal]).
  ///
  /// **A departing lane re-opens nothing** (plan 032 PC14c): its row is no
  /// longer listed, so a re-open would go to a source that has nothing to
  /// open. An end that is not final waits out the grace instead, unhandled —
  /// the grace's last read decides ([_departureExpired]), or the row's
  /// return hands it back to the ladder ([_returned]). A final end is the
  /// departure's whole point: it ends the lane here, and the grace with it
  /// ([_dropHandle]).
  void _onEnded(int generation, String reason) {
    if (_endHandled == generation) return;
    final gone = laneDownIsFinal(reason);
    if (!gone && _departure != null) return;
    _endHandled = generation;
    if (gone) {
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
  /// kept, the person decides. A `/` menu PROMPT row's send ([command], plan
  /// 029 §3.5) says the command wording instead ([laneCommandOutcomeUnknown]),
  /// as the desktop's does.
  ///
  /// Answers the call's own outcome ([LaneVerbOutcome]) — what the composer
  /// settles its draft from.
  Future<LaneVerbOutcome> send(
    String text, {
    BridgeSendMode mode = BridgeSendMode.queue,
    bool command = false,
  }) => _composerVerb(
    (handle) => source.send(handle, text: text, mode: mode),
    unknown: command ? laneCommandOutcomeUnknown : laneSendOutcomeUnknown,
  );

  /// **Rename the session** (plan 029 D4) — the composer's `/rename`: craze's
  /// `session.setTitle` with the title as typed (the argument, trimmed —
  /// craze 0.1.1 stores it verbatim, E5). The new title is the STREAM's to
  /// show (a `meta` delta re-emits the session row, P19), never this answer's.
  ///
  /// The composer's verb: a refusal lands on [LaneState.composerError] —
  /// craze's own words, or, for an answer lost to a drop,
  /// [laneCommandOutcomeUnknown] — and nothing is resent. Answers the call's
  /// own outcome ([LaneVerbOutcome]); a rename that TOOK but craze could not
  /// record (`index_write`) is a [LaneVerbDone] carrying the warning: the
  /// caller clears the draft and shows it beside the header that already says
  /// the new title — never a rollback, never a retry. Never throws.
  Future<LaneVerbOutcome> setTitle(String title) async {
    String? warning;
    final outcome = await _composerVerb(
      (handle) async => warning = await source.setTitle(handle, title),
      unknown: laneCommandOutcomeUnknown,
    );
    return outcome is LaneVerbDone ? LaneVerbDone(warning: warning) : outcome;
  }

  /// **Move the session to a mode from the composer** (plan 029 P7) — a `/`
  /// menu mode row (`/plan`): craze's `session.set` with [change] (always a
  /// `Mode`, built by the shared rules from the catalog).
  ///
  /// The COMPOSER's verb, not the settings sheet's: its refusal lands on
  /// [LaneState.composerError] (an answer lost to a drop as
  /// [laneCommandOutcomeUnknown]), never on a sheet row's mark — the sheet's
  /// [setSetting] returns early where the session does not say `settings`, and
  /// its marks are invisible from the composer anyway. So this does NOT
  /// require `caps.settings`, and re-selecting the mode the session is
  /// already in still sends: the person asked for it. Never throws; answers
  /// the call's own outcome ([LaneVerbOutcome]).
  Future<LaneVerbOutcome> setMode(BridgeLaneSettingChange change) =>
      _composerVerb(
        (handle) => source.set(handle, change),
        unknown: laneCommandOutcomeUnknown,
      );

  /// **Set the effort from the composer** (plan 032 §3.2) — `/effort <level>`:
  /// craze's `session.set` with [change], the shared rules' `SetEffort` (a
  /// `Config` of the effort option, bound to the model the menu was resolved
  /// on — so a session that has moved off it refuses `stale_model`).
  ///
  /// The composer's verb, exactly as [setMode] is: its refusal on
  /// [LaneState.composerError], a lost answer as [laneCommandOutcomeUnknown],
  /// never a sheet row's mark. And it ALWAYS sends, the current level
  /// included — craze's rule for the inline level (a dropped no-op could lose
  /// a concurrent change) — where the sheet's press on its current value
  /// sends nothing ([pressSends]). Never throws.
  Future<LaneVerbOutcome> setEffort(BridgeLaneSettingChange change) =>
      setMode(change);

  /// Stop the turn in flight. `not_accepting` here means the turn ended between
  /// the render and the tap — an inline error next to the button, not a toast.
  Future<LaneVerbOutcome> cancel() => _composerVerb(source.cancel);

  /// **End the SESSION** (plan 025 §3.7.3) — offered only when the snapshot's
  /// capabilities say `stop`, behind a confirm. Its `Ok` is the host's
  /// receipt, not the end: the session's close arrives on the stream as
  /// `Down{"session_closed"}`, which ends this lane for good
  /// ([laneDownIsFinal]) with the transcript kept. A refusal (or a lost
  /// receipt) lands on [LaneState.stopError], beside the control.
  ///
  /// [command]: the stop is the composer's `/exit` (plan 029 §3.5), and its
  /// outcome follows the composer's command lifecycle instead — a refusal on
  /// [LaneState.composerError] in craze's words, a lost receipt there as
  /// [laneCommandOutcomeUnknown] — beside the draft that asked for it, as the
  /// desktop's `slashVerb` settles it. The header's Stop keeps the banner.
  /// Either way the call's own outcome is answered ([LaneVerbOutcome]).
  Future<LaneVerbOutcome> stop({bool command = false}) => command
      ? _composerVerb(source.stop, unknown: laneCommandOutcomeUnknown)
      : _guardedVerb(
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

  /// A verb whose refusal lands on [LaneState.composerError] — an answer
  /// LOST to a drop said as [unknown] (the verb's own wording for "it may
  /// have run") when it has one, as is otherwise.
  Future<LaneVerbOutcome> _composerVerb(
    Future<void> Function(LaneHandle) verb, {
    String? unknown,
  }) => _guardedVerb(
    verb,
    unknown: unknown,
    clearError: () => _emit(_state.copyWith(clearComposerError: true)),
    setError: (error) => _emit(_state.copyWith(composerError: error)),
  );

  /// The shape every verb shares: no handle is a `_noLane()` refusal, a lost
  /// answer is said as [unknown] when the verb has its own wording for it,
  /// and everything else never throws past here — a refusal is state, landed
  /// by [setError] on whichever card raised it.
  ///
  /// **The generation fence, for the lane's own state:** an answer from a
  /// since-superseded generation is nobody's news here — it lands nothing,
  /// success or refusal. Its CALLER still hears of it, as
  /// [LaneVerbSuperseded], never as a success: the request may have reached
  /// craze, and the lane that would have said how it went has let it go.
  /// Every other call answers what it came to ([LaneVerbOutcome]).
  Future<LaneVerbOutcome> _guardedVerb(
    Future<void> Function(LaneHandle) verb, {
    required void Function() clearError,
    required void Function(AppError error) setError,
    String? unknown,
  }) async {
    final handle = _handle;
    if (handle == null) {
      final error = _noLane();
      setError(error);
      return LaneVerbRefused(error);
    }
    final generation = _generation;
    clearError();
    AppError? error;
    try {
      await verb(handle);
    } catch (e) {
      error = appErrorFrom(e);
    }
    if (generation != _generation) {
      return LaneVerbSuperseded(
        AppError(laneOutcomeUnknownCode, unknown ?? laneCommandOutcomeUnknown),
      );
    }
    if (error == null) return const LaneVerbDone();
    if (error.code == laneOutcomeUnknownCode) {
      final lost = unknown == null
          ? error
          : AppError(laneOutcomeUnknownCode, unknown);
      setError(lost);
      return LaneVerbUnknown(lost);
    }
    setError(error);
    return LaneVerbRefused(error);
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
  ///
  /// **Not while departing** (plan 032 PC14c): a lane whose row has left
  /// keeps the handle it has — a re-open through the replacement would ask a
  /// source that no longer lists the row — and the grace decides
  /// ([_departureExpired]). A row that returns re-runs this ([_returned]).
  void _syncCrazeSource() {
    if (_closed || _abandoned || _opening || _leaving) return;
    if (_departure != null) return;
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
  /// * **gone** → close and stop retrying — except an open craze lane, which
  ///   DEPARTS first (below);
  /// * **changed** → close, give the forward back (the port may have moved) and
  ///   re-open against the new stamp, immediately — a new stamp is news, not a
  ///   failure, so it does not wait out a backoff.
  ///
  /// ## A craze lane outlives its row by a grace (plan 032 §3.1.2)
  ///
  /// craze 0.2.0 drops a stopping session's row ahead of the session's last
  /// events, so for a CRAZE lane — the one kind whose rows leave ahead of its
  /// stream — "gone" on an open, live lane arms ONE timer
  /// ([crazeDepartGrace]) instead of giving up, and the lane keeps its own
  /// connection meanwhile:
  ///
  /// * **a final `Down` in the grace** (a Stop's `session_closed`) ends the
  ///   lane as any final end does ([_onEnded]) — its banner says why, and
  ///   nothing says "given up on";
  /// * **the row listed again** cancels the grace — before the same-stamp
  ///   return below, so a row that left and came back unchanged does not
  ///   leave it running ([_returned]); a CHANGED stamp then re-opens as
  ///   always;
  /// * **the grace runs out** → one read at once ([_departureExpired]), and
  ///   unless it holds a final `Down`, the lane is given up on as today.
  ///
  /// Repeated `null`s neither stack timers nor extend the grace. A lane with
  /// no handle (opening, waiting for a source, out on its re-open ladder) has
  /// no connection to wait on, and every other kind keeps the rule above.
  void reconcile(BridgeAgentLaneStamp? stamp) {
    if (_closed) return;
    if (stamp == null) {
      if (_abandoned || _departure != null) return;
      if (_stamp.kind == crazeLaneKind && _handle != null && !_state.ended) {
        _depart();
        return;
      }
      unawaited(_abandon());
      return;
    }
    final returned = _cancelDeparture();
    if (stamp == _stamp) {
      if (returned) _returned();
      return;
    }
    final otherSession = stamp.sessionId != _stamp.sessionId;
    _stamp = stamp;
    // A new stamp revives a lane that was given up on: whatever was permanent
    // about the old one was a property of the old one.
    _abandoned = false;
    _backoff = laneRetryBase;
    unawaited(_reopenNow(otherSession: otherSession));
  }

  /// Arm the departure grace — one timer, fenced to the handle generation it
  /// was armed in ([_departureExpired]).
  void _depart() {
    final departure = _Departure(_generation);
    _departure = departure;
    departure.timer = _timer(
      crazeDepartGrace,
      () => _departureExpired(departure),
    );
    _emit(_state.copyWith(departing: true));
  }

  /// End the departure, if there is one — the row returned, or its handle is
  /// going ([_dropHandle]). Whether there was one.
  bool _cancelDeparture() {
    final departure = _departure;
    if (departure == null) return false;
    _departure = null;
    departure.timer.cancel();
    _emit(_state.copyWith(departing: false));
    return true;
  }

  /// The row came back within the grace, the same stamp: what the departure
  /// held back takes today's path now — an end that is not final its
  /// re-open ladder ([_onEnded]), a source retired meanwhile the move to the
  /// live one ([_syncCrazeSource]).
  void _returned() {
    if (_handle != null && _state.ended) {
      _onEnded(_generation, _state.stale ?? '');
    }
    _syncCrazeSource();
  }

  /// The grace ran out. A timer that is no longer the lane's departure (it
  /// was cancelled, or replaced by a later one) or whose handle generation
  /// has moved on does NOTHING.
  ///
  /// Otherwise: ONE read, now — not on the next frame ([_onNudge]'s
  /// batching), since the lane is about to be closed — so the session's last
  /// rows and a final `Down` that landed late are on screen. A final `Down`
  /// in it ends the lane through [_onEnded] (the departure still set while
  /// it reads, so an end that is NOT final re-opens nothing); otherwise the
  /// lane is given up on, as a vanished row always was.
  void _departureExpired(_Departure departure) {
    if (!identical(departure, _departure)) return;
    if (departure.generation != _generation || _closed || _abandoned) return;
    try {
      _pull(departure.generation);
    } finally {
      // Even past a read that threw: the grace's promise is that the lane
      // ENDS, never that it waits on.
      if (!_closed && !_abandoned) unawaited(_abandon());
    }
  }

  /// Re-open against the stamp [reconcile] just took. [otherSession]: it
  /// names a different agent session, not the same one on a new port (a
  /// restarted tab) — what decides whether the verbs' own errors go too.
  Future<void> _reopenNow({required bool otherSession}) async {
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
        // What a verb said — a refusal, or a lost answer's "may have run" —
        // is about the SESSION it was sent to: gone with it, kept when the
        // same session only moved port (it is still that session's news).
        clearComposerError: otherSession,
        clearStopError: otherSession,
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

  /// **End the lane.** Cancels a departure grace, closes the handle, gives
  /// the forward back, cancels the nudge subscription and bumps the
  /// generation. Idempotent — the provider's `onDispose` calls it, and so may
  /// a screen that is done.
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
    // A departure is waiting on THIS handle; whatever replaces it — a re-open,
    // an abandon, a close — has decided the lane's future instead.
    _cancelDeparture();
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

/// One departure grace: its timer, and the handle generation it was armed in
/// — what [LaneController._departureExpired] fences on, with the departure's
/// own identity.
final class _Departure {
  _Departure(this.generation);

  final int generation;
  late final Timer timer;
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
