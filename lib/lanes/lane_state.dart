import '../core/app_error.dart';
import '../src/rust/api/dto_lane.dart';
import '../src/rust/api/dto_rc.dart';

/// **One agent lane, as a screen renders it** (plan 018 §3.11).
///
/// A projection of the bridge's [BridgeLaneSnapshot] plus the four things Dart
/// itself knows: the adapter's capabilities (read once at open), the error a
/// verb was refused with, whether a re-open is pending, and whether this lane
/// has been given up on.
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
    this.approvals = const [],
    this.capabilities,
    this.needsCredentials = false,
    this.error,
    this.approvalErrors = const {},
    this.composerError,
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

  /// Why the transport is gone, when it is. These rows are then the last
  /// complete generation, and the controller is re-opening (see [retrying]).
  final String? stale;

  /// The asks still waiting on the human, oldest first. Pending only — Rust
  /// applies `lane_status_is_pending`, so a client never has to.
  final List<BridgeLaneApproval> approvals;

  /// What this adapter can do. Null until the lane is open; read ONCE at open
  /// (the contract states these are static for the adapter's life), so an
  /// unwinding panel keeps its buttons rather than watching them vanish.
  final BridgeLaneCapabilities? capabilities;

  /// gx asked for a fresh discovery. Set by the snapshot and cleared by the
  /// next one; the controller re-probes and calls `laneRefreshCredentials`
  /// **without re-opening** — the pin resumes in place (§3.9).
  final bool needsCredentials;

  /// A lane-level failure: the open was refused, or the credential refresh was.
  /// Distinct from the two inline errors below, which belong to one control.
  final AppError? error;

  /// A refused answer, **keyed by the approval id that raised it**. gx refuses
  /// a `Permission` whose decision matches no offered option with `BadRequest`,
  /// and either adapter refuses a second answer to one approval — both belong
  /// on that card, not in a toast that says nothing about which card.
  final Map<String, AppError> approvalErrors;

  /// A refused send or cancel. The composer's own inline error, for the same
  /// reason: `not_accepting` on a cancel means "the turn ended between the
  /// render and the tap", which is only legible next to the button.
  final AppError? composerError;

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
    List<BridgeLaneApproval>? approvals,
    BridgeLaneCapabilities? capabilities,
    bool? needsCredentials,
    AppError? error,
    Map<String, AppError>? approvalErrors,
    AppError? composerError,
    bool? retrying,
    bool? abandoned,
    bool clearStale = false,
    bool clearError = false,
    bool clearComposerError = false,
  }) => LaneState(
    rows: rows ?? this.rows,
    activity: activity ?? this.activity,
    generation: generation ?? this.generation,
    stale: clearStale ? null : (stale ?? this.stale),
    approvals: approvals ?? this.approvals,
    capabilities: capabilities ?? this.capabilities,
    needsCredentials: needsCredentials ?? this.needsCredentials,
    error: clearError ? null : (error ?? this.error),
    approvalErrors: approvalErrors ?? this.approvalErrors,
    composerError: clearComposerError
        ? null
        : (composerError ?? this.composerError),
    retrying: retrying ?? this.retrying,
    abandoned: abandoned ?? this.abandoned,
  );
}
