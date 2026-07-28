//! The add-server PREVIEW op (plan 002 §7 P7, amending plan 001 D8-mobile).
//!
//! First contact with a server cannot be a parser-only bridge call any more: an
//! `auth.mode: mtls` server REJECTS a CSR-less `_bootstrap` before it returns any
//! JSON at all ("this server requires auth.mode: mtls; upgrade shed"), so the
//! side that composes the request has to be the side that can generate a
//! keypair. That is Rust. Dart keeps the SSH transport and the TOFU host-key
//! decision; this module owns the enrollment.
//!
//! One round-trip, one ephemeral credential, one sanitized DTO:
//!
//! ```text
//!   preview_add_server(host, ssh_port)
//!     ├─ generate an ephemeral P-256 keypair + CSR          (shed_core::csr)
//!     ├─ emit a BridgeMintRequest{purpose: AddServerPreview,
//!     │        extra_args: ["csr=<std b64>"]}               (the mint inversion)
//!     ├─ Dart: ssh _bootstrap@host control shed-mobile csr=… (TOFU host key)
//!     ├─ parse the raw stdout                       (parse_control_bundle, D4)
//!     └─ return BridgeAddServerPreview + DROP the ephemeral credential
//! ```
//!
//! # What the DTO carries, and why token mode is different
//!
//! * **mtls**: the issued certificate is DISCARDED with its key. The user has not
//!   confirmed the server yet, and the first real `BridgeClient` mints its own
//!   credential from its own key on its first request. Cost: two SSH round-trips
//!   per mtls add — accepted and documented (also noted against shed #289's
//!   enrollment-rate-limit follow-up).
//! * **token**: the DTO RETURNS the token and its expiry, because that is exactly
//!   today's add-time crossing — `AddServerFlow.commit` persists it into
//!   `ServerRecord.controlToken` and `providers.dart` seeds the provider from it.
//!   Discarding it would make every token-mode cold launch re-mint over SSH: a
//!   regression plan 001 never intended, and one that would invalidate the §7 P8
//!   cold-launch comparison. Nothing else about the posture changes (§7 P7).
//!
//! # Disposal (§7 P7: "dropped on success, decline, cancellation, timeout, and
//! FRB-future disposal")
//!
//! [`EphemeralEnrollment`] (and the [`PreviewSlot`] single-flight token beside
//! it) is a plain LOCAL of the [`preview_add_server`] future — not spawned,
//! cloned, boxed, stashed in a static, or moved into another task. Every one of
//! those five exits is therefore the same mechanism — the future's frame is
//! dropped, so both `Drop`s run:
//!
//! | exit | what happens |
//! |---|---|
//! | success | the fn returns; the local drops |
//! | decline (Dart submits `Failure`) | `?` returns early; the local drops |
//! | timeout | the mint timer resolves the park with `TimedOut`; `?` returns |
//! | sink shutdown | the pending drain resolves the park; `?` returns |
//! | FRB future dropped (cancel) | the whole frame — enrollment included — drops |
//!
//! (`client::run`'s abort-on-drop guard exists because it SPAWNS onto `bridge_rt`
//! and a dropped `JoinHandle` merely detaches. Nothing here is spawned but the
//! mint's own timeout timer, which owns no credential material, so no guard is
//! needed — the absence of a spawn IS the guarantee.) A leak counter
//! (`live_counters().pending_preview_credentials`) makes all five assertable, and
//! a unit test drives each one.
//!
//! "Dropped" is not "zeroized" — stated honestly, as §7 P3 requires; zeroization
//! is out of scope for this plan.

use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use shed_core::csr::ClientKeyPair;
use shed_core::token::{parse_control_bundle, AuthMode, ControlBundle};

use super::bridge_rt::PENDING_PREVIEW_CREDENTIALS;
use super::error::BridgeError;
use super::mint::{csr_extra_args, run_mint_raw, BridgeMintPurpose, RunMintError};

/// What the add-server flow shows the user, and everything Dart needs to persist
/// a `ServerRecord` — with NOTHING it does not need.
///
/// Deliberately absent: the client certificate, its serial, and above all the
/// private key (which never leaves the [`preview_add_server`] frame). The SSH
/// host-key fingerprint is absent too, for a different reason — Dart learns it
/// from the TOFU store during the connection this preview drove, so Rust would
/// only be echoing it back.
pub struct BridgeAddServerPreview {
    /// `"token"` or `"mtls"` — the shape the server issued, normalized through
    /// `AuthMode::from_wire` (so a bundle's legacy `"secure"`, or no `auth_mode`
    /// key at all, reads as `"token"`).
    pub auth_mode: String,
    /// Canonical `sha256:<hex>` pin of the server's TLS leaf, delivered over the
    /// host-key-pinned SSH channel. The user confirms this.
    pub tls_cert_fingerprint: String,
    pub https_port: u16,
    /// The seed bearer token — **token mode only**, `None` in mtls mode.
    pub token: Option<String>,
    /// Expiry of [`Self::token`] in unix seconds; `None` whenever `token` is.
    pub token_expires_at_unix: Option<u64>,
}

/// Redacted `Debug`: in token mode this DTO holds a live bearer, and the
/// add-server flow logs liberally around it.
impl std::fmt::Debug for BridgeAddServerPreview {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("BridgeAddServerPreview")
            .field("auth_mode", &self.auth_mode)
            .field("tls_cert_fingerprint", &self.tls_cert_fingerprint)
            .field("https_port", &self.https_port)
            .field("token", &self.token.as_ref().map(|_| "<redacted>"))
            .field("token_expires_at_unix", &self.token_expires_at_unix)
            .finish()
    }
}

/// The keypair the preview enrolls with: generated here, held only here, dropped
/// here. It is never persisted, never handed to a minter, never returned, and
/// has no accessor for its private half — the ONLY thing that leaves is
/// [`Self::csr_base64`], the public request artifact.
struct EphemeralEnrollment {
    keypair: ClientKeyPair,
}

impl EphemeralEnrollment {
    fn generate() -> Result<Self, BridgeError> {
        let keypair = ClientKeyPair::generate()?;
        PENDING_PREVIEW_CREDENTIALS.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        Ok(Self { keypair })
    }

    fn csr_base64(&self) -> String {
        self.keypair.csr_base64()
    }
}

impl Drop for EphemeralEnrollment {
    fn drop(&mut self) {
        PENDING_PREVIEW_CREDENTIALS.fetch_sub(1, std::sync::atomic::Ordering::SeqCst);
    }
}

/// At most one preview may be in flight process-wide — see
/// [`PreviewSlot`] for why that is a correctness requirement and not a policy.
static PREVIEW_IN_FLIGHT: AtomicBool = AtomicBool::new(false);

/// The single-flight token for [`preview_add_server`], released on every exit by
/// `Drop` (the same discipline, and the same frame, as [`EphemeralEnrollment`]).
///
/// # Why previews must be mutually exclusive
///
/// A response is correlated to its request by `request_id` alone
/// (`submit_mint_result`), and that id is supplied by the CALLER — Dart. Two
/// previews in flight at once are therefore two answers Dart could transpose: a
/// bug (or a compromised listener) submitting host B's stdout under host A's
/// request id would have host A's preview parse host B's bundle, and the user
/// would confirm — and the app would persist — B's TLS pin, port and seed token
/// against A's name.
///
/// Rust cannot detect that transposition after the fact. The natural defence
/// would be to bind the expected host into the pending record and check it
/// against the answer, but a `_bootstrap` bundle carries NOTHING host-identifying
/// to check against: its fields are `auth_mode`, `scope`, `token`/`client_cert`,
/// `cert_serial`, `token_id`, `http_port`, `https_port`, `tls_cert_fingerprint`
/// and `expires_at` (`internal/sshd/bootstrap.go`). The pin is the very thing
/// first contact is here to LEARN, so it cannot also be the thing that
/// authenticates the answer, and the host only exists on the SSH channel, which
/// is Dart's side of the boundary.
///
/// So the transposition is removed rather than detected: with one preview in
/// flight there is exactly one outstanding id, and an answer can only belong to
/// the request that is waiting. The cost is a refusal — an interactive
/// add-server screen the user drives one host at a time — and the second caller
/// gets an actionable [`BridgeError::Config`] rather than a wrong success.
///
/// (A new `BridgeError` variant would be the more expressive error, but the Dart
/// adapter switches exhaustively over the generated sealed class
/// (`bridge_adapters.dart`), so adding one is a breaking change for a refusal
/// that is already unambiguous in its message.)
struct PreviewSlot;

impl PreviewSlot {
    fn acquire() -> Result<Self, BridgeError> {
        PREVIEW_IN_FLIGHT
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
            .map(|_| PreviewSlot)
            .map_err(|_| BridgeError::Config {
                msg: "another add-server preview is already in progress; \
                      finish or cancel it before previewing a second server"
                    .to_string(),
            })
    }
}

impl Drop for PreviewSlot {
    fn drop(&mut self) {
        PREVIEW_IN_FLIGHT.store(false, Ordering::SeqCst);
    }
}

/// Preview a server the app has never talked to: enroll, parse, sanitize, dispose.
///
/// `timeout_ms` bounds the whole SSH round-trip (Dart dial + remote exec +
/// submit). The add-server screen is interactive, so keep it in the same family
/// as Dart's own SSH timeout (15 s) rather than the background mint's 45 s —
/// §7 P8's budget alignment.
///
/// ONE preview at a time, process-wide: a second concurrent call is refused with
/// [`BridgeError::Config`] rather than queued, because two outstanding requests
/// are two answers that could be transposed — see [`PreviewSlot`]. The refusal
/// clears as soon as the first preview settles, by any exit.
///
/// Errors are the typed [`BridgeError`] the app already switches on: a bundle
/// with no usable TLS pin is `TokenPinMissing`, an expired/malformed one is
/// `TokenAuthExpired`, and everything else (no listener, decline, timeout,
/// oversized response, a second concurrent preview) is a `Transport`/`Config`
/// message. None of them carry credential bytes.
pub async fn preview_add_server(
    host: String,
    ssh_port: u16,
    timeout_ms: u64,
) -> Result<BridgeAddServerPreview, BridgeError> {
    // Taken BEFORE the keypair so a refused second caller generates nothing.
    let _slot = PreviewSlot::acquire()?;
    // Generated BEFORE the request is emitted and dropped when this frame ends —
    // see the module docs' disposal table.
    let enrollment = EphemeralEnrollment::generate()?;

    // A CSR is always sent: an mtls server requires one, and a token-mode server
    // (or a pre-mtls one) IGNORES the argument completely — `mintToken` never
    // decodes or validates it, which is the compat leg that lets one add-server
    // flow serve every server generation (plan 001 D4).
    let raw = run_mint_raw(
        BridgeMintPurpose::AddServerPreview,
        host.clone(),
        ssh_port,
        // The https port is what this call is here to LEARN, so the base URL is
        // the portless form the current Dart add-server flow already uses; the
        // real client is built from the bundle's port after the user confirms.
        format!("https://{host}"),
        // No pin is known on first contact — TOFU. The SSH host key is the trust
        // anchor, and the pin the bundle delivers is what the user confirms.
        None,
        csr_extra_args(Some(&enrollment.csr_base64())),
        Duration::from_millis(timeout_ms),
    )
    .await
    .map_err(|e| BridgeError::from(RunMintError::into_shed_error(e)))?;

    // The ADD-SERVER parse (stricter than the mint path's): the fingerprint and a
    // positive https_port are REQUIRED, because this is where they are learned.
    let bundle = parse_control_bundle(raw.as_str(), None)?;
    let preview = sanitize(bundle);

    // Explicit, though `enrollment` would drop here anyway: in mtls mode the
    // certificate the server just issued is already gone (it was never bound to
    // anything), and this drops the key it was issued for. The first real client
    // mints its own.
    drop(enrollment);
    Ok(preview)
}

/// Reduce a parsed bundle to the preview DTO, applying the §7 P7 rule that only
/// token mode carries credential material back to Dart.
fn sanitize(bundle: ControlBundle) -> BridgeAddServerPreview {
    let (token, token_expires_at_unix) = match bundle.auth_mode {
        AuthMode::Token => (Some(bundle.token), Some(bundle.expires_at_unix)),
        // The certificate and its serial stop here; there is nothing in an mtls
        // bundle that Dart could store and later use.
        AuthMode::Mtls => (None, None),
    };
    BridgeAddServerPreview {
        auth_mode: bundle.auth_mode.as_str().to_string(),
        tls_cert_fingerprint: bundle.tls_cert_fingerprint,
        https_port: bundle.https_port,
        token,
        token_expires_at_unix,
    }
}

#[cfg(test)]
mod tests {
    use std::future::Future;
    use std::sync::atomic::Ordering;
    use std::task::Context;

    use super::super::mint::{shutdown_mint_sink, submit_mint_result, BridgeMintOutcome};
    use super::super::testsupport::{
        install_sink_hook, mtls_bundle, noop_waker, pin, test_guard, token_bundle, wait_until,
        TestCa,
    };
    use super::*;

    fn live() -> u64 {
        PENDING_PREVIEW_CREDENTIALS.load(Ordering::SeqCst)
    }

    /// Drive one preview to completion on a throwaway runtime, with `respond`
    /// deciding how the emitted request is answered.
    fn run_preview(
        timeout_ms: u64,
        respond: impl FnOnce(super::super::mint::BridgeMintRequest) + Send + 'static,
    ) -> Result<BridgeAddServerPreview, BridgeError> {
        install_sink_hook(respond);
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
            .block_on(preview_add_server("host.example".into(), 2222, timeout_ms))
    }

    /// The transposition scenario, closed by construction (see [`PreviewSlot`]).
    ///
    /// Host A's preview is in flight — parked awaiting its SSH answer — when a
    /// second preview for host B starts. If both were allowed to park, a Dart
    /// listener that submitted B's stdout under A's `request_id` would have A's
    /// preview return B's pin, port and seed token, and the user would confirm
    /// them under A's name. There is nothing host-identifying in a bundle for
    /// Rust to catch that with, so the second preview is refused instead: only
    /// one request id is ever outstanding, so an answer can only belong to the
    /// request that is waiting.
    #[test]
    fn a_second_concurrent_preview_is_refused_so_answers_cannot_be_transposed() {
        let _g = test_guard();
        let before = live();
        let p = pin("ab");

        // Host A parks inside its emit; while it is parked we attempt host B.
        let inner: std::sync::Arc<std::sync::Mutex<Option<Result<_, BridgeError>>>> =
            std::sync::Arc::new(std::sync::Mutex::new(None));
        let slot = inner.clone();
        let p_a = p.clone();
        let a = run_preview(5_000, move |req| {
            // Still in flight here: the request is parked and unanswered. Polled
            // by hand (no nested runtime) — which also asserts the refusal is
            // IMMEDIATE: a second preview must never park behind the first.
            let mut b = Box::pin(preview_add_server("other.example".into(), 2222, 5_000));
            let waker = noop_waker();
            match b.as_mut().poll(&mut Context::from_waker(&waker)) {
                std::task::Poll::Ready(r) => *slot.lock().unwrap() = Some(r),
                std::task::Poll::Pending => panic!("the second preview parked instead of failing"),
            }
            submit_mint_result(
                req.request_id,
                BridgeMintOutcome::Success {
                    raw_stdout: token_bundle(&p_a, Some("token")),
                },
            );
        })
        .expect("host A's preview");
        assert_eq!(a.tls_cert_fingerprint, p);

        let b = inner.lock().unwrap().take().expect("host B attempted");
        match b.expect_err("the second concurrent preview must be refused") {
            BridgeError::Config { msg } => assert!(msg.contains("already in progress"), "{msg}"),
            other => panic!("expected a Config refusal, got {other:?}"),
        }
        // B generated no keypair, and A disposed of its own.
        assert_eq!(live(), before);
    }

    /// The single-flight token is released on EVERY exit, not just success — so
    /// a failed, timed-out or cancelled preview never wedges the add-server
    /// screen for the rest of the process's life.
    #[test]
    fn the_preview_slot_is_released_on_every_exit() {
        let _g = test_guard();
        let p = pin("ab");

        // 1. failure (decline)
        let _ = run_preview(5_000, |req| {
            submit_mint_result(
                req.request_id,
                BridgeMintOutcome::Failure {
                    code: "MINT_FAILED".into(),
                },
            );
        })
        .unwrap_err();
        // 2. timeout
        let _ = run_preview(60, |_req| {}).unwrap_err();
        // 3. cancellation mid-flight
        {
            install_sink_hook(|_req| {});
            let mut fut = Box::pin(preview_add_server("host.example".into(), 2222, 30_000));
            let waker = noop_waker();
            assert!(fut
                .as_mut()
                .poll(&mut Context::from_waker(&waker))
                .is_pending());
            drop(fut);
        }
        // ...and the next preview still runs.
        let p2 = p.clone();
        let ok = run_preview(5_000, move |req| {
            submit_mint_result(
                req.request_id,
                BridgeMintOutcome::Success {
                    raw_stdout: token_bundle(&p2, Some("token")),
                },
            );
        })
        .expect("the slot was released by every earlier exit");
        assert_eq!(ok.tls_cert_fingerprint, p);
    }

    #[test]
    fn token_mode_preview_returns_the_seed_and_disposes_the_enrollment() {
        let _g = test_guard();
        let before = live();
        let p = pin("ab");
        let p2 = p.clone();
        let out = run_preview(5_000, move |req| {
            // The CSR rides the request even though this server is token mode —
            // the server ignores it (plan 001 D4 legacy parity).
            assert_eq!(req.extra_args.len(), 1);
            assert!(req.extra_args[0].starts_with("csr="));
            assert_eq!(req.purpose, BridgeMintPurpose::AddServerPreview);
            submit_mint_result(
                req.request_id,
                BridgeMintOutcome::Success {
                    raw_stdout: token_bundle(&p2, Some("token")),
                },
            );
        })
        .expect("token preview");

        assert_eq!(out.auth_mode, "token");
        assert_eq!(out.tls_cert_fingerprint, p);
        assert_eq!(out.https_port, 8443);
        // §7 P7: the add-time token crossing is preserved, not regressed.
        assert_eq!(out.token.as_deref(), Some("secret-tok"));
        assert!(out.token_expires_at_unix.is_some());
        assert_eq!(live(), before, "enrollment disposed on success");
    }

    #[test]
    fn mtls_mode_preview_discards_the_certificate_and_the_key() {
        let _g = test_guard();
        let before = live();
        let p = pin("cd");
        let p2 = p.clone();
        let out = run_preview(5_000, move |req| {
            let csr = req.extra_args[0].strip_prefix("csr=").expect("csr arg");
            // A REAL certificate for the CSR this preview just generated.
            let cert = TestCa::new().sign_csr_base64(csr);
            submit_mint_result(
                req.request_id,
                BridgeMintOutcome::Success {
                    raw_stdout: mtls_bundle(&p2, &cert),
                },
            );
        })
        .expect("mtls preview");

        assert_eq!(out.auth_mode, "mtls");
        assert_eq!(out.tls_cert_fingerprint, p);
        assert_eq!(out.https_port, 8443);
        // Nothing usable comes back: no token, no expiry, and (structurally) no
        // certificate or key field exists to carry one.
        assert_eq!(out.token, None);
        assert_eq!(out.token_expires_at_unix, None);
        assert!(!format!("{out:?}").contains("BEGIN"));
        assert_eq!(live(), before, "enrollment disposed on success");
    }

    #[test]
    fn preview_disposes_on_decline() {
        let _g = test_guard();
        let before = live();
        let err = run_preview(5_000, |req| {
            submit_mint_result(
                req.request_id,
                BridgeMintOutcome::Failure {
                    code: "MINT_FAILED".into(),
                },
            );
        })
        .unwrap_err();
        assert!(matches!(err, BridgeError::Transport { .. }));
        assert_eq!(live(), before, "enrollment disposed on decline");
    }

    #[test]
    fn preview_disposes_on_timeout() {
        let _g = test_guard();
        let before = live();
        // Answer nothing: the bridge_rt timer resolves the park.
        let err = run_preview(60, |_req| {}).unwrap_err();
        assert!(matches!(err, BridgeError::Transport { .. }));
        assert_eq!(live(), before, "enrollment disposed on timeout");
    }

    #[test]
    fn preview_disposes_on_sink_shutdown() {
        let _g = test_guard();
        let before = live();
        // Dart tore the sink down (app teardown) while the preview was parked.
        let err = run_preview(30_000, |_req| shutdown_mint_sink()).unwrap_err();
        assert!(matches!(err, BridgeError::Transport { .. }));
        assert_eq!(live(), before, "enrollment disposed on sink shutdown");
    }

    #[test]
    fn preview_disposes_when_no_listener_is_registered() {
        let _g = test_guard();
        let before = live();
        // No hook installed and no Dart sink: the emit fails before any parking.
        let err = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
            .block_on(preview_add_server("host.example".into(), 2222, 5_000))
            .unwrap_err();
        assert!(matches!(err, BridgeError::Transport { .. }));
        assert_eq!(live(), before, "enrollment disposed when no sink exists");
    }

    /// The FRB-cancellation exit: Dart dropped the future while the preview was
    /// parked awaiting the SSH round-trip. Polled by hand so the future really is
    /// mid-await when it is dropped — which is also what proves the ephemeral key
    /// lives in the future's frame and nowhere else.
    #[test]
    fn preview_disposes_when_the_future_is_dropped_mid_flight() {
        let _g = test_guard();
        let before = live();
        install_sink_hook(|_req| {}); // park forever
        let mut fut = Box::pin(preview_add_server("host.example".into(), 30_000, 30_000));
        let waker = noop_waker();
        let mut cx = Context::from_waker(&waker);
        assert!(fut.as_mut().poll(&mut cx).is_pending());
        assert_eq!(live(), before + 1, "the enrollment is live while parked");

        drop(fut);
        assert_eq!(live(), before, "enrollment disposed on future drop");
        // The parked mint entry went with it (the RAII PendingGuard).
        assert!(wait_until(Duration::from_secs(2), || {
            super::super::bridge_rt::live_counters().pending_mints == 0
        }));
    }

    #[test]
    fn a_malformed_bundle_is_a_typed_error_and_still_disposes() {
        let _g = test_guard();
        let before = live();
        let err = run_preview(5_000, |req| {
            submit_mint_result(
                req.request_id,
                BridgeMintOutcome::Success {
                    raw_stdout: r#"{"scope":"control","token":"t","https_port":8443,"expires_at":"2030-01-01T00:00:00Z"}"#
                        .into(),
                },
            );
        })
        .unwrap_err();
        // The add-server parse REQUIRES the pin — this is the whole reason the
        // preview uses parse_control_bundle and not parse_credential_bundle.
        assert_eq!(err, BridgeError::TokenPinMissing);
        assert_eq!(live(), before, "enrollment disposed on a parse failure");
    }

    /// Each preview enrolls with its OWN keypair: two previews of the same host
    /// must never reuse a key (the certificate lifetime is the key lifetime).
    #[test]
    fn every_preview_generates_a_distinct_csr() {
        let _g = test_guard();
        let seen = std::sync::Arc::new(std::sync::Mutex::new(Vec::<String>::new()));
        for _ in 0..2 {
            let sink = seen.clone();
            let _ = run_preview(60, move |req| {
                sink.lock().unwrap().push(req.extra_args[0].clone());
            });
        }
        let seen = seen.lock().unwrap();
        assert_eq!(seen.len(), 2);
        assert_ne!(seen[0], seen[1], "two previews reused one keypair");
    }
}
