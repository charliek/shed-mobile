import '../core/app_error.dart';
import '../src/rust/api/dto.dart';
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

/// Coerce any caught object from a bridge call into an [AppError] (bridge calls
/// throw [BridgeError]; anything else is wrapped).
AppError appErrorFrom(Object e) =>
    e is BridgeError ? appErrorFromBridge(e) : AppError('SHED_ERROR', '$e');
