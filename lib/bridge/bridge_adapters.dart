import '../core/app_error.dart';
import '../src/rust/api/dto.dart';
import '../src/rust/api/dto_lane.dart';
import '../src/rust/api/error.dart';

/// Adapters between the FRB bridge and the app's Dart error/status types.
///
/// B4 finished the RC-domain swap: consumers now render the bridge RC types
/// (`BridgeRcSession`/`BridgeRcCapabilities`/`BridgeRcMessagesPage`) directly, so
/// the transitional RC converters are gone. What remains here is the
/// bridge→[AppError] mapping (status codes preserved) and the shed-status
/// helpers — both genuinely at the bridge boundary.

// ---- shed status ----------------------------------------------------------

/// Canonical wire string for a bridge shed status (folds `unknown` → the same
/// neutral token the Dart tolerant parser produced). Feeds `shedStatusTone`.
String bridgeShedStatusWire(BridgeShedStatus s) => switch (s) {
  BridgeShedStatus.running => 'running',
  BridgeShedStatus.stopped => 'stopped',
  BridgeShedStatus.starting => 'starting',
  BridgeShedStatus.error => 'error',
  BridgeShedStatus.unknown => 'unknown',
};

bool bridgeShedIsRunning(BridgeShed s) => s.status == BridgeShedStatus.running;

// ---- errors ---------------------------------------------------------------

/// Map a [BridgeError] into the app's [AppError], preserving the status code /
/// stable code the UI branches on (401 auth, 404 gone, 409 not-accepting, 503
/// hub-unavailable, and the rc-binary exit classes).
///
/// The `Rc*` variants ONLY arise from the RC-over-SSH path (`shed_core::rc`'s
/// `error_from_exit` / `decode_*`) — the HTTP plane surfaces every rc failure as
/// [BridgeError_BadStatus] (routed through [_fromStatus]), where the 404 arm keeps
/// producing `RC_SESSION_GONE`. So these arms restore the historical SSH-path
/// contract the old Dart `_rcError` mapper produced (exit 4 → `RC_NOT_FOUND`/404,
/// exit 127 / "command not found" → `SHED_EXT_RC_MISSING`/502, other non-zero →
/// `RC_FAILED`/500). The empty-detail fallback messages ("shed-ext-rc exited N",
/// the missing-binary text) are already applied Rust-side (`error_from_exit` +
/// `RcError::MissingBinary`'s Display), so the detail carries through verbatim.
/// The decode-failure case (also an `RcFailed`) is re-mapped to `RC_FAILED`/502 at
/// the decode call sites in `rc_service.dart` (a stale/broken binary contract is a
/// 502, not the exit-path 500).
AppError appErrorFromBridge(BridgeError e) => switch (e) {
  BridgeError_BadStatus(:final code) => _fromStatus(code),
  BridgeError_Transport(:final msg) => AppError('SHED_TRANSPORT', msg),
  BridgeError_Decode(:final msg) => AppError('SHED_PARSE_ERROR', msg),
  BridgeError_Create(:final msg) => AppError('SHED_CREATE_FAILED', msg),
  BridgeError_Config(:final msg) => AppError('SHED_CONFIG', msg),
  // 426 Upgrade Required: the remedy is on the SERVER (a newer
  // shed-host-agent), not something the phone can retry into success, so it
  // must not read as a transient transport error.
  BridgeError_AgentUpgradeRequired(:final server, :final detail) => AppError(
    'SHED_AGENT_UPGRADE_REQUIRED',
    '$server needs a newer shed-host-agent: $detail',
    426,
  ),
  BridgeError_RcSlugTaken(:final detail) => AppError(
    'RC_SLUG_TAKEN',
    detail,
    409,
  ),
  BridgeError_RcNotFound(:final detail) => AppError(
    'RC_NOT_FOUND',
    detail,
    404,
  ),
  BridgeError_RcBadRequest(:final detail) => AppError(
    'RC_BAD_REQUEST',
    detail,
    400,
  ),
  BridgeError_RcMissingBinary() => AppError(
    'SHED_EXT_RC_MISSING',
    'shed-ext-rc is not installed on this shed — update the shed image',
    502,
  ),
  BridgeError_RcFailed(:final detail) => AppError('RC_FAILED', detail, 500),
  BridgeError_TokenAuthExpired() => AppError.authExpired(),
  BridgeError_TokenPinMismatch() => AppError.tlsPinMismatch(),
  BridgeError_TokenPinMissing() => AppError.tlsPinMissing(),
};

AppError _fromStatus(int code) => switch (code) {
  401 => AppError.authExpired(),
  404 => AppError('RC_SESSION_GONE', 'rc session is gone', 404),
  409 => AppError(
    'RC_NOT_ACCEPTING',
    'the session is not accepting input right now',
    409,
  ),
  503 => AppError(
    'RC_HUB_UNAVAILABLE',
    'rc hub is not available for this shed',
    503,
  ),
  _ => AppError('SHED_SERVER_ERROR', 'HTTP $code', code),
};

/// Map a [BridgeLaneError] into the app's [AppError] (plan 018 §3.11).
///
/// One arm per contract variant, because the controller and the screen branch
/// on genuinely different things and a flattened "lane error" would lose all of
/// them:
///
/// * **`unavailable` is quiet** — nothing to talk to (the agent is not running,
///   the dial was refused, the tunnel is down). It renders as an unreachable
///   row with a reason, never as an error dialog, and it is what the re-open
///   ladder exists for.
/// * **`notAccepting` / `alreadySubmitted` / `alreadyResolved` are inline** on
///   the control that raised them. A double-tap is not news; a cancel refused
///   because the turn just ended is only legible next to the button.
/// * **`unsupportedLane` is distinct from `noLane`** and deliberately so:
///   `noLane` means the row carries nothing, while this one means there IS
///   something here that a NEWER build could speak to. Naming the kind is the
///   client's obligation under `AgentLaneStamp`'s own doc.
///
/// The `msg` arms carry the agent's or the adapter's own sentence whole. None of
/// them can carry probe bytes: every refusal Rust composes around a probe names
/// the reported url and nothing from the stdout (`discovery_from_probe`).
AppError appErrorFromLane(BridgeLaneError e) => switch (e) {
  BridgeLaneError_Unauthorized() => AppError(
    'LANE_UNAUTHORIZED',
    'the agent demanded a credential this build cannot supply',
    401,
  ),
  BridgeLaneError_BadRequest(:final msg) => AppError(
    'LANE_BAD_REQUEST',
    msg,
    400,
  ),
  BridgeLaneError_UnknownSession() => AppError(
    'LANE_UNKNOWN_SESSION',
    'the agent does not know this session',
    404,
  ),
  BridgeLaneError_UnknownApproval() => AppError(
    'LANE_UNKNOWN_APPROVAL',
    'that approval is no longer pending',
    404,
  ),
  BridgeLaneError_AlreadySubmitted() => AppError(
    'LANE_ALREADY_SUBMITTED',
    'an answer is already in flight',
    409,
  ),
  BridgeLaneError_AlreadyResolved() => AppError(
    'LANE_ALREADY_RESOLVED',
    'that approval has already been answered',
    409,
  ),
  BridgeLaneError_NotAccepting() => AppError(
    'LANE_NOT_ACCEPTING',
    'the session is not accepting that right now',
    409,
  ),
  BridgeLaneError_Unavailable(:final msg) => AppError(
    'LANE_UNAVAILABLE',
    msg,
    503,
  ),
  BridgeLaneError_Failed(:final msg) => AppError('LANE_FAILED', msg, 500),
  BridgeLaneError_NoLane(:final msg) => AppError('LANE_NONE', msg),
  BridgeLaneError_UnsupportedLane(:final kind) => AppError(
    'LANE_UNSUPPORTED_KIND',
    'this build has no adapter for a "$kind" lane',
  ),
};

/// Coerce any caught object from a bridge call into an [AppError] (bridge calls
/// throw [BridgeError] or [BridgeLaneError]; anything else is wrapped).
AppError appErrorFrom(Object e) => switch (e) {
  // Already typed — re-wrapping would bury the code the UI branches on inside a
  // `SHED_ERROR` message.
  final AppError err => err,
  final BridgeError err => appErrorFromBridge(err),
  final BridgeLaneError err => appErrorFromLane(err),
  _ => AppError('SHED_ERROR', '$e'),
};
