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

use std::sync::Arc;
use std::time::Duration;

use flutter_rust_bridge::frb;

use shed_core::http::Client;
use shed_core::token::{ControlTokenProvider, MintedToken};

use super::bridge_rt::bridge_rt;
use super::dto::{BridgeOverview, BridgeSession, BridgeShed, BridgeShedImage, BridgeSystemDiskUsage};
use super::dto_rc::BridgeRcMessagesPage;
use super::error::BridgeError;
use super::mint::BridgeMinter;

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
    #[allow(clippy::too_many_arguments)]
    pub fn connect(
        base_url: String,
        server_name: String,
        host: String,
        ssh_port: u16,
        tls_pin: Option<String>,
        seed_token: Option<String>,
        seed_expiry_unix: Option<u64>,
    ) -> Result<BridgeClient, BridgeError> {
        let minter = Arc::new(BridgeMinter {
            host,
            ssh_port,
            base_url: base_url.clone(),
            expected_tls_pin: tls_pin.clone(),
        });
        let mut provider = ControlTokenProvider::new(server_name.clone(), minter)
            .with_refresh_window(REFRESH_WINDOW)
            .with_name_jitter(NAME_JITTER)
            .with_mint_cooldown(MINT_COOLDOWN);
        if let Some(token) = seed_token {
            provider = provider.with_seed(MintedToken {
                token,
                expires_at_unix: seed_expiry_unix,
            });
        }
        let inner = Client::with_provider(base_url, server_name, tls_pin, Arc::new(provider))?;
        Ok(BridgeClient { inner })
    }

    /// Build an OPEN-mode client (no minter, empty token) against `base_url`.
    /// Used by the hermetic slice tests (a local plaintext SSE server that
    /// ignores auth) and any future open-mode server; the production app uses
    /// [`BridgeClient::connect`].
    pub fn connect_open(base_url: String, server_name: String) -> Result<BridgeClient, BridgeError> {
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
