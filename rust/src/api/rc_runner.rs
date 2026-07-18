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

use shed_core::rc::{
    create_invocation, decode_list, error_from_exit, kill_argv, list_argv, prompt_argv, RcKind,
};

use super::dto_rc::BridgeRcSessionDto;
use super::error::BridgeError;

/// The rc binary name on the shed. Mobile owns this (not `RcService`'s hard-coded
/// `"shed-desktop"`).
const RC_BIN: &str = "shed-ext-rc";
/// Mobile's provenance tag stamped on created sessions.
const CREATED_BY: &str = "shed-mobile";

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
/// string (`claude-rc`/`shell`/…); mobile owns `created_by`.
#[allow(clippy::too_many_arguments)]
pub fn rc_create_invocation(
    kind: String,
    name: String,
    slug: String,
    target: String,
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
        CREATED_BY,
        &target,
        permission_mode.as_deref(),
        prompt.as_deref(),
    )?;
    Ok(BridgeRcInvocation { argv, stdin })
}

/// Decode a `shed-ext-rc list` stdout (what the Dart runner captured) into the
/// neutral session DTOs — the "decode-in" half of the round-trip.
pub fn rc_decode_list(stdout: String) -> Result<Vec<BridgeRcSessionDto>, BridgeError> {
    let dtos = decode_list(&stdout)?;
    Ok(dtos.into_iter().map(Into::into).collect())
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
            None,
            Some("plan".into()),
            Some("hello".into()),
        )
        .unwrap();
        assert!(inv.argv.contains(&"--wait".to_string()));
        assert!(inv.argv.contains(&"--permission-mode".to_string()));
        assert_eq!(inv.stdin.as_deref(), Some("hello"));

        // An invalid mode for the kind → RcBadRequest, no argv.
        let err = rc_create_invocation(
            "codex".into(),
            "S".into(),
            "c".into(),
            "proj".into(),
            None,
            Some("plan".into()), // claude-only mode, invalid for codex
            None,
        )
        .unwrap_err();
        assert!(matches!(err, BridgeError::RcBadRequest { .. }));
    }

    #[test]
    fn decode_list_and_exit_mapping() {
        let canned = r#"{"rc_sessions":[{"slug":"cdx","tmux_session":"t",
            "kind":"claude-rc","state":"ready","managed":true,"display_name":"My"}]}"#;
        let sessions = rc_decode_list(canned.into()).unwrap();
        assert_eq!(sessions.len(), 1);
        assert_eq!(sessions[0].slug, "cdx");
        assert_eq!(
            sessions[0].kind,
            super::super::dto_rc::BridgeRcKind::ClaudeRc
        );
        assert_eq!(
            sessions[0].state,
            super::super::dto_rc::BridgeRcState::Ready
        );

        assert!(matches!(
            rc_error_from_exit(3, "in use".into(), String::new()),
            BridgeError::RcSlugTaken { .. }
        ));
        assert!(matches!(
            rc_error_from_exit(127, String::new(), String::new()),
            BridgeError::RcMissingBinary
        ));
    }
}
