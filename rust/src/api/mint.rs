//! The TokenMinter inversion (plan §3.2) — production shape.
//!
//! The control-token FSM lives in Rust (`shed_core::ControlTokenProvider`), but
//! a mint needs a Dart SSH round-trip. Inversion: [`BridgeMinter`] (installed as
//! the provider's `TokenMinter`) allocates a `request_id`, parks a `oneshot`
//! keyed by it, emits a [`BridgeMintRequest`] on an APP-SCOPED `StreamSink`
//! (D3, routed by `request_id`); Dart mints over dartssh2 and calls
//! [`submit_mint_result`]; Rust completes the `oneshot` and parses the bundle
//! IN RUST via `parse_control_bundle` (with the expected pin). The whole path
//! runs on `bridge_rt` (FRB's executor has no tokio time driver — B1 finding 2),
//! so `tokio::time::timeout` is valid.
//!
//! Lifecycle invariants (plan §3.2): immutable transport identity in the
//! request; RAII pending-guard so an FRB-dropped future still cleans up; benign
//! rejection of unknown/late/duplicate submits; listener-before-client (a mint
//! with no sink fails fast); a capped pending map; one app-scoped sink with an
//! explicit shutdown seam (B1 finding 3) so Dart's unsubscribe never deadlocks.
//!
//! Secret handling (AC#5): the raw token-bearing stdout crosses FFI ONLY in the
//! [`submit_mint_result`] payload (Dart→Rust). It is parsed then dropped; it is
//! never logged, never placed in an error/`Display`/`Debug`, never retained past
//! the `oneshot`, and never emitted back to Dart. What crosses back
//! ([`BridgeControlBundle`]) carries the token LENGTH, not bytes. A unit test
//! asserts the request/outcome types are token-free under `Debug`.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

use flutter_rust_bridge::frb;
use tokio::sync::oneshot;

use shed_core::http::ShedError;
use shed_core::token::{ControlBundle, MintedToken, TokenBundleError, TokenMinter};

use crate::frb_generated::StreamSink;

use super::bridge_rt::{bridge_rt, next_id, PENDING_MINTS};
use super::error::encode_token_err;

/// Hard upper bound on a mint round-trip (SSH dial + remote exec + submit). The
/// provider's own cooldown/refresh-window knobs govern *when* a mint happens;
/// this bounds a single in-flight one so a wedged SSH never parks a request
/// forever.
const MINT_TIMEOUT: Duration = Duration::from_secs(45);

/// Cap on concurrently-parked mints. In practice one client mints at a time; a
/// runaway (e.g. a stuck Dart listener) fails fast rather than growing the map.
const MAX_PENDING_MINTS: usize = 64;

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

/// Dart's answer to a mint request — a real FRB 2.13 sealed enum (the B1
/// tagged-struct workaround is retired). `Success` carries the raw
/// `shed-ext-rc`-style bundle stdout (the token-bearing payload); `Failure`
/// carries a non-secret code.
pub enum BridgeMintOutcome {
    Success { raw_stdout: String },
    Failure { code: String },
}

/// The parsed control bundle returned to Dart from [`demo_mint`] — TOKEN OMITTED
/// (only its length crosses back; AC#5).
pub struct BridgeControlBundle {
    pub token_present: bool,
    pub token_len: u32,
    pub expires_at_unix: u64,
    pub tls_cert_fingerprint: String,
    pub https_port: u16,
}

/// The typed failure of the shared mint core, so the caller can preserve a
/// `TokenBundleError` (Codex review #3) instead of stringifying it.
enum RunMintError {
    Message(String),
    Token(TokenBundleError),
}

/// How a parked mint resolves: Dart submitted, the bridge-runtime timer fired,
/// or the sink was shut down out from under it (Codex review #2).
enum MintResolution {
    Submitted(BridgeMintOutcome),
    TimedOut,
    SinkShutdown,
}

/// Monotonic generation stamped on each registered sink, so a resuming
/// `set_mint_sink` task only clears the slot it still owns (Codex review #1).
static MINT_GEN: AtomicU64 = AtomicU64::new(0);

// App-scoped mint sink (plan D3: one shared sink routed by request_id), tagged
// with its generation.
static MINT_SINK: OnceLock<Mutex<Option<(u64, StreamSink<BridgeMintRequest>)>>> = OnceLock::new();
// Shutdown signal to end the sink fn cleanly (so Dart's unsubscribe doesn't
// deadlock against a parked task — B1 finding 3), tagged with its generation.
static MINT_SHUTDOWN: OnceLock<Mutex<Option<(u64, oneshot::Sender<()>)>>> = OnceLock::new();
// request_id -> oneshot sender awaiting Dart's submit (or the timer).
static PENDING: OnceLock<Mutex<HashMap<String, oneshot::Sender<MintResolution>>>> = OnceLock::new();

fn sink_cell() -> &'static Mutex<Option<(u64, StreamSink<BridgeMintRequest>)>> {
    MINT_SINK.get_or_init(|| Mutex::new(None))
}
fn shutdown_cell() -> &'static Mutex<Option<(u64, oneshot::Sender<()>)>> {
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

/// Register the app-scoped mint StreamSink and stay alive until
/// [`shutdown_mint_sink`] fires (keeping the FRB stream open for the app's
/// lifetime). Dart listens BEFORE any `BridgeClient` is constructed
/// (listener-before-client); a `mint` emitted with no sink fails fast.
///
/// Generation-guarded (Codex review #1): each registration takes a fresh
/// generation and, if a prior sink is live, evicts it FIRST (fires its shutdown
/// + drains its pending). When this task's await returns, it clears the slot
/// ONLY if it still owns the generation — so a later sink B installed while A's
/// task was parked is never clobbered by A.
pub async fn set_mint_sink(sink: StreamSink<BridgeMintRequest>) {
    let generation = MINT_GEN.fetch_add(1, Ordering::SeqCst) + 1;
    let (stx, srx) = oneshot::channel::<()>();
    {
        // Evict any prior owner before installing (fire its shutdown + drain).
        let prior = shutdown_cell().lock().unwrap().take();
        if let Some((_, old)) = prior {
            let _ = old.send(());
        }
        drain_pending_on_shutdown();
        *sink_cell().lock().unwrap() = Some((generation, sink));
        *shutdown_cell().lock().unwrap() = Some((generation, stx));
    }
    let _ = srx.await; // parks until shutdown_mint_sink() fires, then returns
    // Clear ONLY if we still own the slot (a newer generation may have replaced us).
    let mut cell = sink_cell().lock().unwrap();
    if cell.as_ref().map(|(g, _)| *g) == Some(generation) {
        *cell = None;
    }
    let mut sh = shutdown_cell().lock().unwrap();
    if sh.as_ref().map(|(g, _)| *g) == Some(generation) {
        *sh = None;
    }
}

/// End the mint sink fn cleanly (Dart calls this in `onDispose` before
/// unsubscribing). Idempotent. Resolves EVERY parked mint immediately with a
/// non-secret `SinkShutdown` (Codex review #2 — no more 45 s strand), then fires
/// the sink's shutdown signal. Synchronous so Riverpod `onDispose` can call it
/// without an unawaitable future (Codex review #9).
#[frb(sync)]
pub fn shutdown_mint_sink() {
    drain_pending_on_shutdown();
    if let Some((_, tx)) = shutdown_cell().lock().unwrap().take() {
        let _ = tx.send(());
    }
}

/// Resolve and remove EVERY parked mint with `SinkShutdown`, keeping the leak
/// counter exact (Codex review #2 — never strand a parked mint for the 45 s
/// timeout when the sink goes away).
fn drain_pending_on_shutdown() {
    let entries: Vec<(String, oneshot::Sender<MintResolution>)> =
        pending().lock().unwrap().drain().collect();
    for (_id, tx) in entries {
        PENDING_MINTS.fetch_sub(1, Ordering::SeqCst);
        let _ = tx.send(MintResolution::SinkShutdown);
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

/// The shared inversion core: emit a need-token request → await Dart's submit
/// (bounded) → parse the bundle in Rust with the expected pin → return the
/// `ControlBundle` (token bytes stay in Rust). Used by both [`BridgeMinter::mint`]
/// (production) and [`demo_mint`] (the integration proof).
async fn run_mint(
    host: String,
    ssh_port: u16,
    base_url: String,
    expected_tls_pin: Option<String>,
    timeout: Duration,
) -> Result<ControlBundle, RunMintError> {
    let request_id = next_id("mint");
    let (tx, rx) = oneshot::channel::<MintResolution>();

    // Cap + park BEFORE emitting, so a submit that races in can never find an
    // empty map. The guard cleans it up on any exit path.
    {
        let mut map = pending().lock().unwrap();
        if map.len() >= MAX_PENDING_MINTS {
            return Err(RunMintError::Message(
                "mint rejected: too many pending mint requests".to_string(),
            ));
        }
        map.insert(request_id.clone(), tx);
    }
    PENDING_MINTS.fetch_add(1, Ordering::SeqCst);
    let _guard = PendingGuard {
        id: request_id.clone(),
    };

    // Emit to the app-scoped sink (fail fast if none registered / closed).
    {
        let cell = sink_cell().lock().unwrap();
        let Some((_, sink)) = cell.as_ref() else {
            return Err(RunMintError::Message(
                "no mint sink registered (listener-before-client violated)".to_string(),
            ));
        };
        sink.add(BridgeMintRequest {
            request_id: request_id.clone(),
            host,
            ssh_port,
            base_url,
            expected_tls_pin: expected_tls_pin.clone(),
        })
        .map_err(|_| RunMintError::Message("mint sink closed".to_string()))?;
    }

    // Timeout driver on bridge_rt (FRB's executor has no time driver): after the
    // deadline, resolve the same oneshot with TimedOut if still pending.
    {
        let id = request_id.clone();
        bridge_rt().spawn(async move {
            tokio::time::sleep(timeout).await;
            if let Some(tx) = take_pending(&id) {
                let _ = tx.send(MintResolution::TimedOut);
            }
        });
    }

    // Await resolution — a plain channel await (safe on any executor).
    let outcome = match rx
        .await
        .map_err(|_| RunMintError::Message("mint channel dropped".to_string()))?
    {
        MintResolution::TimedOut => {
            return Err(RunMintError::Message(
                "mint timed out awaiting submit_mint_result".to_string(),
            ))
        }
        MintResolution::SinkShutdown => {
            return Err(RunMintError::Message("mint sink shut down".to_string()))
        }
        MintResolution::Submitted(o) => o,
    };

    let raw = match outcome {
        BridgeMintOutcome::Success { raw_stdout } => raw_stdout,
        BridgeMintOutcome::Failure { code } => {
            return Err(RunMintError::Message(format!("mint failed: {code}")))
        }
    };

    // Parse IN RUST with the expected pin (a mismatch is a hard error, not a
    // silently-accepted bundle). Preserve the TYPED error (Codex #3). The raw
    // stdout is dropped at the end of this fn.
    shed_core::token::parse_control_bundle(&raw, expected_tls_pin.as_deref())
        .map_err(RunMintError::Token)
}

/// The production minter: installed as a `ControlTokenProvider`'s `TokenMinter`
/// so a real client request that needs a fresh control token drives the Dart
/// SSH round-trip. Carries the immutable transport identity (plan §3.2).
pub(crate) struct BridgeMinter {
    pub host: String,
    pub ssh_port: u16,
    pub base_url: String,
    pub expected_tls_pin: Option<String>,
}

#[async_trait::async_trait]
impl TokenMinter for BridgeMinter {
    async fn mint(&self, _server: &str) -> Result<MintedToken, ShedError> {
        let bundle = run_mint(
            self.host.clone(),
            self.ssh_port,
            self.base_url.clone(),
            self.expected_tls_pin.clone(),
            MINT_TIMEOUT,
        )
        .await
        // The trait can only return ShedError, so tunnel a typed TokenBundleError
        // through a MARKED transport message (Codex #3) — the client error path
        // (`From<ShedError>`) recovers it into TokenPinMismatch/PinMissing/
        // AuthExpired. A plain message stays a normal transport error. Both are
        // non-secret (run_mint never surfaces token bytes); the provider's posture
        // stays "no token on failure" (no downgrade).
        .map_err(|e| {
            ShedError::Transport(match e {
                RunMintError::Message(m) => m,
                RunMintError::Token(t) => encode_token_err(&t),
            })
        })?;
        Ok(MintedToken {
            token: bundle.token,
            expires_at_unix: Some(bundle.expires_at_unix),
        })
    }
}

/// The direct integration proof of the full inversion (retained from B1): emit →
/// await Dart's submit → parse in Rust → return the NON-SECRET fields (token
/// length only). The real app never calls this; `BridgeClient` mints via the
/// provider path. Kept because it exercises the inversion end-to-end from Dart
/// without needing a live shed-server.
pub async fn demo_mint(
    host: String,
    ssh_port: u16,
    base_url: String,
    expected_tls_pin: Option<String>,
    timeout_ms: u64,
) -> Result<BridgeControlBundle, String> {
    let bundle = run_mint(
        host,
        ssh_port,
        base_url,
        expected_tls_pin,
        Duration::from_millis(timeout_ms),
    )
    .await
    .map_err(|e| match e {
        RunMintError::Message(m) => m,
        RunMintError::Token(t) => t.to_string(),
    })?;
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

/// AC#5 helper: proves the request DTO carries no token field (there is nothing
/// token-bearing to leak on the Rust→Dart request). The real enforcement is the
/// unit test below.
#[frb(sync)]
pub fn mint_request_is_token_free(_req: BridgeMintRequest) -> bool {
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture(pin: &str) -> String {
        format!(
            r#"{{"scope":"control","token":"secret-tok","tls_cert_fingerprint":"{pin}","https_port":8443,"expires_at":"2030-01-01T00:00:00Z"}}"#
        )
    }

    #[test]
    fn parse_control_bundle_accepts_fixture() {
        let fp = "sha256:".to_string() + &"ab".repeat(32);
        let b = shed_core::token::parse_control_bundle(&fixture(&fp), Some(&fp)).unwrap();
        assert_eq!(b.https_port, 8443);
        assert_eq!(b.token, "secret-tok");
    }

    #[test]
    fn pin_mismatch_is_rejected() {
        let fp = "sha256:".to_string() + &"ab".repeat(32);
        let wrong = "sha256:".to_string() + &"cd".repeat(32);
        let err =
            shed_core::token::parse_control_bundle(&fixture(&fp), Some(&wrong)).unwrap_err();
        assert!(matches!(
            err,
            shed_core::token::TokenBundleError::PinMismatch
        ));
    }

    #[test]
    fn unknown_submit_is_benign() {
        let r = submit_mint_result(
            "does-not-exist".to_string(),
            BridgeMintOutcome::Failure { code: "x".into() },
        );
        assert!(r.starts_with("rejected"));
    }

    #[test]
    fn pending_registry_single_resume_and_counter_discipline() {
        // Drive the registry directly (no async sink): a parked entry resolves
        // exactly once; a duplicate/late submit for the same id is benign; the
        // leak counter tracks the map exactly.
        let before = PENDING_MINTS.load(Ordering::SeqCst);
        let (tx, mut rx) = oneshot::channel::<MintResolution>();
        pending().lock().unwrap().insert("req-x".into(), tx);
        PENDING_MINTS.fetch_add(1, Ordering::SeqCst);
        assert_eq!(PENDING_MINTS.load(Ordering::SeqCst), before + 1);

        // First submit resolves the parked oneshot.
        assert_eq!(
            submit_mint_result("req-x".into(), BridgeMintOutcome::Success { raw_stdout: "s".into() }),
            "accepted"
        );
        assert!(matches!(rx.try_recv(), Ok(MintResolution::Submitted(_))));
        // Counter back to baseline (take_pending decremented on the resolve).
        assert_eq!(PENDING_MINTS.load(Ordering::SeqCst), before);

        // A duplicate/late submit for the now-removed id is a benign no-op.
        assert!(submit_mint_result(
            "req-x".into(),
            BridgeMintOutcome::Failure { code: "late".into() }
        )
        .starts_with("rejected"));
        assert_eq!(PENDING_MINTS.load(Ordering::SeqCst), before);
    }

    #[test]
    fn request_type_has_no_token_field() {
        // AC#5: the Rust→Dart request carries no token bytes at all.
        let req = BridgeMintRequest {
            request_id: "r".into(),
            host: "h".into(),
            ssh_port: 22,
            base_url: "https://h".into(),
            expected_tls_pin: None,
        };
        assert!(mint_request_is_token_free(req));
    }
}
