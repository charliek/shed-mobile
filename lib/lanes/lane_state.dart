import '../core/app_error.dart';
import '../src/rust/api/dto_lane.dart';
import '../src/rust/api/dto_rc.dart';
import 'lane_settings.dart';

/// The three facts a lane's snapshot carries about the SESSION rather than its
/// transcript — its live row, its capabilities and its settings — as one value.
///
/// One value because they are replaced TOGETHER, verbatim, from one snapshot
/// and never merged field by field: the live view is the newer truth,
/// including about what it does not say, so a null in it (no seed yet, a
/// session with no settings) must land as a null rather than leave the
/// previous value showing.
typedef LaneLive = ({
  BridgeLaneSession? session,
  BridgeLaneCapabilities? capabilities,
  BridgeLaneSettings? settings,
});

/// Nothing known about the session yet — what a fresh lane, or a lane re-opened
/// against a new stamp, holds until its first seed lands.
const LaneLive laneLiveUnknown = (
  session: null,
  capabilities: null,
  settings: null,
);

/// **One agent lane, as a screen renders it** (plan 018 §3.11).
///
/// A projection of the bridge's [BridgeLaneSnapshot] plus the three things Dart
/// itself knows: the error a verb was refused with, whether a re-open is
/// pending, and whether this lane has been given up on.
///
/// The session's capabilities, settings and live row are the SNAPSHOT's, not
/// something read once at open (plan 025 §3.2.1): they ride the lane's stream
/// and a craze session's change with its incarnation, so a copy taken at open
/// would be stale by construction.
///
/// **Nothing here is folded.** The transcript, the approval set and the
/// activity are Rust's fold (`shed_app::lane_view`), taken whole under one lock
/// by `lane_snapshot`; the only merge this side does is "replace or append",
/// decided by [BridgeLaneSnapshot.full]. That is the whole reason the phone and
/// the desktop cannot drift: there is one fold, and it is not in Dart.
class LaneState {
  LaneState({
    this.rows = const [],
    this.activity = BridgeRcActivity.unknown,
    BigInt? generation,
    this.stale,
    this.ended = false,
    this.approvals = const [],
    this.session,
    this.capabilities,
    this.settings,
    this.error,
    this.approvalErrors = const {},
    this.composerError,
    this.stopError,
    this.settingMarks = const {},
    this.settingsSeen = 0,
    this.retrying = false,
    this.abandoned = false,
    // `BigInt.zero` is not a compile-time constant, which is the only reason
    // this class is not `const`.
  }) : generation = generation ?? BigInt.zero;

  /// The transcript, oldest first — the lane's rows ARE `RcFeedMessage`s, which
  /// is what lets the RC watch screen's row widgets render them unchanged.
  final List<BridgeRcFeedMessage> rows;

  /// Is the agent running? **Separate from [approvals]**, which answers "is it
  /// blocked on me" — the pinned opencode mapping never emits `needsApproval`,
  /// so a blocked badge keyed off activity alone would miss every opencode
  /// approval.
  final BridgeRcActivity activity;

  /// Rust's generation counter for [rows]. Moves only when a seed COMPLETES, so
  /// a change here means "the transcript you hold was replaced", never "one is
  /// being built".
  final BigInt generation;

  /// The banner: why the stream behind these rows is not live, when it is not.
  /// These rows are then the last complete generation. **Not a lifecycle
  /// fact** — an adapter resuming from its cursor sets it and clears it again
  /// with the lane never ending, so nothing re-opens on it (see [ended]).
  final String? stale;

  /// The lifecycle: the lane's subscription ENDED (a `Down`), and the
  /// controller is re-opening it (see [retrying]) or has given up (see
  /// [abandoned]). The one fact a re-open is keyed on (plan 025 §3.2.4).
  final bool ended;

  /// The asks still waiting on the human, oldest first. Pending only — Rust
  /// applies `lane_status_is_pending`, so a client never has to.
  final List<BridgeLaneApproval> approvals;

  /// The session's row as the live stream last said it — its title, its
  /// permission posture — or null until a seed carrying one has completed.
  /// **This, not the row the lane was opened from, is the session's current
  /// state** (plan 025 §3.6.5): a header reads its facts from here once it is
  /// non-null.
  final BridgeLaneSession? session;

  /// What this SESSION can do, as of the live generation — null until a seed
  /// carrying them has completed. From the snapshot, never cached at open: a
  /// panel gates every affordance on this.
  final BridgeLaneCapabilities? capabilities;

  /// The session's settings, as of the live generation; null when it has none
  /// to show (its capabilities say `settings: false`).
  final BridgeLaneSettings? settings;

  /// A lane-level failure: the open was refused. Distinct from the two inline
  /// errors below, which belong to one control.
  final AppError? error;

  /// A refused answer, **keyed by the approval id that raised it**. An adapter
  /// refuses a `Permission` whose decision matches no offered option with
  /// `BadRequest`, and refuses a second answer to one approval — both belong
  /// on that card, not in a toast that says nothing about which card.
  final Map<String, AppError> approvalErrors;

  /// A refused send or cancel. The composer's own inline error, for the same
  /// reason: `not_accepting` on a cancel means "the turn ended between the
  /// render and the tap", which is only legible next to the button.
  final AppError? composerError;

  /// A refused (or lost) Stop — the header's own error, beside the control
  /// that raised it. Not [composerError]: Stop ends the SESSION, and its
  /// refusal says nothing about what was typed. A stop that WORKED says
  /// nothing here at all: its completion is the lane ending (`ended`, with
  /// `session_closed`), which is the banner's.
  final AppError? stopError;

  /// **Each settings row's mark** (plan 025 §3.10), keyed by
  /// [SettingsRow.key]: a change pending, refused, or not confirmed — the
  /// desktop's `RowMark`s. Held HERE, on the lane, not in the settings sheet,
  /// for the desktop's reason (its marks live in the panel): closing the sheet
  /// while a change is in flight loses nothing, and reopening it shows the row
  /// as it stands. Read through [shownMark] with [settingsSeen].
  final Map<String, RowMark> settingMarks;

  /// How many `Settings` the session has sent that a read of a LIVE view
  /// reflects — what ends a lost change's "not confirmed" ([shownMark]).
  /// Monotonic for the lane's life, across re-opens (each handle counts from
  /// zero; the controller carries the total), and moved only by a snapshot
  /// whose `stale` is clear, so a mark never goes before the value that
  /// replaces it is on screen.
  final int settingsSeen;

  /// A re-open is waiting out its backoff. The screen says "reconnecting"
  /// rather than showing a dead lane as if it were live.
  final bool retrying;

  /// This lane will not be re-opened: its row is gone from the machine, the
  /// agent does not know the session, or the kind has no adapter in this build.
  /// **Terminal** — the only way back is a new stamp on the row.
  final bool abandoned;

  LaneState copyWith({
    List<BridgeRcFeedMessage>? rows,
    BridgeRcActivity? activity,
    BigInt? generation,
    String? stale,
    bool? ended,
    List<BridgeLaneApproval>? approvals,
    LaneLive? live,
    AppError? error,
    Map<String, AppError>? approvalErrors,
    AppError? composerError,
    AppError? stopError,
    Map<String, RowMark>? settingMarks,
    int? settingsSeen,
    bool? retrying,
    bool? abandoned,
    bool clearStale = false,
    bool clearError = false,
    bool clearComposerError = false,
    bool clearStopError = false,
  }) => LaneState(
    rows: rows ?? this.rows,
    activity: activity ?? this.activity,
    generation: generation ?? this.generation,
    stale: clearStale ? null : (stale ?? this.stale),
    ended: ended ?? this.ended,
    approvals: approvals ?? this.approvals,
    session: live == null ? session : live.session,
    capabilities: live == null ? capabilities : live.capabilities,
    settings: live == null ? settings : live.settings,
    error: clearError ? null : (error ?? this.error),
    approvalErrors: approvalErrors ?? this.approvalErrors,
    composerError: clearComposerError
        ? null
        : (composerError ?? this.composerError),
    stopError: clearStopError ? null : (stopError ?? this.stopError),
    settingMarks: settingMarks ?? this.settingMarks,
    settingsSeen: settingsSeen ?? this.settingsSeen,
    retrying: retrying ?? this.retrying,
    abandoned: abandoned ?? this.abandoned,
  );
}
