//! Slice (c) — the RC-over-SSH path driven through the PURE `shed_core::rc`
//! functions directly (plan §3.5 option a), NOT `shed-app::RcService`. Proves
//! the argv-out → Dart-exec → decode-in round-trip: Rust builds the argv (the
//! validating `create_invocation` gate + `list_argv`/`prompt_argv`/`kill_argv`),
//! Dart runs it over dartssh2 (here a fake runner returns canned shed-ext-rc
//! JSON), and Rust decodes via `decode_list` / maps exits via `error_from_exit`.
//! No `rc`/`tokio-process` feature is pulled — these are pure builders/decoders.

use shed_core::rc::{
    create_invocation, decode_list, error_from_exit, kill_argv, list_argv, prompt_argv, RcKind,
};

const RC_BIN: &str = "shed-ext-rc";
const CREATED_BY: &str = "shed-mobile/frb-spike";

/// argv + optional stdin, marshalled to Dart.
pub struct BridgeRcInvocation {
    pub argv: Vec<String>,
    /// The stdin payload (e.g. the initial prompt), if any.
    pub stdin: Option<String>,
}

/// A decoded session row (the small DTO the app renders).
pub struct BridgeRcSession {
    pub slug: String,
    pub kind: String,
    pub state: String,
    pub managed: bool,
    pub display_name: Option<String>,
}

/// `shed-ext-rc list` argv (pure builder).
pub fn rc_list_argv() -> Vec<String> {
    list_argv(RC_BIN)
}

/// `shed-ext-rc kill --slug <slug>` argv (pure builder).
pub fn rc_kill_argv(slug: String) -> Vec<String> {
    kill_argv(RC_BIN, &slug)
}

/// `shed-ext-rc prompt --slug <slug> [--session-id <id>]` argv (added in the
/// merged shed rev — the B0 `prompt_argv` gap is already closed here).
pub fn rc_prompt_argv(slug: String, session_id: Option<String>) -> Vec<String> {
    prompt_argv(RC_BIN, &slug, session_id.as_deref())
}

/// The validating create gate: builds the `create --wait` argv + stdin, running
/// `permission_mode` through `validate_permission_mode`. An invalid mode for the
/// kind returns an error (no argv built). `kind` is the wire string
/// (`claude`/`shell`/…); mobile owns `created_by`.
pub fn rc_create_invocation(
    kind: String,
    name: String,
    slug: String,
    target: String,
    workdir: Option<String>,
    permission_mode: Option<String>,
    prompt: Option<String>,
) -> Result<BridgeRcInvocation, String> {
    let rc_kind = RcKind::from_wire(&kind);
    let (argv, stdin) = create_invocation(
        RC_BIN,
        &rc_kind,
        &name,
        &slug,
        workdir.as_deref(),
        CREATED_BY,
        &target,
        permission_mode.as_deref(),
        prompt.as_deref(),
    )
    .map_err(|e| format!("{e:?}"))?;
    Ok(BridgeRcInvocation { argv, stdin })
}

/// Serialize a serde enum (e.g. `RcState`) to its canonical wire string.
fn wire_of<T: serde::Serialize>(v: &T) -> String {
    serde_json::to_value(v)
        .ok()
        .and_then(|j| j.as_str().map(str::to_string))
        .unwrap_or_default()
}

/// Decode a `shed-ext-rc list` stdout (what the Dart runner captured) into the
/// session DTOs. This is the "decode-in" half of the round-trip.
pub fn rc_decode_list(stdout: String) -> Result<Vec<BridgeRcSession>, String> {
    let dtos = decode_list(&stdout).map_err(|e| format!("{e:?}"))?;
    Ok(dtos
        .into_iter()
        .map(|d| BridgeRcSession {
            slug: d.slug,
            kind: d.kind.as_str().to_string(),
            state: wire_of(&d.state),
            managed: d.managed,
            display_name: d.display_name,
        })
        .collect())
}

/// Map a non-zero exit from the Dart runner to a stable error string (proves the
/// typed-error path: exit 3 → SlugTaken, 4 → NotFound, 127 → MissingBinary, …).
pub fn rc_error_from_exit(exit_code: i32, stderr: String, stdout: String) -> String {
    format!("{:?}", error_from_exit(exit_code, &stderr, &stdout))
}
