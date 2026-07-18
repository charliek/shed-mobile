import '../core/app_error.dart';
import '../rc/rc_capabilities.dart';
import '../rc/rc_feed.dart';
import '../rc/rc_models.dart';
import '../src/rust/api/dto.dart';
import '../src/rust/api/dto_rc.dart';
import '../src/rust/api/error.dart';

/// Adapters between the FRB bridge DTOs and the app's Dart domain types.
///
/// B3 swaps the HTTP/DTO/token plane onto the bridge, but leaves the RC domain
/// (`rc_models`/`rc_capabilities`/`rc_feed` + `ActivityOverlay`) in Dart for B4.
/// The overview call now returns bridge DTOs, so the RC sub-objects it embeds
/// (`BridgeRcSession`/`BridgeRcCapabilities`) are converted back to the Dart RC
/// types here — that keeps every RC-rendering widget (session_card, codex watch,
/// shed detail) on the untouched Dart domain until B4 swaps it wholesale.

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

// ---- RC enums -------------------------------------------------------------

RcKind rcKindFromBridge(BridgeRcKind k) => switch (k) {
  BridgeRcKind_ClaudeRc() => RcKind.claudeRc,
  BridgeRcKind_ClaudeBroker() => RcKind.claudeBroker,
  BridgeRcKind_Codex() => RcKind.codex,
  BridgeRcKind_Opencode() => RcKind.opencode,
  BridgeRcKind_Cursor() => RcKind.cursor,
  BridgeRcKind_Shell() => RcKind.shell,
  BridgeRcKind_Other(:final raw) => RcKind.other(raw),
};

RcState rcStateFromBridge(BridgeRcState s) => switch (s) {
  BridgeRcState.starting => RcState.starting,
  BridgeRcState.ready => RcState.ready,
  BridgeRcState.reconnecting => RcState.reconnecting,
  BridgeRcState.needsTrust => RcState.needsTrust,
  BridgeRcState.needsAuth => RcState.needsAuth,
  BridgeRcState.dead => RcState.dead,
};

RcActivity? rcActivityFromBridge(BridgeRcActivity? a) => switch (a) {
  null => null,
  BridgeRcActivity.working => RcActivity.working,
  BridgeRcActivity.needsInput => RcActivity.needsInput,
  BridgeRcActivity.idle => RcActivity.idle,
  BridgeRcActivity.unknown => RcActivity.unknown,
};

// ---- RC sessions / capabilities (embedded in the overview) ----------------

RcSession rcSessionFromBridge(BridgeRcSession b) => RcSession(
  slug: b.slug,
  tmuxSession: b.tmuxSession,
  displayName: b.displayName,
  kind: rcKindFromBridge(b.kind),
  state: rcStateFromBridge(b.state),
  managed: b.managed,
  workdir: b.workdir,
  url: b.url,
  id: b.rcId,
  createdBy: b.createdBy,
  createdAt: b.createdAt,
  targetLabel: b.targetLabel,
  activity: rcActivityFromBridge(b.activity),
  activityAt: b.activityAt,
  lastMessage: b.lastMessage,
);

RcCapabilities rcCapabilitiesFromBridge(BridgeRcCapabilities c) =>
    RcCapabilities(
      rcVersion: c.rcVersion,
      kinds: c.kinds.map(rcKindFromBridge).toList(),
      agents: c.agents.map(
        (k, v) =>
            MapEntry(k, AgentInfo(installed: v.installed, version: v.version)),
      ),
      features: c.features,
      kindFeatures: c.kindFeatures.map(
        (k, v) => MapEntry(
          k,
          KindFeatures(
            postInput: v.postInput,
            approvals: v.approvals,
            watch: v.watch,
            input: v.input,
          ),
        ),
      ),
    );

// ---- RC message feed (codex watch) ----------------------------------------

RcMessagesPage rcMessagesPageFromBridge(BridgeRcMessagesPage p) =>
    RcMessagesPage(
      messages: p.messages
          .map(
            (m) => RcFeedMessage(
              seq: m.seq.toInt(),
              ts: m.ts,
              role: m.role,
              type: m.msgType,
              text: m.text,
              tool: m.tool == null
                  ? null
                  : RcFeedTool(name: m.tool!.name, detail: m.tool!.detail),
            ),
          )
          .toList(),
      truncated: p.truncated,
    );

// ---- errors ---------------------------------------------------------------

/// Map a [BridgeError] into the app's [AppError], preserving the status code /
/// stable code the UI branches on (401 auth, 404 gone, 409 not-accepting, 503
/// hub-unavailable, and the rc-binary exit classes).
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
    'RC_SESSION_GONE',
    detail,
    404,
  ),
  BridgeError_RcBadRequest(:final detail) => AppError(
    'RC_BAD_REQUEST',
    detail,
    400,
  ),
  BridgeError_RcMissingBinary() => AppError(
    'RC_MISSING_BINARY',
    'shed-ext-rc is not installed',
    127,
  ),
  BridgeError_RcFailed(:final detail) => AppError('RC_INPUT_FAILED', detail),
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
