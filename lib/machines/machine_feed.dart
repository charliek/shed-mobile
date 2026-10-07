import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../rc/rc_ui.dart';
import '../src/rust/api/craze.dart';
import '../src/rust/api/dto_lane.dart';
import '../src/rust/api/dto_rc.dart';
import '../src/rust/api/lane.dart';
import '../src/rust/api/roost.dart';
import '../src/rust/api/roost_bootstrap.dart';
import '../ssh/craze_reach.dart';
import '../ssh/exec_bytes.dart';
import '../ssh/host_key_store.dart';
import '../ssh/lane_forward.dart';
import '../ssh/roost_bootstrap_runner.dart';
import '../ssh/roost_entitlement.dart';
import '../ssh/roost_reach.dart';
import '../ssh/roost_tunnel.dart';
import '../ssh/ssh_connection.dart';
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
    this.craze,
    this.foldedRows,
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

  /// **The machine's craze source, as its last snapshot said it** (plan 025
  /// §3.7.2) — the sessions craze's hub lists here, whether that list is live,
  /// and why not when it is not. Null while the feed has opened no craze
  /// source, or the source has not been read yet.
  ///
  /// Kept across a [MachineFeed.stop] for [sessions]' reason, and marked not
  /// live there: the last known craze rows stay on screen, stale, until the
  /// next source says what is true now.
  final BridgeCrazeSnapshot? craze;

  /// The rows the feed FOLDED for this state — null on a state built by hand.
  /// Read [rows], which falls back for exactly that case.
  final List<MachineRow>? foldedRows;

  /// **This machine's rows, merged — what every view renders** (plan 025
  /// §3.7.2): its roost tabs and its craze sessions, one row per session.
  ///
  /// The merge is `shed_app::craze_rows::fold_plan` over the bridge
  /// (`crazeFoldPlan`, applied by [machineRows]): with the craze feed LIVE,
  /// every roost tab craze owns is absorbed into the hub row it names (that row
  /// then carries the tab's id) or hidden, and the hub row is the row (D4);
  /// with the feed down, nothing is absorbed and roost's craze tabs stand
  /// alone. **Every state [MachineFeed] emits carries rows from that fold.** A
  /// state built by hand — a test, the feed's first frame — folds nothing: its
  /// rows are its roost rows and its craze rows side by side, which is the
  /// fold's own answer whenever the craze feed is not live.
  List<MachineRow> get rows =>
      foldedRows ??
      machineRows(sessions: sessions, craze: craze, plan: _foldsNothing);

  MachineFeedState copyWith({
    List<BridgeRcSession>? sessions,
    Map<String, MachinePatch>? overlay,
    bool? reachable,
    String? detail,
    bool? connectedOnce,
    BridgeRcCapabilities? capabilities,
    BridgeReachKind? downKind,
    BridgeCrazeSnapshot? craze,
    List<MachineRow>? rows,
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
    craze: craze ?? this.craze,
    // Folded rows survive a change that cannot move them (reachability, a
    // detail); a new roost or craze list voids them, and the feed folds again
    // before it emits.
    foldedRows:
        rows ?? ((sessions == null && craze == null) ? foldedRows : null),
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

/// **One row of a machine's sessions list** (plan 025 §3.7.2) — a roost tab,
/// or a craze session. Sealed, so a view that renders rows renders both kinds
/// or does not compile.
sealed class MachineRow {
  const MachineRow();

  /// A roost tab, as roost's watcher reported it.
  const factory MachineRow.roost(BridgeRcSession session) = RoostMachineRow;

  /// A craze session, as the machine's craze hub lists it.
  const factory MachineRow.craze({
    required BridgeLaneSession session,
    int? tabId,
    required bool stale,
  }) = CrazeMachineRow;

  /// The row's identity within its machine — what a list keys it by and a
  /// lane is addressed by (`LaneRef`'s `slug`): roost's slug (its tab id), or
  /// craze's hostId (P11). The two never collide: a hostId is twelve hex
  /// digits, and roost's tab ids are its own small counter.
  String get key;
}

/// One roost tab (an opencode or Claude session, or any agent tab roost
/// reports), unchanged from roost's watcher.
final class RoostMachineRow extends MachineRow {
  const RoostMachineRow(this.session);

  final BridgeRcSession session;

  @override
  String get key => session.slug;
}

/// **One craze session** — its status is craze's (D4): provider, model, what
/// it is doing, what it is blocked on, who is attached, why it failed to start.
final class CrazeMachineRow extends MachineRow {
  const CrazeMachineRow({
    required this.session,
    this.tabId,
    required this.stale,
  });

  /// The hub's row: `id` is the hostId, which is what its transcript opens on.
  final BridgeLaneSession session;

  /// The roost tab the merge attached to this row — the craze TUI the session
  /// runs in, when it runs in one. Its terminal actions (Peek, End) act on THIS
  /// tab, never on the row's key: a hostId is not a tab id.
  final int? tabId;

  /// The craze feed is not live: this is the LAST KNOWN row (§3.6.2).
  final bool stale;

  @override
  String get key => session.id;
}

/// The row merge, over the bridge — `crazeFoldPlan` in production. A seam so
/// the merge's application ([machineRows]) is testable without the native
/// library; the RULE is never re-derived on this side.
typedef CrazeFoldPlanner =
    BridgeFoldPlan Function(
      List<BridgeRoostTabRef> roost,
      List<BridgeLaneSession>? hub,
    );

/// The production [CrazeFoldPlanner]: `shed_app::craze_rows::fold_plan`.
BridgeFoldPlan crazeFoldPlanner(
  List<BridgeRoostTabRef> roost,
  List<BridgeLaneSession>? hub,
) => crazeFoldPlan(roost: roost, hub: hub);

/// The plan that absorbs nothing — the fold's own answer whenever the craze
/// feed is not live, and what a hand-built state's [MachineFeedState.rows]
/// falls back to.
BridgeFoldPlan _foldsNothing(
  List<BridgeRoostTabRef> roost,
  List<BridgeLaneSession>? hub,
) => const BridgeFoldPlan(folded: []);

/// A machine's roost tabs, as the merge reads them.
///
/// `craze_owner` is set **only** for a tab roost reports as craze's — the
/// one-line rule of "only craze ownership folds": an opencode tab whose session
/// id happens to equal a craze session's provider id is never absorbed. A craze
/// tab's owner is its row's `rc_id` (roost's ownership session id); an empty
/// one is still a craze tab, and with the feed live it folds silently, exactly
/// as the desktop's does.
List<BridgeRoostTabRef> roostTabRefs(List<BridgeRcSession> sessions) => [
  for (final s in sessions)
    if (s.tabId case final tabId?)
      BridgeRoostTabRef(
        tabId: tabId,
        crazeOwner: s.kind is BridgeRcKind_Craze ? (s.rcId ?? '') : null,
      ),
];

/// **Build a machine's rows** — roost's, then craze's — from [plan]'s answer
/// for this machine (plan 025 §3.6.3, §3.7.2).
///
/// The feed calls this once per update with the real fold. It passes the hub's
/// rows only while the craze feed is LIVE — a feed that is down absorbs
/// nothing — and every craze row the source holds while it is not live is
/// stamped [CrazeMachineRow.stale].
List<MachineRow> machineRows({
  required List<BridgeRcSession> sessions,
  required BridgeCrazeSnapshot? craze,
  required CrazeFoldPlanner plan,
}) {
  final live = craze?.live ?? false;
  final hub = craze?.rows ?? const <BridgeLaneSession>[];
  final folded = plan(roostTabRefs(sessions), live ? hub : null).folded;
  final gone = <int>{for (final t in folded) t.tabId};
  final tabOf = <String, int>{for (final t in folded) ?t.hostId: t.tabId};
  return [
    for (final s in sessions)
      if (!gone.contains(s.tabId)) MachineRow.roost(s),
    for (final r in hub)
      MachineRow.craze(session: r, tabId: tabOf[r.id], stale: !live),
  ];
}

/// What a machine's card SAYS about its craze, if anything (plan 025 §3.2.4,
/// §3.8, A2m): a craze too old for shed asks to be updated, and so does a LIVE
/// hub that cannot create (its `hello` lacks `createOptions` or
/// `sessionCreate` — listing still works, the create screen does not offer
/// craze there); every other state — not installed above all — is quiet.
/// Branches on the offline CAUSE and the hub's capabilities, never on the
/// reason's text (which is copy).
String? crazeNoteFor(MachineFeedState state) =>
    state.craze?.offline?.cause is BridgeSourceOffline_TooOld
    ? 'craze on this machine is too old for shed; update it'
    : crazeCreateUpdateNote(state.craze);

/// **Whether a machine offers a craze create** (plan 025 §3.6.5, §3.8) — its
/// craze source is LIVE and its hub can list providers and create. What the
/// create screen's craze choice is gated on.
///
/// The desktop also offers it on a DORMANT machine (craze installed, no hub
/// yet). The phone has no dormant phase: its craze tunnel runs `bridge --hub`,
/// which starts a hub on connect (plan 025 §9), so a machine with craze is live
/// within a second of being viewed. A live hub without those capabilities, a
/// too-old craze, an offline or absent one offers nothing.
bool crazeCreateOffered(BridgeCrazeSnapshot? craze) =>
    craze != null &&
    craze.live &&
    (craze.caps?.create ?? false) &&
    (craze.caps?.createOptions ?? false);

/// The machine's line when its LIVE hub cannot create — listing still works,
/// creating does not (§3.8's "update craze on this machine"). Null otherwise (a
/// too-old craze has its own note).
String? crazeCreateUpdateNote(BridgeCrazeSnapshot? craze) =>
    craze != null && craze.live && !crazeCreateOffered(craze)
    ? 'update craze on this machine to create sessions here'
    : null;

/// [snapshot], no longer live: the same rows and cause, rendered stale — what a
/// stopped feed keeps.
BridgeCrazeSnapshot? staleCraze(BridgeCrazeSnapshot? snapshot) =>
    snapshot == null || !snapshot.live
    ? snapshot
    : BridgeCrazeSnapshot(
        rows: snapshot.rows,
        live: false,
        offline: snapshot.offline,
        caps: snapshot.caps,
        truncated: snapshot.truncated,
      );

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

/// **What a machine card may OFFER about its roost reach** — an install, a
/// start, or nothing at all.
///
/// Two members and no third, because only two of roost's four reach kinds name
/// something a phone could do about them. The other two are reported and
/// nothing more, and [roostOfferFor] answers null for both rather than
/// inventing a `none` member that every call site would then have to remember
/// to handle as "no button".
enum RoostOffer {
  /// Nothing on roost's candidate ladder — an install would fix it.
  install,

  /// A `roost-session` is installed and not serving — a start would fix it.
  start,
}

/// **The kind → affordance decision, as a pure function of the state** (plan
/// 020 §3.8, shed-mobile AC 2).
///
/// Extracted beside [foldRoostUpdate] and [foldOpenedRow] for the reason those
/// two are: the decision is the whole of what a card offers, it breaks silently
/// in production when it is wrong, and buried in a widget it can only ever be
/// checked by driving a live machine into each of four states. Here all four
/// are a table.
///
/// It reads [MachineFeedState.downKind] and nothing else, and that field is
/// already the EFFECTIVE kind — [foldRoostUpdate] resolves Dart's own
/// observation over the update's (amendment A2) before it lands there, which on
/// a phone is the only thing that makes the datum mean anything. Branching on
/// the last `Down`'s own kind instead would branch on `Other` forever and the
/// install offer would never appear on a machine that genuinely has no
/// `roost-session`.
///
/// **Never a substring of [MachineFeedState.detail]**, which §3.8 forbids: that
/// is copy — translated, shortened and reworded — and a branch on it is a bug
/// waiting for an edit.
///
/// There is deliberately no second condition on [MachineFeedState.reachable].
/// A kind survives exactly as long as the machine is down: only a `Snapshot`
/// clears it, and a `Snapshot` is also the only thing that sets `reachable`, so
/// a non-null kind already means "not answering". A second gate would be a
/// second answer to one question.
///
/// Not `@visibleForTesting`, unlike its neighbours: the render site that acts
/// on it lives in another library (`lib/features/machines/`), so this is
/// ordinary public API. The extraction is what AC 2 asks for, not the
/// annotation.
RoostOffer? roostOfferFor(MachineFeedState state) => switch (state.downKind) {
  BridgeReachKind.notInstalled => RoostOffer.install,
  BridgeReachKind.noSession => RoostOffer.start,
  // Reported, and nothing more. `unreachable` is "shed never got as far as
  // asking" and `other` is "nothing classified this at all" — neither is
  // evidence that installing or starting anything would help, and offering a
  // button that cannot work is worse than offering none.
  BridgeReachKind.unreachable || BridgeReachKind.other => null,
  // Unclassified, which is not the same as reachable: a feed error or a pause
  // marks a machine down with no `Down` to classify. The honest answer is to
  // offer nothing.
  null => null,
};

/// **Where one of a machine's rows came from** — the sessions view's source
/// stamp (plan 020 §5, C-M4; shed-mobile AC 3).
enum MachineRowSource {
  /// The machine's own `roost-session`, read over the phone's tunnel.
  roost('roost'),

  /// The shed RC activity hub — the pre-plan-013 source, which a machine's
  /// rows no longer come from.
  hub('hub');

  const MachineRowSource(this.label);

  /// The word the card shows and the drive transcript counts.
  final String label;
}

/// Which source a row came from.
///
/// `tab_id` is the discriminator because it is the one field only roost fills:
/// "roost's tab id, for a roost-sourced row; `None` for every shed row". AC 3
/// asks the live leg to prove the app is reading roost rather than the hub, and
/// a field that only one of the two ever sets is the only honest way to say so
/// — a count of rows says nothing about where they came from.
MachineRowSource rowSourceOf(BridgeRcSession row) =>
    row.tabId != null ? MachineRowSource.roost : MachineRowSource.hub;

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

/// Opening one of the feed's tunnels — `RoostTunnel.open`'s own signature,
/// named as a type for [WatcherSpawn]'s reason (a drift is a compile error
/// here).
///
/// **The seam the craze harness needs** (plan 025 §3.7.2): `start()` used to
/// call `RoostTunnel.open` directly, so an integration test could not put a
/// local process where the SSH exec goes. Production is `RoostTunnel.open`
/// (through `machineTunnelOpenProvider`); the hermetic harness hands in
/// `RoostTunnel.openWithExec` over a local `Process` running the JAILED craze
/// ladder. One seam for both tunnels: the feed opens its roost tunnel and its
/// craze tunnel through it, and tells them apart only by the command.
typedef TunnelOpen =
    Future<RoostTunnel> Function({
      required Future<SSHClient> Function() connect,
      required String remoteCommand,
      required String machine,
      void Function(String)? onStderr,
    });

/// Opening one machine's craze source on the craze tunnel's port —
/// `crazeSourceOpen`'s own signature. A seam so the teardown harness can hold
/// an open in flight while the feed is disposed underneath it.
typedef CrazeSourceOpen =
    Future<BridgeCrazeSource> Function({
      required String machine,
      required int port,
    });

/// A craze source's nudge stream — `crazeSourceNudges`' own signature. A seam
/// so a harness can DELAY the nudges and prove that what must not wait for one
/// (a created session's row, [MachineFeed.crazeCreateSession]) does not.
typedef CrazeSourceNudges =
    Stream<bool> Function({required BridgeCrazeSource src});

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
/// ## The craze half (plan 025 §3.7.2)
///
/// Beside roost's tunnel the feed holds a SECOND one, whose every accepted
/// connection execs `craze bridge --hub` (craze's published ladder,
/// `crazeRemoteCommand()`), and a craze source handle Rust reads the machine's
/// hub through — with exactly the roost half's lifecycle: built by [start],
/// torn down by [_teardown], fenced by the same generation. Every state the
/// feed emits carries [MachineFeedState.rows], the two halves merged by shed's
/// own row rule over the bridge ([machineRows]); a lane on a craze row opens
/// through the source ([openCrazeLane]), never through a forward.
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
    TunnelOpen? openTunnel,
    CrazeSourceOpen? openCrazeSource,
    CrazeSourceNudges? crazeNudges,
    CrazeFoldPlanner? foldPlan,
  }) : _spawnWatcher = spawnWatcher ?? createRoostWatcher,
       _openTunnel = openTunnel ?? RoostTunnel.open,
       _openCrazeSource = openCrazeSource ?? crazeSourceOpen,
       _crazeNudges = crazeNudges ?? crazeSourceNudges,
       _foldPlan = foldPlan ?? crazeFoldPlanner,
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

  /// How [start] opens both tunnels — see [TunnelOpen].
  final TunnelOpen _openTunnel;

  /// How [start] opens the craze source — see [CrazeSourceOpen].
  final CrazeSourceOpen _openCrazeSource;

  /// How [start] subscribes to the source's nudges — see [CrazeSourceNudges].
  final CrazeSourceNudges _crazeNudges;

  /// The row merge every emitted state is folded with — see [machineRows].
  final CrazeFoldPlanner _foldPlan;

  final _controller = StreamController<MachineFeedState>.broadcast();
  MachineFeedState _state;

  RoostTunnel? _tunnel;
  BridgeRoostWatcher? _watcher;
  StreamSubscription<BridgeRoostUpdate>? _sub;
  bool _starting = false;

  /// A [start] was asked for while one was in flight: the in-flight start
  /// runs it once it finishes ([_startIfAsked]). Cleared by [stop] and
  /// [dispose] — an owner's stop after the request outranks it — and by
  /// nothing else: a teardown the in-flight start runs on its own failure is
  /// not the owner stopping the feed.
  bool _startAgain = false;

  /// **The craze half** (plan 025 §3.7.2, P16): a second tunnel beside
  /// [_tunnel] whose every accepted connection execs `craze bridge --hub`, the
  /// source handle Rust reads the machine's hub through, and the handle's
  /// nudge stream — owned in that order, built in that order by [start], and
  /// torn down by [_teardownCraze] with exactly the roost feed's lifecycle.
  RoostTunnel? _crazeTunnel;
  BridgeCrazeSource? _crazeSource;
  StreamSubscription<bool>? _crazeSub;

  /// The craze source's epoch — bumped at every source handle this feed
  /// installs, so a lane can tell the handle it was opened through from its
  /// replacement after a restart (see [crazeLiveEpoch]).
  int _crazeEpoch = 0;

  /// Whether the installed source has swapped a roster seed in yet. A lane is
  /// opened only through a SEEDED source: one that has not seeded lists no row,
  /// and a lane bound there would read its own session as unknown.
  bool _crazeSeeded = false;

  final _crazeSources = StreamController<int?>.broadcast();

  /// What the craze tunnel's stderr last proved about this machine's craze
  /// (not installed, too old) — Dart's pre-`hello` class (see
  /// `craze_reach.dart`). Handed to every source this feed opens, and spent
  /// once a snapshot is live: only a seed proves the far side answers.
  CrazeReachNote? _crazeNote;

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

  /// The craze tunnel's local port, or null while it is down — what a teardown
  /// cell dials to prove the tunnel went with the feed.
  @visibleForTesting
  int? get crazeTunnelPort => _crazeTunnel?.port;

  /// **The epoch of the craze source a lane may open through NOW**, or null
  /// while there is none: no source installed (a stopped feed, a restart in
  /// progress), or one that has not seeded yet. A craze lane records it at
  /// open and follows [crazeSources] from then on (`LaneController`'s craze
  /// source rule).
  int? get crazeLiveEpoch =>
      (_crazeSource != null && _crazeSeeded) ? _crazeEpoch : null;

  /// **Every change of [crazeLiveEpoch]** — null when the source a lane rode
  /// is retired (a [stop], the first half of a restart), the new epoch once
  /// its replacement has seeded. What lets an open craze transcript leave a
  /// retired source at once and re-open through the next one, instead of
  /// redialling a closed port (plan 025 §3.7.2, the CM3 review).
  Stream<int?> get crazeSources => _crazeSources.stream;

  /// Open the tunnels and start watching — roost's, then craze's
  /// ([_startCraze]). Idempotent, and safe to call on every foreground.
  ///
  /// **With roost already running, only a missing craze half is started.** A
  /// craze half that failed (a port that would not bind, a source that would
  /// not open) is torn down and leaves roost running; returning early on that
  /// running watcher would leave the machine with no craze rows and no craze
  /// create until the feed was rebuilt. So this call retries [_startCraze]
  /// alone, at the current generation, under the same [_starting] guard.
  /// Roost is not restarted for it; the source it installs is a new epoch,
  /// announced on [crazeSources] like any replacement.
  ///
  /// **A start asked for while one is in flight is not dropped.** A roost
  /// install restarts the feed — [stop], then [start] ([_entitle]) — and when
  /// that lands while a start (or a craze retry) is still opening, the stop
  /// has fenced the in-flight one off: it builds nothing more, and returning
  /// early here as well would leave the feed stopped until some other start.
  /// So the request is recorded ([_startAgain]) and the in-flight start runs
  /// it once it finishes — unless the owner has stopped the feed since.
  Future<void> start() async {
    if (_starting) {
      _startAgain = true;
      return;
    }
    if (_watcher != null) {
      if (_crazeSource == null && _crazeTunnel == null) {
        _starting = true;
        try {
          await _startCraze(_generation);
        } finally {
          _starting = false;
          await _startIfAsked();
        }
      }
      return;
    }
    _starting = true;
    // The same fence `_connect` uses: a `stop()` during either await below has
    // already run `_teardown()`, so installing what this call built would put a
    // tunnel or a watcher back behind the feed's back. Nothing owns them at that
    // point, so this call closes what it made rather than leaking it.
    final generation = _generation;
    try {
      final tunnel = await _openTunnel(
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
      // The machine's craze hub, beside its roost (plan 025 §3.7.2). It can
      // fail without taking roost down with it: a machine with roost and no
      // usable craze tunnel is still a machine with sessions to show.
      await _startCraze(generation);
    } catch (e) {
      // Binding the port failed — the machine itself is not dialled here at
      // all (the tunnel execs per accepted connection), so an asleep or
      // unauthorized machine arrives as the watcher's `Down` instead.
      await _teardown();
      _emit(_state.copyWith(reachable: false, detail: _describe(e)));
    } finally {
      _starting = false;
      await _startIfAsked();
    }
  }

  /// Run the [start] asked for while the one finishing now was in flight —
  /// once. [stop] and [dispose] cancel the request, so a feed its owner
  /// stopped after asking stays stopped.
  Future<void> _startIfAsked() async {
    if (!_startAgain) return;
    _startAgain = false;
    await start();
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

  /// **Open the craze half**: the craze tunnel, then the source handle on its
  /// port, then the handle's nudge stream — each await fenced by the
  /// generation, so a [stop] or [dispose] that lands mid-open releases what
  /// this call built instead of installing it behind the feed's back.
  ///
  /// A failure here (a port that will not bind, a source that will not open)
  /// leaves craze absent and roost running: [_teardownCraze] releases whatever
  /// was installed, and the next [start] tries this half again, alone.
  Future<void> _startCraze(int generation) async {
    try {
      final tunnel = await _openTunnel(
        connect: _connect,
        // Opaque, and composed by shed-core — craze's published ladder ending
        // in `craze bridge --hub` (plan 025 §3.4). Dart composes no part of it.
        remoteCommand: crazeRemoteCommand(),
        machine: machine.name,
        onStderr: _observeCrazeStderr,
      );
      if (await releaseIfStopped(
        startedAt: generation,
        current: _generation,
        resource: tunnel,
        release: (t) => t.close(),
      )) {
        return;
      }
      _crazeTunnel = tunnel;

      // Rust is handed the PORT and nothing else, exactly as the watcher is.
      final source = await _openCrazeSource(
        machine: machine.name,
        port: tunnel.port,
      );
      if (await releaseIfStopped(
        startedAt: generation,
        current: _generation,
        resource: source,
        release: (s) async => _closeCrazeSource(s),
      )) {
        return;
      }
      _crazeSource = source;
      _crazeEpoch++;
      _crazeSeeded = false;
      // What an earlier tunnel's stderr already proved about this machine.
      final note = _crazeNote;
      if (note != null) {
        crazeSourceNoteReach(
          src: source,
          cause: note.cause,
          message: note.message,
        );
      }
      _crazeSub = _crazeNudges(src: source).listen(
        (_) => _pullCraze(generation),
        // A nudge stream that errors is still "something changed", and the
        // snapshot is the authority on what.
        onError: (Object _) => _pullCraze(generation),
      );
      // The source may already have something to say (Dart's own note above).
      _pullCraze(generation);
    } catch (_) {
      if (generation == _generation) await _teardownCraze();
    }
  }

  /// Read the source's snapshot into the state — the nudge's acknowledgement.
  void _pullCraze(int generation) {
    if (generation != _generation) return;
    final source = _crazeSource;
    if (source == null) return;
    final snapshot = crazeSourceSnapshot(src: source);
    // Only a seed proves craze answers here — the one thing that spends what
    // the tunnel's stderr said (the roost reach's rule, `_apply`).
    if (snapshot.live) _crazeNote = null;
    _emit(_state.copyWith(craze: snapshot));
    // The first seed through THIS source: lanes may open through it now, and
    // a lane the last restart left waiting re-opens here.
    if (snapshot.live && !_crazeSeeded) {
      _crazeSeeded = true;
      if (!_crazeSources.isClosed) _crazeSources.add(_crazeEpoch);
    }
  }

  /// The craze tunnel exec's stderr TAIL — the only place the phone learns
  /// that a machine has no craze, or a craze too old for shed. See
  /// [crazeNoteForExec] for what is recorded and what deliberately is not.
  void _observeCrazeStderr(String text) {
    final note = crazeNoteForExec(stderr: text);
    if (note == null) return;
    _crazeNote = note;
    final source = _crazeSource;
    if (source != null) {
      crazeSourceNoteReach(
        src: source,
        cause: note.cause,
        message: note.message,
      );
    }
  }

  /// **Open one craze session's transcript** — the lane the machine's craze
  /// source opens on `hostId` (plan 025 §3.7.2): no forward and no stamp URL,
  /// the source's own dial. Throws while the craze half is down; a lane treats
  /// that as transient and retries on its ladder.
  Future<BridgeLane> openCrazeLane(String hostId) async {
    final source = _crazeSource;
    // Not before the source has SEEDED: a source that has not read its roster
    // yet holds no row, and a lane bound through it would answer
    // `unknown_session` — permanent — for a session that is right there. A
    // restart's replacement source is in exactly that state for its first
    // second.
    if (source == null || !_crazeSeeded) {
      throw StateError('craze is not connected on ${machine.name}');
    }
    return crazeLaneOpen(src: source, hostId: hostId);
  }

  /// What a craze create can start on this machine — its own connection,
  /// owned by this feed: a [dispose] cuts it short.
  Future<BridgeLaneCreateOptions> crazeOptions() async {
    final source = _crazeSource;
    if (source == null) {
      throw StateError('craze is not connected on ${machine.name}');
    }
    return crazeCreateOptions(src: source);
  }

  /// Create a craze session — its own connection, owned by this feed.
  ///
  /// **The new session's row is in [state] when this returns** (plan 025
  /// §3.6.4, §3.8): the source lists it at once (its created rows), and this
  /// reads the source's snapshot right after the create rather than waiting
  /// for the nudge it raised — so the transcript the create screen opens next,
  /// whose lane resolves its row from [state] the moment it is built, finds
  /// it, and a row this read does NOT list is a session craze answered for
  /// that has already ended. The roster's own frame follows and replaces it.
  ///
  /// Throws a [StateError] — before anything is sent — while the machine has
  /// no craze source.
  Future<BridgeLaneCreated> crazeCreateSession(
    BridgeLaneCreateRequest request,
  ) async {
    final source = _crazeSource;
    if (source == null) {
      throw StateError('craze is not connected on ${machine.name}');
    }
    final created = await crazeCreate(src: source, request: request);
    // Only through the source that created it: a restart's replacement has
    // its own pull, and reading a retired handle would emit its last view.
    if (identical(source, _crazeSource)) _pullCraze(_generation);
    return created;
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
    // A start asked for before this stop does not outlive it.
    _startAgain = false;
    await _teardown();
    _emit(
      _state.copyWith(
        reachable: false,
        detail: 'paused',
        // The craze rows stay, last known — as the roost rows do.
        craze: staleCraze(_state.craze),
      ),
    );
  }

  Future<void> dispose() async {
    _startAgain = false;
    await _teardown();
    await _controller.close();
    await _crazeSources.close();
  }

  Future<void> _teardown() async {
    _generation++;
    final sub = _sub;
    _sub = null;
    final watcher = _watcher;
    _watcher = null;
    if (watcher != null) {
      // The SYNCHRONOUS stop, not just a drop: it aborts the watcher and the
      // forwarder even while they are parked.
      await stopRoostWatcher(handle: watcher);
    }
    // **The stop FIRST, the cancel after it** — the lane's deadlock rule
    // (`LaneController._dropHandle`), which this teardown used to break. An
    // FRB stream's cancel completes only once the Rust side sends its next
    // frame or closes its sink, so a cancel awaited before the stop waited for
    // the watcher's NEXT update: forever on a quiet machine, and every step
    // below it — the tunnel, the craze half, the connection — with it. The
    // craze harness's teardown cells caught it as a dispose that hung until
    // the next roost `Down` (plan 025 CM3).
    await sub?.cancel();
    await _tunnel?.close();
    _tunnel = null;
    await _teardownCraze();
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

  /// **The craze half's teardown, in its one safe order** (plan 025 §3.7.2):
  /// the source handle FIRST — `crazeSourceClose` aborts its roster pump and
  /// its nudge forwarder and cuts short any create in flight — and only then
  /// the nudge subscription's cancel, because an FRB stream's cancel does not
  /// complete while the Rust side still holds it (the lane's deadlock,
  /// `LaneController._dropHandle`); then the tunnel, whose port and execs go
  /// with it. A restart therefore never holds two source handles: the old one
  /// is closed here before [start] opens the next on the new port.
  Future<void> _teardownCraze() async {
    final source = _crazeSource;
    _crazeSource = null;
    final sub = _crazeSub;
    _crazeSub = null;
    if (source != null) _closeCrazeSource(source);
    await sub?.cancel();
    final tunnel = _crazeTunnel;
    _crazeTunnel = null;
    await tunnel?.close();
    // The source is retired: say so, so a lane opened through it closes now
    // and waits for the replacement ([crazeSources]).
    final wasLive = _crazeSeeded;
    _crazeSeeded = false;
    if (source != null && wasLive && !_crazeSources.isClosed) {
      _crazeSources.add(null);
    }
  }

  /// Close a source handle and let go of this side's reference — the sync
  /// close is the teardown; the dispose releases the opaque explicitly rather
  /// than waiting on its finalizer (`BridgeLaneSource.close`'s precedent). Both
  /// are idempotent.
  static void _closeCrazeSource(BridgeCrazeSource source) {
    crazeSourceClose(src: source);
    if (!source.isDisposed) source.dispose();
  }

  /// Fold [update] as if the roost watcher had pushed it.
  ///
  /// The hermetic craze harness's way to put a craze-owned roost tab beside a
  /// LIVE craze feed (plan 025 §3.7.4's "a fake roost row") without a
  /// `roost-session` to report one — so the row merge it asserts is the one
  /// every real update goes through ([_apply] → [_emit]).
  @visibleForTesting
  void applyRoostUpdateForTest(BridgeRoostUpdate update) => _apply(update);

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
  /// every lane forward use, exactly as [acquireForward] does: a bootstrap
  /// costs no second SSH link and inherits the dial's dedupe and generation
  /// fencing.
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

  /// Publish [next] — **folded**: every state the feed emits carries its rows
  /// from the row merge ([machineRows] over [_foldPlan], once per update), so
  /// no view ever merges roost and craze rows for itself.
  void _emit(MachineFeedState next) {
    _state = next.copyWith(
      rows: machineRows(
        sessions: next.sessions,
        craze: next.craze,
        plan: _foldPlan,
      ),
    );
    if (!_controller.isClosed) _controller.add(_state);
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
