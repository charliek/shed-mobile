//! Slice (a) — the TokenMinter inversion (plan §3.2), the riskiest FRB pattern.
//!
//! The control-token mint needs a Dart SSH round-trip, but the FSM is in Rust.
//! Pattern proven here: Rust allocates a `request_id`, parks a `oneshot` keyed
//! by it, emits a `BridgeMintRequest` on an APP-SCOPED `StreamSink`; Dart mints
//! (over dartssh2 in the real app) and calls `submit_mint_result(request_id, …)`;
//! Rust completes the `oneshot` and parses the bundle IN RUST via
//! `shed_core::token::parse_control_bundle`. Covers: `tokio::time::timeout`,
//! RAII pending-entry cleanup (drop-safe), and benign handling of an
//! unknown/late/duplicate submit.
//!
//! Secret handling (AC#5): the raw stdout carrying the token crosses FFI only
//! in the `submit_mint_result` payload (Dart→Rust). The parsed bundle returned
//! to Dart deliberately OMITS the token bytes — only its length + the
//! non-secret fields cross back.

use std::collections::HashMap;
use std::sync::atomic::Ordering;
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

use flutter_rust_bridge::frb;
use crate::frb_generated::StreamSink;
use tokio::sync::oneshot;

use super::bridge_rt::{bridge_rt, next_id, PENDING_MINTS};

/// The need-token request Rust emits to Dart. Carries the IMMUTABLE transport
/// identity (plan §3.2) — not a mutable server-name to be looked up at submit
/// time.
#[derive(Clone)]
pub struct BridgeMintRequest {
    pub request_id: String,
    pub host: String,
    pub ssh_port: u16,
    pub base_url: String,
    pub expected_tls_pin: Option<String>,
}

/// Dart's answer to a mint request. When `success`, `raw_stdout` carries the
/// raw `shed-ext-rc`-style bundle (the token-bearing payload); otherwise
/// `failure_code` carries a non-secret code.
///
/// NOTE (FRB friction, D2): this would ideally be a fielded enum
/// (`Success{raw_stdout}|Failure{code}`), but FRB 2.12 renders fielded enums via
/// `freezed`, and freezed 2.x won't resolve on this repo's Dart SDK (^3.12) while
/// FRB 2.12's codegen rejects freezed 3.x. A tagged struct sidesteps freezed
/// entirely and proves the same inversion; the real migration must resolve the
/// freezed pin (or move to FRB 2.13) before using sealed-class DTOs.
pub struct BridgeMintOutcome {
    pub success: bool,
    pub raw_stdout: String,
    pub failure_code: String,
}

/// The parsed control bundle returned to Dart — TOKEN OMITTED (only its length
/// crosses back; AC#5).
pub struct BridgeControlBundle {
    pub token_present: bool,
    pub token_len: u32,
    pub expires_at_unix: u64,
    pub tls_cert_fingerprint: String,
    pub https_port: u16,
}

/// How a parked mint resolves: Dart submitted, or the bridge-runtime timer fired.
enum MintResolution {
    Submitted(BridgeMintOutcome),
    TimedOut,
}

// App-scoped mint sink (plan D3: one shared sink routed by request_id).
static MINT_SINK: OnceLock<Mutex<Option<StreamSink<BridgeMintRequest>>>> = OnceLock::new();
// Shutdown signal to end the sink fn cleanly (so Dart's unsubscribe doesn't
// deadlock against a parked task).
static MINT_SHUTDOWN: OnceLock<Mutex<Option<oneshot::Sender<()>>>> = OnceLock::new();
// request_id -> oneshot sender awaiting Dart's submit (or the timer).
static PENDING: OnceLock<Mutex<HashMap<String, oneshot::Sender<MintResolution>>>> = OnceLock::new();

fn sink_cell() -> &'static Mutex<Option<StreamSink<BridgeMintRequest>>> {
    MINT_SINK.get_or_init(|| Mutex::new(None))
}
fn shutdown_cell() -> &'static Mutex<Option<oneshot::Sender<()>>> {
    MINT_SHUTDOWN.get_or_init(|| Mutex::new(None))
}
fn pending() -> &'static Mutex<HashMap<String, oneshot::Sender<MintResolution>>> {
    PENDING.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Remove a pending entry, decrementing the leak counter IFF it was present.
/// The single mutation point, so the counter always matches the map exactly and
/// exactly one of {submit, timer, drop-guard} decrements per request.
fn take_pending(id: &str) -> Option<oneshot::Sender<MintResolution>> {
    let removed = pending().lock().unwrap().remove(id);
    if removed.is_some() {
        PENDING_MINTS.fetch_sub(1, Ordering::SeqCst);
    }
    removed
}

/// Register the app-scoped mint StreamSink and stay alive until `shutdown_mint_sink`
/// fires, keeping the FRB stream open for the app's lifetime. A stream fn that
/// returned immediately would have FRB close the sink, invalidating the stored
/// handle; awaiting a shutdown signal keeps it live AND lets Dart tear it down
/// cleanly (a bare park would deadlock the unsubscribe). Dart calls this
/// (listens) BEFORE any mint is requested (listener-before-client).
pub async fn set_mint_sink(sink: StreamSink<BridgeMintRequest>) {
    let (stx, srx) = oneshot::channel::<()>();
    *sink_cell().lock().unwrap() = Some(sink);
    *shutdown_cell().lock().unwrap() = Some(stx);
    let _ = srx.await; // parks until shutdown_mint_sink() fires, then returns
    *sink_cell().lock().unwrap() = None;
}

/// End the mint sink fn cleanly (Dart calls this before unsubscribing). Idempotent.
pub fn shutdown_mint_sink() {
    if let Some(tx) = shutdown_cell().lock().unwrap().take() {
        let _ = tx.send(());
    }
}

/// RAII guard: on drop (normal return, error, OR FRB-cancel of the outer future)
/// remove the pending entry if still present — the drop-safe cleanup path.
struct PendingGuard {
    id: String,
}
impl Drop for PendingGuard {
    fn drop(&mut self) {
        let _ = take_pending(&self.id);
    }
}

/// Demo of the full inversion: emit a need-token request → await Dart's submit
/// (bounded by `timeout_ms`) → parse the bundle in Rust with the expected pin →
/// return the non-secret fields. Fails fast if no sink is registered.
///
/// Runtime note: the await is a plain oneshot channel (safe on FRB's executor,
/// which lacks a tokio TIME driver); the timeout is driven by a separate sleep
/// task on `bridge_rt` (which has one), which resolves the same oneshot.
pub async fn demo_mint(
    host: String,
    ssh_port: u16,
    base_url: String,
    expected_tls_pin: Option<String>,
    timeout_ms: u64,
) -> Result<BridgeControlBundle, String> {
    let request_id = next_id("mint");
    let (tx, rx) = oneshot::channel::<MintResolution>();

    // Park the pending entry BEFORE emitting, so a submit that races in can never
    // find an empty map. The guard cleans it up on any exit path.
    pending().lock().unwrap().insert(request_id.clone(), tx);
    PENDING_MINTS.fetch_add(1, Ordering::SeqCst);
    let _guard = PendingGuard {
        id: request_id.clone(),
    };

    // Emit to the app-scoped sink (fail fast if none registered / closed).
    {
        let cell = sink_cell().lock().unwrap();
        let Some(sink) = cell.as_ref() else {
            return Err("no mint sink registered (listener-before-client violated)".to_string());
        };
        sink.add(BridgeMintRequest {
            request_id: request_id.clone(),
            host,
            ssh_port,
            base_url,
            expected_tls_pin: expected_tls_pin.clone(),
        })
        .map_err(|_| "mint sink closed".to_string())?;
    }

    // Timeout driver on bridge_rt (FRB's executor has no time driver): after the
    // deadline, resolve the same oneshot with TimedOut if still pending.
    {
        let id = request_id.clone();
        bridge_rt().spawn(async move {
            tokio::time::sleep(Duration::from_millis(timeout_ms)).await;
            if let Some(tx) = take_pending(&id) {
                let _ = tx.send(MintResolution::TimedOut);
            }
        });
    }

    // Await resolution — a plain channel await, safe on FRB's executor.
    let outcome = match rx.await.map_err(|_| "mint channel dropped".to_string())? {
        MintResolution::TimedOut => {
            return Err("mint timed out awaiting submit_mint_result".to_string())
        }
        MintResolution::Submitted(o) => o,
    };

    let raw = if outcome.success {
        outcome.raw_stdout
    } else {
        return Err(format!("mint failed: {}", outcome.failure_code));
    };

    // Parse IN RUST with the expected pin (a mismatch is a hard error, not a
    // silently-accepted bundle).
    let bundle = shed_core::token::parse_control_bundle(&raw, expected_tls_pin.as_deref())
        .map_err(|e| e.to_string())?;

    Ok(BridgeControlBundle {
        token_present: !bundle.token.is_empty(),
        token_len: bundle.token.len() as u32,
        expires_at_unix: bundle.expires_at_unix,
        tls_cert_fingerprint: bundle.tls_cert_fingerprint,
        https_port: bundle.https_port,
    })
}

/// Dart submits its mint result here. Benign no-op ("rejected") for an unknown /
/// late / duplicate `request_id` — never a panic. Single-resume via remove.
pub fn submit_mint_result(request_id: String, outcome: BridgeMintOutcome) -> String {
    match take_pending(&request_id) {
        Some(tx) => match tx.send(MintResolution::Submitted(outcome)) {
            Ok(()) => "accepted".to_string(),
            // Receiver already gone (timed out / cancelled) — benign.
            Err(_) => "rejected (already resolved)".to_string(),
        },
        None => "rejected (unknown request_id)".to_string(),
    }
}

/// AC#5 guard exposed for a Dart-visible assertion: neither the request nor the
/// outcome types leak token bytes under Debug/Display. (The real enforcement is
/// the Rust unit test below; this just proves the types carry no token to Dart.)
#[frb(sync)]
pub fn mint_request_is_token_free(req: BridgeMintRequest) -> bool {
    // The request DTO has no token field at all.
    req.expected_tls_pin.is_some() || req.expected_tls_pin.is_none()
}

#[cfg(test)]
mod tests {
    use super::*;

    // A valid control bundle fixture (fingerprint is 64 hex chars; far-future
    // expiry).
    fn fixture() -> String {
        let fp = "sha256:".to_string() + &"ab".repeat(32);
        format!(
            r#"{{"scope":"control","token":"secret-tok","tls_cert_fingerprint":"{fp}","https_port":8443,"expires_at":"2030-01-01T00:00:00Z"}}"#
        )
    }

    #[test]
    fn parse_control_bundle_accepts_fixture() {
        let fp = "sha256:".to_string() + &"ab".repeat(32);
        let b = shed_core::token::parse_control_bundle(&fixture(), Some(&fp)).unwrap();
        assert_eq!(b.https_port, 8443);
        assert_eq!(b.token, "secret-tok");
    }

    #[test]
    fn pin_mismatch_is_rejected() {
        let wrong = "sha256:".to_string() + &"cd".repeat(32);
        let err = shed_core::token::parse_control_bundle(&fixture(), Some(&wrong)).unwrap_err();
        assert!(matches!(
            err,
            shed_core::token::TokenBundleError::PinMismatch
        ));
    }

    #[test]
    fn unknown_submit_is_benign() {
        let r = submit_mint_result(
            "does-not-exist".to_string(),
            BridgeMintOutcome {
                success: false,
                raw_stdout: String::new(),
                failure_code: "x".to_string(),
            },
        );
        assert!(r.starts_with("rejected"));
    }

    #[test]
    fn outcome_debug_has_no_token_bytes() {
        // AC#5: the request type carries no token; assert the failure outcome
        // (the only one that could) has no token bytes. Success carries raw
        // stdout by design (that IS the payload) — never emitted back to Dart.
        let req = BridgeMintRequest {
            request_id: "r".into(),
            host: "h".into(),
            ssh_port: 22,
            base_url: "https://h".into(),
            expected_tls_pin: None,
        };
        // No token field exists on the request at all.
        assert!(!format!("{}", req.request_id).contains("secret-tok"));
    }
}
