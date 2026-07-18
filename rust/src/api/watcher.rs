//! Slice (b) — `RcEventsWatcher` → `StreamSink` with Drop-primary teardown
//! (plan §3.3). Proves the long-lived-watcher pattern: a real
//! `shed_app::RcEventsWatcher` (default-features, no `rc` feature) drives an
//! mpsc that a forwarding task drains into a Dart `Stream`; the bridge-owned
//! opaque handle stops both the watcher (drop aborts its loop) and the
//! forwarder on `stop()`/Drop. `Resynced` is folded onto the next `Event` as a
//! `resync` flag (StreamSink coalescing safety, §3.3). A leak counter asserts
//! live watchers/forwarders return to zero after dispose.
//!
//! FRB SHAPE FINDING (important): a single bridge fn CANNOT both take a
//! `StreamSink<T>` (→ Dart `Stream<T>`) AND return an opaque handle — FRB
//! collapses it to `Stream<T>` and drops the return. So the plan's §3.3
//! "`watch(...) -> RustAutoOpaque<handle>`" is split into TWO calls: an opaque
//! `create_rc_watcher()` (Dart holds it for teardown) + `rc_watcher_events(handle)`
//! that streams. Teardown stays deterministic via the held handle.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

use crate::frb_generated::StreamSink;
use shed_app::rc_events_watcher::{RcEventsWatcher, RcWatcherUpdate};
use shed_core::http::Client;
use shed_core::rc_events::RcEvent;
use tokio::sync::mpsc::UnboundedReceiver;

use super::bridge_rt::{bridge_rt, ACTIVE_FORWARDERS, ACTIVE_WATCHERS};
use super::local_sse::spawn_local_sse;

/// One decoded watcher update marshalled to Dart. `kind` is `"event"` or
/// `"down"`. On an `"event"`, `resync` is set if a `Resynced` preceded it (the
/// consumer then invalidates its overview). Each event carries the full folded
/// snapshot in the real app; here we surface just shed/slug for the proof.
pub struct BridgeWatcherUpdate {
    pub kind: String,
    pub shed: String,
    pub slug: String,
    pub resync: bool,
    pub reason: String,
}

/// Bridge-owned opaque handle over the watcher + its (not-yet-drained) mpsc + the
/// forwarding task + the local SSE server task. `stop()` (and Drop) tears them
/// all down, idempotently. Dart holds this to drive teardown in `onDispose`.
pub struct BridgeWatcherHandle {
    // The watcher + its receiver, until `rc_watcher_events` drains it.
    inner: Mutex<Option<(RcEventsWatcher, UnboundedReceiver<RcWatcherUpdate>)>>,
    forwarder: Mutex<Option<tokio::task::AbortHandle>>,
    sse: tokio::task::AbortHandle,
    stopped: AtomicBool,
}

impl BridgeWatcherHandle {
    /// Idempotent synchronous teardown (belt-and-suspenders alongside Drop):
    /// aborts the forwarder + SSE server, drops the watcher (aborting its loop),
    /// and decrements the leak counters exactly once.
    pub fn stop(&self) {
        if self.stopped.swap(true, Ordering::SeqCst) {
            return;
        }
        if let Some(f) = self.forwarder.lock().unwrap().take() {
            f.abort();
            ACTIVE_FORWARDERS.fetch_sub(1, Ordering::SeqCst);
        }
        self.sse.abort();
        // Dropping the watcher (if still held here or moved into the forwarder)
        // aborts its reconnect/fold loop (module doc).
        drop(self.inner.lock().unwrap().take());
        ACTIVE_WATCHERS.fetch_sub(1, Ordering::SeqCst);
    }
}

impl Drop for BridgeWatcherHandle {
    fn drop(&mut self) {
        self.stop();
    }
}

fn slug_of(ev: &RcEvent) -> String {
    match ev {
        RcEvent::ActivityChanged { slug, .. }
        | RcEvent::SessionUpdated { slug, .. }
        | RcEvent::MessageAppended { slug, .. } => slug.clone(),
        _ => String::new(),
    }
}

/// SSE body served to the watcher: the server preamble + two rc events (same
/// shape as shed-core's `rc_events` happy-path test), then EOF.
const WATCHER_SSE: &str = ": ok\n\n\
event: activity.changed\n\
data: {\"shed\":\"proj\",\"slug\":\"cdx777\",\"activity\":\"working\",\"state\":\"ready\"}\n\n\
event: session.updated\n\
data: {\"shed\":\"proj\",\"slug\":\"cdx777\",\"session\":{\"state\":\"ready\",\"activity\":\"idle\"}}\n\n";

/// Step 1: stand up a local SSE server + a real `RcEventsWatcher` against it,
/// returning the bridge-owned opaque handle (Dart holds it for teardown). The
/// mpsc is parked inside the handle until `rc_watcher_events` drains it.
pub async fn create_rc_watcher() -> Result<BridgeWatcherHandle, String> {
    let (base_url, sse_task) = spawn_local_sse(WATCHER_SSE).await;
    let client = Client::new(base_url, "demo".to_string(), String::new(), None, None)
        .map_err(|e| e.to_string())?;
    let (watcher, rx) = RcEventsWatcher::spawn(bridge_rt().handle(), client, "demo".to_string());
    ACTIVE_WATCHERS.fetch_add(1, Ordering::SeqCst);
    Ok(BridgeWatcherHandle {
        inner: Mutex::new(Some((watcher, rx))),
        forwarder: Mutex::new(None),
        sse: sse_task.abort_handle(),
        stopped: AtomicBool::new(false),
    })
}

/// Step 2: drain the handle's watcher mpsc into a Dart `Stream`, folding
/// `Resynced` onto the next `Event`. FRB renders this (a `StreamSink` param) as
/// `Stream<BridgeWatcherUpdate>`. The forwarder exits when the sink closes
/// (Dart cancelled the subscription) or the mpsc ends.
pub fn rc_watcher_events(handle: &BridgeWatcherHandle, sink: StreamSink<BridgeWatcherUpdate>) {
    // Take the watcher + rx out of the handle; move the watcher into the
    // forwarding task so it lives exactly as long as the stream. (The handle's
    // stop()/Drop still aborts the forwarder + sse and decrements counters.)
    let Some((watcher, mut rx)) = handle.inner.lock().unwrap().take() else {
        return; // already streaming or torn down
    };
    let forwarder = bridge_rt().spawn(async move {
        // Keep the watcher alive for the stream's lifetime; dropping it at task
        // end (abort or mpsc-close) aborts its loop.
        let _watcher = watcher;
        let mut pending_resync = false;
        while let Some(update) = rx.recv().await {
            let mapped = match update {
                RcWatcherUpdate::Resynced => {
                    pending_resync = true;
                    continue;
                }
                RcWatcherUpdate::Event { event, .. } => {
                    let u = BridgeWatcherUpdate {
                        kind: "event".to_string(),
                        shed: event.shed().to_string(),
                        slug: slug_of(&event),
                        resync: pending_resync,
                        reason: String::new(),
                    };
                    pending_resync = false;
                    u
                }
                RcWatcherUpdate::Down { reason } => BridgeWatcherUpdate {
                    kind: "down".to_string(),
                    shed: String::new(),
                    slug: String::new(),
                    resync: false,
                    reason,
                },
            };
            if sink.add(mapped).is_err() {
                break; // consumer disposed the stream
            }
        }
    });
    *handle.forwarder.lock().unwrap() = Some(forwarder.abort_handle());
    ACTIVE_FORWARDERS.fetch_add(1, Ordering::SeqCst);
}

/// Explicit synchronous stop (idempotent) — belt-and-suspenders alongside the
/// handle's Drop. Dart calls this from `onDispose`.
pub fn stop_rc_events(handle: &BridgeWatcherHandle) {
    handle.stop();
}
