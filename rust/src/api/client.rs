//! `BridgeClient` — the bridge-owned opaque wrapper over `shed_core::http::Client`
//! (plan §3.6). Dart never touches `shed_core::Client`; it holds this opaque and
//! calls the async methods below, each returning `Result<T, BridgeError>` with
//! locally-defined DTOs.
//!
//! Construction ([`BridgeClient::connect`]) wires the mobile control-token path:
//! a [`BridgeMinter`] (the SSH-mint inversion) behind a `ControlTokenProvider`
//! built with the MOBILE knobs — `with_refresh_window(2h5m)`,
//! `with_name_jitter(5m)`, `with_mint_cooldown(60s)`, and an optional seed —
//! then `Client::with_provider` (NEVER `Client::new`, which installs desktop
//! defaults). A `Client`+provider pair is immutable per transport identity; the
//! app builds a NEW `BridgeClient` when host/port/pin change.
//!
//! Every method runs on the persistent [`bridge_rt`] runtime, NOT FRB's per-call
//! executor: the token-refresh FSM inside a request uses `tokio::time`, and
//! FRB's executor has no time driver (B1 finding 2). We `spawn` the shed-core
//! call onto `bridge_rt` and await the join handle (a plain channel await, safe
//! on FRB's executor).
//!
//! # Auth mode: learned, never configured (plan 002 §7 P1, plan 001 D5)
//!
//! [`BridgeClient::connect`] ACCEPTS the mode the app last stored for a server,
//! but only as a starting hint — it decides nothing. The SERVER picks the
//! credential shape at every mint, so an operator flipping `auth.mode` needs no
//! client reconfiguration: the next mint moves the provider to the other state
//! and the transport is NEVER rebuilt (the client-certificate resolver is
//! installed unconditionally and written through on each adoption).
//!
//! What the stored mode is actually used for is the SEED: a bearer token
//! persisted for a server that now issues certificates is meaningless, so it is
//! not planted in the provider's cache.
//!
//! The learned mode reaches Dart through [`set_credential_event_sink`], whose
//! events are what mobile persists into `ServerRecord.authMode` — mobile is the
//! one client that DOES persist it (the desktop keeps it in memory; §7 P1).

use std::sync::Arc;
use std::time::Duration;

use flutter_rust_bridge::frb;

use shed_core::http::Client;
use shed_core::token::{
    AuthMode, ControlTokenProvider, CredentialAdopted, CredentialObserver, MintedToken, TokenMinter,
};

use crate::frb_generated::StreamSink;

use super::bridge_rt::bridge_rt;
use super::dto::{
    BridgeOverview, BridgeSession, BridgeShed, BridgeShedImage, BridgeSystemDiskUsage,
};
use super::dto_rc::BridgeRcMessagesPage;
use super::error::BridgeError;
use super::mint::BridgeMinter;
use crate::sink_registry::SinkRegistry;

// The mobile control-token knobs (plan §3.2), distinct from shed-core's
// desktop defaults. `with_provider` demands we pass them explicitly.
const REFRESH_WINDOW: Duration = Duration::from_secs(2 * 60 * 60 + 5 * 60); // 2h5m
const NAME_JITTER: Duration = Duration::from_secs(5 * 60); // 5m
const MINT_COOLDOWN: Duration = Duration::from_secs(60); // 60s

/// A bridge-owned handle to one shed-server host. Opaque to Dart (FRB never
/// marshals the inner `shed_core::Client` — it holds a live reqwest client).
#[frb(opaque)]
pub struct BridgeClient {
    inner: Client,
}

impl BridgeClient {
    /// Build a secure, provider-backed client for one host (the production
    /// path). `tls_pin` (`sha256:<hex>`) enables leaf pinning on the https
    /// `base_url`; `host`/`ssh_port` are the SSH transport identity the mint
    /// inversion dials; `seed_token`/`seed_expiry_unix`, when present, prime the
    /// provider so the first request skips a mint. Fails with
    /// [`BridgeError::Config`] on a pin/URL mismatch (fail-closed).
    ///
    /// `auth_mode` is the shape the app last stored for this server
    /// (`ServerRecord.authMode`) — `"token"`, `"mtls"`, or absent. It is a HINT,
    /// not a switch: an unrecognized value (including the legacy `"secure"`
    /// spelling) reads as token, and whatever the server issues at the next mint
    /// wins regardless. Its one effect is that a stored seed token is ignored for
    /// a server the app believes is in mtls mode, where a bearer cannot
    /// authenticate anything.
    #[allow(clippy::too_many_arguments)]
    pub fn connect(
        base_url: String,
        server_name: String,
        host: String,
        ssh_port: u16,
        tls_pin: Option<String>,
        auth_mode: Option<String>,
        seed_token: Option<String>,
        seed_expiry_unix: Option<u64>,
    ) -> Result<BridgeClient, BridgeError> {
        let minter = Arc::new(BridgeMinter {
            host,
            ssh_port,
            base_url: base_url.clone(),
            expected_tls_pin: tls_pin.clone(),
        });
        let provider = build_provider(
            server_name.clone(),
            minter,
            AuthMode::from_wire(auth_mode.as_deref()),
            seed_token,
            seed_expiry_unix,
        );
        let inner = Client::with_provider(base_url, server_name, tls_pin, provider)?;
        Ok(BridgeClient { inner })
    }

    /// Build an OPEN-mode client (no minter, empty token) against `base_url`.
    /// Used by the hermetic slice tests (a local plaintext SSE server that
    /// ignores auth) and any future open-mode server; the production app uses
    /// [`BridgeClient::connect`].
    pub fn connect_open(
        base_url: String,
        server_name: String,
    ) -> Result<BridgeClient, BridgeError> {
        let inner = Client::new(base_url, server_name, String::new(), None, None)?;
        Ok(BridgeClient { inner })
    }

    /// Borrow the inner shed-core client (for the watcher/create-stream helpers
    /// in sibling modules — they need a `Client` to spawn their long-lived sinks).
    pub(crate) fn inner(&self) -> &Client {
        &self.inner
    }

    pub async fn overview(&self) -> Result<BridgeOverview, BridgeError> {
        let client = self.inner.clone();
        run(async move { client.overview().await })
            .await
            .map(Into::into)
            .map_err(Into::into)
    }

    pub async fn list_sheds(&self) -> Result<Vec<BridgeShed>, BridgeError> {
        let client = self.inner.clone();
        run(async move { client.list_sheds().await })
            .await
            .map(|v| v.into_iter().map(Into::into).collect())
            .map_err(Into::into)
    }

    pub async fn list_images(&self) -> Result<Vec<BridgeShedImage>, BridgeError> {
        let client = self.inner.clone();
        run(async move { client.list_images().await })
            .await
            .map(|v| v.into_iter().map(Into::into).collect())
            .map_err(Into::into)
    }

    pub async fn system_df(&self) -> Result<BridgeSystemDiskUsage, BridgeError> {
        let client = self.inner.clone();
        run(async move { client.system_df().await })
            .await
            .map(Into::into)
            .map_err(Into::into)
    }

    pub async fn list_sessions(&self, shed: String) -> Result<Vec<BridgeSession>, BridgeError> {
        let client = self.inner.clone();
        run(async move { client.list_sessions(&shed).await })
            .await
            .map(|r| r.sessions.into_iter().map(Into::into).collect())
            .map_err(Into::into)
    }

    pub async fn delete_session(&self, shed: String, session: String) -> Result<(), BridgeError> {
        let client = self.inner.clone();
        run(async move { client.delete_session(&shed, &session).await })
            .await
            .map_err(Into::into)
    }

    pub async fn rc_messages(
        &self,
        shed: String,
        slug: String,
        since: u64,
        limit: Option<u32>,
    ) -> Result<BridgeRcMessagesPage, BridgeError> {
        let client = self.inner.clone();
        run(async move { client.rc_messages(&shed, &slug, since, limit).await })
            .await
            .map(Into::into)
            .map_err(Into::into)
    }

    pub async fn rc_input(
        &self,
        shed: String,
        slug: String,
        text: String,
    ) -> Result<(), BridgeError> {
        let client = self.inner.clone();
        run(async move { client.rc_input(&shed, &slug, &text).await })
            .await
            .map_err(Into::into)
    }

    pub async fn start(&self, name: String) -> Result<(), BridgeError> {
        let client = self.inner.clone();
        run(async move { client.start(&name).await })
            .await
            .map_err(Into::into)
    }

    pub async fn stop(&self, name: String) -> Result<(), BridgeError> {
        let client = self.inner.clone();
        run(async move { client.stop(&name).await })
            .await
            .map_err(Into::into)
    }

    pub async fn reset(&self, name: String) -> Result<(), BridgeError> {
        let client = self.inner.clone();
        run(async move { client.reset(&name).await })
            .await
            .map_err(Into::into)
    }

    pub async fn delete(&self, name: String) -> Result<(), BridgeError> {
        let client = self.inner.clone();
        run(async move { client.delete(&name).await })
            .await
            .map_err(Into::into)
    }
}

/// Build the mobile-knobbed [`ControlTokenProvider`] a `BridgeClient` runs on:
/// the mobile refresh/jitter/cooldown constants, the credential observer that
/// feeds Dart's persistence, and — in token mode only — the persisted seed.
///
/// Extracted from [`BridgeClient::connect`] so the minter is injectable: the
/// mode-flip tests drive a provider assembled EXACTLY as production assembles it
/// (trap 4 — test what production assembles), which is the only way the
/// "one client survives a token↔mtls flip" claim means anything.
pub(crate) fn build_provider(
    server_name: String,
    minter: Arc<dyn TokenMinter>,
    stored_mode: AuthMode,
    seed_token: Option<String>,
    seed_expiry_unix: Option<u64>,
) -> Arc<ControlTokenProvider> {
    let mut provider = ControlTokenProvider::new(server_name, minter)
        .with_refresh_window(REFRESH_WINDOW)
        .with_name_jitter(NAME_JITTER)
        .with_mint_cooldown(MINT_COOLDOWN)
        .with_observer(Arc::new(BridgeCredentialObserver));
    // A seed is a BEARER token. Planting one for a server the app last saw in
    // mtls mode would cache a credential that cannot authenticate a single
    // request — the first mint would have to throw it away anyway, and until then
    // `surviving_credential` would offer it as a fallback. Skip it and let the
    // first request enroll.
    if let (AuthMode::Token, Some(token)) = (stored_mode, seed_token) {
        provider = provider.with_seed(MintedToken {
            token,
            expires_at_unix: seed_expiry_unix,
        });
    }
    Arc::new(provider)
}

// ---------------------------------------------------------------------------
// credential_adopted → Dart (plan 002 §7 P1)
// ---------------------------------------------------------------------------

/// What the provider adopted, on its way to Dart's `ServerRecord` — an
/// app-scoped stream shared by every [`BridgeClient`], routed by `server`
/// (the same one-sink shape as the mint inversion, plan D3).
///
/// # What it deliberately does NOT carry
///
/// No credential material of any kind — no certificate, no serial, and no bearer
/// token. mtls is obvious (the private key never leaves the provider, and a
/// certificate without it is useless), but the TOKEN omission is a decision worth
/// stating: `shed_core::CredentialAdopted` DOES carry the bearer in token mode,
/// for consumers whose store is the sanctioned home for it. Mobile's is not, at
/// mint time: today's app persists a token exactly once, at ADD time, from the
/// preview DTO (`AddServerFlow.commit` → `ServerRecord.controlToken`), and
/// nothing rewrites it afterwards. Forwarding a token on every rotation would
/// therefore ADD a crossing (and a secure-storage write per mint) that no
/// existing behavior needs — so §7 P1 pins mobile's event to "auth_mode +
/// expiry, and nothing else". The expiry is here because a UI wants to render
/// "renews at …", not because anything authenticates with it.
pub enum BridgeCredentialEvent {
    /// A mint succeeded and the provider adopted this shape. Fires on EVERY
    /// successful mint, including a plain rotation — Dart's write must be
    /// idempotent (it is: same `authMode`, same record).
    Adopted {
        server: String,
        /// `"token"` or `"mtls"`.
        auth_mode: String,
        expires_at_unix: Option<u64>,
    },
    /// The DERIVED transition (plan 001 D5's `mode_changed`): the adopted shape
    /// differs from the one last announced, in either direction. Always
    /// immediately follows the [`Self::Adopted`] that caused it, so a consumer
    /// handling both sees the adoption first. This is the event a UI reacts to;
    /// persistence can hang off `Adopted` alone.
    ModeChanged { server: String, auth_mode: String },
}

/// Bridges `shed_core`'s observer callbacks onto the app-scoped Dart stream.
///
/// One instance per provider; the callbacks arrive on the provider's own
/// dispatcher thread with no lock held, so emitting here can never block a mint
/// (`CredentialObserver`'s delivery contract). An event emitted with no sink
/// registered is DROPPED, not queued: a missed event costs exactly one re-learn
/// on the next launch, and nothing in the credential path depends on the write
/// having happened.
struct BridgeCredentialObserver;

impl CredentialObserver for BridgeCredentialObserver {
    fn on_credential_adopted(&self, event: &CredentialAdopted) {
        // `event.token` is deliberately not read — see BridgeCredentialEvent.
        emit_credential_event(BridgeCredentialEvent::Adopted {
            server: event.server.clone(),
            auth_mode: event.mode.as_str().to_string(),
            expires_at_unix: event.expires_at_unix,
        });
    }

    fn on_mode_changed(&self, server: &str, mode: AuthMode) {
        emit_credential_event(BridgeCredentialEvent::ModeChanged {
            server: server.to_string(),
            auth_mode: mode.as_str().to_string(),
        });
    }
}

/// The app-scoped credential-event registration — the same single-slot
/// {sink, shutdown, generation} structure the mint sink uses, for the same
/// reason (see [`SinkRegistry`]).
pub(crate) static CRED_SINK: SinkRegistry<BridgeCredentialEvent> = SinkRegistry::new();

/// Register the app-scoped credential-event stream and stay alive until
/// [`shutdown_credential_event_sink`] fires.
///
/// Same generation-guarded shape as the mint sink (`mint::set_mint_sink`): a new
/// registration supersedes the previous one atomically, and a task whose await
/// returns clears the slot only if it still owns it, so a sink installed while
/// an older task was parked is never clobbered. Unlike the mint sink there is
/// nothing to drain — these events are fire-and-forget notifications, not parked
/// requests, so a lost one costs exactly one re-learn.
///
/// Register it at startup alongside the mint sink; a client built before it
/// exists simply drops the events it would have delivered.
pub async fn set_credential_event_sink(sink: StreamSink<BridgeCredentialEvent>) {
    let (generation, srx) = CRED_SINK.install(Arc::new(sink), || {});
    let _ = srx.await;
    CRED_SINK.release(generation);
}

/// End the credential-event stream cleanly (Dart calls this in `onDispose`
/// before unsubscribing). Idempotent, and synchronous so Riverpod's `onDispose`
/// can call it without an unawaitable future.
#[frb(sync)]
pub fn shutdown_credential_event_sink() {
    CRED_SINK.shutdown(|| {});
}

/// Deliver one event, or drop it. There is deliberately no queue and no error
/// path: this runs on the provider's dispatcher thread, and a consumer that
/// missed an adoption re-learns the mode on its next launch.
fn emit_credential_event(event: BridgeCredentialEvent) {
    let _ = CRED_SINK.emit(event);
}

/// Run a shed-core call on `bridge_rt` (which has a tokio time driver) and await
/// its join handle from FRB's executor.
///
/// **Abort-on-drop (Codex review #10):** dropping a `JoinHandle` DETACHES the
/// task (it keeps running), so if the outer FRB future is dropped mid-await
/// (Dart cancelled the call), the shed-core request — and any mint it parked —
/// would live on until its own timeout, and repeated cancels could fill the mint
/// cap. The guard holds the task's `AbortHandle` and aborts on drop; we disarm it
/// only after a successful join. Aborting the request future runs its locals'
/// destructors (including the mint `PendingGuard`), freeing the pending slot.
///
/// A join failure (task panic/abort) maps to a transport error rather than
/// propagating a panic across the FFI boundary.
async fn run<T, F>(fut: F) -> Result<T, shed_core::http::ShedError>
where
    F: std::future::Future<Output = Result<T, shed_core::http::ShedError>> + Send + 'static,
    T: Send + 'static,
{
    struct AbortOnDrop(Option<tokio::task::AbortHandle>);
    impl Drop for AbortOnDrop {
        fn drop(&mut self) {
            if let Some(a) = self.0.take() {
                a.abort();
            }
        }
    }

    let handle = bridge_rt().spawn(fut);
    let mut guard = AbortOnDrop(Some(handle.abort_handle()));
    let joined = handle.await;
    guard.0 = None; // successful join — disarm the abort
    match joined {
        Ok(res) => res,
        Err(e) => Err(shed_core::http::ShedError::Transport(format!(
            "bridge task join error: {e}"
        ))),
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Mutex as StdMutex;

    use shed_core::http::ShedError;
    use shed_core::token::{
        CredentialRequest, MintedCertificate, MintedCredential, TokenBundleError,
    };

    use super::super::testsupport::{
        credential_events_for, test_guard, unique, wait_until, TestCa,
    };
    use super::*;

    /// A minter that answers with a scripted sequence of credential shapes,
    /// signing a REAL certificate for whatever CSR the provider hands it (the
    /// provider verifies the pairing, so a canned fixture cannot work).
    struct ScriptedMinter {
        script: StdMutex<Vec<AuthMode>>,
        ca: TestCa,
        /// Every CSR this minter was handed, in order.
        seen_csrs: StdMutex<Vec<Option<String>>>,
    }

    impl ScriptedMinter {
        fn new(script: Vec<AuthMode>) -> Arc<Self> {
            Arc::new(Self {
                script: StdMutex::new(script.into_iter().rev().collect()),
                ca: TestCa::new(),
                seen_csrs: StdMutex::new(Vec::new()),
            })
        }
    }

    #[async_trait::async_trait]
    impl TokenMinter for ScriptedMinter {
        fn supports_mtls(&self) -> bool {
            true
        }

        async fn mint_credential(
            &self,
            _server: &str,
            req: &CredentialRequest,
        ) -> Result<MintedCredential, ShedError> {
            self.seen_csrs
                .lock()
                .unwrap()
                .push(req.csr_base64().map(str::to_string));
            let next = self
                .script
                .lock()
                .unwrap()
                .pop()
                .ok_or_else(|| ShedError::Transport("script exhausted".into()))?;
            Ok(match next {
                AuthMode::Token => MintedCredential::Token(MintedToken {
                    token: format!("tok-{}", uuid_ish()),
                    expires_at_unix: Some(4_102_444_800),
                }),
                AuthMode::Mtls => {
                    let csr = req
                        .csr_base64()
                        .ok_or_else(|| ShedError::Transport("no csr offered".into()))?;
                    MintedCredential::Certificate(MintedCertificate {
                        cert_pem: self.ca.sign_csr_base64(csr),
                        serial: "2a".into(),
                        expires_at_unix: Some(4_102_444_800),
                    })
                }
            })
        }

        async fn mint(&self, server: &str) -> Result<MintedToken, ShedError> {
            match self
                .mint_credential(server, &CredentialRequest::default())
                .await?
            {
                MintedCredential::Token(t) => Ok(t),
                MintedCredential::Certificate(_) => {
                    Err(ShedError::Transport("unexpected certificate".into()))
                }
            }
        }
    }

    fn uuid_ish() -> u64 {
        use std::time::{SystemTime, UNIX_EPOCH};
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .subsec_nanos() as u64
    }

    /// Plan 001 D5 / 002 §7 P2, at the bridge's own wiring: ONE `Client`, built
    /// once, carries a server through token → mtls → token with no rebuild.
    ///
    /// The proof is structural rather than incidental: the client is constructed
    /// from `build_provider` (the exact assembly `BridgeClient::connect` uses) and
    /// is never touched again, while the credential shape flips underneath it.
    /// The seam that makes that possible — the certificate resolver the transport
    /// holds — keeps the SAME identity across every flip and is simply written
    /// through, which is what "the transport is never rebuilt" means concretely.
    #[test]
    fn one_client_carries_a_server_across_token_mtls_flips() {
        let _g = test_guard();
        let server = unique("flip");
        let minter = ScriptedMinter::new(vec![AuthMode::Token, AuthMode::Mtls, AuthMode::Token]);
        let provider = build_provider(server.clone(), minter.clone(), AuthMode::Token, None, None);
        // The resolver handed to the transport at build time, captured BEFORE the
        // client exists.
        let resolver = provider.cert_resolver();

        // Built ONCE, exactly as `connect` builds it, and never rebuilt below.
        let client = Client::with_provider(
            "https://host.example:8443".into(),
            server.clone(),
            Some(crate::api::testsupport::pin("ab")),
            provider.clone(),
        )
        .expect("client");

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();

        // 1. token: nothing to present at the handshake, a bearer to send.
        let cred = rt.block_on(provider.credential()).unwrap();
        assert_eq!(cred.mode, Some(AuthMode::Token));
        assert!(cred.bearer_token().is_some());
        assert!(resolver.current().is_none());

        // 2. the operator flips the server to mtls; the next mint (after the
        //    server refuses what we hold) adopts a certificate.
        rt.block_on(provider.invalidate());
        let cred = rt.block_on(provider.credential()).unwrap();
        assert_eq!(cred.mode, Some(AuthMode::Mtls));
        assert!(
            cred.bearer_token().is_none(),
            "no bearer exists in mtls mode"
        );
        assert!(
            resolver.current().is_some(),
            "the certificate must be armed on the SAME resolver"
        );

        // 3. ...and back again.
        rt.block_on(provider.invalidate());
        let cred = rt.block_on(provider.credential()).unwrap();
        assert_eq!(cred.mode, Some(AuthMode::Token));
        assert!(resolver.current().is_none(), "the certificate is withdrawn");

        // The resolver the transport holds is the one that was written through,
        // all three times — no new client, no new resolver.
        assert!(Arc::ptr_eq(&resolver, &provider.cert_resolver()));
        drop(client);

        // Every mint offered a fresh CSR (a capable minter always gets one).
        let csrs = minter.seen_csrs.lock().unwrap();
        assert_eq!(csrs.len(), 3);
        assert!(csrs.iter().all(Option::is_some));
        assert_ne!(csrs[0], csrs[1]);
        assert_ne!(csrs[1], csrs[2]);
    }

    /// §7 P1: every adoption reaches Dart, a real transition also emits the
    /// derived `mode_changed` (adoption FIRST), and neither event carries
    /// credential material.
    #[test]
    fn credential_events_reach_dart_with_mode_and_expiry_only() {
        let _g = test_guard();
        let server = unique("events");
        let minter = ScriptedMinter::new(vec![AuthMode::Token, AuthMode::Token, AuthMode::Mtls]);
        let provider = build_provider(server.clone(), minter, AuthMode::Token, None, None);
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();

        rt.block_on(provider.credential()).unwrap(); // adopt token  (+ mode_changed)
        rt.block_on(provider.invalidate());
        rt.block_on(provider.credential()).unwrap(); // rotate token (no mode_changed)
        rt.block_on(provider.invalidate());
        rt.block_on(provider.credential()).unwrap(); // adopt mtls   (+ mode_changed)

        // Delivery is asynchronous by contract (a dispatcher thread), so wait.
        assert!(
            wait_until(Duration::from_secs(5), || {
                credential_events_for(&server).len() == 5
            }),
            "events: {:?}",
            credential_events_for(&server)
        );
        let events = credential_events_for(&server);
        let shape: Vec<(&str, &str)> = events
            .iter()
            .map(|e| (e.kind, e.auth_mode.as_str()))
            .collect();
        assert_eq!(
            shape,
            vec![
                ("adopted", "token"),
                ("mode_changed", "token"),
                // A rotation is an adoption, NOT a transition.
                ("adopted", "token"),
                ("adopted", "mtls"),
                ("mode_changed", "mtls"),
            ]
        );
        // The expiry rides along (a UI renders it); nothing else does.
        assert_eq!(events[0].expires_at_unix, Some(4_102_444_800));
        for e in &events {
            let rendered = format!("{e:?}");
            assert!(!rendered.contains("tok-"), "a token crossed: {rendered}");
            assert!(
                !rendered.contains("BEGIN"),
                "a certificate crossed: {rendered}"
            );
        }
    }

    /// The stored-mode hint governs the SEED only: a bearer persisted for a
    /// server that now issues certificates is not planted in the cache.
    #[test]
    fn a_stored_mtls_mode_ignores_a_stale_seed_token() {
        let _g = test_guard();
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();

        // token mode: the seed is used, and the first request mints nothing.
        let minter = ScriptedMinter::new(vec![]); // any mint would fail the script
        let provider = build_provider(
            unique("seeded"),
            minter,
            AuthMode::Token,
            Some("seed-tok".into()),
            Some(4_102_444_800),
        );
        assert_eq!(
            rt.block_on(provider.credential()).unwrap().token,
            "seed-tok"
        );

        // mtls mode: the same stored token is ignored, so the provider must mint.
        let minter = ScriptedMinter::new(vec![AuthMode::Mtls]);
        let provider = build_provider(
            unique("seeded"),
            minter,
            AuthMode::Mtls,
            Some("seed-tok".into()),
            Some(4_102_444_800),
        );
        let cred = rt.block_on(provider.credential()).unwrap();
        assert_eq!(cred.mode, Some(AuthMode::Mtls));
        assert!(cred.token.is_empty());
    }

    /// The wire spellings `connect` accepts for a stored mode. Unknown values
    /// (including the legacy `"secure"`) read as token — never as mtls, whose
    /// branch expects a certificate.
    #[test]
    fn stored_auth_mode_decoding_is_tolerant() {
        assert_eq!(AuthMode::from_wire(None), AuthMode::Token);
        assert_eq!(AuthMode::from_wire(Some("")), AuthMode::Token);
        assert_eq!(AuthMode::from_wire(Some("secure")), AuthMode::Token);
        assert_eq!(AuthMode::from_wire(Some("token")), AuthMode::Token);
        assert_eq!(AuthMode::from_wire(Some("future")), AuthMode::Token);
        assert_eq!(AuthMode::from_wire(Some("mtls")), AuthMode::Mtls);
    }

    /// The source audit §7 P3(b) asks for: PRODUCTION control-scope code makes no
    /// persistence call for a private key.
    ///
    /// Only two things in this crate ever hold one — the provider's per-mint
    /// keypair (shed-core, in memory) and the add-server preview's ephemeral
    /// enrollment (dropped with its future) — and neither writes it anywhere.
    /// What this pins is the absence of the third option: someone reaching for
    /// `ClientKeyPair::key_pem()` / `key_pkcs8_der()`, the serializers that exist
    /// for the BROKER's state dir (which legitimately persists) and must never be
    /// called on this side of the fence. Every `.rs` file is scanned up to its
    /// `#[cfg(test)]` line, so a test may still reference them to prove a
    /// negative — as `production_request_dto_carries_no_secret` does.
    #[test]
    fn no_bridge_code_persists_a_keypair() {
        let src = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
        let mut hits = Vec::new();
        let mut scanned = 0usize;
        scan(&src, &mut hits, &mut scanned);
        assert!(scanned > 5, "the audit scanned almost nothing ({scanned})");
        assert!(
            hits.is_empty(),
            "private-key serialization reached production code: {hits:?}"
        );

        fn scan(dir: &std::path::Path, hits: &mut Vec<String>, scanned: &mut usize) {
            for entry in std::fs::read_dir(dir).unwrap() {
                let path = entry.unwrap().path();
                if path.is_dir() {
                    scan(&path, hits, scanned);
                    continue;
                }
                if path.extension().is_none_or(|e| e != "rs") {
                    continue;
                }
                *scanned += 1;
                let text = std::fs::read_to_string(&path).unwrap();
                for (i, line) in text.lines().enumerate() {
                    let code = line.trim_start();
                    // Production only: everything from the test module down is
                    // audit code, not shipped code.
                    if code.starts_with("#[cfg(test)]") {
                        break;
                    }
                    if code.starts_with("//") {
                        continue;
                    }
                    if code.contains("key_pem()") || code.contains("key_pkcs8_der()") {
                        hits.push(format!("{}:{}", path.display(), i + 1));
                    }
                }
            }
        }
    }

    /// A parse failure on the mint path still maps to the typed app error.
    #[test]
    fn token_bundle_errors_map_to_bridge_errors() {
        assert_eq!(
            BridgeError::from(TokenBundleError::PinMismatch),
            BridgeError::TokenPinMismatch
        );
    }
}
