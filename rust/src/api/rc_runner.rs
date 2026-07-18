//! The RC-over-SSH path driven through the PURE `shed_core::rc` functions
//! directly (plan §3.5 option a), NOT `shed-app::RcService`. Rust builds the
//! argv (the validating `create_invocation` gate + `list`/`prompt`/`kill`), Dart
//! runs it over dartssh2, and Rust decodes the captured stdout (`decode_list`) /
//! maps the exit code (`error_from_exit`). No `rc`/`tokio-process` feature is
//! pulled — these are pure builders/decoders.
//!
//! Trap (B1): `RcKind::Other("claude")` does NOT accept typed input — a create
//! that delivers a prompt must use `claude-rc`. `from_wire` preserves an unknown
//! kind as `Other`, whose `accepts_typed_input()` is false, so a prompt for such
//! a kind is dropped by `create_invocation` (not an error).

use serde_json::Value;
use shed_core::rc::{
    create_invocation, decode_list, decode_session, error_from_exit, kill_argv, list_argv,
    prompt_argv, RcKind, RcSession, RcSessionDto, RcState,
};

use super::dto_rc::BridgeRcSession;
use super::error::BridgeError;

/// The rc binary name on the shed. Mobile owns this (not `RcService`'s hard-coded
/// `"shed-desktop"`).
const RC_BIN: &str = "shed-ext-rc";

/// argv + optional stdin, marshalled to Dart. The Dart runner executes `argv`
/// over dartssh2, writing `stdin` (the initial prompt) to the process stdin.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRcInvocation {
    pub argv: Vec<String>,
    pub stdin: Option<String>,
}

/// `shed-ext-rc list` argv (pure builder).
pub fn rc_list_argv() -> Vec<String> {
    list_argv(RC_BIN)
}

/// `shed-ext-rc kill --slug <slug>` argv (pure builder).
pub fn rc_kill_argv(slug: String) -> Vec<String> {
    kill_argv(RC_BIN, &slug)
}

/// `shed-ext-rc prompt --slug <slug> [--session-id <id>]` argv (the B0 builder).
pub fn rc_prompt_argv(slug: String, session_id: Option<String>) -> Vec<String> {
    prompt_argv(RC_BIN, &slug, session_id.as_deref())
}

/// The validating create gate: builds the `create --wait` argv + stdin, running
/// `permission_mode` through `validate_permission_mode`. An invalid mode for the
/// kind is an [`BridgeError::RcBadRequest`] (no argv built). `kind` is the wire
/// string (`claude-rc`/`shell`/…). `created_by` is supplied by Dart so the wire
/// provenance carries the app version (`shed-mobile/<version>`) — the Rust side
/// deliberately owns no version constant.
#[allow(clippy::too_many_arguments)]
pub fn rc_create_invocation(
    kind: String,
    name: String,
    slug: String,
    target: String,
    created_by: String,
    workdir: Option<String>,
    permission_mode: Option<String>,
    prompt: Option<String>,
) -> Result<BridgeRcInvocation, BridgeError> {
    let rc_kind = RcKind::from_wire(&kind);
    let (argv, stdin) = create_invocation(
        RC_BIN,
        &rc_kind,
        &name,
        &slug,
        workdir.as_deref(),
        &created_by,
        &target,
        permission_mode.as_deref(),
        prompt.as_deref(),
    )?;
    Ok(BridgeRcInvocation { argv, stdin })
}

/// Decode a `shed-ext-rc list` stdout (what the Dart runner captured) into the
/// ENRICHED sessions the app renders. `from_dto` injects `host`/`shed` and
/// applies the `<shed>/<slug>` display-name fallback, so the SSH-`list` path and
/// the overview path converge on ONE session type ([`BridgeRcSession`]).
///
/// Two shims run before/after the strict `shed_core` decode (both target
/// contract-drift that shed-core is PINNED against here): [`prenormalize_states`]
/// makes the strict `state` field tolerant of a future token (F3), and [`enrich`]
/// corrects the `from_dto` display-name/workdir normalization drift (F4).
pub fn rc_decode_sessions(
    stdout: String,
    host: String,
    shed: String,
) -> Result<Vec<BridgeRcSession>, BridgeError> {
    let dtos = decode_list(&prenormalize_list_states(&stdout))?;
    Ok(dtos.into_iter().map(|d| enrich(d, &host, &shed)).collect())
}

/// Decode a single-session `create --wait` response into an enriched session
/// (same `from_dto` enrichment + `<shed>/<slug>` fallback as [`rc_decode_sessions`],
/// same F3 state-tolerance + F4 normalization shims).
pub fn rc_decode_session(
    stdout: String,
    host: String,
    shed: String,
) -> Result<BridgeRcSession, BridgeError> {
    let dto = decode_session(&prenormalize_session_state(&stdout))?;
    Ok(enrich(dto, &host, &shed))
}

/// F3 — the strict-`state` shim. shed-core's `RcSessionDto.state` is a STRICT
/// kebab-case serde derive (a future state string from a newer `shed-ext-rc`, e.g.
/// "paused", fails the WHOLE decode), while `RcKind`/`RcActivity` are already
/// tolerant custom `from_wire` deserializers. shed-core is pinned here, so close
/// the one gap in the bridge: rewrite each session object's `state` string through
/// `RcState::from_wire` (identity on a known value, `Starting` on an unknown one)
/// before the strict decode. Only the `state` key is touched. Malformed JSON that
/// won't parse to a `Value` is returned unchanged so the caller's decode still
/// reports the proper `RcError`.
// TODO(shed): make RcSessionDto.state tolerant in shed-core and retire this shim.
fn normalize_state(obj: &mut serde_json::Map<String, Value>) {
    if let Some(Value::String(s)) = obj.get("state") {
        // `from_wire` is infallible; the derived `Serialize` yields the kebab wire
        // form (`Ready` → "ready", `Starting` → "starting", …).
        if let Some(wire) = serde_json::to_value(RcState::from_wire(s))
            .ok()
            .and_then(|v| v.as_str().map(str::to_string))
        {
            obj.insert("state".to_string(), Value::String(wire));
        }
    }
}

/// Normalize the `state` of every session inside a `{"rc_sessions":[…]}` envelope.
fn prenormalize_list_states(stdout: &str) -> String {
    match serde_json::from_str::<Value>(stdout) {
        Ok(mut v) => {
            if let Some(arr) = v.get_mut("rc_sessions").and_then(Value::as_array_mut) {
                for item in arr {
                    if let Some(obj) = item.as_object_mut() {
                        normalize_state(obj);
                    }
                }
            }
            v.to_string()
        }
        // Not JSON at all — let `decode_list` report the malformed payload.
        Err(_) => stdout.to_string(),
    }
}

/// Normalize the `state` of a single bare-session `create --wait` response object.
fn prenormalize_session_state(stdout: &str) -> String {
    match serde_json::from_str::<Value>(stdout) {
        Ok(mut v) => {
            if let Some(obj) = v.as_object_mut() {
                normalize_state(obj);
            }
            v.to_string()
        }
        Err(_) => stdout.to_string(),
    }
}

/// F4 — enrich a DTO into a bridge session, correcting two `RcSession::from_dto`
/// normalization drifts vs. the historical Dart mapper (shed-core is pinned):
///   * `from_dto` only falls back `display_name` on `None` — a BLANK or
///     whitespace-only value survives; the old Dart mapper fell back on those too.
///     Restore the `<shed>/<slug>` fallback when the raw value trims to empty.
///   * `from_dto` synthesizes `Some(DEFAULT_WORKDIR)` ("/workspace", which no
///     current shed has) when the DTO omits `workdir`; the old mapper kept it
///     `None`. Restore the DTO's raw `workdir` Option (None stays None).
fn enrich(dto: RcSessionDto, host: &str, shed: &str) -> BridgeRcSession {
    let raw_display = dto.display_name.clone();
    let raw_workdir = dto.workdir.clone();
    let slug = dto.slug.clone();
    let mut session: BridgeRcSession = RcSession::from_dto(dto, host, shed).into();
    if raw_display
        .as_deref()
        .map(str::trim)
        .unwrap_or("")
        .is_empty()
    {
        session.display_name = format!("{shed}/{slug}");
    }
    session.workdir = raw_workdir;
    session
}

/// Map a non-zero exit from the Dart runner to a typed [`BridgeError`] (exit 3 →
/// `RcSlugTaken`, 4 → `RcNotFound`, 2 → `RcBadRequest`, 127 → `RcMissingBinary`,
/// … ). Returns the error value (not a `Result`) — the caller already knows the
/// run failed.
pub fn rc_error_from_exit(exit_code: i32, stderr: String, stdout: String) -> BridgeError {
    error_from_exit(exit_code, &stderr, &stdout).into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn list_and_kill_and_prompt_argv() {
        assert_eq!(rc_list_argv(), vec!["shed-ext-rc", "list"]);
        assert_eq!(
            rc_kill_argv("cdx".into()),
            vec!["shed-ext-rc", "kill", "--slug", "cdx"]
        );
        let p = rc_prompt_argv("cdx".into(), Some("sess".into()));
        assert!(p.contains(&"prompt".to_string()));
        assert!(p.contains(&"--session-id".to_string()));
        // No session id → no --session-id flag.
        let p2 = rc_prompt_argv("cdx".into(), None);
        assert!(!p2.contains(&"--session-id".to_string()));
    }

    #[test]
    fn create_invocation_gate_validates_mode() {
        // claude-rc accepts a prompt + a claude-only mode.
        let inv = rc_create_invocation(
            "claude-rc".into(),
            "My Session".into(),
            "cdx".into(),
            "proj".into(),
            "shed-mobile/1.0.0".into(),
            None,
            Some("plan".into()),
            Some("hello".into()),
        )
        .unwrap();
        assert!(inv.argv.contains(&"--wait".to_string()));
        assert!(inv.argv.contains(&"--permission-mode".to_string()));
        // Dart-supplied provenance carries the app version verbatim.
        assert!(inv.argv.contains(&"shed-mobile/1.0.0".to_string()));
        assert_eq!(inv.stdin.as_deref(), Some("hello"));

        // An invalid mode for the kind → RcBadRequest, no argv.
        let err = rc_create_invocation(
            "codex".into(),
            "S".into(),
            "c".into(),
            "proj".into(),
            "shed-mobile/1.0.0".into(),
            None,
            Some("plan".into()), // claude-only mode, invalid for codex
            None,
        )
        .unwrap_err();
        assert!(matches!(err, BridgeError::RcBadRequest { .. }));
    }

    #[test]
    fn decode_sessions_enriches_and_exit_mapping() {
        use super::super::dto_rc::{BridgeRcKind, BridgeRcState};
        let canned = r#"{"rc_sessions":[{"slug":"cdx","tmux_session":"t",
            "kind":"claude-rc","state":"ready","managed":true,"display_name":"My"}]}"#;
        let sessions = rc_decode_sessions(canned.into(), "mini3".into(), "proj".into()).unwrap();
        assert_eq!(sessions.len(), 1);
        assert_eq!(sessions[0].slug, "cdx");
        assert_eq!(sessions[0].host, "mini3");
        assert_eq!(sessions[0].shed, "proj");
        assert_eq!(sessions[0].kind, BridgeRcKind::ClaudeRc);
        assert_eq!(sessions[0].state, BridgeRcState::Ready);
        // display_name present → used as-is.
        assert_eq!(sessions[0].display_name, "My");

        // A single create-response decodes to the same enriched type; a missing
        // display_name falls back to "<shed>/<slug>".
        let one = rc_decode_session(
            r#"{"slug":"cdx","tmux_session":"t","kind":"shell","state":"ready","managed":true}"#
                .into(),
            "mini3".into(),
            "proj".into(),
        )
        .unwrap();
        assert_eq!(one.display_name, "proj/cdx");

        assert!(matches!(
            rc_error_from_exit(3, "in use".into(), String::new()),
            BridgeError::RcSlugTaken { .. }
        ));
        assert!(matches!(
            rc_error_from_exit(127, String::new(), String::new()),
            BridgeError::RcMissingBinary
        ));
    }

    // ---- F3: tolerant state decode on the SSH path ------------------------

    #[test]
    fn unknown_state_decodes_as_starting_in_list() {
        use super::super::dto_rc::BridgeRcState;
        // "paused" is a future state a newer shed-ext-rc might report — the strict
        // shed-core derive would fail the whole decode without the F3 shim.
        let canned = r#"{"rc_sessions":[{"slug":"cdx","tmux_session":"t",
            "kind":"claude-rc","state":"paused","managed":true,"display_name":"My"}]}"#;
        let sessions = rc_decode_sessions(canned.into(), "mini3".into(), "proj".into()).unwrap();
        assert_eq!(sessions.len(), 1);
        assert_eq!(sessions[0].state, BridgeRcState::Starting);
    }

    #[test]
    fn unknown_state_decodes_as_starting_in_single_session() {
        use super::super::dto_rc::BridgeRcState;
        let one = rc_decode_session(
            r#"{"slug":"cdx","tmux_session":"t","kind":"shell","state":"paused","managed":true}"#
                .into(),
            "mini3".into(),
            "proj".into(),
        )
        .unwrap();
        assert_eq!(one.state, BridgeRcState::Starting);
    }

    #[test]
    fn known_states_are_unchanged_by_the_shim() {
        use super::super::dto_rc::BridgeRcState;
        for (wire, want) in [
            ("ready", BridgeRcState::Ready),
            ("needs-auth", BridgeRcState::NeedsAuth),
            ("dead", BridgeRcState::Dead),
            ("starting", BridgeRcState::Starting),
        ] {
            let one = rc_decode_session(
                format!(
                    r#"{{"slug":"c","tmux_session":"t","kind":"shell","state":"{wire}","managed":true}}"#
                ),
                "h".into(),
                "s".into(),
            )
            .unwrap();
            assert_eq!(one.state, want, "state {wire}");
        }
    }

    #[test]
    fn malformed_json_still_surfaces_a_decode_error() {
        // The shim must NOT mask a genuinely malformed payload — it falls through
        // to the strict decode, which reports RcFailed.
        assert!(matches!(
            rc_decode_session("not json".into(), "h".into(), "s".into()),
            Err(BridgeError::RcFailed { .. })
        ));
        assert!(matches!(
            rc_decode_sessions(r#"{"rc_sessions":null}"#.into(), "h".into(), "s".into()),
            Err(BridgeError::RcFailed { .. })
        ));
    }

    // ---- F4: from_dto normalization drift ---------------------------------

    #[test]
    fn blank_display_name_falls_back_to_shed_slug() {
        for blank in ["", "   ", "\t\n"] {
            let one = rc_decode_session(
                format!(
                    r#"{{"slug":"cdx","tmux_session":"t","kind":"shell","state":"ready","managed":true,"display_name":"{}"}}"#,
                    blank.escape_default()
                ),
                "mini3".into(),
                "proj".into(),
            )
            .unwrap();
            assert_eq!(one.display_name, "proj/cdx", "blank {blank:?}");
        }
    }

    #[test]
    fn absent_workdir_stays_none_not_synthesized() {
        // from_dto synthesizes Some("/workspace"); the F4 shim restores None.
        let one = rc_decode_session(
            r#"{"slug":"cdx","tmux_session":"t","kind":"shell","state":"ready","managed":true}"#
                .into(),
            "mini3".into(),
            "proj".into(),
        )
        .unwrap();
        assert_eq!(one.workdir, None);
        // A present workdir is preserved verbatim.
        let with = rc_decode_session(
            r#"{"slug":"cdx","tmux_session":"t","kind":"shell","state":"ready","managed":true,"workdir":"/home/shed/proj"}"#
                .into(),
            "mini3".into(),
            "proj".into(),
        )
        .unwrap();
        assert_eq!(with.workdir.as_deref(), Some("/home/shed/proj"));
    }
}
