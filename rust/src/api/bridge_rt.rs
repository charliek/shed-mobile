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
/// Ephemeral add-server enrollment credentials currently alive (plan 002 §7 P7).
/// Bumped when `preview::preview_add_server` generates its keypair, dropped by
/// that keypair's `Drop` — so a non-zero reading after every preview has settled
/// means a preview credential outlived its future, which is the ONE thing the
/// disposal contract forbids.
pub(crate) static PENDING_PREVIEW_CREDENTIALS: AtomicU64 = AtomicU64::new(0);
/// Hermetic test-support SSE servers (local_sse.rs). Tracked so the zero-leak
/// assertions stay HONEST — the accept loops would otherwise run detached until
/// process exit (Codex review #11).
pub(crate) static ACTIVE_SSE_SERVERS: AtomicU64 = AtomicU64::new(0);
/// Open agent lanes ([`super::lane::BridgeLane`], plan 018 §3.9). Each one owns
/// an adapter holding HTTP connections plus a subscription pump, so a non-zero
/// reading after every panel has closed means a lane whose `Drop` never ran —
/// the one thing [`super::lane::lane_close`] exists to make impossible.
pub(crate) static ACTIVE_LANES: AtomicU64 = AtomicU64::new(0);
/// Lane NUDGE forwarders, counted beside [`ACTIVE_LANES`] rather than folded
/// into [`ACTIVE_FORWARDERS`].
///
/// Separate because the two answer different questions: a lane can be open with
/// no nudge stream claimed (nothing is looking at it yet), and a forwarder that
/// self-tore-down after a cancelled Dart stream must show up as one gone and one
/// lane gone, not as an ambiguous single decrement.
pub(crate) static ACTIVE_LANE_FORWARDERS: AtomicU64 = AtomicU64::new(0);

/// Snapshot of the live-resource counters (plan AC#2). A Dart integration test
/// asserts every field is 0 after disposing each slice's resources.
pub struct BridgeLiveCounters {
    pub active_watchers: u64,
    pub active_forwarders: u64,
    pub active_create_streams: u64,
    pub pending_mints: u64,
    pub active_sse_servers: u64,
    pub pending_preview_credentials: u64,
    pub active_lanes: u64,
    pub active_lane_forwarders: u64,
}

/// Read the current live-resource counters.
pub fn live_counters() -> BridgeLiveCounters {
    BridgeLiveCounters {
        active_watchers: ACTIVE_WATCHERS.load(Ordering::SeqCst),
        active_forwarders: ACTIVE_FORWARDERS.load(Ordering::SeqCst),
        active_create_streams: ACTIVE_CREATE_STREAMS.load(Ordering::SeqCst),
        pending_mints: PENDING_MINTS.load(Ordering::SeqCst),
        active_sse_servers: ACTIVE_SSE_SERVERS.load(Ordering::SeqCst),
        pending_preview_credentials: PENDING_PREVIEW_CREDENTIALS.load(Ordering::SeqCst),
        active_lanes: ACTIVE_LANES.load(Ordering::SeqCst),
        active_lane_forwarders: ACTIVE_LANE_FORWARDERS.load(Ordering::SeqCst),
    }
}

/// Run `fut` on the persistent bridge runtime, **aborting it if the caller's
/// future is dropped**, and hand back what it produced.
///
/// The two properties, both load-bearing and both easy to lose by writing
/// `bridge_rt().spawn(fut).await` instead:
///
/// * **Abort-on-drop.** Dropping a `JoinHandle` DETACHES the task, so an FRB
///   future dropped mid-await (Dart cancelled the call) would leave the work —
///   and whatever connection it holds — running to its own timeout. The guard
///   holds the `AbortHandle` and fires on drop; it is disarmed only after a
///   successful join.
/// * **The reactor.** A held connection spawns tasks of its own
///   (`copy_bidirectional` on a roost `Conn`, reqwest's pool), and
///   `tokio::spawn` binds a task to whatever runtime is current. On FRB's
///   per-call executor that runtime goes away with the call.
///
/// The `Err` is a join failure (the task panicked, or was aborted); each caller
/// maps it into its own error type rather than propagating a panic across the
/// FFI boundary.
pub(crate) async fn joined_on_bridge_rt<T, F>(fut: F) -> Result<T, tokio::task::JoinError>
where
    F: std::future::Future<Output = T> + Send + 'static,
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
    joined
}

/// Monotonic id source for mint/runner request routing.
pub(crate) fn next_id(prefix: &str) -> String {
    static SEQ: AtomicU64 = AtomicU64::new(1);
    format!("{prefix}-{}", SEQ.fetch_add(1, Ordering::SeqCst))
}
