//! Shared infrastructure for the B1 vertical-slice proofs: one persistent
//! multi-threaded tokio runtime for the long-lived background work (watchers,
//! create streams, the local SSE test servers) and the debug leak counters
//! (plan AC#2) that every slice increments/decrements so a Dart test can assert
//! they return to zero across subscribe→dispose / mint→complete cycles.
//!
//! Why a dedicated runtime: FRB's per-call async executor is fine for a bridge
//! `async fn` that returns to Dart, but the watcher/create tasks OUTLIVE the
//! call that spawned them — they must live on a persistent runtime with a real
//! reactor. This is also how the real app should structure background tasks.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::OnceLock;

use tokio::runtime::Runtime;

/// The persistent runtime backing all long-lived bridge tasks + the local SSE
/// test servers. Lazily built on first use.
pub(crate) fn bridge_rt() -> &'static Runtime {
    static RT: OnceLock<Runtime> = OnceLock::new();
    RT.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .expect("build bridge tokio runtime")
    })
}

// --- Debug leak counters (AC#2): each is bumped on resource create, dropped on
// teardown; a Dart test asserts they return to zero. ---
pub(crate) static ACTIVE_WATCHERS: AtomicU64 = AtomicU64::new(0);
pub(crate) static ACTIVE_FORWARDERS: AtomicU64 = AtomicU64::new(0);
pub(crate) static ACTIVE_CREATE_STREAMS: AtomicU64 = AtomicU64::new(0);
pub(crate) static PENDING_MINTS: AtomicU64 = AtomicU64::new(0);
/// Hermetic test-support SSE servers (local_sse.rs). Tracked so the zero-leak
/// assertions stay HONEST — the accept loops would otherwise run detached until
/// process exit (Codex review #11).
pub(crate) static ACTIVE_SSE_SERVERS: AtomicU64 = AtomicU64::new(0);

/// Snapshot of the live-resource counters (plan AC#2). A Dart integration test
/// asserts every field is 0 after disposing each slice's resources.
pub struct BridgeLiveCounters {
    pub active_watchers: u64,
    pub active_forwarders: u64,
    pub active_create_streams: u64,
    pub pending_mints: u64,
    pub active_sse_servers: u64,
}

/// Read the current live-resource counters.
pub fn live_counters() -> BridgeLiveCounters {
    BridgeLiveCounters {
        active_watchers: ACTIVE_WATCHERS.load(Ordering::SeqCst),
        active_forwarders: ACTIVE_FORWARDERS.load(Ordering::SeqCst),
        active_create_streams: ACTIVE_CREATE_STREAMS.load(Ordering::SeqCst),
        pending_mints: PENDING_MINTS.load(Ordering::SeqCst),
        active_sse_servers: ACTIVE_SSE_SERVERS.load(Ordering::SeqCst),
    }
}

/// Monotonic id source for mint/runner request routing.
pub(crate) fn next_id(prefix: &str) -> String {
    static SEQ: AtomicU64 = AtomicU64::new(1);
    format!("{prefix}-{}", SEQ.fetch_add(1, Ordering::SeqCst))
}
