//! **One agent lane, on the phone** (plan 018 §3.9) — the client half of
//! [`shed_core::lane`], shaped exactly like the desktop's
//! (`desktop/tauri/src-tauri/src/lane.rs`) and for the same reasons.
//!
//! ```text
//!   Dart: machine row ──agent_lane{kind, session_id, server_url}──▶ lane_open
//!                     ◀── one `true` nudge ───────────────────────  lane_nudges
//!                     ──▶ lane_snapshot(since_seq) ── one atomic read
//!
//!   Rust: Arc<dyn AgentLane>  ──subscribe()──▶  Reset … Ready … frames
//!                                                     │
//!                                       LaneView (staged, then swapped)
//!                                                     │
//!                                        dirty bit ──▶ forwarder ──▶ sink
//! ```
//!
//! # Rust never calls into Dart, Dart never folds, and Rust owns reconnection
//!
//! The three sentences that decide everything else in this module:
//!
//! * **Rust owns the adapter, the subscription pump and the staged view.** The
//!   fold is [`LaneView`] — the SAME fold the
//!   desktop uses, moved down into `shed-app` in this plan precisely so there is
//!   not a second one. Nothing here re-implements staging, generations or the
//!   `since_seq` cut.
//! * **Dart gets a nudge and pulls one atomic snapshot.** Not a stream of
//!   frames: an FRB `StreamSink` carrying every `LaneEvent` would be a second
//!   unbounded buffer sitting behind the contract's already-bounded one, and a
//!   phone that backgrounds mid-turn would come back to a queue instead of a
//!   view. A `bool` nudge cannot queue anything.
//! * **Rust owns reconnection.** [`spawn_pump`] carries the desktop's whole
//!   resubscribe ladder. Dart's only two lifecycle jobs are the ones that need
//!   SSH: supplying gx credentials when asked
//!   ([`lane_refresh_credentials`]) and re-opening after a terminal `Down`
//!   (§3.11). It re-probes only on `needs_credentials` and re-opens only on
//!   `stale`.
//!
//! # The snapshot IS the nudge acknowledgement
//!
//! [`LaneInner::apply`] folds every frame under the view lock and, **if the
//! dirty bit was clean**, sets it and wakes the forwarder once; the forwarder
//! pushes one `true`. [`lane_snapshot`] takes the SAME lock, projects the view
//! plus the approvals and the credential flag, and clears the dirty bit. So a
//! burst of a hundred frames with no snapshot in between yields exactly one
//! nudge, and the first frame after a snapshot yields the next one.
//!
//! Two reads would TEAR — a frame can land between "give me the messages" and
//! "give me the approvals", and the panel would render two different instants —
//! and a bare `Notify` with no dirty bit would either coalesce nothing or lose
//! the wakeup that arrived while the forwarder was mid-push. One lock and one
//! bit answers both.
//!
//! # There is no registry
//!
//! Two [`lane_open`] calls are two lanes. "One lane per row" is the Riverpod
//! provider's job (§3.11), which is where the phone's identity for a row lives;
//! a second map in here would be a second answer to the same question. That is
//! the one structural difference from the desktop, whose `Lanes` map exists
//! because its IPC verbs address a lane by `(machine, session_id)` strings
//! rather than by holding a handle.
//!
//! [`lane_close`] is the synchronous teardown seam (the
//! [`super::roost::stop_roost_watcher`] precedent — a Riverpod `onDispose`
//! calls it), and `Drop` is the backstop.

use std::future::Future;
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex, MutexGuard, Weak};
use std::time::Duration;

use flutter_rust_bridge::frb;
use shed_app::lane_view::LaneView;
use shed_core::lane::{AgentLane, LaneError, LaneEvent};
use shed_gx::{FixedDial, GxClient, GxCredentialSource, GxDiscovery, GxTimings, GxTransport};
use shed_opencode::OpencodeClient;

use crate::frb_generated::StreamSink;

use super::bridge_rt::{bridge_rt, joined_on_bridge_rt, ACTIVE_LANES, ACTIVE_LANE_FORWARDERS};
use super::dto_lane::{
    BridgeLaneAnswer, BridgeLaneCapabilities, BridgeLaneError, BridgeLaneSnapshot, BridgeSendMode,
};

/// The `agent_lane` kinds THIS BUILD has an adapter for.
///
/// One list, two readers: [`lane_open`]'s pre-dispatch guard and the refusal it
/// raises. The `match` in [`build_client`] is deliberately not a third — that is
/// where a kind binds to a constructor, the one place a concrete client type may
/// be named.
const LANE_KINDS: [&str; 2] = ["opencode", "gx"];

/// The re-subscribe backoff, floor and ceiling — **the desktop's constants**
/// (`lane.rs`'s `RESUBSCRIBE_BASE`/`RESUBSCRIBE_MAX`), deliberately identical so
/// a lane that comes back on the desktop comes back on the phone at the same
/// cadence.
///
/// Short because the thing being retried is a loopback dial through a forward
/// the phone already holds, not a WAN round trip, and a panel the user is
/// looking at should come back quickly. Reset once a generation reaches its
/// `Ready`.
const RESUBSCRIBE_BASE: Duration = Duration::from_millis(200);
/// See [`RESUBSCRIBE_BASE`].
const RESUBSCRIBE_MAX: Duration = Duration::from_secs(5);

/// The [`LaneEvent::Down`] reason that means **stop trying**.
///
/// The adapter emits it when a reseed answers 404: the session was deleted, and
/// no amount of reconnecting brings it back. Every other `Down` is worth another
/// attempt (the agent restarted, the tunnel blipped) — which is why the pump
/// ends on this one alone, exactly as the desktop's does.
const DOWN_UNKNOWN_SESSION: &str = "unknown_session";

/// How long a gx credential ask waits for Dart to answer it before the adapter's
/// own retry ladder takes over.
///
/// It is a bound on a HUMAN-SPEED path: Dart has to run an SSH exec on the
/// machine and parse what came back. Thirty seconds is long enough for a slow
/// link and a phone that just woke up, and short enough that a backgrounded app
/// does not hold gx's pin gate (and with it every gx verb on this lane) for
/// minutes. On expiry the source answers [`LaneError::Unavailable`], which the
/// adapter maps to retry-with-backoff rather than `Down`, so the ask simply
/// happens again.
///
/// Under gx's own 60 s `down_after` (`shed_gx::GxTimings::down_after`), so a
/// single unanswered ask cannot by itself end the subscription.
const CREDENTIAL_REFRESH_WAIT: Duration = Duration::from_secs(30);

/// Take a lock, ignoring poisoning — [`super::roost`]'s rule, for the same
/// reason: every mutex here guards plain data, and turning one unrelated panic
/// into a permanently dead lane layer is strictly worse than reading a slightly
/// stale view.
fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

fn unavailable(msg: String) -> BridgeLaneError {
    BridgeLaneError::Unavailable { msg }
}

// ---------------------------------------------------------------------------
// the handle
// ---------------------------------------------------------------------------

/// Everything [`lane_open`] needs to build one lane — the row's stamp plus the
/// two things only the phone's transport knows.
///
/// **`reported_url` and `dial_url` are different values and are never
/// conflated.** `reported_url` is the loopback URL the agent announced on ITS
/// host, and it is what a gx discovery record is matched against;
/// `dial_url` is where this phone actually reaches it — the near end of the
/// `RoostTunnel`-shaped forward Dart already holds, or the same address again
/// when the agent is on this device. The contract is explicit that an
/// implementation which dialled the reported URL would be wrong over SSH.
pub struct BridgeLaneSpec {
    /// `"opencode"` or `"gx"`. Anything else is
    /// [`BridgeLaneError::UnsupportedLane`], refused before any I/O.
    pub kind: String,
    pub session_id: String,
    pub reported_url: String,
    pub dial_url: String,
    /// The raw stdout of [`gx_probe_remote_command`], run by Dart over the
    /// machine's SSH client. Required for a `"gx"` lane and ignored for every
    /// other kind.
    ///
    /// **These bytes are one `cat` away from being a bearer token.** They are
    /// parsed inside [`discovery_from_probe`] and dropped there; nothing in this
    /// module logs them, stores them past the parse, or puts any part of them in
    /// an error string.
    pub gx_probe_stdout: Option<Vec<u8>>,
}

/// The staged view and the two flags a snapshot reads — **all under one lock**.
///
/// They are one struct because they are read together, atomically, by
/// [`lane_snapshot`]. Splitting them would reintroduce the tear this design
/// exists to remove.
struct LaneState {
    view: LaneView,
    /// Set by [`LaneInner::apply`] when the view changed, cleared by
    /// [`lane_snapshot`]. The nudge is this bit's clean→dirty transition, which
    /// is what coalesces a burst into one wakeup.
    dirty: bool,
    /// The gx credential ask (see [`BridgeGxCredentials`]). Lives here rather
    /// than beside the credential source so `lane_snapshot` reads it under the
    /// same lock as everything else.
    needs_credentials: bool,
}

/// The adapter and the two tasks, plus the idempotence flags — the teardown
/// half, deliberately behind a DIFFERENT lock from [`LaneState`] so a snapshot
/// on the hot path never contends with a close.
struct LaneTasks {
    /// `None` once closed: dropping the adapter is what closes its transport.
    client: Option<Arc<dyn AgentLane>>,
    pump: Option<tokio::task::AbortHandle>,
    forwarder: Option<tokio::task::AbortHandle>,
    /// One claim on the nudge stream. A second [`lane_nudges`] would silently
    /// split the nudges between two consumers, and a nudge is not repeatable.
    streaming: bool,
    /// The single-shot teardown latch: every counter is decremented exactly
    /// once, and only for a resource that was actually counted.
    closed: bool,
}

struct LaneInner {
    state: Mutex<LaneState>,
    tasks: Mutex<LaneTasks>,
    /// The forwarder's wakeup. `notify_one` stores a permit when nobody is
    /// waiting, so a nudge raised before [`lane_nudges`] is not lost.
    wake: tokio::sync::Notify,
    /// The agent session id every verb addresses.
    session_id: String,
    /// Cached at open. The contract states capabilities are static for the life
    /// of the adapter and invites a client to cache them, and caching is what
    /// lets [`lane_capabilities`] stay `sync` and keep answering after a close.
    capabilities: BridgeLaneCapabilities,
    /// `Some` on a gx lane only — the thing
    /// [`lane_refresh_credentials`] delivers into.
    credentials: Option<Arc<BridgeGxCredentials>>,
}

/// One open agent lane: the adapter, the fold, the pump and the nudge
/// forwarder.
///
/// Opaque because none of that can cross FRB. Dart holds it, reads through
/// [`lane_snapshot`], and ends it with [`lane_close`].
#[frb(opaque)]
pub struct BridgeLane {
    inner: Arc<LaneInner>,
}

impl Drop for BridgeLane {
    fn drop(&mut self) {
        teardown(&self.inner);
    }
}

impl LaneInner {
    /// Fold one frame in and nudge **at most once per un-acknowledged burst**.
    ///
    /// The lock is released before the notify: `Notify::notify_one` can wake a
    /// task, and waking one while holding the lock it is about to want is how a
    /// hot path acquires a convoy.
    fn apply(&self, event: &LaneEvent) {
        let first = {
            let mut s = lock(&self.state);
            s.view.apply(event);
            let first = !s.dirty;
            s.dirty = true;
            first
        };
        if first {
            self.wake.notify_one();
        }
    }

    /// Record a transport-level failure as the same stale-with-a-reason state a
    /// [`LaneEvent::Down`] produces — the desktop's `note_down`.
    ///
    /// The panel must not care whether the thing that went away was the agent or
    /// the reach to it: both mean "this transcript is not live", and both are
    /// recovered by the same retry.
    fn note_down(&self, reason: String) {
        self.apply(&LaneEvent::Down { reason });
    }

    /// Raise the gx credential ask: set the flag Dart reads on its next
    /// snapshot, and nudge so it takes one.
    ///
    /// It goes through the same dirty bit as a frame, so an ask raised in the
    /// middle of a busy generation costs no extra nudge — and one raised on an
    /// idle lane produces exactly one.
    fn request_credentials(&self) {
        let first = {
            let mut s = lock(&self.state);
            let first = !s.dirty;
            s.dirty = true;
            s.needs_credentials = true;
            first
        };
        if first {
            self.wake.notify_one();
        }
    }

    fn clear_credentials_ask(&self) {
        lock(&self.state).needs_credentials = false;
    }

    /// The adapter, or the refusal for a lane that is closed.
    fn client(&self) -> Result<Arc<dyn AgentLane>, BridgeLaneError> {
        lock(&self.tasks)
            .client
            .clone()
            .ok_or_else(|| BridgeLaneError::NoLane {
                msg: format!("the lane for session {:?} is closed", self.session_id),
            })
    }
}

/// The SINGLE teardown/decrement point, idempotent via `closed`: abort the
/// forwarder and the pump (immediately, even parked on `recv`), drop the
/// adapter — which closes the transport it holds — and decrement each counter
/// exactly once, only for resources that were actually counted.
///
/// The counter discipline is [`super::roost::stop_roost_watcher`]'s, and it
/// matters for its reason: the counters are `u64`, so a double-decrement would
/// wrap to `u64::MAX` and every later leak assertion would pass for the wrong
/// reason.
fn teardown(inner: &Arc<LaneInner>) {
    let mut t = lock(&inner.tasks);
    if t.closed {
        return;
    }
    t.closed = true;
    if let Some(f) = t.forwarder.take() {
        f.abort();
        ACTIVE_LANE_FORWARDERS.fetch_sub(1, Ordering::SeqCst);
    }
    if let Some(p) = t.pump.take() {
        p.abort();
    }
    drop(t.client.take());
    ACTIVE_LANES.fetch_sub(1, Ordering::SeqCst);
}

// ---------------------------------------------------------------------------
// open
// ---------------------------------------------------------------------------

/// Open a live lane on one agent session: dispatch on `kind`, fetch the roster
/// row, and start the pump.
///
/// **Dispatch is the desktop `Lanes::open`'s, arm for arm**: `"opencode"` →
/// [`OpencodeClient`] on the dial URL with no credential source (opencode needs
/// none — a password-protected server answers 401, which surfaces as
/// [`BridgeLaneError::Unauthorized`] and a status-only panel); `"gx"` →
/// [`GxClient`] on the REPORTED url with a [`FixedDial`] transport and the
/// probe's discovery; anything else → [`BridgeLaneError::UnsupportedLane`]
/// **before any I/O**, because a kind with no adapter is a permanent property of
/// the row and there is no reason to spend a round trip discovering it.
///
/// The roster row is fetched BEFORE the subscription starts, for the desktop's
/// reason: a 404 here is an honest `unknown_session` the caller can render,
/// where the same failure inside the pump would be a `Down` the panel has to
/// wait for. It is also the call that fails on a password-protected agent and,
/// on gx, the one that discovers and pins the credential.
///
/// Everything runs on [`bridge_rt`] — not tidiness: the pump and the adapter's
/// held HTTP connections OUTLIVE this call, so they must be created on a runtime
/// that outlives it. FRB's per-call executor goes away when the call returns.
pub async fn lane_open(spec: BridgeLaneSpec) -> Result<BridgeLane, BridgeLaneError> {
    // Refused before the runtime hop, so the test that asserts "no I/O" is
    // asserting something structural rather than an ordering inside a task.
    if !LANE_KINDS.contains(&spec.kind.as_str()) {
        return Err(BridgeLaneError::UnsupportedLane { kind: spec.kind });
    }
    on_bridge_rt(async move { open_inner(spec).await }).await
}

async fn open_inner(spec: BridgeLaneSpec) -> Result<BridgeLane, BridgeLaneError> {
    let (client, credentials) = build_client(&spec)?;
    // The roster GET. On a gx lane it is also what pins the epoch, so it is the
    // first place a bad credential shows up.
    client
        .session(&spec.session_id)
        .await
        .map_err(BridgeLaneError::from)?;
    // Read once, here, rather than on every `lane_capabilities` call: the
    // contract states these are static for the life of the adapter and invites
    // a client to cache them.
    let capabilities: BridgeLaneCapabilities = client.capabilities().into();

    let inner = Arc::new(LaneInner {
        state: Mutex::new(LaneState {
            view: LaneView::default(),
            dirty: false,
            needs_credentials: false,
        }),
        tasks: Mutex::new(LaneTasks {
            client: Some(Arc::clone(&client)),
            pump: None,
            forwarder: None,
            streaming: false,
            closed: false,
        }),
        wake: tokio::sync::Notify::new(),
        session_id: spec.session_id.clone(),
        capabilities,
        credentials: credentials.clone(),
    });
    // The credential source holds a WEAK reference, and this is where it learns
    // which lane it belongs to. Weak because the adapter owns the source and the
    // lane owns the adapter: a strong reference the other way would be a cycle
    // that only `lane_close` could break, and a handle Dart dropped without
    // closing would leak the whole lane.
    if let Some(creds) = credentials.as_ref() {
        creds.bind(Arc::downgrade(&inner));
    }

    // Counted only once the lane exists and will be handed back. Every failure
    // above returns before this, so nothing decrements a counter that was never
    // incremented.
    ACTIVE_LANES.fetch_add(1, Ordering::SeqCst);
    let pump = spawn_pump(Arc::clone(&inner), client);
    lock(&inner.tasks).pump = Some(pump.abort_handle());
    Ok(BridgeLane { inner })
}

/// **The one place this module names a concrete adapter.** Everything after it
/// is written against `dyn AgentLane`.
///
/// The gx arm hands back its credential source as well, because the lane has to
/// hold it for [`lane_refresh_credentials`] to deliver into — an
/// `Arc<dyn GxCredentialSource>` inside the client is not reachable from there.
#[allow(clippy::type_complexity)]
fn build_client(
    spec: &BridgeLaneSpec,
) -> Result<(Arc<dyn AgentLane>, Option<Arc<BridgeGxCredentials>>), BridgeLaneError> {
    match spec.kind.as_str() {
        "opencode" => {
            let url =
                reqwest::Url::parse(&spec.dial_url).map_err(|e| BridgeLaneError::BadRequest {
                    msg: format!(
                        "the agent server dial url {:?} is not usable: {e}",
                        spec.dial_url
                    ),
                })?;
            let client = OpencodeClient::new(url, None).map_err(BridgeLaneError::from)?;
            Ok((Arc::new(client), None))
        }
        "gx" => {
            let stdout = spec.gx_probe_stdout.as_deref().ok_or_else(|| {
                unavailable(format!(
                    "the gx lane at {} needs a discovery probe",
                    spec.reported_url
                ))
            })?;
            let discovery = discovery_from_probe(stdout, &spec.reported_url)?;
            let credentials = Arc::new(BridgeGxCredentials::new(
                &spec.reported_url,
                discovery,
                CREDENTIAL_REFRESH_WAIT,
            ));
            // `FixedDial` because the phone's local port is FIXED (§3.10): the
            // Dart side re-dials the SSH connection underneath the same
            // listening socket, so from Rust the port simply keeps working and
            // there is no forward to repair. `PinnedDial` wraps it for the one
            // thing the contract has no other seam for — see its doc.
            let dial = FixedDial::parse(&spec.dial_url).map_err(BridgeLaneError::from)?;
            let transport: Arc<dyn GxTransport> =
                Arc::new(PinnedDial::new(dial, Arc::clone(&credentials)));
            let client = GxClient::new(
                spec.reported_url.clone(),
                transport,
                Arc::clone(&credentials) as Arc<dyn GxCredentialSource>,
                GxTimings::default(),
            )
            .map_err(BridgeLaneError::from)?;
            Ok((Arc::new(client), Some(credentials)))
        }
        // Unreachable: `lane_open`'s guard ran before anything was built.
        // Restated rather than `unreachable!()` so that adding a kind to one
        // list and forgetting the other is a refusal, not a panic across the
        // FFI boundary.
        other => Err(BridgeLaneError::UnsupportedLane {
            kind: other.to_string(),
        }),
    }
}

// ---------------------------------------------------------------------------
// the pump
// ---------------------------------------------------------------------------

/// The desktop's `spawn_pump`, **minus forward repair**.
///
/// The desktop re-`ensure`s an `ssh -N -L` child on every `Reset` after the
/// first, because its tunnel is a process it owns and a dead one under an
/// established lane never ends `rx.recv()`. The phone has nothing to repair: the
/// local port is fixed and Dart re-establishes the SSH connection underneath the
/// same socket (§3.10), so a dropped tunnel is an ordinary "the socket refused"
/// the adapter retries through. Everything else is the same ladder, with the same
/// two constants, ending on the same one terminal reason.
fn spawn_pump(inner: Arc<LaneInner>, client: Arc<dyn AgentLane>) -> tokio::task::JoinHandle<()> {
    bridge_rt().spawn(async move {
        let session_id = inner.session_id.clone();
        let mut backoff = RESUBSCRIBE_BASE;
        loop {
            let subscription = match client.subscribe(&session_id, None).await {
                Ok(subscription) => subscription,
                // The session is gone for good. Anything else is worth
                // retrying — the agent may simply be restarting.
                Err(LaneError::UnknownSession) => {
                    inner.note_down(DOWN_UNKNOWN_SESSION.to_string());
                    return;
                }
                Err(e) => {
                    inner.note_down(e.to_string());
                    tokio::time::sleep(backoff).await;
                    backoff = next_backoff(backoff);
                    continue;
                }
            };
            // BOTH halves, for the whole read: taking `.rx` alone drops the stop
            // handle, which aborts the adapter's pump it is reading from, and
            // the receiver then yields nothing for ever with no error and no
            // `Down`. `LaneSubscription`'s own doc is three screens about this.
            let (mut rx, stop) = subscription.into_parts();
            let mut down: Option<String> = None;
            while let Some(event) = rx.recv().await {
                match &event {
                    // A generation that reached steady state is the signal the
                    // transport is healthy again.
                    LaneEvent::Ready { .. } => backoff = RESUBSCRIBE_BASE,
                    LaneEvent::Down { reason } => down = Some(reason.clone()),
                    _ => {}
                }
                // The fold and the nudge, in that order and under one lock. The
                // terminal `Down` above therefore ALSO marks the view stale and
                // raises the last nudge — which is what lets Dart tell "stale,
                // re-open me" from "closed by me".
                inner.apply(&event);
            }
            drop(stop);
            if down.as_deref() == Some(DOWN_UNKNOWN_SESSION) {
                return;
            }
            tokio::time::sleep(backoff).await;
            backoff = next_backoff(backoff);
        }
    })
}

fn next_backoff(current: Duration) -> Duration {
    std::cmp::min(current.saturating_mul(2), RESUBSCRIBE_MAX)
}

// ---------------------------------------------------------------------------
// the nudge forwarder
// ---------------------------------------------------------------------------

/// Push one nudge; `Err` means the Dart stream is gone.
///
/// A **closure**, not a trait, and the reason is the FRB surface: a trait
/// DEFINED in this crate makes the codegen emit an `abstract class` for it into
/// Dart, which `mint.rs`'s FRB-surface allowlist correctly refuses — an internal
/// seam is not API, and `#[frb(ignore)]` is not honoured on a trait in
/// 2.13-beta.5. A closure bound is invisible to the codegen.
///
/// It exists at all for the reason `api::testsupport`'s fake emitters exist: a
/// [`StreamSink`] can only be constructed by the generated Dart-facing glue, so
/// a `cargo test` process has no way to make one — and the forwarder's lifecycle
/// (the single claim, the abort handle, the self-teardown when a push fails) is
/// exactly the part that has to be tested. Production passes the real sink's
/// `add`, tests pass a capturing fake, and NOTHING in [`forward_loop`] branches
/// on `cfg(test)`.
type NudgeResult = Result<(), ()>;

/// Stream this lane's nudges. **One claim**: a second call on the same handle is
/// a no-op rather than a silent split of the nudges between two consumers.
///
/// Dart gets a `true` and nothing else — the payload is "something changed, take
/// a snapshot". The stream stays open until [`lane_close`], INCLUDING after a
/// terminal `Down`: that is how Dart distinguishes "stale, re-open me" (the
/// snapshot says `stale`) from "closed by me" (it called `lane_close`). A stream
/// that ended on `Down` would make those two indistinguishable.
pub fn lane_nudges(lane: &BridgeLane, sink: StreamSink<bool>) {
    spawn_forwarder(&lane.inner, move || sink.add(true).map_err(|_| ()));
}

/// [`lane_nudges`] with the push abstracted — the whole lifecycle, and the only
/// thing the real entry point adds is the concrete [`StreamSink`].
///
/// Answers whether it CLAIMED the stream, which is what the one-claim test reads.
fn spawn_forwarder(
    inner: &Arc<LaneInner>,
    push: impl Fn() -> NudgeResult + Send + 'static,
) -> bool {
    {
        let mut t = lock(&inner.tasks);
        if t.closed || t.streaming {
            return false;
        }
        t.streaming = true;
    }
    let forwarder = bridge_rt().spawn(forward_loop(Arc::clone(inner), push));
    // Re-check `closed`: if teardown won the race during the spawn, abort the
    // task we just started and do NOT count it — the decrement already
    // happened. [`super::roost::roost_watcher_events`]'s rule, for its reason.
    let mut t = lock(&inner.tasks);
    if t.closed {
        forwarder.abort();
        return false;
    }
    t.forwarder = Some(forwarder.abort_handle());
    ACTIVE_LANE_FORWARDERS.fetch_add(1, Ordering::SeqCst);
    true
}

/// Wait for a dirty transition, push one `true`, repeat — and SELF-TEAR-DOWN
/// when the loop ends.
///
/// That last part is why `inner` is passed in. The loop ends either because the
/// lane was closed (teardown already ran, and this is a no-op) or because the
/// push failed — and the second case is a Dart consumer that cancelled the
/// stream WITHOUT calling [`lane_close`]. Without the teardown here the pump
/// would keep subscribing, folding and holding a connection with nobody reading
/// it. `teardown` is idempotent, so a later `lane_close` or `Drop` still costs
/// exactly one decrement.
async fn forward_loop(inner: Arc<LaneInner>, push: impl Fn() -> NudgeResult) {
    loop {
        inner.wake.notified().await;
        if lock(&inner.tasks).closed {
            break;
        }
        if push().is_err() {
            break;
        }
    }
    teardown(&inner);
}

// ---------------------------------------------------------------------------
// reads
// ---------------------------------------------------------------------------

/// What this lane's adapter can do. Cached at open (the contract states these
/// are static for the life of the adapter), so it is a lock-free read that keeps
/// answering after [`lane_close`] — a panel unwinding does not need its buttons
/// to start throwing.
#[frb(sync)]
pub fn lane_capabilities(lane: &BridgeLane) -> BridgeLaneCapabilities {
    lane.inner.capabilities.clone()
}

/// **The one read**, and the nudge acknowledgement: the staged view projected,
/// the pending approvals, the credential flag — under ONE lock — and the dirty
/// bit cleared.
///
/// `since_seq` is `None` for everything (`full: true`) and `Some(s)` for the
/// rows after `s`. The cursor is honored only when it lands inside the current
/// generation's seq window; outside it the answer is every row with
/// `full: true`, which is what makes a generation change, a resubscription and a
/// cursor evicted by the 500-row cap all answer "replace what you hold" instead
/// of a delta with a hole in it. That rule is
/// [`shed_app::lane_view::LaneView::snapshot`]'s and is not restated here.
///
/// Sync: it is a memory read behind a mutex. Making Dart await it would add a
/// microtask to the one call it makes on every nudge.
#[frb(sync)]
pub fn lane_snapshot(lane: &BridgeLane, since_seq: Option<u64>) -> BridgeLaneSnapshot {
    let mut s = lock(&lane.inner.state);
    // Cleared BEFORE the projection is built, under the same guard: a frame that
    // lands after this read raises the next nudge, and one that landed before it
    // is in the value being returned. There is no ordering here in which a
    // change is both un-nudged and unseen.
    s.dirty = false;
    let needs_credentials = s.needs_credentials;
    BridgeLaneSnapshot::from_view(s.view.snapshot(since_seq), needs_credentials)
}

// ---------------------------------------------------------------------------
// writes
// ---------------------------------------------------------------------------

/// Send `text` to the session. [`BridgeSendMode::Interject`] needs
/// [`BridgeLaneCapabilities::interject`]; an adapter that cannot do it answers
/// [`BridgeLaneError::NotAccepting`].
pub async fn lane_send(
    lane: &BridgeLane,
    text: String,
    mode: BridgeSendMode,
) -> Result<(), BridgeLaneError> {
    let client = lane.inner.client()?;
    let session_id = lane.inner.session_id.clone();
    on_bridge_rt(async move {
        client
            .send(&session_id, &text, mode.into())
            .await
            .map_err(BridgeLaneError::from)
    })
    .await
}

/// Stop the turn in flight.
///
/// An adapter whose agent refuses a cancel with nothing to cancel surfaces
/// [`BridgeLaneError::NotAccepting`] rather than swallowing it — a hidden
/// refusal is indistinguishable from a cancel that worked. Gate the affordance
/// on the row's `Working` activity so the refusal is rare and explicable (the
/// turn ended between the render and the tap).
pub async fn lane_cancel(lane: &BridgeLane) -> Result<(), BridgeLaneError> {
    let client = lane.inner.client()?;
    let session_id = lane.inner.session_id.clone();
    on_bridge_rt(async move {
        client
            .cancel(&session_id)
            .await
            .map_err(BridgeLaneError::from)
    })
    .await
}

/// Answer one approval.
///
/// A second answer to the same approval is refused with
/// [`BridgeLaneError::AlreadySubmitted`] or
/// [`BridgeLaneError::AlreadyResolved`] — a double-tap, not a bug. A
/// [`BridgeLaneAnswer::Choice`] naming an id the approval did not offer, and a
/// [`BridgeLaneAnswer::Permission`] whose decision matches no offered option
/// kind (or SEVERAL of them), are [`BridgeLaneError::BadRequest`]: the adapter
/// never picks the nearest option, and never breaks a tie only the human can
/// break. [`super::dto_lane::lane_option_for`] is how a panel finds out in
/// advance.
pub async fn lane_answer(
    lane: &BridgeLane,
    approval_id: String,
    answer: BridgeLaneAnswer,
) -> Result<(), BridgeLaneError> {
    let client = lane.inner.client()?;
    let session_id = lane.inner.session_id.clone();
    on_bridge_rt(async move {
        client
            .answer(&session_id, &approval_id, answer.into())
            .await
            .map_err(BridgeLaneError::from)
    })
    .await
}

/// Answer a pending gx credential ask: parse a FRESH probe and hand it to the
/// waiting discovery.
///
/// The controller calls it when a snapshot reports
/// [`BridgeLaneSnapshot::needs_credentials`]. Pinning then resumes **in place** —
/// no `Down`, no re-open, the generation and the ring intact — which is the
/// whole point of asking rather than failing: a leader restart is recoverable
/// without the panel flickering.
///
/// Calling it with nothing waiting is fine and cheap: the value is held for the
/// next epoch's ask. Calling it on a lane that needs no credentials is a
/// [`BridgeLaneError::BadRequest`], because a client that ran an SSH probe for
/// an opencode lane has a bug worth hearing about.
pub async fn lane_refresh_credentials(
    lane: &BridgeLane,
    gx_probe_stdout: Vec<u8>,
) -> Result<(), BridgeLaneError> {
    let Some(credentials) = lane.inner.credentials.clone() else {
        return Err(BridgeLaneError::BadRequest {
            msg: format!(
                "the {} lane for session {:?} needs no credentials",
                lane.inner.capabilities.kind, lane.inner.session_id
            ),
        });
    };
    let discovery = discovery_from_probe(&gx_probe_stdout, credentials.reported_url())?;
    credentials.deliver(discovery);
    lane.inner.clear_credentials_ask();
    Ok(())
}

/// End the lane — the SYNCHRONOUS co-primary teardown (a Riverpod `onDispose`
/// calls this). Idempotent; `Drop` is the backstop.
///
/// It aborts the pump and the forwarder and drops the adapter, which closes the
/// connections it holds. The nudge stream ends here and only here.
#[frb(sync)]
pub fn lane_close(lane: &BridgeLane) {
    teardown(&lane.inner);
}

// ---------------------------------------------------------------------------
// gx credentials
// ---------------------------------------------------------------------------

/// The command Dart execs on the far side to read gx's discovery, verbatim.
///
/// **Dart composes no part of it**, and that is the whole point: SSH has no argv
/// API, so this multi-line script crosses as ONE string the far side re-parses,
/// and every transport that composes it has to compose it identically. It is
/// [`shed_core::machine::display_line`] over `["sh", "-c", PROBE_SCRIPT]` — the
/// same quoter [`shed_app::machine::exec`] hands `ssh`, so the phone's
/// `dartssh2` and the desktop's `ssh` binary put the same bytes on the wire.
/// shed's `tests/machine-transport` owns that contract as its `gx-probe`
/// scenario; a Rust test in this module pins the exact line against that
/// scenario's golden.
///
/// Sync because it is a constant, and a `String` rather than an argv list
/// because an argv list is precisely what Dart must not be given: it would then
/// own the quoting.
#[frb(sync)]
pub fn gx_probe_remote_command() -> String {
    shed_core::machine::display_line(&[
        "sh".to_string(),
        "-c".to_string(),
        shed_gx::PROBE_SCRIPT.to_string(),
    ])
}

/// Read a probe's stdout into a discovery for `reported_url`.
///
/// **The one function probe bytes are alive in.** They arrive, they are parsed,
/// and the parse's inputs are dropped when it returns — nothing is stored past
/// it, nothing is logged, and every refusal below is a fixed sentence naming
/// only the reported URL. [`shed_gx::ProbeError`]'s own variants are fixed
/// strings by construction (its doc is explicit that it never carries probe
/// output), which is why THAT one is safe to include: it is the difference
/// between "the probe never ran" and "the token file is not eligible", which is
/// the whole of what a user can act on.
///
/// Invalid UTF-8 is replaced rather than refused. The probe's output is JSON
/// records and hex, so a lossy byte is a corrupt read that the record parse will
/// reject anyway — and refusing on the encoding would mean reporting something
/// about the bytes.
fn discovery_from_probe(stdout: &[u8], reported_url: &str) -> Result<GxDiscovery, BridgeLaneError> {
    let text = String::from_utf8_lossy(stdout);
    let probe = shed_gx::parse_probe(&text)
        .map_err(|e| unavailable(format!("gx discovery for {reported_url}: {e}")))?;
    // The FIRST record naming this URL wins — `local_discovery`'s rule, and the
    // desktop's: a URL is a port, two leaders cannot bind one, so a second
    // record for it is stale, and the client's `instanceId` pin is what catches
    // a wrong pick anyway.
    let record = shed_gx::records_for(&probe.records, reported_url)
        .into_iter()
        .next()
        .ok_or_else(|| unavailable(format!("no gx discovery record for {reported_url}")))?;
    let token = probe
        .token
        .ok_or_else(|| unavailable(format!("the gx token could not be read for {reported_url}")))?;
    Ok(GxDiscovery {
        token,
        instance_id: record.instance_id.clone(),
    })
}

/// The held discovery, and how many times it has been asked for since the pin
/// gate last opened.
struct GxCredState {
    held: Option<GxDiscovery>,
    /// Asks since the last [`PinnedDial::dial`]. `0` means the next ask is this
    /// pin's FIRST.
    asks_this_pin: u32,
    /// Bumped by every accepted [`BridgeGxCredentials::deliver`], so a waiter
    /// can tell "a refresh landed" from "a stale wakeup".
    refresh_gen: u64,
}

/// **Where the gx lane's bearer token comes from on a phone** — the desktop's
/// rule with the re-read pushed up to Dart.
///
/// # Answer on EVERY ask, because every epoch asks
///
/// `GxClient::pin_epoch` calls `discover()` at the start of every epoch
/// (`shed-gx/src/client.rs:401`), and an epoch is opened by every stream
/// reconnect. So a source that served its answer once and then refused would
/// break every reconnect — not degrade it: the second epoch would find no
/// credential and the lane would never come back. The first ask of every pin is
/// therefore answered from the held discovery, unconditionally.
///
/// # The second ask within one pin is the leader restart, and it AWAITS
///
/// `pin_epoch` asks a SECOND time when the `instanceId` it discovered does not
/// match what `healthz` answered (`client.rs:411`) — a leader restarted, and its
/// instance moved while its token did not. Serving the same stale value again
/// turns a recoverable restart into a permanent `unavailable`: the pin fails,
/// the adapter retries, the next epoch asks, the same value comes back, for
/// ever.
///
/// So the second ask [`LaneInner::request_credentials`]s — sets the flag, raises
/// one nudge — and **awaits** a value delivered through
/// [`lane_refresh_credentials`], bounded by [`CREDENTIAL_REFRESH_WAIT`]. Waiting
/// here is safe in a way it would not be elsewhere: `pin_epoch` runs with the
/// epoch UNPINNED and no transport held, which is exactly the position the
/// adapter is already in. On expiry the answer is [`LaneError::Unavailable`],
/// which the adapter maps to retry-with-backoff, so the ask simply happens
/// again on the next epoch.
///
/// The phone does not read `$GROK_HOME` from disk on either path — not even for
/// a `localhost` lane, where Dart runs the same probe over the local SSH client
/// it already holds. One reader, one contract, and no second code path whose
/// containment rules could drift from `PROBE_SCRIPT`'s.
///
/// # What never leaves
///
/// The token is a [`shed_gx::GxToken`] from the moment [`discovery_from_probe`]
/// parses it, so it has no `Display`, no `Serialize`, and a `Debug` that prints
/// `<redacted>`. Nothing in this type formats a probe, and nothing in this
/// module logs one.
struct BridgeGxCredentials {
    /// Half the identity of what this source discovers, and what a record is
    /// matched against. The `reported_url` argument on `discover` is IGNORED for
    /// the desktop's reason: this source was built for one reported URL, and a
    /// client asking it about another would be asking the wrong source.
    reported_url: String,
    /// Set once, by [`lane_open`], after the lane exists. Weak — see the call
    /// site: the lane owns the adapter, the adapter owns this, so a strong
    /// reference back would be a cycle.
    lane: Mutex<Weak<LaneInner>>,
    state: Mutex<GxCredState>,
    /// Woken by [`BridgeGxCredentials::deliver`]. `notify_waiters` rather than
    /// `notify_one`, so a refresh with nobody waiting leaves no stale permit to
    /// wake the NEXT ask spuriously; the generation re-check covers the window
    /// before the waiter registers.
    refreshed: tokio::sync::Notify,
    wait: Duration,
}

impl BridgeGxCredentials {
    fn new(reported_url: &str, discovery: GxDiscovery, wait: Duration) -> BridgeGxCredentials {
        BridgeGxCredentials {
            reported_url: reported_url.to_string(),
            lane: Mutex::new(Weak::new()),
            state: Mutex::new(GxCredState {
                held: Some(discovery),
                asks_this_pin: 0,
                refresh_gen: 0,
            }),
            refreshed: tokio::sync::Notify::new(),
            wait,
        }
    }

    fn reported_url(&self) -> &str {
        &self.reported_url
    }

    fn bind(&self, lane: Weak<LaneInner>) {
        *lock(&self.lane) = lane;
    }

    /// A new pin is starting: the next ask is its first. Called by
    /// [`PinnedDial::dial`].
    fn begin_pin(&self) {
        lock(&self.state).asks_this_pin = 0;
    }

    /// Store a fresh discovery and wake whoever is waiting for one.
    fn deliver(&self, discovery: GxDiscovery) {
        {
            let mut st = lock(&self.state);
            st.held = Some(discovery);
            st.refresh_gen = st.refresh_gen.wrapping_add(1);
        }
        self.refreshed.notify_waiters();
    }

    /// The held value, but only if a refresh has landed since `since_gen`.
    fn refreshed_since(&self, since_gen: u64) -> Option<GxDiscovery> {
        let st = lock(&self.state);
        if st.refresh_gen == since_gen {
            return None;
        }
        st.held.clone()
    }

    /// Raise the ask, wait for Dart, and answer with whatever it delivered.
    async fn ask_for_a_refresh(&self) -> Result<GxDiscovery, LaneError> {
        let Some(lane) = lock(&self.lane).upgrade() else {
            // Nothing to ask: the lane is gone (closed, or `lane_open` failed
            // before it bound). Quiet, like every other "this transcript is not
            // live".
            return Err(LaneError::Unavailable(format!(
                "the gx lane at {} is closed",
                self.reported_url
            )));
        };
        let since_gen = lock(&self.state).refresh_gen;
        let notified = self.refreshed.notified();
        tokio::pin!(notified);
        // Registered BEFORE the ask is published, so a refresh that lands
        // between publishing and waiting still wakes this waiter. The
        // generation re-check below closes the remaining sliver — a refresh
        // between reading `since_gen` and this `enable()`.
        notified.as_mut().enable();
        lane.request_credentials();
        if let Some(fresh) = self.refreshed_since(since_gen) {
            return Ok(fresh);
        }
        match tokio::time::timeout(self.wait, notified).await {
            Ok(()) => self
                .refreshed_since(since_gen)
                .ok_or_else(|| self.timed_out()),
            Err(_) => Err(self.timed_out()),
        }
    }

    /// The expiry answer. `Unavailable` and not `Unauthorized`: nothing was
    /// refused, nobody answered — and `Unauthorized` would make the adapter give
    /// up on the request instead of retrying the epoch.
    fn timed_out(&self) -> LaneError {
        LaneError::Unavailable(format!(
            "no fresh gx credentials for {} within {}s",
            self.reported_url,
            self.wait.as_secs()
        ))
    }
}

#[async_trait::async_trait]
impl GxCredentialSource for BridgeGxCredentials {
    async fn discover(&self, _reported_url: &str) -> Result<GxDiscovery, LaneError> {
        let first_of_pin = {
            let mut st = lock(&self.state);
            let first = st.asks_this_pin == 0;
            st.asks_this_pin = st.asks_this_pin.saturating_add(1);
            if first {
                if let Some(held) = st.held.clone() {
                    return Ok(held);
                }
            }
            first
        };
        // Either the second ask of this pin (the leader-restart path) or a first
        // ask with nothing held at all. Both want the same thing: a fresh read,
        // which on a phone means asking Dart.
        let _ = first_of_pin;
        self.ask_for_a_refresh().await
    }
}

/// [`FixedDial`], plus **the pin boundary** — the one thing the bridge needs
/// that the contract has no other seam for.
///
/// [`BridgeGxCredentials`] has to tell an epoch's FIRST ask from its second, and
/// `GxCredentialSource::discover` is handed only a URL. The signal exists
/// anyway, one layer down: `GxClient::ensure_pinned` takes its pin lock, calls
/// `transport.dial()` EXACTLY ONCE (`shed-gx/src/client.rs:323` — the only call
/// site in the crate), and only then decides whether to run `pin_epoch`. So
/// every `pin_epoch` is immediately preceded by exactly one `dial`, no
/// `discover` happens without one before it, and the whole sequence runs under
/// the pin lock — no concurrent dial can interleave. Resetting the ask counter
/// on `dial` is therefore an exact per-pin boundary rather than a heuristic.
///
/// The alternative was to time the gap between two asks, or to string-match
/// `pin_epoch`'s "gx lane instance changed" message — which the contract
/// explicitly forbids ("a caller branches on the variant, never on the text").
///
/// It delegates the dialling itself to [`FixedDial`], which shed-gx wrote for
/// exactly this case: the phone's local port is fixed (§3.10), so there is
/// nothing to ensure and nothing to move.
struct PinnedDial {
    dial: FixedDial,
    credentials: Arc<BridgeGxCredentials>,
}

impl PinnedDial {
    fn new(dial: FixedDial, credentials: Arc<BridgeGxCredentials>) -> PinnedDial {
        PinnedDial { dial, credentials }
    }
}

#[async_trait::async_trait]
impl GxTransport for PinnedDial {
    async fn dial(&self) -> Result<reqwest::Url, LaneError> {
        self.credentials.begin_pin();
        self.dial.dial().await
    }
}

// ---------------------------------------------------------------------------
// the runtime hop
// ---------------------------------------------------------------------------

/// Run `fut` on the persistent bridge runtime and await its result —
/// [`super::roost`]'s hop, with this module's error type.
///
/// Both of its reasons apply here and the second one is the sharp one: an
/// adapter's HTTP client and the pump it spawns outlive the call that made them,
/// and `tokio::spawn` binds a task to whatever runtime is current. Built on
/// FRB's per-call executor they would lose their reactor when the call returned.
async fn on_bridge_rt<T, F>(fut: F) -> Result<T, BridgeLaneError>
where
    F: Future<Output = Result<T, BridgeLaneError>> + Send + 'static,
    T: Send + 'static,
{
    match joined_on_bridge_rt(fut).await {
        Ok(res) => res,
        Err(e) => Err(BridgeLaneError::Failed {
            msg: format!("bridge task join error: {e}"),
        }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    use std::sync::atomic::AtomicU64;

    use shed_core::rc::RcFeedMessage;
    use shed_gx::testing::FakeGx;
    use shed_opencode::testing::FakeOpencode;

    use crate::api::bridge_rt::live_counters;
    use crate::api::testsupport::{test_guard, wait_until};

    /// **The `gx-probe` scenario's golden wire line, byte for byte.**
    ///
    /// This is the value shed's `tests/machine-transport/goldens/wire.json`
    /// holds under the key `gx-probe` — the ONE string that crosses SSH when the
    /// far side is asked to read gx's discovery. Three other legs pin it (the
    /// Rust `machine_transport_contract`, the LIVE leg through a throwaway sshd,
    /// and `shed-gx`'s own `probe_contract.rs` against `scenarios.json`); this
    /// is the fourth, and the only one that runs in shed-mobile's own tree.
    ///
    /// # To refresh it
    ///
    /// Do NOT retype it. In a shed checkout:
    ///
    /// ```text
    /// python3 -c 'import json; print(json.load(open("tests/machine-transport/goldens/wire.json"))["gx-probe"])'
    /// ```
    ///
    /// and paste the output between the raw-string delimiters below. A change to
    /// `shed_gx::PROBE_SCRIPT` requires re-recording BOTH machine-transport
    /// goldens (`UPDATE_GOLDEN=1`), bumping `scenarios.json`'s version, and
    /// re-running the Dart leg — this constant is the notice that all of that is
    /// due, not a thing to bring back into agreement on its own.
    const GX_PROBE_WIRE_GOLDEN: &str = r#"'sh' '-c' 'h=${GROK_HOME:-$HOME/.grok}
for f in "$h"/gx-remote*.json; do
  [ -f "$f" ] || continue
  cat "$f" 2>/dev/null
  printf "\n---\n"
done
printf "===token===\n"
t="$h/gx-remote.token"
find "$t" -prune -type f -perm 0600 -user "$(id -un)" -exec cat {} \; 2>/dev/null
exit 0
'"#;

    /// A 64-lowercase-hex token that is not the fakes' own, for the
    /// "no record matched" fixture — so the leak assertion has something
    /// distinctive to look for.
    const OTHER_TOKEN: &str = "beefcafe11223344556677889900aabbccddeeff00112233445566778899aabb";

    /// A capabilities row for a lane with no adapter behind it.
    fn bare_capabilities(kind: &str) -> BridgeLaneCapabilities {
        BridgeLaneCapabilities {
            kind: kind.to_string(),
            interject: false,
            create: false,
            cancel: false,
            approvals: false,
            history_cursor: false,
        }
    }

    /// A lane with **no adapter and no pump** — the shape the view, nudge and
    /// teardown tests want.
    ///
    /// It is counted exactly as [`lane_open`] counts one, so every leak
    /// assertion below is against the real counter and not a test-local
    /// substitute. `credentials` is bound both ways when supplied, the way
    /// `open_inner` binds it.
    fn bare_lane(credentials: Option<Arc<BridgeGxCredentials>>) -> BridgeLane {
        let inner = Arc::new(LaneInner {
            state: Mutex::new(LaneState {
                view: LaneView::default(),
                dirty: false,
                needs_credentials: false,
            }),
            tasks: Mutex::new(LaneTasks {
                client: None,
                pump: None,
                forwarder: None,
                streaming: false,
                closed: false,
            }),
            wake: tokio::sync::Notify::new(),
            session_id: "ses_test".to_string(),
            capabilities: bare_capabilities("test"),
            credentials: credentials.clone(),
        });
        if let Some(creds) = credentials.as_ref() {
            creds.bind(Arc::downgrade(&inner));
        }
        ACTIVE_LANES.fetch_add(1, Ordering::SeqCst);
        BridgeLane { inner }
    }

    /// A nudge sink that counts pushes, and optionally fails every one of them
    /// (the "Dart cancelled the stream without closing the lane" shape).
    #[derive(Clone)]
    struct CountingSink {
        count: Arc<AtomicU64>,
        fail: bool,
    }

    impl CountingSink {
        fn new(fail: bool) -> CountingSink {
            CountingSink {
                count: Arc::new(AtomicU64::new(0)),
                fail,
            }
        }

        fn pushes(&self) -> u64 {
            self.count.load(Ordering::SeqCst)
        }

        /// The push closure [`spawn_forwarder`] takes — the same argument
        /// production passes, so the lifecycle under test is the shipped one.
        fn push_fn(&self) -> impl Fn() -> NudgeResult + Send + 'static {
            let count = Arc::clone(&self.count);
            let fail = self.fail;
            move || {
                count.fetch_add(1, Ordering::SeqCst);
                if fail {
                    Err(())
                } else {
                    Ok(())
                }
            }
        }
    }

    fn message(seq: u64) -> LaneEvent {
        LaneEvent::Message {
            message: RcFeedMessage {
                seq,
                role: "assistant".to_string(),
                msg_type: "text".to_string(),
                text: Some(format!("m{seq}")),
                ..RcFeedMessage::default()
            },
            cursor: None,
        }
    }

    /// One discovery record plus a token, in exactly the grammar
    /// [`shed_gx::PROBE_SCRIPT`] prints.
    fn probe_stdout(url: &str, instance_id: &str, token: &str) -> Vec<u8> {
        format!(
            concat!(
                r#"{{"url":"{url}","pid":4242,"instanceId":"{instance}","#,
                r#""socketPath":"/run/user/1000/gx.sock","#,
                r#""tokenFile":"/home/shed/.grok/gx-remote.token","#,
                r#""version":"1.0.16+gx.12","startedAt":1788931000}}"#,
                "\n---\n===token===\n{token}\n"
            ),
            url = url,
            instance = instance_id,
            token = token
        )
        .into_bytes()
    }

    /// Poll `cond` on the test's own runtime — never [`wait_until`], which
    /// blocks the thread, and the in-process fakes' accept loops are spawned on
    /// the TEST runtime. Blocking it deadlocks them.
    async fn until(within: Duration, mut cond: impl FnMut() -> bool) -> bool {
        let deadline = std::time::Instant::now() + within;
        loop {
            if cond() {
                return true;
            }
            if std::time::Instant::now() >= deadline {
                return false;
            }
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    }

    // ---- dispatch ----

    /// **A kind with no adapter is refused BEFORE any I/O**, and the negative
    /// control is the point: a real server is standing right there on the dial
    /// URL and must see no request at all.
    ///
    /// It matters because the refusal is a permanent property of the row — there
    /// is no reason to spend a round trip discovering it, and on a phone that
    /// round trip is an SSH exec.
    #[tokio::test]
    async fn an_unsupported_kind_is_refused_before_any_io() {
        let _g = test_guard();
        let fake = FakeOpencode::start().await;
        // `let Err(..) else` rather than `expect_err`: a `BridgeLane` is opaque
        // and deliberately has no `Debug`, so the panic message cannot render
        // the Ok side.
        let Err(err) = lane_open(BridgeLaneSpec {
            kind: "claude-rc".to_string(),
            session_id: "ses_a".to_string(),
            reported_url: fake.base_url().to_string(),
            dial_url: fake.base_url().to_string(),
            gx_probe_stdout: None,
        })
        .await
        else {
            panic!("a kind with no adapter must be refused, not opened");
        };
        assert_eq!(
            err,
            BridgeLaneError::UnsupportedLane {
                kind: "claude-rc".to_string()
            },
            "the refusal must NAME the kind — a newer build may well speak it"
        );
        assert!(
            fake.get_paths().is_empty() && fake.post_paths().is_empty(),
            "the refusal dialled the server: {:?} / {:?}",
            fake.get_paths(),
            fake.post_paths()
        );
        assert_eq!(live_counters().active_lanes, 0);
    }

    /// The opencode arm, end to end against the real adapter: dispatch, the
    /// roster GET, the cached capabilities, and a teardown that returns every
    /// counter.
    #[tokio::test]
    async fn an_opencode_lane_dispatches_and_tears_down() {
        let _g = test_guard();
        let fake = FakeOpencode::start().await;
        fake.add_session("ses_a", "fix the thing", "/home/shed/proj", None);
        fake.set_status("ses_a", "idle");

        let lane = lane_open(BridgeLaneSpec {
            kind: "opencode".to_string(),
            session_id: "ses_a".to_string(),
            reported_url: fake.base_url().to_string(),
            dial_url: fake.base_url().to_string(),
            // Ignored on this arm, and supplied deliberately: an opencode lane
            // must not care.
            gx_probe_stdout: Some(b"junk".to_vec()),
        })
        .await
        .expect("the opencode lane opens");

        let caps = lane_capabilities(&lane);
        assert_eq!(caps.kind, "opencode");
        assert!(!caps.interject, "opencode cannot interject");
        assert!(!caps.history_cursor, "opencode has no history cursor");
        assert!(caps.approvals && caps.cancel && caps.create);
        assert_eq!(live_counters().active_lanes, 1);

        // No credential seam on this arm — a client that ran an SSH probe for it
        // has a bug worth hearing about.
        let refused = lane_refresh_credentials(&lane, b"anything".to_vec())
            .await
            .expect_err("an opencode lane needs no credentials");
        assert!(matches!(refused, BridgeLaneError::BadRequest { .. }));

        lane_close(&lane);
        assert_eq!(live_counters().active_lanes, 0);
        // Idempotent: a second close must not decrement again. The counters are
        // `u64`, so a double decrement would wrap to `u64::MAX` and every later
        // leak assertion would pass for the wrong reason.
        lane_close(&lane);
        lane_close(&lane);
        assert_eq!(live_counters().active_lanes, 0);
        // A closed lane still projects — a panel unwinding does not need its
        // reads to start throwing — and still answers for its capabilities.
        assert!(lane_snapshot(&lane, None).messages.is_empty());
        assert_eq!(lane_capabilities(&lane).kind, "opencode");
    }

    /// The gx arm: the probe's discovery is what pins the epoch, so a lane that
    /// opens at all is a lane whose bearer token was accepted.
    #[tokio::test]
    async fn a_gx_lane_dispatches_on_the_probes_discovery() {
        let _g = test_guard();
        let fake = FakeGx::start().await;
        fake.add_session(
            "ses_a",
            Some("fix the thing"),
            "/home/shed/proj",
            "idle",
            0,
            false,
        );
        let stdout = probe_stdout(&fake.reported_url(), &fake.instance_id(), &fake.token());

        let lane = lane_open(BridgeLaneSpec {
            kind: "gx".to_string(),
            session_id: "ses_a".to_string(),
            reported_url: fake.reported_url(),
            dial_url: fake.dial_url().to_string(),
            gx_probe_stdout: Some(stdout),
        })
        .await
        .expect("the gx lane opens");

        let caps = lane_capabilities(&lane);
        assert_eq!(caps.kind, "gx");
        assert!(caps.interject, "gx can interject");
        assert!(caps.history_cursor, "gx honors a history cursor");
        assert!(
            !fake.bearer_requests().is_empty(),
            "the roster GET must have travelled WITH a bearer: {:?}",
            fake.paths()
        );
        assert!(fake.violations().is_empty(), "{:?}", fake.violations());
        assert_eq!(live_counters().active_lanes, 1);

        lane_close(&lane);
        assert_eq!(live_counters().active_lanes, 0);
    }

    /// One record block, verbatim — so a test can plant an unparseable one.
    fn record_block(url: &str, instance_id: &str, socket: &str) -> String {
        format!(
            concat!(
                r#"{{"url":"{url}","pid":4242,"instanceId":"{instance}","#,
                r#""socketPath":"{socket}","#,
                r#""tokenFile":"/home/shed/.grok/gx-remote.token","#,
                r#""version":"1.0.16+gx.12","startedAt":1788931000}}"#,
                "\n---\n"
            ),
            url = url,
            instance = instance_id,
            socket = socket
        )
    }

    /// **Every way a probe can be refused, and NOT ONE of them carries a byte of
    /// the probe.**
    ///
    /// The bytes are one `cat` away from being a bearer token, so this is not
    /// "the message is tidy": it is that neither a token, nor an instance id,
    /// nor another host's URL, nor a marker planted anywhere in the stdout
    /// survives into anything a caller can read or log. Table-driven because
    /// there are FOUR refusal paths through `discovery_from_probe` and a test
    /// that exercised one of them would leave the other three unguarded — which
    /// is exactly what an earlier version of this test did (its fixture's
    /// trailing marker made `parse_probe` answer `MalformedToken`, so the
    /// no-record path it was named for never ran).
    #[tokio::test]
    async fn every_gx_probe_refusal_echoes_no_byte_of_the_probe() {
        let _g = test_guard();
        let fake = FakeGx::start().await;
        let mine = fake.reported_url();

        let cases: Vec<(&str, String)> = vec![
            // 1. The records parse and the token is fine, but NONE of them
            //    names this lane. Plus an unparseable block, so the
            //    unreadable-record path is walked too.
            (
                "no record for this url",
                format!(
                    "{}{}===token===\n{OTHER_TOKEN}\n",
                    record_block(
                        "http://127.0.0.1:59999",
                        "inst-elsewhere",
                        "/run/user/1000/MARKER-e7f1c0de.sock"
                    ),
                    "{ this block is not json: MARKER-e7f1c0de }\n---\n",
                ),
            ),
            // 2. The record is ours, and the token file's CONTENTS are wrong —
            //    `parse_probe`'s `MalformedToken`.
            (
                "a malformed token",
                format!(
                    "{}===token===\nMARKER-e7f1c0de not a token\n",
                    record_block(&mine, "inst-A", "/run/user/1000/gx.sock")
                ),
            ),
            // 3. The sentinel never arrived — the probe did not run to
            //    completion. `parse_probe`'s `Truncated`.
            (
                "a truncated probe",
                record_block(&mine, "inst-A", "/run/user/1000/MARKER-e7f1c0de.sock"),
            ),
            // 4. Our record, sentinel present, and no token behind it: the file
            //    failed one of gx's three eligibility checks on the far side.
            (
                "no readable token",
                format!(
                    "{}===token===\n",
                    record_block(&mine, "MARKER-e7f1c0de", "/run/user/1000/gx.sock")
                ),
            ),
        ];

        for (what, stdout) in cases {
            let Err(err) = lane_open(BridgeLaneSpec {
                kind: "gx".to_string(),
                session_id: "ses_a".to_string(),
                reported_url: mine.clone(),
                dial_url: fake.dial_url().to_string(),
                gx_probe_stdout: Some(stdout.clone().into_bytes()),
            })
            .await
            else {
                panic!("{what}: a probe this broken must refuse, not open a lane");
            };

            assert!(
                matches!(err, BridgeLaneError::Unavailable { .. }),
                "{what}: a lane that cannot be reached is QUIET, not loud: {err:?}"
            );
            // `Debug` is the widest surface a plain enum has — there is no
            // `Display` and no `Serialize` — so it is what the audit reads.
            let rendered = format!("{err:?}");
            for secret in [
                OTHER_TOKEN,
                "inst-elsewhere",
                "127.0.0.1:59999",
                "MARKER-e7f1c0de",
                "gx-remote.token",
                "/run/user/1000",
            ] {
                assert!(
                    !rendered.contains(secret),
                    "{what}: the refusal leaked {secret:?} from the probe: {rendered}"
                );
            }
            // Negative control for the loop above: it must be reading a real
            // message, not an empty one. The reported URL is the ONE thing the
            // refusal is allowed — and required — to name.
            assert!(
                rendered.contains(&mine),
                "{what}: the refusal must say which lane it was: {rendered}"
            );
            assert!(
                fake.paths().is_empty(),
                "{what}: the refusal dialled the agent: {:?}",
                fake.paths()
            );
            assert_eq!(live_counters().active_lanes, 0);
        }

        // And the same for a gx spec with NO probe at all — the caller forgot to
        // run it, which is still "this lane cannot be reached".
        let Err(err) = lane_open(BridgeLaneSpec {
            kind: "gx".to_string(),
            session_id: "ses_a".to_string(),
            reported_url: mine.clone(),
            dial_url: fake.dial_url().to_string(),
            gx_probe_stdout: None,
        })
        .await
        else {
            panic!("a gx lane with no probe must refuse");
        };
        assert!(
            matches!(err, BridgeLaneError::Unavailable { .. }),
            "{err:?}"
        );
    }

    /// The pump, the fold and the nudge, end to end against the real adapter:
    /// the view fills without Dart having seen a single frame.
    #[tokio::test]
    async fn the_pump_folds_a_live_subscription_into_the_view() {
        let _g = test_guard();
        let fake = FakeOpencode::start().await;
        fake.add_session("ses_a", "fix the thing", "/home/shed/proj", None);
        fake.set_status("ses_a", "busy");
        fake.set_simple_transcript("ses_a", "do the thing", "doing the thing");

        let lane = lane_open(BridgeLaneSpec {
            kind: "opencode".to_string(),
            session_id: "ses_a".to_string(),
            reported_url: fake.base_url().to_string(),
            dial_url: fake.base_url().to_string(),
            gx_probe_stdout: None,
        })
        .await
        .expect("the lane opens");

        assert!(
            until(Duration::from_secs(10), || !lane_snapshot(&lane, None)
                .messages
                .is_empty())
            .await,
            "the pump never folded the seed into the view"
        );
        let snap = lane_snapshot(&lane, None);
        assert!(snap.full, "a cursorless read is a full read");
        assert_eq!(snap.stale, None, "a live generation is not stale");
        assert!(
            snap.generation >= 1,
            "a completed seed moves the generation"
        );
        assert!(!snap.needs_credentials, "opencode asks for no credentials");

        lane_close(&lane);
        assert_eq!(live_counters().active_lanes, 0);
    }

    /// **The terminal `Down`**: the pump ends, the view is marked stale with the
    /// reason, and the NUDGE STREAM STAYS OPEN — which is the whole of how Dart
    /// tells "stale, re-open me" from "closed by me".
    #[tokio::test]
    async fn a_deleted_session_ends_the_pump_stale_but_leaves_the_stream_open() {
        let _g = test_guard();
        let fake = FakeOpencode::start().await;
        fake.add_session("ses_a", "fix the thing", "/home/shed/proj", None);
        fake.set_status("ses_a", "idle");

        let lane = lane_open(BridgeLaneSpec {
            kind: "opencode".to_string(),
            session_id: "ses_a".to_string(),
            reported_url: fake.base_url().to_string(),
            dial_url: fake.base_url().to_string(),
            gx_probe_stdout: None,
        })
        .await
        .expect("the lane opens");
        let sink = CountingSink::new(false);
        assert!(spawn_forwarder(&lane.inner, sink.push_fn()));

        // The session goes away and the stream is cut, so the adapter reseeds
        // into a 404.
        fake.remove_session("ses_a");
        fake.close_streams();

        assert!(
            until(Duration::from_secs(15), || lane_snapshot(&lane, None)
                .stale
                .is_some())
            .await,
            "a deleted session never marked the view stale"
        );
        assert_eq!(
            lane_snapshot(&lane, None).stale.as_deref(),
            Some(DOWN_UNKNOWN_SESSION),
            "the terminal reason is the adapter's own, not a paraphrase"
        );
        // Awaited for the reason above: the push lands on `bridge_rt`, not on
        // this thread.
        assert!(
            until(Duration::from_secs(5), || sink.pushes() >= 1).await,
            "the last Down raised no nudge"
        );
        // Still counted: the pump is finished, the lane is not.
        assert_eq!(live_counters().active_lanes, 1);
        assert_eq!(live_counters().active_lane_forwarders, 1);

        lane_close(&lane);
        assert!(
            until(Duration::from_secs(5), || live_counters().active_lanes == 0).await,
            "close left the counters at {:?}",
            (
                live_counters().active_lanes,
                live_counters().active_lane_forwarders
            )
        );
        assert_eq!(live_counters().active_lane_forwarders, 0);
    }

    // ---- the nudge ----

    /// **A hundred frames are ONE nudge, and the snapshot is the
    /// acknowledgement.**
    ///
    /// The property the whole design rests on: the nudge is the dirty bit's
    /// clean→dirty transition, and [`lane_snapshot`] is what clears it. So a
    /// burst costs one wakeup, and the first frame after a read costs the next
    /// one. A bare `Notify` per frame would give Dart a hundred snapshots to
    /// take; a `Notify` with no bit would lose the wakeup that arrived while the
    /// forwarder was mid-push.
    #[test]
    fn a_burst_is_one_nudge_and_the_next_frame_is_the_next_nudge() {
        let _g = test_guard();
        let lane = bare_lane(None);
        let sink = CountingSink::new(false);
        assert!(spawn_forwarder(&lane.inner, sink.push_fn()));

        for seq in 1..=100u64 {
            lane.inner.apply(&message(seq));
        }
        assert!(
            wait_until(Duration::from_secs(5), || sink.pushes() >= 1),
            "the burst raised no nudge at all"
        );
        // Settle, then assert it is still exactly one: frames 2..=100 found the
        // bit already dirty and must have notified nobody.
        std::thread::sleep(Duration::from_millis(100));
        assert_eq!(
            sink.pushes(),
            1,
            "a hundred un-acknowledged frames produced more than one nudge"
        );

        // The acknowledgement. It also proves the burst was FOLDED, not merely
        // counted — a nudge with no rows behind it would be worse than none.
        let snap = lane_snapshot(&lane, None);
        assert_eq!(snap.messages.len(), 100);
        assert!(snap.full);

        lane.inner.apply(&message(101));
        assert!(
            wait_until(Duration::from_secs(5), || sink.pushes() >= 2),
            "the first frame after a snapshot raised no nudge"
        );
        std::thread::sleep(Duration::from_millis(100));
        assert_eq!(sink.pushes(), 2, "one frame produced more than one nudge");
        // And a delta read answers only what arrived since — the cursor cut is
        // `LaneView`'s and this is the wiring, not a second implementation.
        let delta = lane_snapshot(&lane, Some(100));
        assert!(!delta.full);
        assert_eq!(delta.messages.len(), 1);

        lane_close(&lane);
        assert_eq!(live_counters().active_lane_forwarders, 0);
        assert_eq!(live_counters().active_lanes, 0);
    }

    /// One claim. A second nudge stream on one handle would silently split the
    /// nudges between two consumers — and a nudge is not repeatable, so the
    /// consumer that missed one would sit on a stale view for ever.
    #[test]
    fn a_second_nudge_claim_is_refused() {
        let _g = test_guard();
        let lane = bare_lane(None);
        assert!(spawn_forwarder(
            &lane.inner,
            CountingSink::new(false).push_fn()
        ));
        let second = CountingSink::new(false);
        assert!(
            !spawn_forwarder(&lane.inner, second.push_fn()),
            "a second claim must be refused"
        );
        assert_eq!(
            live_counters().active_lane_forwarders,
            1,
            "the refused claim was counted"
        );

        lane.inner.apply(&message(1));
        std::thread::sleep(Duration::from_millis(100));
        assert_eq!(second.pushes(), 0, "the refused sink received a nudge");

        lane_close(&lane);
        // Negative control: a claim on a CLOSED lane is refused too, and
        // counted nowhere.
        assert!(!spawn_forwarder(
            &lane.inner,
            CountingSink::new(false).push_fn()
        ));
        assert_eq!(live_counters().active_lane_forwarders, 0);
        assert_eq!(live_counters().active_lanes, 0);
    }

    /// **Self-teardown**: a Dart consumer that cancelled the stream without
    /// calling [`lane_close`] must not leave the pump subscribing, folding and
    /// holding a connection with nobody reading it.
    #[test]
    fn a_forwarder_whose_sink_is_gone_tears_the_lane_down() {
        let _g = test_guard();
        let lane = bare_lane(None);
        let sink = CountingSink::new(true);
        assert!(spawn_forwarder(&lane.inner, sink.push_fn()));
        assert_eq!(live_counters().active_lanes, 1);

        lane.inner.apply(&message(1));
        assert!(
            wait_until(Duration::from_secs(5), || live_counters().active_lanes == 0),
            "a failed push left the lane alive"
        );
        assert_eq!(sink.pushes(), 1, "it should have tried exactly once");
        assert_eq!(live_counters().active_lane_forwarders, 0);
        assert!(lock(&lane.inner.tasks).closed);

        // And the later `lane_close` / `Drop` still costs exactly one
        // decrement, which is what `teardown`'s latch is for.
        lane_close(&lane);
        assert_eq!(live_counters().active_lanes, 0);
        assert_eq!(live_counters().active_lane_forwarders, 0);
    }

    /// `Drop` is the backstop: a handle Dart lets go of without closing must
    /// still return every counter.
    #[test]
    fn dropping_the_handle_tears_the_lane_down() {
        let _g = test_guard();
        {
            let lane = bare_lane(None);
            assert!(spawn_forwarder(
                &lane.inner,
                CountingSink::new(false).push_fn()
            ));
            assert_eq!(live_counters().active_lanes, 1);
        }
        assert_eq!(live_counters().active_lanes, 0);
        assert_eq!(live_counters().active_lane_forwarders, 0);
    }

    // ---- gx credentials ----

    fn discovery(instance_id: &str, token: &str) -> GxDiscovery {
        discovery_from_probe(
            &probe_stdout("http://127.0.0.1:2431", instance_id, token),
            "http://127.0.0.1:2431",
        )
        .expect("the fixture probe parses")
    }

    fn creds_lane(wait: Duration) -> (Arc<BridgeGxCredentials>, BridgeLane) {
        let creds = Arc::new(BridgeGxCredentials::new(
            "http://127.0.0.1:2431",
            discovery("inst-A", shed_gx::testing::SENTINEL_TOKEN),
            wait,
        ));
        let lane = bare_lane(Some(Arc::clone(&creds)));
        (creds, lane)
    }

    /// **The held discovery is answered on the FIRST ask of EVERY pin.**
    ///
    /// `pin_epoch` asks at the start of every epoch, and an epoch is opened by
    /// every stream reconnect — so a source that served once and then refused
    /// would not degrade a reconnect, it would end the lane. Five pins, five
    /// answers, no Dart involved.
    #[tokio::test]
    async fn the_credential_source_answers_the_first_ask_of_every_pin() {
        let _g = test_guard();
        let (creds, lane) = creds_lane(Duration::from_millis(50));
        for pin in 0..5 {
            // What `PinnedDial::dial` does, and the only per-pin boundary the
            // contract exposes.
            creds.begin_pin();
            let got = creds
                .discover("http://127.0.0.1:2431")
                .await
                .unwrap_or_else(|e| panic!("pin {pin} was refused a credential: {e}"));
            assert_eq!(got.instance_id, "inst-A");
        }
        assert!(
            !lane_snapshot(&lane, None).needs_credentials,
            "answering from the held discovery must ask Dart for nothing"
        );

        // Negative control: the SECOND ask inside ONE pin does NOT get the held
        // value — that ask exists because the value was just rejected. With
        // nobody answering it, it expires.
        creds.begin_pin();
        creds
            .discover("x")
            .await
            .expect("the first ask is answered");
        let err = creds
            .discover("x")
            .await
            .expect_err("a second ask within one pin must not re-serve the stale value");
        assert!(matches!(err, LaneError::Unavailable(_)), "{err:?}");
        assert!(
            lane_snapshot(&lane, None).needs_credentials,
            "the second ask must raise the flag Dart reads"
        );

        lane_close(&lane);
    }

    /// **The leader restart, recovered in place.** The second ask within one pin
    /// raises the flag, nudges, and AWAITS — and
    /// [`lane_refresh_credentials`] resumes pinning with a fresh instance. No
    /// `Down`, no re-open.
    #[tokio::test]
    async fn a_second_ask_within_one_pin_awaits_a_refresh() {
        let _g = test_guard();
        let (creds, lane) = creds_lane(CREDENTIAL_REFRESH_WAIT);
        let sink = CountingSink::new(false);
        assert!(spawn_forwarder(&lane.inner, sink.push_fn()));

        creds.begin_pin();
        assert_eq!(
            creds
                .discover("x")
                .await
                .expect("the first ask")
                .instance_id,
            "inst-A"
        );

        // The two halves of the rendezvous, concurrently: the adapter asking,
        // and the controller answering what it read off a snapshot.
        let asking = creds.discover("x");
        let answering = async {
            assert!(
                until(Duration::from_secs(5), || {
                    lane_snapshot(&lane, None).needs_credentials
                })
                .await,
                "the ask never reached Dart"
            );
            lane_refresh_credentials(
                &lane,
                probe_stdout(
                    "http://127.0.0.1:2431",
                    "inst-B",
                    shed_gx::testing::SENTINEL_TOKEN,
                ),
            )
            .await
            .expect("a fresh probe is accepted");
        };
        let (got, ()) = tokio::join!(asking, answering);
        assert_eq!(
            got.expect("the awaited ask is answered").instance_id,
            "inst-B",
            "the ask must be answered with the FRESH discovery, not the stale one"
        );
        assert!(
            !lane_snapshot(&lane, None).needs_credentials,
            "a delivered refresh must clear the ask"
        );
        // Awaited, not asserted: the forwarder runs on `bridge_rt`'s own
        // threads, so "the permit was stored" and "the push happened" are
        // different instants. Reading the count the moment `join!` returns was
        // a real intermittent failure.
        assert!(
            until(Duration::from_secs(5), || sink.pushes() >= 1).await,
            "the ask raised no nudge"
        );

        lane_close(&lane);
    }

    /// The bound, proved against the REAL constant.
    ///
    /// `start_paused` is what makes that possible: `tokio::time` auto-advances a
    /// paused clock to the next timer whenever the runtime is idle, so the
    /// thirty seconds elapse in microseconds and the test asserts the shipped
    /// value rather than an injected stand-in.
    ///
    /// `Unavailable` and not `Unauthorized` on expiry: nothing was refused,
    /// nobody answered — and `Unauthorized` would make the adapter abandon the
    /// request instead of retrying the epoch.
    #[tokio::test(start_paused = true)]
    async fn an_unanswered_ask_expires_to_unavailable_at_the_bound() {
        let _g = test_guard();
        let (creds, lane) = creds_lane(CREDENTIAL_REFRESH_WAIT);

        creds.begin_pin();
        creds.discover("x").await.expect("the first ask");

        let started = tokio::time::Instant::now();
        let err = creds
            .discover("x")
            .await
            .expect_err("an unanswered ask must expire");
        let waited = started.elapsed();
        assert!(matches!(err, LaneError::Unavailable(_)), "{err:?}");
        assert_eq!(
            waited, CREDENTIAL_REFRESH_WAIT,
            "the ask expired after {waited:?}, not the shipped bound"
        );
        // The flag stays up: Dart has not answered, so the next snapshot must
        // still tell it to.
        assert!(lane_snapshot(&lane, None).needs_credentials);

        // Negative control for the bound being a BOUND: an answer that lands
        // just inside it is honored, and the ask does not wait the full window.
        creds.begin_pin();
        creds
            .discover("x")
            .await
            .expect("the first ask of a new pin");
        let started = tokio::time::Instant::now();
        let asking = creds.discover("x");
        let answering = async {
            tokio::time::sleep(CREDENTIAL_REFRESH_WAIT - Duration::from_secs(1)).await;
            lane_refresh_credentials(
                &lane,
                probe_stdout(
                    "http://127.0.0.1:2431",
                    "inst-C",
                    shed_gx::testing::SENTINEL_TOKEN,
                ),
            )
            .await
            .expect("a fresh probe is accepted");
        };
        let (got, ()) = tokio::join!(asking, answering);
        assert_eq!(got.expect("answered in time").instance_id, "inst-C");
        assert!(started.elapsed() < CREDENTIAL_REFRESH_WAIT);

        lane_close(&lane);
    }

    /// **The dial hook IS the pin boundary**, which is the one design decision
    /// [`PinnedDial`] exists for: `GxCredentialSource::discover` is handed only
    /// a URL, so without this the source could not tell an epoch's first ask
    /// from its second, and the alternatives were timing the gap or
    /// string-matching an error message the contract forbids branching on.
    ///
    /// Asserted THROUGH the `GxTransport` impl rather than by calling
    /// `begin_pin` directly, so a refactor that drops the reset from `dial`
    /// fails here.
    #[tokio::test]
    async fn the_dial_hook_is_the_pin_boundary() {
        let _g = test_guard();
        let (creds, lane) = creds_lane(Duration::from_millis(50));
        let transport = PinnedDial::new(
            FixedDial::parse("http://127.0.0.1:2431").expect("the dial url parses"),
            Arc::clone(&creds),
        );

        for pin in 0..3 {
            let dialled = transport.dial().await.expect("FixedDial always answers");
            assert_eq!(dialled.as_str(), "http://127.0.0.1:2431/");
            let got = creds
                .discover("x")
                .await
                .unwrap_or_else(|e| panic!("pin {pin}'s first ask was refused: {e}"));
            assert_eq!(got.instance_id, "inst-A");
        }

        // Negative control: with NO dial in between, the next ask is a second
        // ask within the same pin — the leader-restart path — and it awaits
        // rather than re-serving the value that was just rejected.
        let err = creds
            .discover("x")
            .await
            .expect_err("a second ask within one pin must not be re-served");
        assert!(matches!(err, LaneError::Unavailable(_)), "{err:?}");

        lane_close(&lane);
    }

    /// An ask on a lane that has gone away answers quietly rather than parking
    /// for thirty seconds: there is nobody left to ask.
    #[tokio::test]
    async fn an_ask_on_a_closed_lane_answers_at_once() {
        let _g = test_guard();
        let (creds, lane) = creds_lane(CREDENTIAL_REFRESH_WAIT);
        creds.begin_pin();
        creds.discover("x").await.expect("the first ask");
        lane_close(&lane);
        drop(lane);

        let started = std::time::Instant::now();
        let err = creds.discover("x").await.expect_err("nobody left to ask");
        assert!(matches!(err, LaneError::Unavailable(_)), "{err:?}");
        assert!(
            started.elapsed() < Duration::from_secs(5),
            "it waited for a lane that is gone"
        );
        assert_eq!(live_counters().active_lanes, 0);
    }

    // ---- the probe command ----

    /// **The probe line is a shared contract, pinned byte for byte.**
    ///
    /// SSH has no argv API: this crosses as ONE string the far side re-parses,
    /// so the phone's `dartssh2` and the desktop's `ssh` binary must put
    /// identical bytes on the wire. See [`GX_PROBE_WIRE_GOLDEN`] for how to
    /// refresh it and what else has to move with it.
    #[test]
    fn the_probe_remote_command_is_the_machine_transport_golden() {
        assert_eq!(
            gx_probe_remote_command(),
            GX_PROBE_WIRE_GOLDEN,
            "the probe line drifted from tests/machine-transport's `gx-probe` \
             golden. See GX_PROBE_WIRE_GOLDEN's doc: whichever side changed, \
             BOTH machine-transport goldens must be re-recorded, \
             scenarios.json's version bumped, and this constant re-pasted."
        );
        // Negative controls: it is the QUOTED line and not the script, and the
        // script really is in it whole. Either alone would pass for a quoter
        // that dropped the payload or one that did no quoting at all.
        assert!(gx_probe_remote_command().starts_with("'sh' '-c' '"));
        assert_ne!(gx_probe_remote_command(), shed_gx::PROBE_SCRIPT);
        assert!(gx_probe_remote_command().contains(shed_gx::PROBE_SCRIPT));
    }

    /// The backoff ladder doubles to the ceiling and stops there — the
    /// desktop's `next_backoff`, so a lane that comes back there comes back
    /// here at the same cadence.
    #[test]
    fn the_backoff_doubles_to_the_ceiling_and_stays() {
        let mut d = RESUBSCRIBE_BASE;
        let mut steps = 0;
        while d < RESUBSCRIBE_MAX {
            d = next_backoff(d);
            steps += 1;
            assert!(steps < 20, "the ladder never reached the ceiling");
        }
        assert_eq!(d, RESUBSCRIBE_MAX);
        assert_eq!(next_backoff(d), RESUBSCRIBE_MAX, "the ceiling must hold");
    }
}
