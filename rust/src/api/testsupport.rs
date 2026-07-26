//! Test-only support shared by the bridge slices' unit tests: `_bootstrap`
//! bundle fixtures, a throwaway CA that can actually sign a CSR the
//! `ControlTokenProvider` just generated, and the fake emitters that let a Rust
//! test drive the REAL emit→submit→parse round-trip.
//!
//! Compiled only under `cfg(test)` (`mod testsupport` is gated in `api/mod.rs`),
//! so none of this exists in a shipped build and none of it appears on the FRB
//! surface.
//!
//! # Fake emitters, not production seams
//!
//! `flutter_rust_bridge::StreamSink` can only be constructed by the generated
//! Dart-facing glue, so a `cargo test` process has no way to register one. The
//! answer is `sink_registry::Emitter`: production registers the `StreamSink`, tests
//! register a capturing fake INTO THE SAME `SinkRegistry`. Nothing in the
//! shipped code path branches on `cfg(test)` — the tests exercise the registry's
//! real locking, generations and shutdown ordering, which is exactly where the
//! races the review found lived.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, SystemTime};

use super::client::{BridgeCredentialEvent, CRED_SINK};
use super::mint::{BridgeMintRequest, MINT_SINK};
use crate::sink_registry::Emitter;

/// A registered fake that hands each emitted value to `f` (a mint request) or
/// records it (a credential event).
struct FnEmitter<T>(Box<dyn Fn(T) + Send + Sync>);

impl<T> Emitter<T> for FnEmitter<T> {
    fn emit(&self, value: T) -> Result<(), ()> {
        (self.0)(value);
        Ok(())
    }
}

/// A registered fake whose Dart stream is CLOSED — every emit fails.
pub(crate) struct ClosedEmitter;

impl<T> Emitter<T> for ClosedEmitter {
    fn emit(&self, _value: T) -> Result<(), ()> {
        Err(())
    }
}

/// Serializes every test that touches the process-global mint state (the sink
/// registries, the pending map, the leak counters), which would otherwise
/// interleave across `cargo test`'s threads.
static TEST_LOCK: Mutex<()> = Mutex::new(());

/// Hold the global test lock for the duration of a test, tearing down whatever
/// it registered on the way out — including when the test panics, so one failure
/// cannot corrupt the next test.
pub(crate) struct TestGuard(#[allow(dead_code)] MutexGuard<'static, ()>);

impl Drop for TestGuard {
    fn drop(&mut self) {
        reset_sinks();
    }
}

/// Acquire the global test lock, starting from a clean slate: no mint sink, and
/// a credential sink that captures into [`credential_events_for`].
///
/// Recovers from a poisoned mutex — a panicking test must fail on its own
/// assertion, not cascade into every later one.
pub(crate) fn test_guard() -> TestGuard {
    let g = TEST_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    reset_sinks();
    // Credential events are asserted by nearly every client test, and delivery is
    // asynchronous, so the capturing sink is always installed rather than opted
    // into per test.
    CRED_SINK.install(
        Arc::new(FnEmitter(Box::new(|e: BridgeCredentialEvent| {
            record_credential_event(&e)
        }))),
        || {},
    );
    TestGuard(g)
}

fn reset_sinks() {
    MINT_SINK.shutdown(|| {});
    CRED_SINK.shutdown(|| {});
}

/// Register a fake mint sink that answers exactly one request with `f`. Later
/// requests emit into the same fake and are ignored (`f` is consumed), which is
/// what the "parked forever" tests want.
pub(crate) fn install_sink_hook(f: impl FnOnce(BridgeMintRequest) + Send + 'static) {
    let once = Mutex::new(Some(f));
    install_mint_emitter(Arc::new(FnEmitter(Box::new(move |req| {
        if let Some(f) = once.lock().unwrap_or_else(|e| e.into_inner()).take() {
            f(req);
        }
    }))));
}

/// Register an arbitrary emitter as the app-scoped mint sink, through the SAME
/// install point production uses (`mint::install_mint_sink`), so tests inherit
/// its eviction/drain semantics. The returned generation is what
/// `SinkRegistry::release` takes; the shutdown receiver is dropped (no parked
/// FRB stream function exists in a unit test).
pub(crate) fn install_mint_emitter(e: Arc<dyn Emitter<BridgeMintRequest>>) -> u64 {
    super::mint::install_mint_sink(e).0
}

/// One credential event, flattened to plain data a test can assert on (and
/// scan): exactly the fields that crossed, nothing reconstructed.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct CapturedEvent {
    pub kind: &'static str,
    pub server: String,
    pub auth_mode: String,
    pub expires_at_unix: Option<u64>,
}

static CRED_EVENTS: Mutex<Vec<CapturedEvent>> = Mutex::new(Vec::new());

fn record_credential_event(event: &BridgeCredentialEvent) {
    let captured = match event {
        BridgeCredentialEvent::Adopted {
            server,
            auth_mode,
            expires_at_unix,
        } => CapturedEvent {
            kind: "adopted",
            server: server.clone(),
            auth_mode: auth_mode.clone(),
            expires_at_unix: *expires_at_unix,
        },
        BridgeCredentialEvent::ModeChanged { server, auth_mode } => CapturedEvent {
            kind: "mode_changed",
            server: server.clone(),
            auth_mode: auth_mode.clone(),
            expires_at_unix: None,
        },
    };
    CRED_EVENTS
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .push(captured);
}

/// Every credential event captured for `server`, in emission order.
pub(crate) fn credential_events_for(server: &str) -> Vec<CapturedEvent> {
    CRED_EVENTS
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .iter()
        .filter(|e| e.server == server)
        .cloned()
        .collect()
}

/// A canonical `sha256:<64 hex>` pin built from one repeated byte.
pub(crate) fn pin(byte: &str) -> String {
    format!("sha256:{}", byte.repeat(32))
}

/// A token-mode `_bootstrap control` bundle. `auth_mode` is passed through
/// verbatim (`None` omits the key entirely — the pre-mtls server shape).
pub(crate) fn token_bundle(pin: &str, auth_mode: Option<&str>) -> String {
    let mode = auth_mode
        .map(|m| format!(r#""auth_mode":"{m}","#))
        .unwrap_or_default();
    format!(
        r#"{{{mode}"scope":"control","token":"secret-tok","tls_cert_fingerprint":"{pin}","https_port":8443,"expires_at":"2030-01-01T00:00:00Z"}}"#
    )
}

/// An mtls `_bootstrap control` bundle carrying `cert_pem`.
pub(crate) fn mtls_bundle(pin: &str, cert_pem: &str) -> String {
    let cert = cert_pem.replace('\n', "\\n");
    format!(
        r#"{{"auth_mode":"mtls","scope":"control","client_cert":"{cert}","cert_serial":"2a","tls_cert_fingerprint":"{pin}","https_port":8443,"expires_at":"2030-01-01T00:00:00Z"}}"#
    )
}

/// A throwaway CA that signs a CSR the way shed-server's internal CA does.
///
/// Needed because `ControlTokenProvider::adopt` VERIFIES that the certificate it
/// adopts belongs to the key it generated for that mint — so a mode-flip test
/// cannot use a canned certificate fixture, it has to sign the live CSR. Ported
/// from `shed-core`'s own `testtls::TestCa::sign_csr` (that module is
/// `cfg(test)`-private to shed-core, so it cannot be imported).
pub(crate) struct TestCa {
    key: rcgen::KeyPair,
    cert: rcgen::Certificate,
}

impl TestCa {
    pub(crate) fn new() -> Self {
        let key = rcgen::KeyPair::generate().unwrap();
        let mut params = rcgen::CertificateParams::new(Vec::<String>::new()).unwrap();
        params.is_ca = rcgen::IsCa::Ca(rcgen::BasicConstraints::Unconstrained);
        params
            .distinguished_name
            .push(rcgen::DnType::CommonName, "shed-mobile test CA");
        let cert = params.self_signed(&key).unwrap();
        Self { key, cert }
    }

    /// Sign `csr_base64` (standard base64 DER, exactly what rides `csr=`) and
    /// return the leaf PEM.
    pub(crate) fn sign_csr_base64(&self, csr_base64: &str) -> String {
        use base64::engine::general_purpose::STANDARD as BASE64;
        use base64::Engine as _;
        let der = BASE64.decode(csr_base64.as_bytes()).expect("base64 CSR");
        self.sign_csr(&der)
    }

    fn sign_csr(&self, csr_der: &[u8]) -> String {
        let point = p256_public_point(csr_der).expect("P-256 SPKI in CSR");
        struct RawP256(Vec<u8>);
        impl rcgen::PublicKeyData for RawP256 {
            fn der_bytes(&self) -> &[u8] {
                &self.0
            }
            fn algorithm(&self) -> &'static rcgen::SignatureAlgorithm {
                &rcgen::PKCS_ECDSA_P256_SHA256
            }
        }
        let mut params = rcgen::CertificateParams::new(Vec::<String>::new()).unwrap();
        params
            .distinguished_name
            .push(rcgen::DnType::CommonName, "test-client");
        params.extended_key_usages = vec![rcgen::ExtendedKeyUsagePurpose::ClientAuth];
        params.serial_number = Some(rcgen::SerialNumber::from(42u64));
        params.not_before = (SystemTime::now() - Duration::from_secs(60)).into();
        params.not_after = (SystemTime::now() + Duration::from_secs(3600)).into();
        let leaf = params
            .signed_by(&RawP256(point), &self.cert, &self.key)
            .unwrap();
        pem_encode_certificate(leaf.der())
    }
}

/// The 65-byte uncompressed P-256 point inside a DER SubjectPublicKeyInfo:
/// `BIT STRING` of length 0x42 with 0 unused bits, whose content starts with the
/// uncompressed-point tag `0x04`.
fn p256_public_point(der: &[u8]) -> Option<Vec<u8>> {
    der.windows(4)
        .position(|w| w == [0x03, 0x42, 0x00, 0x04])
        .map(|i| der[i + 3..i + 3 + 65].to_vec())
}

fn pem_encode_certificate(der: &[u8]) -> String {
    use base64::engine::general_purpose::STANDARD as BASE64;
    use base64::Engine as _;
    let body = BASE64.encode(der);
    let mut out = String::from("-----BEGIN CERTIFICATE-----\n");
    for chunk in body.as_bytes().chunks(64) {
        out.push_str(std::str::from_utf8(chunk).unwrap());
        out.push('\n');
    }
    out.push_str("-----END CERTIFICATE-----\n");
    out
}

/// Spin until `cond` holds or `within` elapses, so a test can wait on work that
/// completes on another thread (the credential-event dispatcher, the mint timer)
/// without a fixed sleep. Returns whether it held.
pub(crate) fn wait_until(within: Duration, mut cond: impl FnMut() -> bool) -> bool {
    let deadline = std::time::Instant::now() + within;
    loop {
        if cond() {
            return true;
        }
        if std::time::Instant::now() >= deadline {
            return false;
        }
        std::thread::sleep(Duration::from_millis(5));
    }
}

/// A `Waker` that does nothing, for a test that polls a future by hand (to park
/// it, then drop it — the FRB-cancellation shape).
pub(crate) fn noop_waker() -> std::task::Waker {
    std::task::Waker::noop().clone()
}

/// Monotonic suffix so parallel-ish tests don't collide on server names.
pub(crate) fn unique(prefix: &str) -> String {
    static SEQ: AtomicU64 = AtomicU64::new(1);
    format!("{prefix}-{}", SEQ.fetch_add(1, Ordering::SeqCst))
}
