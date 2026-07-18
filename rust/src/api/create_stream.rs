//! Slice (d) — `Client::create_shed` streaming → `StreamSink` with its own
//! handle/cancellation (plan §3.4), mirroring the watcher. A `CreateSink` impl
//! forwards progress/complete/error to a Dart `Stream`; the bridge-owned opaque
//! handle aborts the create task (and the local SSE server) on `cancel()`/Drop.
//! A leak counter asserts live create streams return to zero after dispose.
//!
//! Same two-step FRB shape as the watcher (§watcher.rs finding): `create_shed_stream()`
//! returns the opaque handle (Dart holds it for cancellation); `create_shed_events(handle)`
//! streams. One call can't both stream and return the handle.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

use crate::frb_generated::StreamSink;
use shed_core::http::{Client, CreateSink};
use shed_core::models::{CreateShedRequest, Shed};

use super::bridge_rt::{bridge_rt, ACTIVE_CREATE_STREAMS};
use super::local_sse::spawn_local_sse;

/// One create-stream update marshalled to Dart. `kind` is
/// `"progress"`/`"complete"`/`"error"`.
pub struct BridgeCreateUpdate {
    pub kind: String,
    pub message: String,
    pub name: String,
}

/// A `CreateSink` that forwards to a Dart `StreamSink`. A closed sink is a
/// benign no-op (the create task is aborted separately on cancel/Drop).
struct ForwardingCreateSink {
    sink: StreamSink<BridgeCreateUpdate>,
}
impl CreateSink for ForwardingCreateSink {
    fn on_progress(&self, message: String) {
        let _ = self.sink.add(BridgeCreateUpdate {
            kind: "progress".to_string(),
            message,
            name: String::new(),
        });
    }
    fn on_complete(&self, shed: Shed) {
        let _ = self.sink.add(BridgeCreateUpdate {
            kind: "complete".to_string(),
            message: String::new(),
            name: shed.name,
        });
    }
    fn on_error(&self, message: String) {
        let _ = self.sink.add(BridgeCreateUpdate {
            kind: "error".to_string(),
            message,
            name: String::new(),
        });
    }
}

/// Bridge-owned opaque handle over the create task + local SSE server. Dart holds
/// it to cancel the in-flight create in `onDispose`.
pub struct BridgeCreateHandle {
    base_url: String,
    task: Mutex<Option<tokio::task::AbortHandle>>,
    sse: tokio::task::AbortHandle,
    stopped: AtomicBool,
}
impl BridgeCreateHandle {
    /// Idempotent synchronous cancel (belt-and-suspenders alongside Drop):
    /// aborts the in-flight create + the SSE server and decrements the counter.
    pub fn cancel(&self) {
        if self.stopped.swap(true, Ordering::SeqCst) {
            return;
        }
        if let Some(t) = self.task.lock().unwrap().take() {
            t.abort();
        }
        self.sse.abort();
        ACTIVE_CREATE_STREAMS.fetch_sub(1, Ordering::SeqCst);
    }
}
impl Drop for BridgeCreateHandle {
    fn drop(&mut self) {
        self.cancel();
    }
}

const CREATE_SSE: &str = "event: progress\n\
data: {\"message\":\"building rootfs\"}\n\n\
event: progress\n\
data: {\"message\":\"booting vm\"}\n\n\
event: complete\n\
data: {\"name\":\"folio\",\"status\":\"running\"}\n\n";

/// Step 1: stand up the local SSE server, returning the bridge-owned opaque
/// handle (Dart holds it for cancellation). The create isn't started until
/// `create_shed_events` supplies the sink.
pub async fn create_shed_stream() -> Result<BridgeCreateHandle, String> {
    let (base_url, sse_task) = spawn_local_sse(CREATE_SSE).await;
    ACTIVE_CREATE_STREAMS.fetch_add(1, Ordering::SeqCst);
    Ok(BridgeCreateHandle {
        base_url,
        task: Mutex::new(None),
        sse: sse_task.abort_handle(),
        stopped: AtomicBool::new(false),
    })
}

/// Step 2: run `create_shed` against the handle's SSE server, forwarding progress
/// → a Dart `Stream`. FRB renders this (a `StreamSink` param) as
/// `Stream<BridgeCreateUpdate>`.
pub fn create_shed_events(
    handle: &BridgeCreateHandle,
    sink: StreamSink<BridgeCreateUpdate>,
) -> Result<(), String> {
    let client = Client::new(
        handle.base_url.clone(),
        "demo".to_string(),
        String::new(),
        None,
        None,
    )
    .map_err(|e| e.to_string())?;
    let req = CreateShedRequest {
        name: "folio".to_string(),
        repo: None,
        local_dir: None,
        image: None,
        backend: None,
        cpus: None,
        memory_mb: None,
        no_provision: None,
    };
    let fwd = ForwardingCreateSink { sink };
    let task = bridge_rt().spawn(async move {
        client.create_shed(&req, &fwd).await;
    });
    *handle.task.lock().unwrap() = Some(task.abort_handle());
    Ok(())
}

/// Explicit synchronous cancel (idempotent) — belt-and-suspenders alongside Drop.
pub fn cancel_create(handle: &BridgeCreateHandle) {
    handle.cancel();
}
