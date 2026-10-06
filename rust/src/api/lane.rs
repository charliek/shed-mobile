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
//!   resubscribe ladder. Dart's only lifecycle job is re-opening after a
//!   terminal `Down` (§3.11), and it re-opens only on the snapshot's `ended` —
//!   never on `stale`, which an adapter's silent resume sets and clears again
//!   without the lane ever ending (plan 025 §3.2.4). Re-opening there would
//!   throw away the cursor the resume is using.
//!
//! # The snapshot IS the nudge acknowledgement
//!
//! [`LaneInner::apply`] folds every frame under the view lock and, **if the
//! dirty bit was clean**, sets it and wakes the forwarder once; the forwarder
//! pushes one `true`. [`lane_snapshot`] takes the SAME lock, projects the view
//! plus the approvals, and clears the dirty bit. So a burst of a hundred frames
//! with no snapshot in between yields exactly one nudge, and the first frame
//! after a snapshot yields the next one.
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
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::Duration;

use flutter_rust_bridge::frb;
use shed_app::lane_view::LaneView;
use shed_core::lane::{AgentLane, AgentSource, LaneError, LaneEvent};
use shed_opencode::OpencodeSource;

use crate::frb_generated::StreamSink;

use super::bridge_rt::{bridge_rt, joined_on_bridge_rt, ACTIVE_LANES, ACTIVE_LANE_FORWARDERS};
use super::dto_lane::{BridgeLaneAnswer, BridgeLaneError, BridgeLaneSnapshot, BridgeSendMode};

/// The `agent_lane` kinds THIS BUILD has an adapter for.
///
/// Three readers: [`lane_open`]'s pre-dispatch guard and the refusal it
/// raises; [`super::dto_rc::BridgeRcSession::from_roost_dto`], which drops any
/// stamp whose kind is not here so a row never offers a Transcript this build
/// cannot open (plan 025 CM1 finding 3 — at the pinned shed rev roost still
/// yields a `gx` stamp, and an unfiltered DTO conversion let a tap acquire a
/// forward and open a `LaneScreen` that `lane_open` would then refuse). The
/// `match` in [`build_client`] is deliberately not a fourth — that is where a
/// kind binds to a constructor, the one place a concrete adapter type may be
/// named.
pub(crate) const LANE_KINDS: [&str; 1] = ["opencode"];

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

/// Take a lock, ignoring poisoning — [`super::roost`]'s rule, for the same
/// reason: every mutex here guards plain data, and turning one unrelated panic
/// into a permanently dead lane layer is strictly worse than reading a slightly
/// stale view.
fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

// ---------------------------------------------------------------------------
// the handle
// ---------------------------------------------------------------------------

/// Everything [`lane_open`] needs to build one lane — the row's stamp plus the
/// two things only the phone's transport knows.
///
/// **`reported_url` and `dial_url` are different values and are never
/// conflated.** `reported_url` is the loopback URL the agent announced on ITS
/// host; `dial_url` is where this phone actually reaches it — the near end of the
/// `RoostTunnel`-shaped forward Dart already holds, or the same address again
/// when the agent is on this device. The contract is explicit that an
/// implementation which dialled the reported URL would be wrong over SSH.
pub struct BridgeLaneSpec {
    /// `"opencode"`. Anything else is
    /// [`BridgeLaneError::UnsupportedLane`], refused before any I/O.
    pub kind: String,
    pub session_id: String,
    pub reported_url: String,
    pub dial_url: String,
}

/// The staged view and the dirty flag a snapshot reads — **all under one
/// lock**.
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
    /// The agent session id the lane is bound to — the adapter holds the same
    /// id (`AgentLane::session_id`); this copy names it in a refusal.
    ///
    /// There is no cached capabilities field beside it any more (plan 025
    /// §3.2.1): capabilities are per session and ride the stream, so the view
    /// holds them and [`lane_snapshot`] projects them. A copy taken at open is
    /// stale by construction before the first seed.
    session_id: String,
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

    /// Record a failure THIS layer saw — a `subscribe` that was refused before
    /// any stream existed — as a [`LaneEvent::Down`]: stale with a reason, and
    /// ENDED.
    ///
    /// Ended, not merely stale (the desktop says `Stale` here, and the phone
    /// deliberately does not): on the phone it is Dart's re-open that
    /// re-acquires a forward the machine's feed may have lost underneath this
    /// lane, so a failure before the stream is what Dart must hear as "re-open
    /// me". The pump keeps its own ladder going meanwhile, and Dart's re-open
    /// supersedes it. An ADAPTER's `Stale` — a transport loss it is resuming
    /// across with its cursor intact — is folded as it stands and ends nothing.
    ///
    /// The panel must not care whether the thing that went away was the agent or
    /// the reach to it: both mean "this transcript is not live", and both are
    /// recovered by the same retry.
    fn note_down(&self, reason: String) {
        self.apply(&LaneEvent::Down { reason });
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
/// an [`OpencodeSource`] on the dial URL with no credential source (opencode
/// needs none — a password-protected server answers 401, which surfaces as
/// [`BridgeLaneError::Unauthorized`] and a status-only panel), and the
/// session-scoped lane it opens for the row's id (plan 025 §3.2.6); anything
/// else → [`BridgeLaneError::UnsupportedLane`] **before any I/O**, because a
/// kind with no adapter is a permanent property of the row and there is no
/// reason to spend a round trip discovering it.
///
/// The roster row is fetched BEFORE the subscription starts, for the desktop's
/// reason: a 404 here is an honest `unknown_session` the caller can render,
/// where the same failure inside the pump would be a `Down` the panel has to
/// wait for. It is also the call that fails on a password-protected agent.
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
    let client = build_client(&spec).await?;
    // The roster GET: it is also the call that fails on a password-protected
    // agent, so a 404 here is an honest `unknown_session` the caller can
    // render before the pump ever starts. (Opening the lane above was binding,
    // not dialling — this is the first I/O.)
    client.session().await.map_err(BridgeLaneError::from)?;

    let inner = Arc::new(LaneInner {
        state: Mutex::new(LaneState {
            view: LaneView::default(),
            dirty: false,
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
    });

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
/// Through the adapter's SOURCE, the contract's two levels (plan 025 §3.2.1):
/// the source is built on the dial URL and `open`s the session-scoped lane for
/// the row's id — binding, not dialling, so nothing here touches the network.
/// The source is dropped once it has opened the lane; the lane holds the
/// transport it shares with it.
async fn build_client(spec: &BridgeLaneSpec) -> Result<Arc<dyn AgentLane>, BridgeLaneError> {
    match spec.kind.as_str() {
        "opencode" => {
            let url =
                reqwest::Url::parse(&spec.dial_url).map_err(|e| BridgeLaneError::BadRequest {
                    msg: format!(
                        "the agent server dial url {:?} is not usable: {e}",
                        spec.dial_url
                    ),
                })?;
            let source = OpencodeSource::new(url, None).map_err(BridgeLaneError::from)?;
            source
                .open(&spec.session_id)
                .await
                .map_err(BridgeLaneError::from)
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
        let mut backoff = RESUBSCRIBE_BASE;
        loop {
            let subscription = match client.subscribe(None).await {
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
                    // An adapter's `Stale` is it retrying on its own, cursor
                    // intact: keep reading. Folded into the view (the banner)
                    // like any other frame, and that is all — it ends nothing.
                    _ => {}
                }
                // The fold and the nudge, in that order and under one lock. The
                // terminal `Down` above therefore ALSO marks the view ended and
                // raises the last nudge — which is what lets Dart tell "ended,
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
/// terminal `Down`: that is how Dart distinguishes "ended, re-open me" (the
/// snapshot says `ended`) from "closed by me" (it called `lane_close`). A stream
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

/// **The one read**, and the nudge acknowledgement: the staged view projected
/// — the transcript, the pending approvals, and the session's live row,
/// capabilities and settings — under ONE lock, and the dirty bit cleared.
///
/// It is also where a panel reads what the session can do. There is no
/// `lane_capabilities` getter (plan 025 §3.2.1): capabilities are per session
/// and ride the stream, so a getter cached at open would be stale by
/// construction before the first seed. A closed lane still projects its last
/// view, capabilities included, so a panel unwinding keeps its buttons.
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
    BridgeLaneSnapshot::from_view(s.view.snapshot(since_seq))
}

// ---------------------------------------------------------------------------
// writes
// ---------------------------------------------------------------------------

/// Send `text` to the session. [`BridgeSendMode::Interject`] needs the
/// snapshot's [`super::dto_lane::BridgeLaneCapabilities::interject`]; an adapter
/// that cannot do it answers [`BridgeLaneError::NotAccepting`].
pub async fn lane_send(
    lane: &BridgeLane,
    text: String,
    mode: BridgeSendMode,
) -> Result<(), BridgeLaneError> {
    let client = lane.inner.client()?;
    on_bridge_rt(async move {
        client
            .send(&text, mode.into())
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
    on_bridge_rt(async move { client.cancel().await.map_err(BridgeLaneError::from) }).await
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
    on_bridge_rt(async move {
        client
            .answer(&approval_id, answer.into())
            .await
            .map_err(BridgeLaneError::from)
    })
    .await
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
    use shed_opencode::testing::FakeOpencode;

    use shed_core::lane::LaneCapabilities;

    use crate::api::bridge_rt::live_counters;
    use crate::api::testsupport::{test_guard, wait_until};

    /// A lane with **no adapter and no pump** — the shape the view, nudge and
    /// teardown tests want.
    ///
    /// It is counted exactly as [`lane_open`] counts one, so every leak
    /// assertion below is against the real counter and not a test-local
    /// substitute.
    fn bare_lane() -> BridgeLane {
        let inner = Arc::new(LaneInner {
            state: Mutex::new(LaneState {
                view: LaneView::default(),
                dirty: false,
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
        });
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

    /// The opencode arm, end to end against the real adapter: dispatch through
    /// `OpencodeSource`, the roster GET, the capabilities the SEED carries, and
    /// a teardown that returns every counter.
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
        })
        .await
        .expect("the opencode lane opens");

        // From the snapshot, once the seed has swapped in — there is no getter
        // to read them from at open (plan 025 §3.2.1).
        assert!(
            until(Duration::from_secs(10), || lane_snapshot(&lane, None)
                .capabilities
                .is_some())
            .await,
            "the seed never carried the session's capabilities into the view"
        );
        let caps = lane_snapshot(&lane, None)
            .capabilities
            .expect("seeded capabilities");
        assert_eq!(caps.kind, "opencode");
        assert!(!caps.interject, "opencode cannot interject");
        assert!(!caps.history_cursor, "opencode has no history cursor");
        assert!(caps.approvals && caps.cancel);
        assert!(
            !caps.settings && !caps.stop,
            "opencode has no settings and cannot be stopped from here"
        );
        assert_eq!(live_counters().active_lanes, 1);

        lane_close(&lane);
        assert_eq!(live_counters().active_lanes, 0);
        // Idempotent: a second close must not decrement again. The counters are
        // `u64`, so a double decrement would wrap to `u64::MAX` and every later
        // leak assertion would pass for the wrong reason.
        lane_close(&lane);
        lane_close(&lane);
        assert_eq!(live_counters().active_lanes, 0);
        // A closed lane still projects — a panel unwinding does not need its
        // reads to start throwing — capabilities included.
        let closed = lane_snapshot(&lane, None);
        assert!(closed.messages.is_empty());
        assert_eq!(
            closed.capabilities.map(|c| c.kind).as_deref(),
            Some("opencode")
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

        lane_close(&lane);
        assert_eq!(live_counters().active_lanes, 0);
    }

    /// **The terminal `Down`**: the pump ends, the view is marked stale with the
    /// reason AND ended, and the NUDGE STREAM STAYS OPEN — which is the whole of
    /// how Dart tells "ended, re-open me" from "closed by me".
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
        assert!(
            lane_snapshot(&lane, None).ended,
            "a terminal Down ENDS the lane — the one thing Dart re-opens on"
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
        let lane = bare_lane();
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

    /// **A `Stale` is a banner, not an end** (plan 025 §3.2.4) — through the
    /// bridge's own snapshot, which is what Dart's re-open rule reads.
    ///
    /// An adapter that can resume (craze) emits `Stale` when its transport
    /// drops and a lone `Ready` of the same generation once it has resumed from
    /// its cursor. The snapshot must say `stale` for the banner and NOT
    /// `ended`, or the controller would tear the lane down and re-open it —
    /// throwing away the very cursor the resume is using. The `Down` at the end
    /// is the control: the same snapshot field does go true for a real end.
    #[test]
    fn a_stale_frame_is_a_banner_and_only_a_down_ends_the_lane() {
        let _g = test_guard();
        let lane = bare_lane();
        let caps = LaneCapabilities {
            kind: "craze".to_string(),
            interject: true,
            cancel: true,
            approvals: true,
            history_cursor: true,
            settings: false,
            stop: true,
        };
        lane.inner.apply(&LaneEvent::Reset {
            reason: "connect".to_string(),
            generation: 1,
        });
        lane.inner.apply(&message(1));
        lane.inner.apply(&LaneEvent::Capabilities {
            capabilities: caps.clone(),
        });
        lane.inner.apply(&LaneEvent::Ready { generation: 1 });
        let live = lane_snapshot(&lane, None);
        assert_eq!(live.stale, None);
        assert!(!live.ended);
        assert_eq!(live.capabilities, Some(caps.clone().into()));

        lane.inner.apply(&LaneEvent::Stale {
            reason: "hub connection lost".to_string(),
        });
        let resuming = lane_snapshot(&lane, None);
        assert_eq!(resuming.stale.as_deref(), Some("hub connection lost"));
        assert!(
            !resuming.ended,
            "a Stale must not read as ended — Dart would re-open and lose the cursor"
        );
        assert_eq!(resuming.messages.len(), 1, "the rows stay on screen");
        assert_eq!(
            resuming.capabilities,
            Some(caps.into()),
            "and so do the capabilities"
        );

        // The silent resume's end: a lone Ready of the SAME generation.
        lane.inner.apply(&LaneEvent::Ready { generation: 1 });
        let resumed = lane_snapshot(&lane, None);
        assert_eq!(
            resumed.stale, None,
            "a lone same-generation Ready clears it"
        );
        assert!(!resumed.ended);
        assert_eq!(resumed.generation, live.generation, "no reseed happened");

        // The control: a terminal Down does end it.
        lane.inner.apply(&LaneEvent::Down {
            reason: "session_closed".to_string(),
        });
        let down = lane_snapshot(&lane, None);
        assert!(down.ended);
        assert_eq!(down.stale.as_deref(), Some("session_closed"));

        lane_close(&lane);
        assert_eq!(live_counters().active_lanes, 0);
    }

    /// One claim. A second nudge stream on one handle would silently split the
    /// nudges between two consumers — and a nudge is not repeatable, so the
    /// consumer that missed one would sit on a stale view for ever.
    #[test]
    fn a_second_nudge_claim_is_refused() {
        let _g = test_guard();
        let lane = bare_lane();
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
        let lane = bare_lane();
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
            let lane = bare_lane();
            assert!(spawn_forwarder(
                &lane.inner,
                CountingSink::new(false).push_fn()
            ));
            assert_eq!(live_counters().active_lanes, 1);
        }
        assert_eq!(live_counters().active_lanes, 0);
        assert_eq!(live_counters().active_lane_forwarders, 0);
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
