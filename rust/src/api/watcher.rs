//! `RcEventsWatcher` → Dart `Stream` (plan §3.3) — production shape.
//!
//! **Two-call shape (B1 finding 1):** [`create_rc_watcher`] returns the opaque
//! [`BridgeWatcherHandle`]; [`rc_watcher_events`] streams `BridgeWatcherUpdate`.
//!
//! **Unified locked lifecycle (Codex review #5/#6, the Phase-A C5 lessons):** the
//! watcher, its receiver, the forwarder abort-handle, and the counters live in one
//! `Mutex<WatcherInner>` behind an `Arc` shared by the handle and the forwarding
//! task. [`teardown`] is the single decrement point, guarded by a `stopped` flag,
//! so start-races-stop and self-exit-vs-external-stop can't double-count or leak.
//! Teardown is driven by the SYNCHRONOUS co-primary [`stop_rc_events`] (Riverpod
//! `onDispose` — Codex review #9) which aborts the forwarder immediately even
//! while it is parked on `rx.recv()`; `Drop` is the backstop. (FRB's `StreamSink`
//! exposes no `closed()` future, so a `select!{ recv, closed }` is not
//! expressible — the sync stop IS the deterministic cancellation seam, stronger
//! than polling a closed-signal; a `sink.add` failure is the additional
//! Dart-cancelled-without-stop backstop.)
//!
//! **Resync is folded onto the Event (Codex review #4, plan §3.3):** shed-app
//! emits `Resynced` as a SEPARATE update; if FRB coalesces/drops it the consumer
//! would get the fresh event but never invalidate the overview. So `Resynced` is
//! latched and delivered as `resync: true` ON the next `Event` (never standalone),
//! guaranteeing atomic delivery of the invalidation signal with its snapshot.
//!
//! **Overlay snapshot:** shed-app's folded `ActivityOverlay` isn't publicly
//! enumerable on this shed rev (only `lookup(shed, slug)`), so the forwarder
//! reconstructs an enumerable snapshot by mirroring the overlay's membership.
//! The LiveActivity VALUES come from shed-app's fold (suppression applied); only
//! key membership is mirrored here. Each `Event` carries the full snapshot, so a
//! coalesced/dropped intermediate is tolerable.

use std::collections::HashMap;
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex};

use flutter_rust_bridge::frb;
use shed_app::rc_events_watcher::{RcEventsWatcher, RcWatcherUpdate};
use shed_core::rc_events::{LiveActivity, RcEvent};
use tokio::sync::mpsc::UnboundedReceiver;

use crate::frb_generated::StreamSink;

use super::bridge_rt::{bridge_rt, ACTIVE_FORWARDERS, ACTIVE_WATCHERS};
use super::client::BridgeClient;
use super::dto_rc::{BridgeRcActivity, BridgeRcEvent, BridgeRcState};

/// One folded live-activity patch, keyed by `(shed, slug)` — the enumerable
/// mirror of one `ActivityOverlay` entry.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeOverlayEntry {
    pub shed: String,
    pub slug: String,
    pub activity: Option<BridgeRcActivity>,
    pub state: Option<BridgeRcState>,
    pub last_message: Option<String>,
    pub last_seq: Option<u64>,
}

impl BridgeOverlayEntry {
    fn from_live(shed: &str, slug: &str, la: &LiveActivity) -> BridgeOverlayEntry {
        BridgeOverlayEntry {
            shed: shed.to_string(),
            slug: slug.to_string(),
            activity: la.activity.map(Into::into),
            state: la.state.map(Into::into),
            last_message: la.last_message.clone(),
            last_seq: la.last_seq,
        }
    }
}

/// A watcher update marshalled to Dart — a FRB 2.13 sealed class. `Event` carries
/// the decoded event, the full folded overlay snapshot, and `resync` (set when a
/// reconnect just cleared the held overlay — the consumer refetches its overview;
/// Codex review #4). There is deliberately NO standalone `Resynced` variant.
pub enum BridgeWatcherUpdate {
    Event {
        event: BridgeRcEvent,
        overlay: Vec<BridgeOverlayEntry>,
        resync: bool,
    },
    /// The connection ended; the watcher backs off and reconnects.
    Down { reason: String },
}

/// The unified, mutex-protected watcher lifecycle (Codex review #5/#6).
struct WatcherInner {
    watcher: Option<RcEventsWatcher>,
    rx: Option<UnboundedReceiver<RcWatcherUpdate>>,
    forwarder: Option<tokio::task::AbortHandle>,
    streaming: bool,
    stopped: bool,
}

/// Bridge-owned opaque handle. Dart holds it and drives teardown via the sync
/// [`stop_rc_events`] in `onDispose`; `Drop` is the backstop.
pub struct BridgeWatcherHandle {
    state: Arc<Mutex<WatcherInner>>,
}

impl Drop for BridgeWatcherHandle {
    fn drop(&mut self) {
        teardown(&self.state);
    }
}

/// The SINGLE teardown/decrement point, idempotent via `stopped`. Aborts the
/// forwarder (immediately, even parked on `rx.recv()`), drops the watcher
/// (aborting its reconnect loop), and decrements each counter exactly once —
/// only for resources that were actually counted.
fn teardown(state: &Arc<Mutex<WatcherInner>>) {
    let mut s = state.lock().unwrap();
    if s.stopped {
        return;
    }
    s.stopped = true;
    if let Some(f) = s.forwarder.take() {
        f.abort();
        ACTIVE_FORWARDERS.fetch_sub(1, Ordering::SeqCst);
    }
    s.rx = None;
    drop(s.watcher.take());
    ACTIVE_WATCHERS.fetch_sub(1, Ordering::SeqCst);
}

/// The session `(shed, slug)` a data event pertains to (`None` for the
/// shed-wide hub/stopped events).
fn event_session_key(ev: &RcEvent) -> Option<(String, String)> {
    match ev {
        RcEvent::ActivityChanged { shed, slug, .. }
        | RcEvent::SessionUpdated { shed, slug, .. }
        | RcEvent::MessageAppended { shed, slug, .. } => Some((shed.clone(), slug.clone())),
        _ => None,
    }
}

/// Step 1: spawn a real `RcEventsWatcher` against `client` on `bridge_rt`,
/// returning the bridge-owned opaque handle. The mpsc is parked inside the handle
/// until [`rc_watcher_events`] drains it.
pub async fn create_rc_watcher(client: &BridgeClient, server_name: String) -> BridgeWatcherHandle {
    let (watcher, rx) =
        RcEventsWatcher::spawn(bridge_rt().handle(), client.inner().clone(), server_name);
    ACTIVE_WATCHERS.fetch_add(1, Ordering::SeqCst);
    BridgeWatcherHandle {
        state: Arc::new(Mutex::new(WatcherInner {
            watcher: Some(watcher),
            rx: Some(rx),
            forwarder: None,
            streaming: false,
            stopped: false,
        })),
    }
}

/// Step 2: drain the handle's watcher mpsc into a Dart `Stream`, folding
/// `Resynced` onto the next `Event` and reconstructing the enumerable overlay
/// snapshot per event.
pub fn rc_watcher_events(handle: &BridgeWatcherHandle, sink: StreamSink<BridgeWatcherUpdate>) {
    // Claim the receiver under the lock (refuse if torn down or already streaming).
    let rx = {
        let mut s = handle.state.lock().unwrap();
        if s.stopped || s.streaming {
            return;
        }
        let Some(rx) = s.rx.take() else {
            return;
        };
        s.streaming = true;
        rx
    };
    let state = handle.state.clone();
    let forwarder = bridge_rt().spawn(forward_loop(rx, sink, state.clone()));
    // Install the abort handle, RE-CHECKING stopped: if teardown won during the
    // spawn, abort the just-spawned forwarder and do not count it (Codex #6).
    let mut s = state.lock().unwrap();
    if s.stopped {
        forwarder.abort();
    } else {
        s.forwarder = Some(forwarder.abort_handle());
        ACTIVE_FORWARDERS.fetch_add(1, Ordering::SeqCst);
    }
}

/// The forwarding loop: drain `rx`, map each update, push to the Dart sink.
/// Self-tears-down on mpsc-end or a closed sink (Dart cancelled without calling
/// stop). Runs on `bridge_rt`.
async fn forward_loop(
    mut rx: UnboundedReceiver<RcWatcherUpdate>,
    sink: StreamSink<BridgeWatcherUpdate>,
    state: Arc<Mutex<WatcherInner>>,
) {
    let mut snapshot: HashMap<(String, String), BridgeOverlayEntry> = HashMap::new();
    // Latched Resynced, delivered on the NEXT Event (atomic with its snapshot).
    let mut pending_resync = false;
    while let Some(update) = rx.recv().await {
        let mapped = match update {
            RcWatcherUpdate::Resynced => {
                // Clear the held snapshot (stale patches can't override the fresh
                // one) and latch the flag; do NOT emit standalone.
                pending_resync = true;
                snapshot.clear();
                continue;
            }
            RcWatcherUpdate::Down { reason } => BridgeWatcherUpdate::Down { reason },
            RcWatcherUpdate::Event { event, overlay } => {
                match &event {
                    RcEvent::HubUnavailable { shed } | RcEvent::ShedStopped { shed } => {
                        snapshot.retain(|(s, _), _| s != shed);
                    }
                    _ => {
                        if let Some((shed, slug)) = event_session_key(&event) {
                            match overlay.lookup(&shed, &slug) {
                                Some(la) => {
                                    snapshot.insert(
                                        (shed.clone(), slug.clone()),
                                        BridgeOverlayEntry::from_live(&shed, &slug, la),
                                    );
                                }
                                None => {
                                    snapshot.remove(&(shed, slug));
                                }
                            }
                        }
                    }
                }
                let u = BridgeWatcherUpdate::Event {
                    event: event.into(),
                    overlay: snapshot.values().cloned().collect(),
                    resync: pending_resync,
                };
                pending_resync = false;
                u
            }
        };
        if sink.add(mapped).is_err() {
            break; // consumer disposed the stream (detected on this add)
        }
    }
    teardown(&state);
}

/// Explicit SYNCHRONOUS stop (idempotent, co-primary with Drop). Dart calls this
/// from `onDispose`; it aborts a parked forwarder immediately (Codex #5/#9).
#[frb(sync)]
pub fn stop_rc_events(handle: &BridgeWatcherHandle) {
    teardown(&handle.state);
}
