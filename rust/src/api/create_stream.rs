//! `Client::create_shed` streaming → Dart `Stream` (plan §3.4) — production shape,
//! mirroring the watcher's unified lifecycle.
//!
//! **Two-call shape (B1 finding 1):** [`create_shed_stream`] stashes the client +
//! request and returns the opaque [`BridgeCreateHandle`]; [`create_shed_events`]
//! streams `BridgeCreateUpdate`.
//!
//! **Unified locked lifecycle (Codex review #7):** the client, request, task
//! abort-handle, and counter live in one `Mutex<CreateInner>` behind an `Arc`.
//! [`teardown`] is the single decrement point, guarded by a `stopped` flag, and
//! CLEARS the stashed client+request so a cancelled handle can never start work.
//! The SYNCHRONOUS co-primary [`cancel_create`] (Riverpod `onDispose` — Codex #9)
//! aborts the in-flight create immediately; `Drop` is the backstop; the create
//! task self-tears-down on completion so the counter is honest even if Dart never
//! cancels.
//!
//! **401 behavior — ACCEPTED CHANGE, NOT parity (Codex review #8):** shed-core's
//! `create_stream` is deliberately ONE-SHOT on a stream-open 401 — it invalidates
//! the token it sent (so the NEXT create re-mints) and returns `BadStatus(401)`
//! immediately (`http.rs` create_stream, Phase A). The pre-bridge Dart create
//! retried a stream-open 401 once transparently. B2 does NOT restore that retry:
//! a stale-token create surfaces `BridgeError::BadStatus{401}` (an `Error` update)
//! and the USER retries (the re-mint already happened). This is recorded as an
//! accepted behavior change; restoring retry-once belongs in shed-core
//! `create_stream`, not the bridge (candidate shed follow-up).

use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex};

use flutter_rust_bridge::frb;
use shed_core::http::{Client, CreateSink};
use shed_core::models::{CreateShedRequest, Shed};

use crate::frb_generated::StreamSink;

use super::bridge_rt::{bridge_rt, ACTIVE_CREATE_STREAMS};
use super::client::BridgeClient;
use super::dto::BridgeShed;

/// The create request Dart passes (mirrors `models::CreateShedRequest`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeCreateShedRequest {
    pub name: String,
    pub repo: Option<String>,
    pub local_dir: Option<String>,
    pub image: Option<String>,
    pub backend: Option<String>,
    pub cpus: Option<i64>,
    pub memory_mb: Option<i64>,
    pub no_provision: Option<bool>,
}

impl From<BridgeCreateShedRequest> for CreateShedRequest {
    fn from(r: BridgeCreateShedRequest) -> Self {
        CreateShedRequest {
            name: r.name,
            repo: r.repo,
            local_dir: r.local_dir,
            image: r.image,
            backend: r.backend,
            cpus: r.cpus,
            memory_mb: r.memory_mb,
            no_provision: r.no_provision,
        }
    }
}

/// One create-stream update marshalled to Dart — a FRB 2.13 sealed class.
pub enum BridgeCreateUpdate {
    Progress { message: String },
    Complete { shed: BridgeShed },
    Error { message: String },
}

/// A `CreateSink` that forwards to a Dart `StreamSink`. A closed sink is a benign
/// no-op (the create task is aborted separately on cancel/Drop).
struct ForwardingCreateSink {
    sink: StreamSink<BridgeCreateUpdate>,
}
impl CreateSink for ForwardingCreateSink {
    fn on_progress(&self, message: String) {
        let _ = self.sink.add(BridgeCreateUpdate::Progress { message });
    }
    fn on_complete(&self, shed: Shed) {
        let _ = self.sink.add(BridgeCreateUpdate::Complete { shed: shed.into() });
    }
    fn on_error(&self, message: String) {
        let _ = self.sink.add(BridgeCreateUpdate::Error { message });
    }
}

/// The unified, mutex-protected create lifecycle (Codex review #7).
struct CreateInner {
    client: Option<Client>,
    req: Option<CreateShedRequest>,
    task: Option<tokio::task::AbortHandle>,
    started: bool,
    stopped: bool,
}

/// Bridge-owned opaque handle. Dart holds it to cancel the in-flight create in
/// `onDispose` via the sync [`cancel_create`]; `Drop` is the backstop.
pub struct BridgeCreateHandle {
    state: Arc<Mutex<CreateInner>>,
}

impl Drop for BridgeCreateHandle {
    fn drop(&mut self) {
        teardown(&self.state);
    }
}

/// The SINGLE teardown/decrement point, idempotent via `stopped`. Clears the
/// stashed client+request (so a post-cancel start is impossible), aborts the
/// in-flight create, and decrements the counter exactly once.
fn teardown(state: &Arc<Mutex<CreateInner>>) {
    let mut s = state.lock().unwrap();
    if s.stopped {
        return;
    }
    s.stopped = true;
    s.client = None;
    s.req = None;
    if let Some(t) = s.task.take() {
        t.abort();
    }
    ACTIVE_CREATE_STREAMS.fetch_sub(1, Ordering::SeqCst);
}

/// Step 1: stash the client + request, returning the bridge-owned opaque handle.
/// The create isn't started until [`create_shed_events`] supplies the sink.
pub async fn create_shed_stream(
    client: &BridgeClient,
    req: BridgeCreateShedRequest,
) -> BridgeCreateHandle {
    ACTIVE_CREATE_STREAMS.fetch_add(1, Ordering::SeqCst);
    BridgeCreateHandle {
        state: Arc::new(Mutex::new(CreateInner {
            client: Some(client.inner().clone()),
            req: Some(req.into()),
            task: None,
            started: false,
            stopped: false,
        })),
    }
}

/// Step 2: run `create_shed` against the handle's client, forwarding progress →
/// a Dart `Stream`. Refuses to start if cancelled or already started (Codex #7).
pub fn create_shed_events(handle: &BridgeCreateHandle, sink: StreamSink<BridgeCreateUpdate>) {
    // Claim the stashed client+request under the lock.
    let (client, req) = {
        let mut s = handle.state.lock().unwrap();
        if s.stopped || s.started {
            return;
        }
        let (Some(client), Some(req)) = (s.client.take(), s.req.take()) else {
            return;
        };
        s.started = true;
        (client, req)
    };
    let state = handle.state.clone();
    let fwd = ForwardingCreateSink { sink };
    let task = bridge_rt().spawn(async move {
        client.create_shed(&req, &fwd).await;
        // Self-teardown on completion so the counter is honest even if Dart never
        // cancels (Codex #7).
        teardown(&state);
    });
    // Install the abort handle, RE-CHECKING stopped: if cancel won during the
    // spawn, abort the just-spawned task (Codex #7).
    let mut s = handle.state.lock().unwrap();
    if s.stopped {
        task.abort();
    } else {
        s.task = Some(task.abort_handle());
    }
}

/// Explicit SYNCHRONOUS cancel (idempotent, co-primary with Drop). Dart calls
/// this from `onDispose` (Codex #9).
#[frb(sync)]
pub fn cancel_create(handle: &BridgeCreateHandle) {
    teardown(&handle.state);
}
