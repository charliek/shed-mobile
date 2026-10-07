//! **A machine's craze source, on the phone** (plan 025 §3.7.2, CM3) — the
//! client half of `shed_craze::CrazeSource`, shaped like [`super::lane`] and for
//! the same reasons.
//!
//! ```text
//!   Dart: MachineFeed ──second RoostTunnel (craze bridge --hub per accept)──▶ port
//!                     ──craze_source_open(machine, port)──▶ BridgeCrazeSource
//!                     ◀── one `true` nudge ─────────────────  craze_source_nudges
//!                     ──▶ craze_source_snapshot() ── one atomic read
//!
//!   Rust: CrazeSource(TcpDial(port)) ──subscribe()──▶ Reset … Session* … Ready …
//!                                                         │
//!                                       CrazeView (staged, then swapped)
//!                                                         │
//!                                        dirty bit ──▶ forwarder ──▶ sink
//! ```
//!
//! craze is the provider abstraction (plan 025 D2): one per-machine **hub**
//! lists every cursor, grok, gx and native session there, says what a create can
//! start, starts one, and splices a client through to a session's host. On a
//! phone the hub is reached exactly as a machine's `roost-session` is: Dart owns
//! the SSH connection and serves a fixed loopback port whose every accepted
//! connection execs [`craze_remote_command`] — craze's published ladder ending in
//! `craze bridge --hub` — and Rust is handed nothing but the port (D10). Every
//! connection is its own exec: the roster's, every `createOptions`, every create
//! and every open transcript's.
//!
//! # The same three sentences as a lane
//!
//! * **Rust owns the source, the roster pump and the staged view.** The pump is
//!   `CrazeSource`'s own (shed-craze reconnects, backs off and reseeds); the fold
//!   is [`CrazeView`], the desktop's `CrazeState` stage-and-swap rule (a seed is
//!   swapped in by ITS `Ready` only, an `Offline` keeps the last swapped-in rows)
//!   minus the desktop's dormant phase — the phone's craze tunnel runs `bridge
//!   --hub` and is never attach-only (plan 025 §9).
//! * **Dart gets a nudge and pulls one atomic snapshot** ([`craze_source_snapshot`])
//!   — never a stream of `SourceEvent`s, for the lane's reason: a phone that
//!   backgrounds would come back to a queue instead of a view.
//! * **Dart folds nothing** — not even the row merge. A machine's rows are its
//!   roost tabs beside its craze sessions, and which roost tab IS a craze session
//!   (plan 025 D4) is `shed_app::craze_rows::fold_plan`, the one rule the desktop
//!   runs too; [`craze_fold_plan`] hands it to Dart over the bridge rather than
//!   letting a second reading of it grow there.
//!
//! # Who decides why a machine has no craze
//!
//! Over a loopback port Rust sees no exit status and no stderr: a machine with
//! no craze, and one with v0.0.1 (which refuses `--hub`), both reach Rust as a
//! connection that ended before `hello` — `Offline{Unreachable}`. Dart owns the
//! exec, reads its stderr band (`craze: command not found` from the ladder's
//! last line; cobra's `unknown flag: --hub`), and is therefore **authoritative
//! for a failure before `hello`**: it hands its class to
//! [`craze_source_note_reach`], and the snapshot's `offline` carries it in place
//! of Rust's `Unreachable` until a seed proves the far side is answering. Rust
//! stays authoritative after `hello` — a hub whose capabilities or codecs are
//! too old is Rust's own `TooOld`, which a Dart note never overrides.
//!
//! # The created rows, and the one change no frame announces
//!
//! A session this source created is openable at once — `CrazeSource` keeps the
//! create's own row until its roster lists it — and the snapshot lists those
//! rows ([`shed_craze::CrazeSource::created_rows`], read AT the snapshot, never
//! copied). A created session that ends before any roster listed it leaves that
//! set with no roster frame to say so (plan 025 Amendment A16, the ghost row),
//! so the source's [`on_created_gone`](shed_craze::CrazeSource::on_created_gone)
//! hook is wired to this handle's dirty bit: the end raises a nudge, and the
//! next snapshot no longer lists the row.
//!
//! # Ownership
//!
//! The feed owns the handle and closes it with [`craze_source_close`] — before
//! cancelling its nudge stream (the lane's deadlock rule), and before opening
//! the next one on a restarted tunnel's new port. Closing stops the roster pump
//! (and so its connection) and cuts short every `createOptions`/`create` still
//! in flight on the handle. Lanes opened through it ([`craze_lane_open`]) are
//! [`BridgeLane`]s and are closed through the lane API like any other.

use std::collections::BTreeMap;
use std::future::Future;
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex, MutexGuard};

use flutter_rust_bridge::frb;
use shed_app::craze_rows::{fold_plan, RoostTabRef};
use shed_core::lane::{
    AgentSource, LaneError, LaneSession, SourceCapabilities, SourceEvent, SourceOffline,
};
use shed_craze::{CrazeDial, CrazeSource, TcpDial};
use tokio::sync::{watch, Notify};

use crate::frb_generated::StreamSink;

use super::bridge_rt::{
    bridge_rt, ACTIVE_CRAZE_FORWARDERS, ACTIVE_CRAZE_SOURCES, PENDING_CRAZE_CALLS,
};
use super::dto_lane::{
    BridgeLaneCreateOptions, BridgeLaneCreateRequest, BridgeLaneCreated, BridgeLaneError,
    BridgeLaneSession, BridgeSourceCapabilities, BridgeSourceOffline,
};
use super::lane::{on_bridge_rt, open_adapter, BridgeLane};

/// Who the phone says it is in a hub's `hello` (`client {kind: "shed", name}`).
const CLIENT_NAME: &str = "shed-mobile";

/// Take a lock, ignoring poisoning — [`super::lane`]'s rule, for its reason.
fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

// ---------------------------------------------------------------------------
// the commands Dart execs
// ---------------------------------------------------------------------------

/// The command the craze tunnel execs on the far side, verbatim — craze's
/// published ladder ending in `craze bridge --hub`, plus the exec-only PATH
/// (`shed_core::craze::bridge_hub_command`, plan 025 §3.4).
///
/// **Dart composes no part of it**, for [`super::roost::roost_remote_command`]'s
/// reason: which rung wins and how the script is quoted is pinned by shed's
/// `tests/machine-transport` corpus, through a real sshd, and a second
/// composition here could only drift from it.
#[frb(sync)]
pub fn craze_remote_command() -> String {
    shed_core::craze::bridge_hub_command()
}

/// **Test mode only**: the JAILED bridge argv (`shed_core::craze::
/// bridge_hub_argv_jailed` — `["sh", "-c", <rungs 1–2 only, no exec PATH>]`).
///
/// The hermetic harness (`integration_test/craze_test.dart`) runs its craze
/// tunnel as a local process over this, under craze's recipe environment, so a
/// craze installed on the host running the tests — an absolute rung, an
/// injected Homebrew directory — can never answer a hermetic cell. No
/// production transport sends it; the shipped feed execs
/// [`craze_remote_command`].
#[frb(sync)]
pub fn craze_jailed_bridge_argv() -> Vec<String> {
    shed_core::craze::bridge_hub_argv_jailed()
}

/// A fresh create request id in craze's form (`shed_craze::new_request_id`):
/// minted for a submission, and reused ONLY while that submission's outcome is
/// unknown (plan 025 §3.8).
#[frb(sync)]
pub fn craze_new_request_id() -> String {
    shed_craze::new_request_id()
}

// ---------------------------------------------------------------------------
// the row merge, over the bridge
// ---------------------------------------------------------------------------

/// One roost tab on the machine being folded, as the merge needs it (mirrors
/// `shed_app::craze_rows::RoostTabRef`).
///
/// `craze_owner` is `Some(X)` **only** for a tab roost reports as craze's
/// (`kind == Craze`), `X` being its ownership session id — the provider session
/// a craze TUI claimed (a roost row's `rc_id`). `None` for every other tab,
/// whatever its session id says: a tab of another source whose id happens to
/// equal `X` is never absorbed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRoostTabRef {
    pub tab_id: i64,
    pub craze_owner: Option<String>,
}

/// One roost tab the merge folds away: ABSORBED into the hub row `host_id`
/// names (that row then carries the tab's id), or HIDDEN (`None`) — a craze tab
/// the live roster names no row for. One list rather than `FoldPlan`'s map and
/// set: FRB would have to invent a Dart shape for a map, and it carries a
/// `Vec<i64>` across as a typed list of `BigInt`s.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeFoldedTab {
    pub tab_id: i64,
    pub host_id: Option<String>,
}

/// What the merge decided for one machine (mirrors
/// `shed_app::craze_rows::FoldPlan`): every roost tab it folds away, in tab id
/// order — at most one per hub row absorbed (the newest), the rest hidden. A tab
/// in this list is NOT shown as a roost row.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeFoldPlan {
    pub folded: Vec<BridgeFoldedTab>,
}

/// **The row merge for ONE machine** (plan 025 §3.6.3, D4) —
/// `shed_app::craze_rows::fold_plan`, the rule the desktop runs, called rather
/// than re-derived.
///
/// `hub` is the machine's craze rows **only while its craze feed is live**, and
/// `None` otherwise (offline, never reached): a feed that is not live absorbs
/// nothing, so roost's craze rows stand alone exactly as they would with no
/// craze source at all. With a live feed EVERY craze-owned tab is absorbed —
/// attached to the hub row whose `provider_session_id` it names (two tabs of one
/// session: the newest attaches; two rows claiming one session: the newer
/// `since`/`startedAt`, ties to the greater hostId), or hidden when no row names
/// it. A fold never crosses machines: the caller passes one machine's tabs and
/// that machine's rows.
#[frb(sync)]
pub fn craze_fold_plan(
    roost: Vec<BridgeRoostTabRef>,
    hub: Option<Vec<BridgeLaneSession>>,
) -> BridgeFoldPlan {
    let tabs: Vec<RoostTabRef> = roost
        .into_iter()
        .map(|t| RoostTabRef {
            tab_id: t.tab_id,
            craze_owner: t.craze_owner,
        })
        .collect();
    let hub: Option<Vec<LaneSession>> = hub.map(|rows| rows.into_iter().map(Into::into).collect());
    let plan = fold_plan(&tabs, hub.as_deref());
    let mut folded: Vec<BridgeFoldedTab> = plan
        .absorbed
        .into_iter()
        .map(|(tab_id, host_id)| BridgeFoldedTab {
            tab_id,
            host_id: Some(host_id),
        })
        .chain(plan.hidden.into_iter().map(|tab_id| BridgeFoldedTab {
            tab_id,
            host_id: None,
        }))
        .collect();
    folded.sort_by_key(|t| t.tab_id);
    BridgeFoldPlan { folded }
}

// ---------------------------------------------------------------------------
// the view
// ---------------------------------------------------------------------------

/// Why a source is offline, and its own words for it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeCrazeOffline {
    pub cause: BridgeSourceOffline,
    pub reason: String,
}

/// **One machine's craze source, as one atomic read** — what
/// [`craze_source_snapshot`] answers.
///
/// * `rows` — the sessions the source holds, by hostId (P11): the roster's
///   swapped-in rows, then the rows only a create answered with (not yet
///   listed by the roster, unexpired). While the source is not `live` these
///   are the LAST KNOWN rows, and a client renders them stale (§3.6.2).
/// * `live` — a roster seed is swapped in and its connection is following the
///   hub. The row merge absorbs roost's craze tabs only while this is true.
/// * `offline` — why it is not live, once it has said; `None` while it has
///   never said anything (connecting). `NotInstalled` is QUIET (the machine
///   simply has no craze); `TooOld` asks the person to update craze there.
/// * `caps` — what a create may do here (`create`, `create_options`), from
///   the hub's `hello`; `None` until a seed carried them.
/// * `truncated` — the hub cut its roster to a bound of its own.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeCrazeSnapshot {
    pub rows: Vec<BridgeLaneSession>,
    pub live: bool,
    pub offline: Option<BridgeCrazeOffline>,
    pub caps: Option<BridgeSourceCapabilities>,
    pub truncated: bool,
}

/// A roster seed in progress: the rows and capabilities between a `Reset` and
/// its own `Ready`.
///
/// No `#[derive]` on this or on any other private type in this file, and that
/// is load-bearing rather than style: the codegen emits Dart glue for a derived
/// type in `crate::api` whether or not anything public names it (the
/// precedent every private struct in this crate's API modules follows).
struct Staged {
    generation: u64,
    rows: BTreeMap<String, LaneSession>,
    caps: Option<SourceCapabilities>,
}

/// One machine's craze roster as the phone shows it — the desktop's
/// `CrazeState` fold (`desktop/tauri/src-tauri/src/craze.rs`), minus its
/// dormant phase (the phone is never attach-only).
struct CrazeView {
    /// The swapped-in rows, by hostId — live while `live`, retained (and
    /// rendered stale) after an `Offline`.
    rows: BTreeMap<String, LaneSession>,
    live: bool,
    offline: Option<(SourceOffline, String)>,
    caps: Option<SourceCapabilities>,
    truncated: bool,
    staged: Option<Staged>,
}

impl CrazeView {
    /// Nothing said yet: no rows, not live, no cause.
    fn empty() -> CrazeView {
        CrazeView {
            rows: BTreeMap::new(),
            live: false,
            offline: None,
            caps: None,
            truncated: false,
            staged: None,
        }
    }

    /// Fold one source event (stage-and-swap). Answers whether a reader can see
    /// the change, which is what decides a nudge.
    fn apply(&mut self, event: SourceEvent) -> bool {
        match event {
            SourceEvent::Reset { generation, .. } => {
                self.staged = Some(Staged {
                    generation,
                    rows: BTreeMap::new(),
                    caps: None,
                });
                false
            }
            SourceEvent::Session { session } => match self.staged.as_mut() {
                Some(staged) => {
                    staged.rows.insert(session.id.clone(), session);
                    false
                }
                None => {
                    self.rows.insert(session.id.clone(), session);
                    true
                }
            },
            SourceEvent::Removed { session_id } => match self.staged.as_mut() {
                Some(staged) => {
                    staged.rows.remove(&session_id);
                    false
                }
                None => self.rows.remove(&session_id).is_some(),
            },
            SourceEvent::Capabilities { capabilities } => match self.staged.as_mut() {
                Some(staged) => {
                    staged.caps = Some(capabilities);
                    false
                }
                None => {
                    self.caps = Some(capabilities);
                    true
                }
            },
            SourceEvent::Ready {
                generation,
                truncated,
            } => {
                // MATCHED, never assumed: only the seed this `Ready` names swaps
                // in (plan 025 §3.2.4, "generations are matched").
                if self.staged.as_ref().map(|s| s.generation) != Some(generation) {
                    return false;
                }
                let Some(staged) = self.staged.take() else {
                    return false;
                };
                self.rows = staged.rows;
                if staged.caps.is_some() {
                    self.caps = staged.caps;
                }
                self.truncated = truncated;
                self.live = true;
                self.offline = None;
                true
            }
            SourceEvent::Offline { reason, cause } => {
                // A loss abandons a seed in progress; the last swapped-in rows
                // stay, and render stale.
                self.staged = None;
                let said = Some((cause, reason));
                let changed = self.live || self.offline != said;
                self.live = false;
                self.offline = said;
                changed
            }
            SourceEvent::Unknown => false,
        }
    }
}

/// The view, Dart's pre-`hello` class, and the dirty bit — **all under one
/// lock**, because [`craze_source_snapshot`] reads them together.
struct SourceState {
    view: CrazeView,
    /// What Dart's own transport learned before any `hello` (the module doc):
    /// `NotInstalled` or `TooOld`, with the far side's line. Cleared by a seed
    /// — the one proof the far side answers — and by nothing else.
    noted: Option<(SourceOffline, String)>,
    dirty: bool,
}

impl SourceState {
    fn empty() -> SourceState {
        SourceState {
            view: CrazeView::empty(),
            noted: None,
            dirty: false,
        }
    }

    /// Fold one event; a seed swapped in also clears Dart's note.
    fn fold(&mut self, event: SourceEvent) -> bool {
        let ready = matches!(event, SourceEvent::Ready { .. });
        let changed = self.view.apply(event);
        if ready && self.view.live {
            self.noted = None;
        }
        changed
    }

    /// Why the source is not live: Rust's own cause, except that Dart's
    /// pre-`hello` class replaces a cause Rust could only call `Unreachable`
    /// (an EOF before `hello` over the loopback) — and stands alone while Rust
    /// has said nothing yet. Rust's `TooOld`/`Failed`/`NotInstalled` (after
    /// `hello`) always stand.
    fn offline(&self) -> Option<(SourceOffline, String)> {
        if self.view.live {
            return None;
        }
        match (&self.view.offline, &self.noted) {
            (None | Some((SourceOffline::Unreachable, _)), Some(noted)) => Some(noted.clone()),
            (offline, _) => offline.clone(),
        }
    }

    /// The projection, with `created` — the source's created rows, read under
    /// this lock — after the roster's own (a hostId the roster lists is the
    /// roster's row, never twice).
    fn snapshot(&self, created: Vec<LaneSession>) -> BridgeCrazeSnapshot {
        let mut rows: Vec<BridgeLaneSession> =
            self.view.rows.values().cloned().map(Into::into).collect();
        rows.extend(
            created
                .into_iter()
                .filter(|row| !self.view.rows.contains_key(&row.id))
                .map(Into::into),
        );
        BridgeCrazeSnapshot {
            rows,
            live: self.view.live,
            offline: self.offline().map(|(cause, reason)| BridgeCrazeOffline {
                cause: cause.into(),
                reason,
            }),
            caps: self.view.caps.clone().map(Into::into),
            truncated: self.view.truncated,
        }
    }
}

// ---------------------------------------------------------------------------
// the handle
// ---------------------------------------------------------------------------

/// The pump and forwarder, plus the idempotence flags — behind a DIFFERENT lock
/// from [`SourceState`], so a snapshot on the hot path never contends with a
/// close ([`super::lane`]'s split).
struct SourceTasks {
    pump: Option<tokio::task::AbortHandle>,
    forwarder: Option<tokio::task::AbortHandle>,
    /// One claim on the nudge stream.
    streaming: bool,
    /// The single-shot teardown latch.
    closed: bool,
}

struct SourceInner {
    /// The machine — it names this source in a refusal.
    machine: String,
    source: CrazeSource,
    state: Mutex<SourceState>,
    tasks: Mutex<SourceTasks>,
    /// The forwarder's wakeup; a permit is stored when nobody waits, so a nudge
    /// raised before [`craze_source_nudges`] is not lost.
    wake: Notify,
    /// Flipped once, by teardown: every call in flight is waiting on it too.
    closed: watch::Sender<bool>,
}

impl SourceInner {
    /// Fold one frame in and nudge at most once per un-acknowledged burst. The
    /// lock is released before the notify ([`super::lane`]'s rule).
    fn apply(&self, event: SourceEvent) {
        let first = {
            let mut s = lock(&self.state);
            if !s.fold(event) {
                return;
            }
            let first = !s.dirty;
            s.dirty = true;
            first
        };
        if first {
            self.wake.notify_one();
        }
    }

    /// Something a snapshot reads changed outside the event stream — a create's
    /// row, a created row the source let go, Dart's own note: mark dirty and
    /// nudge (once per un-acknowledged burst).
    fn touch(&self) {
        let first = {
            let mut s = lock(&self.state);
            let first = !s.dirty;
            s.dirty = true;
            first
        };
        if first {
            self.wake.notify_one();
        }
    }

    fn is_closed(&self) -> bool {
        lock(&self.tasks).closed
    }

    fn closed_error(&self) -> BridgeLaneError {
        BridgeLaneError::Unavailable {
            msg: format!("the craze source for {} was closed", self.machine),
        }
    }

    /// Run one source call on its own connection, counted, and **cut short by
    /// the handle's close** — the feed owns every `createOptions` and `create`
    /// in flight (plan 025 §3.7.2), so a torn-down feed never leaves one holding
    /// a connection to a machine the phone has let go of. A create cut short is
    /// an outcome the caller does not know; the caller's sheet is gone with the
    /// feed.
    async fn call<T, F, Fut>(&self, f: F) -> Result<T, BridgeLaneError>
    where
        F: FnOnce(CrazeSource) -> Fut,
        Fut: Future<Output = Result<T, LaneError>>,
    {
        let mut closed = self.closed.subscribe();
        if *closed.borrow() {
            return Err(self.closed_error());
        }
        let _pending = Pending::new();
        let work = f(self.source.clone());
        tokio::select! {
            biased;
            _ = closed.wait_for(|c| *c) => Err(self.closed_error()),
            result = work => result.map_err(BridgeLaneError::from),
        }
    }
}

/// [`PENDING_CRAZE_CALLS`], held for one call: decremented however the call
/// ends — answered, refused, cut short by a close, or aborted.
struct Pending;

impl Pending {
    fn new() -> Pending {
        PENDING_CRAZE_CALLS.fetch_add(1, Ordering::SeqCst);
        Pending
    }
}

impl Drop for Pending {
    fn drop(&mut self) {
        PENDING_CRAZE_CALLS.fetch_sub(1, Ordering::SeqCst);
    }
}

/// One machine's craze source: the source, the fold, the roster pump and the
/// nudge forwarder. Opaque because none of that can cross FRB; Dart holds it,
/// reads through [`craze_source_snapshot`], and ends it with
/// [`craze_source_close`].
#[frb(opaque)]
pub struct BridgeCrazeSource {
    inner: Arc<SourceInner>,
}

impl Drop for BridgeCrazeSource {
    fn drop(&mut self) {
        teardown(&self.inner);
    }
}

/// The SINGLE teardown/decrement point, idempotent via `closed`: flip the close
/// every in-flight call waits on, abort the forwarder and the roster pump (whose
/// subscription's stop ends the source's own pump and its connection), and
/// decrement each counter exactly once — [`super::lane`]'s discipline, for its
/// reason (the counters are `u64`; a double decrement wraps).
fn teardown(inner: &Arc<SourceInner>) {
    let mut t = lock(&inner.tasks);
    if t.closed {
        return;
    }
    t.closed = true;
    // `send_replace`, not `send`: with no call waiting there is no receiver,
    // and `send` would then refuse to store the value a LATER call reads.
    inner.closed.send_replace(true);
    if let Some(f) = t.forwarder.take() {
        f.abort();
        ACTIVE_CRAZE_FORWARDERS.fetch_sub(1, Ordering::SeqCst);
    }
    if let Some(p) = t.pump.take() {
        p.abort();
    }
    ACTIVE_CRAZE_SOURCES.fetch_sub(1, Ordering::SeqCst);
}

// ---------------------------------------------------------------------------
// open
// ---------------------------------------------------------------------------

/// **Open one machine's craze source** on the craze tunnel's local port: a
/// `CrazeSource` over `TcpDial(port)`, and the pump folding its events into the
/// staged view.
///
/// Returns at once. The source dials on its own schedule — a machine with no
/// craze, or one asleep, is the snapshot's `offline`, never this call's error —
/// and keeps redialling with shed-craze's backoff for as long as the handle is
/// open.
///
/// `machine` names the source in a refusal; it is not dialled.
pub fn craze_source_open(machine: String, port: u16) -> BridgeCrazeSource {
    open_on(machine, Arc::new(TcpDial(port)))
}

/// [`craze_source_open`] over any dial — the production `TcpDial`, or a test's
/// scripted hub.
fn open_on(machine: String, dial: Arc<dyn CrazeDial>) -> BridgeCrazeSource {
    let (closed, _) = watch::channel(false);
    let inner = Arc::new(SourceInner {
        machine,
        source: CrazeSource::new(dial, CLIENT_NAME),
        state: Mutex::new(SourceState::empty()),
        tasks: Mutex::new(SourceTasks {
            pump: None,
            forwarder: None,
            streaming: false,
            closed: false,
        }),
        wake: Notify::new(),
        closed,
    });
    // **The ghost row's hook** (plan 025 Amendment A16): a created session that
    // ends before any roster listed it leaves `created_rows()` with no roster
    // frame to say so, so the source calls back and the snapshot is re-read.
    // WEAK: the hook is stored inside the source this handle owns, and a strong
    // reference there would keep the handle's state alive for ever.
    let weak = Arc::downgrade(&inner);
    inner.source.on_created_gone(move || {
        if let Some(inner) = weak.upgrade() {
            inner.touch();
        }
    });
    ACTIVE_CRAZE_SOURCES.fetch_add(1, Ordering::SeqCst);
    let pump = bridge_rt().spawn(roster_pump(Arc::clone(&inner)));
    lock(&inner.tasks).pump = Some(pump.abort_handle());
    BridgeCrazeSource { inner }
}

/// The roster subscription, folded for as long as the handle is open. The
/// source reconnects on its own, so this loop has no ladder: it ends only when
/// teardown aborts it — and its subscription's stop, dropped with it, ends the
/// source's pump and the connection it holds.
async fn roster_pump(inner: Arc<SourceInner>) {
    let subscription = match inner.source.subscribe().await {
        Ok(subscription) => subscription,
        // `CrazeSource::subscribe` answers every outage on the stream itself;
        // a refusal here is a source that cannot even start.
        Err(e) => {
            inner.apply(SourceEvent::Offline {
                reason: e.to_string(),
                cause: SourceOffline::Failed,
            });
            return;
        }
    };
    let (mut rx, _stop) = subscription.into_parts();
    while let Some(event) = rx.recv().await {
        inner.apply(event);
    }
}

// ---------------------------------------------------------------------------
// the nudge forwarder
// ---------------------------------------------------------------------------

/// Push one nudge; `Err` means the Dart stream is gone. A closure for
/// [`super::lane`]'s reason (a trait defined here would land on the FRB
/// surface).
type NudgeResult = Result<(), ()>;

/// Stream this source's nudges. **One claim**: a second call on the same handle
/// is a no-op rather than a silent split. The stream stays open until
/// [`craze_source_close`].
pub fn craze_source_nudges(src: &BridgeCrazeSource, sink: StreamSink<bool>) {
    spawn_forwarder(&src.inner, move || sink.add(true).map_err(|_| ()));
}

/// [`craze_source_nudges`] with the push abstracted. Answers whether it claimed
/// the stream.
fn spawn_forwarder(
    inner: &Arc<SourceInner>,
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
    // Re-check `closed`: a teardown that won the race during the spawn already
    // decremented — abort, and count nothing.
    let mut t = lock(&inner.tasks);
    if t.closed {
        forwarder.abort();
        return false;
    }
    t.forwarder = Some(forwarder.abort_handle());
    ACTIVE_CRAZE_FORWARDERS.fetch_add(1, Ordering::SeqCst);
    true
}

/// Wait for a dirty transition, push one `true`, repeat — and SELF-TEAR-DOWN
/// when the loop ends: a Dart consumer that cancelled the stream without closing
/// the source must not leave the roster pump holding a connection nobody reads.
async fn forward_loop(inner: Arc<SourceInner>, push: impl Fn() -> NudgeResult) {
    loop {
        inner.wake.notified().await;
        if inner.is_closed() {
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

/// **The one read**, and the nudge acknowledgement: the staged view, the
/// created rows and Dart's note, projected under ONE lock with the dirty bit
/// cleared.
///
/// The dirty bit is cleared BEFORE the created rows are read, under the same
/// guard: a created row the source lets go after this read raises the next
/// nudge, and one it let go before is already absent from the answer. A closed
/// source still projects its last view.
#[frb(sync)]
pub fn craze_source_snapshot(src: &BridgeCrazeSource) -> BridgeCrazeSnapshot {
    let mut s = lock(&src.inner.state);
    s.dirty = false;
    // Lock order: this handle's state, then the source's rows (inside
    // `created_rows`). The source calls its hook only after releasing its rows
    // lock, so nothing takes the two the other way round.
    let created = src.inner.source.created_rows();
    s.snapshot(created)
}

/// **Dart's class for a failure before `hello`** (the module doc): what the
/// craze tunnel's stderr said — `NotInstalled` (the ladder's `craze: command
/// not found`) or `TooOld` (v0.0.1's `unknown flag: --hub`) — with the far
/// side's line. The snapshot's `offline` carries it in place of an
/// `Unreachable` until a seed proves the far side answers.
#[frb(sync)]
pub fn craze_source_note_reach(
    src: &BridgeCrazeSource,
    cause: BridgeSourceOffline,
    message: String,
) {
    let note = Some((SourceOffline::from(cause), message));
    {
        let mut s = lock(&src.inner.state);
        if s.noted == note {
            return;
        }
        s.noted = note;
    }
    src.inner.touch();
}

// ---------------------------------------------------------------------------
// create
// ---------------------------------------------------------------------------

/// What a create can start on this machine — craze's `sessions.createOptions`,
/// on a connection of its own (each call is its own exec of the bridge, which
/// Ensures a hub: an explicit user action). Providers in craze's order, the
/// default as craze states it, the recent directories newest first.
pub async fn craze_create_options(
    src: &BridgeCrazeSource,
) -> Result<BridgeLaneCreateOptions, BridgeLaneError> {
    let inner = Arc::clone(&src.inner);
    on_bridge_rt(async move {
        inner
            .call(|source| async move { source.create_options().await })
            .await
            .map(Into::into)
    })
    .await
}

/// Create a session — craze's `session.create{cwd, provider?, prompt?,
/// requestId}`, on a connection of its own, retried once under the same id
/// when its outcome is unknown (shed-craze's rule, plan 025 §3.3.3).
///
/// The new session's row is the source's at once (its created rows): this
/// handle is nudged, so the row is listed — and a lane opens on its hostId —
/// before the roster has caught up.
pub async fn craze_create(
    src: &BridgeCrazeSource,
    request: BridgeLaneCreateRequest,
) -> Result<BridgeLaneCreated, BridgeLaneError> {
    let inner = Arc::clone(&src.inner);
    on_bridge_rt(async move {
        let created = inner
            .call(|source| async move { source.create(request.into()).await })
            .await?;
        inner.touch();
        Ok(created.into())
    })
    .await
}

// ---------------------------------------------------------------------------
// lanes
// ---------------------------------------------------------------------------

/// **Open one craze session's transcript** — the source's lane on `host_id`
/// (the row's id, P11), as the SAME [`BridgeLane`] an opencode lane is, so every
/// `lane_*` verb serves it.
///
/// No forward and no stamp: the lane reaches its session through the hub's
/// splice over this source's own dial, one connection of its own (D10). It binds
/// the row (and its craze session id) the source holds — a roster's or a
/// create's — and a hostId the source has never listed is `UnknownSession`. A
/// CLOSED source refuses with `Unavailable` — transient, see the body.
/// Opened through the source, the lane says its session's end back to it, which
/// is what lets a created row go (Amendment A16).
pub async fn craze_lane_open(
    src: &BridgeCrazeSource,
    host_id: String,
) -> Result<BridgeLane, BridgeLaneError> {
    let inner = Arc::clone(&src.inner);
    // `Unavailable`, not `NoLane`: a closed source is a feed that stopped or
    // is restarting, and a lane whose open raced that must try again through
    // the replacement — `NoLane` would read as permanent and abandon it.
    if inner.is_closed() {
        return Err(inner.closed_error());
    }
    on_bridge_rt(async move {
        let lane = inner
            .source
            .open(&host_id)
            .await
            .map_err(BridgeLaneError::from)?;
        open_adapter(lane, host_id).await
    })
    .await
}

/// End the source — the SYNCHRONOUS co-primary teardown. Idempotent; `Drop` is
/// the backstop. Call it BEFORE cancelling the nudge stream: the stream ends
/// here, and a cancel awaited first never completes (the lane's rule).
#[frb(sync)]
pub fn craze_source_close(src: &BridgeCrazeSource) {
    teardown(&src.inner);
}

#[cfg(test)]
mod tests {
    use super::*;

    use std::sync::atomic::AtomicU64;
    use std::time::Duration;

    use serde_json::{json, Value};
    use shed_core::rc::RcActivity;
    use shed_craze::testing::{
        attach_result, full_hub_capabilities, host_session_row, roster_row, session_caps,
        session_info, snapshot_at, HubEnd, ScriptedDial,
    };

    use crate::api::bridge_rt::live_counters;
    use crate::api::lane::{lane_close, lane_snapshot};
    use crate::api::testsupport::test_guard;

    /// The host a scripted create answers with.
    const CREATED: &str = "cccccccccccc";

    /// A nudge sink that counts pushes, and optionally fails every one (the
    /// "Dart cancelled the stream without closing the source" shape) — the
    /// lane tests' own, for this handle.
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

    /// Poll `cond` on the test's own runtime — never a thread-blocking wait:
    /// the scripted hub's end is driven on this runtime.
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

    async fn next_conn(conns: &mut tokio::sync::mpsc::UnboundedReceiver<HubEnd>) -> HubEnd {
        tokio::time::timeout(Duration::from_secs(10), conns.recv())
            .await
            .expect("the source dialled in time")
            .expect("the dial is alive")
    }

    fn row(host_id: &str, session_id: &str, facts: Value) -> Value {
        roster_row(host_id, session_id, &format!("/w/{host_id}"), facts)
    }

    fn session(id: &str, provider_session_id: Option<&str>, since: Option<i64>) -> LaneSession {
        LaneSession {
            id: id.to_string(),
            title: id.to_string(),
            cwd: "/work".to_string(),
            activity: RcActivity::Idle,
            pending_approvals: 0,
            approximate: false,
            parent_id: None,
            last_change_unix_ms: since,
            provider: Some("grok".to_string()),
            model: None,
            doing: None,
            head_ask_summary: None,
            last_reply: None,
            since_unix_ms: since,
            attached: None,
            start_error: None,
            provider_session_id: provider_session_id.map(str::to_string),
            permission_mode: None,
            tab_id: None,
        }
    }

    fn caps() -> SourceCapabilities {
        SourceCapabilities {
            kind: "craze".to_string(),
            create: true,
            create_options: true,
        }
    }

    fn seed(view: &mut CrazeView, generation: u64, rows: &[&str]) {
        view.apply(SourceEvent::Reset {
            reason: "connect".to_string(),
            generation,
        });
        for id in rows {
            view.apply(SourceEvent::Session {
                session: session(id, None, None),
            });
        }
        view.apply(SourceEvent::Capabilities {
            capabilities: caps(),
        });
        view.apply(SourceEvent::Ready {
            generation,
            truncated: false,
        });
    }

    fn ids(view: &CrazeView) -> Vec<&str> {
        view.rows.keys().map(String::as_str).collect()
    }

    fn snap_ids(snap: &BridgeCrazeSnapshot) -> Vec<&str> {
        snap.rows.iter().map(|r| r.id.as_str()).collect()
    }

    // ---- the view ----

    /// **A seed swaps in on its OWN `Ready` and on nothing else** (plan 025
    /// §3.2.4, "generations are matched"): a late `Ready` for an older `Reset`
    /// does not commit the newer seed half-built.
    #[test]
    fn a_seed_swaps_in_only_on_its_own_ready() {
        let mut view = CrazeView::empty();
        view.apply(SourceEvent::Reset {
            reason: "connect".to_string(),
            generation: 1,
        });
        view.apply(SourceEvent::Session {
            session: session("aaaaaaaaaaaa", None, None),
        });
        view.apply(SourceEvent::Reset {
            reason: "server_reset:omitted".to_string(),
            generation: 2,
        });
        view.apply(SourceEvent::Session {
            session: session("bbbbbbbbbbbb", None, None),
        });
        assert!(
            !view.apply(SourceEvent::Ready {
                generation: 1,
                truncated: false
            }),
            "a Ready for the abandoned seed swaps nothing"
        );
        assert!(!view.live);
        assert!(ids(&view).is_empty());
        assert!(view.apply(SourceEvent::Ready {
            generation: 2,
            truncated: true
        }));
        assert!(view.live);
        assert_eq!(ids(&view), ["bbbbbbbbbbbb"]);
        assert!(view.truncated);
    }

    /// Between seeds a `Session` upserts and a `Removed` removes — each a
    /// visible change, which is what raises a nudge.
    #[test]
    fn between_seeds_a_session_upserts_and_a_removed_removes() {
        let mut view = CrazeView::empty();
        seed(&mut view, 1, &["aaaaaaaaaaaa"]);
        assert!(view.apply(SourceEvent::Session {
            session: session("bbbbbbbbbbbb", None, None),
        }));
        assert_eq!(ids(&view), ["aaaaaaaaaaaa", "bbbbbbbbbbbb"]);
        assert!(view.apply(SourceEvent::Removed {
            session_id: "aaaaaaaaaaaa".to_string(),
        }));
        assert_eq!(ids(&view), ["bbbbbbbbbbbb"]);
        assert!(
            !view.apply(SourceEvent::Removed {
                session_id: "aaaaaaaaaaaa".to_string(),
            }),
            "removing what is not there changes nothing a reader sees"
        );
    }

    /// **An `Offline` keeps the last rows and ends `live`** — retained rows
    /// render stale (§3.6.2) — and the next seed restores both.
    #[test]
    fn an_offline_keeps_the_rows_and_a_seed_restores_live() {
        let mut view = CrazeView::empty();
        seed(&mut view, 1, &["aaaaaaaaaaaa"]);
        assert!(view.apply(SourceEvent::Offline {
            reason: "the connection to craze's hub closed".to_string(),
            cause: SourceOffline::Unreachable,
        }));
        assert!(!view.live);
        assert_eq!(ids(&view), ["aaaaaaaaaaaa"], "the last known rows stay");
        assert!(
            !view.apply(SourceEvent::Offline {
                reason: "the connection to craze's hub closed".to_string(),
                cause: SourceOffline::Unreachable,
            }),
            "the same outage said again is no news"
        );
        seed(&mut view, 2, &["aaaaaaaaaaaa", "bbbbbbbbbbbb"]);
        assert!(view.live);
        assert_eq!(view.offline, None);
        assert_eq!(ids(&view), ["aaaaaaaaaaaa", "bbbbbbbbbbbb"]);
    }

    /// **Dart is authoritative before `hello`, Rust after** (the module doc):
    /// Dart's class names an outage Rust could only call `Unreachable`, and
    /// stands alone before Rust has said anything; Rust's own `TooOld` (a hub
    /// too old by its `hello`) is never overridden; a seed clears the note.
    #[test]
    fn darts_note_names_a_pre_hello_outage_until_a_seed() {
        let mut s = SourceState::empty();
        assert_eq!(s.offline(), None, "nothing said yet: connecting");
        s.noted = Some((
            SourceOffline::NotInstalled,
            "craze: command not found".to_string(),
        ));
        assert_eq!(
            s.offline(),
            Some((
                SourceOffline::NotInstalled,
                "craze: command not found".to_string()
            )),
            "Dart's class stands alone before Rust says anything"
        );
        s.fold(SourceEvent::Offline {
            reason: "the connection closed before hello".to_string(),
            cause: SourceOffline::Unreachable,
        });
        assert_eq!(
            s.offline().map(|(c, _)| c),
            Some(SourceOffline::NotInstalled),
            "an EOF before hello is Dart's to name"
        );
        s.fold(SourceEvent::Offline {
            reason: "craze on this machine is too old".to_string(),
            cause: SourceOffline::TooOld,
        });
        assert_eq!(
            s.offline().map(|(c, _)| c),
            Some(SourceOffline::TooOld),
            "Rust's own cause after hello is never overridden"
        );
        // A seed: the far side answers, and the note is spent.
        s.fold(SourceEvent::Reset {
            reason: "reconnect".to_string(),
            generation: 1,
        });
        s.fold(SourceEvent::Ready {
            generation: 1,
            truncated: false,
        });
        assert_eq!(s.offline(), None);
        assert_eq!(s.noted, None, "a seed clears Dart's note");
        s.fold(SourceEvent::Offline {
            reason: "eof".to_string(),
            cause: SourceOffline::Unreachable,
        });
        assert_eq!(
            s.offline().map(|(c, _)| c),
            Some(SourceOffline::Unreachable),
            "with the note spent, an outage is what Rust says it is"
        );
    }

    /// The snapshot lists a create's row after the roster's own, and never a
    /// hostId twice.
    #[test]
    fn the_snapshot_lists_created_rows_after_the_rosters_never_twice() {
        let mut s = SourceState::empty();
        s.fold(SourceEvent::Reset {
            reason: "connect".to_string(),
            generation: 1,
        });
        s.fold(SourceEvent::Session {
            session: session("bbbbbbbbbbbb", None, None),
        });
        s.fold(SourceEvent::Ready {
            generation: 1,
            truncated: false,
        });
        let snap = s.snapshot(vec![
            session("bbbbbbbbbbbb", None, None),
            session(CREATED, None, None),
        ]);
        assert_eq!(snap_ids(&snap), ["bbbbbbbbbbbb", CREATED]);
        assert!(snap.live);
    }

    // ---- the fold plan, over the bridge ----

    fn craze_tab(tab_id: i64, owner: &str) -> BridgeRoostTabRef {
        BridgeRoostTabRef {
            tab_id,
            craze_owner: Some(owner.to_string()),
        }
    }

    fn plain_tab(tab_id: i64) -> BridgeRoostTabRef {
        BridgeRoostTabRef {
            tab_id,
            craze_owner: None,
        }
    }

    fn hub_row(id: &str, owner: &str, since: Option<i64>) -> BridgeLaneSession {
        session(id, Some(owner), since).into()
    }

    fn absorbed(plan: &BridgeFoldPlan) -> Vec<(i64, &str)> {
        plan.folded
            .iter()
            .filter_map(|t| t.host_id.as_deref().map(|h| (t.tab_id, h)))
            .collect()
    }

    fn hidden(plan: &BridgeFoldPlan) -> Vec<i64> {
        plan.folded
            .iter()
            .filter(|t| t.host_id.is_none())
            .map(|t| t.tab_id)
            .collect()
    }

    /// **The shared rule crosses whole** (plan 025 §3.6.3): a craze tab
    /// attaches to the row it names and a plain tab never folds; a feed that is
    /// not live absorbs nothing; an unmatched craze tab is hidden; two tabs of
    /// one session attach the newest; two rows claiming one session take the
    /// newer, ties to the greater hostId.
    #[test]
    fn the_fold_plan_crosses_the_bridge_as_the_shared_rule() {
        let hub = vec![hub_row("aaaaaaaaaaaa", "ses-a", Some(10))];
        let plan = craze_fold_plan(vec![craze_tab(4, "ses-a"), plain_tab(5)], Some(hub.clone()));
        assert_eq!(absorbed(&plan), [(4, "aaaaaaaaaaaa")]);
        assert!(hidden(&plan).is_empty());

        let plan = craze_fold_plan(vec![craze_tab(4, "ses-a")], None);
        assert_eq!(
            plan,
            BridgeFoldPlan { folded: vec![] },
            "a feed that is not live absorbs nothing"
        );

        let plan = craze_fold_plan(vec![craze_tab(4, "ses-gone")], Some(hub.clone()));
        assert!(absorbed(&plan).is_empty());
        assert_eq!(hidden(&plan), [4], "an unmatched craze tab is hidden");

        let plan = craze_fold_plan(
            vec![craze_tab(3, "ses-a"), craze_tab(9, "ses-a")],
            Some(hub.clone()),
        );
        assert_eq!(absorbed(&plan), [(9, "aaaaaaaaaaaa")]);
        assert_eq!(hidden(&plan), [3]);

        let rows = vec![
            hub_row("ffffffffffff", "ses-a", Some(10)),
            hub_row("111111111111", "ses-a", Some(20)),
        ];
        let plan = craze_fold_plan(vec![craze_tab(4, "ses-a")], Some(rows));
        assert_eq!(absorbed(&plan), [(4, "111111111111")], "the newer row");
        let rows = vec![
            hub_row("bbbbbbbbbbbb", "ses-a", Some(10)),
            hub_row("aaaaaaaaaaaa", "ses-a", Some(10)),
        ];
        let plan = craze_fold_plan(vec![craze_tab(4, "ses-a")], Some(rows));
        assert_eq!(absorbed(&plan), [(4, "bbbbbbbbbbbb")], "the greater hostId");
    }

    // ---- the handle, against a scripted hub ----

    /// **One source, seeded, followed, and torn down to zero.** The roster's
    /// seed reaches the snapshot through one nudge; an upsert after it raises
    /// the next; the close returns both counters, is idempotent, and leaves the
    /// last view readable.
    #[tokio::test]
    async fn a_source_seeds_follows_and_tears_down_to_zero() {
        let _g = test_guard();
        let (dial, mut conns) = ScriptedDial::new();
        let src = open_on("mini3".to_string(), dial);
        let sink = CountingSink::new(false);
        assert!(spawn_forwarder(&src.inner, sink.push_fn()));
        assert_eq!(live_counters().active_craze_sources, 1);
        assert_eq!(live_counters().active_craze_forwarders, 1);

        let mut hub = next_conn(&mut conns).await;
        let hello = hub.hello("epoch-1", full_hub_capabilities()).await;
        assert_eq!(
            hello["params"]["client"]["name"], CLIENT_NAME,
            "the phone says it is the phone"
        );
        hub.subscribed(
            "sub-1",
            "epoch-1",
            json!([row(
                "0a0a0a0a0a0a",
                "sess-a",
                json!({"title": "alpha", "activity": "working", "pendingAsks": 0, "model": "grok-4"})
            )]),
        )
        .await;
        assert!(
            until(Duration::from_secs(10), || craze_source_snapshot(&src).live).await,
            "the seed never reached the snapshot"
        );
        let snap = craze_source_snapshot(&src);
        assert_eq!(snap_ids(&snap), ["0a0a0a0a0a0a"]);
        assert_eq!(snap.rows[0].title, "alpha");
        assert_eq!(snap.rows[0].model.as_deref(), Some("grok-4"));
        assert_eq!(snap.offline, None);
        assert_eq!(
            snap.caps,
            Some(BridgeSourceCapabilities {
                kind: "craze".to_string(),
                create: true,
                create_options: true
            })
        );
        assert!(
            until(Duration::from_secs(5), || sink.pushes() >= 1).await,
            "the seed raised no nudge"
        );
        let before = sink.pushes();

        hub.roster(
            "sub-1",
            "epoch-1",
            json!([row("0b0b0b0b0b0b", "sess-b", json!({"activity": "idle"}))]),
            json!([]),
        )
        .await;
        assert!(
            until(Duration::from_secs(5), || sink.pushes() > before).await,
            "an upsert after the snapshot raised no nudge"
        );
        assert_eq!(
            snap_ids(&craze_source_snapshot(&src)),
            ["0a0a0a0a0a0a", "0b0b0b0b0b0b"]
        );

        craze_source_close(&src);
        assert_eq!(live_counters().active_craze_sources, 0);
        assert_eq!(live_counters().active_craze_forwarders, 0);
        craze_source_close(&src);
        craze_source_close(&src);
        assert_eq!(
            live_counters().active_craze_sources,
            0,
            "a second close must not decrement again"
        );
        assert_eq!(
            snap_ids(&craze_source_snapshot(&src)),
            ["0a0a0a0a0a0a", "0b0b0b0b0b0b"],
            "a closed source still projects its last view"
        );
        // The roster connection went with the close.
        assert!(
            tokio::time::timeout(Duration::from_secs(5), hub.recv())
                .await
                .expect("the connection ended in time")
                .is_none(),
            "the roster connection outlived the close"
        );
    }

    /// The create's answer under the scripted hub: the new session's row, its
    /// prompt taken.
    fn created_result() -> Value {
        json!({"session": roster_row(CREATED, "session-created", "/w/new",
                                     json!({"activity": "working", "pendingAsks": 0})),
               "prompt": "accepted"})
    }

    fn created_info() -> Value {
        session_info(CREATED, "session-created", "INC-1", session_caps(true))
    }

    fn create_request(id: &str) -> BridgeLaneCreateRequest {
        BridgeLaneCreateRequest {
            cwd: "/w/new".to_string(),
            provider: Some("grok".to_string()),
            prompt: Some("hello".to_string()),
            request_id: id.to_string(),
        }
    }

    /// **The ghost row** (plan 025 Amendment A16): a session created through
    /// this source and ended before any roster listed it leaves the source with
    /// no roster frame to say so — the source's `on_created_gone` hook is what
    /// tells this handle, so the end RAISES A NUDGE and the next snapshot no
    /// longer lists the row. Without the hook the phone kept the row until an
    /// unrelated frame happened to nudge it.
    #[tokio::test]
    async fn a_created_session_that_ends_unlisted_leaves_with_a_nudge() {
        let _g = test_guard();
        let (dial, mut conns) = ScriptedDial::new();
        let src = open_on("mini3".to_string(), dial);
        let sink = CountingSink::new(false);
        assert!(spawn_forwarder(&src.inner, sink.push_fn()));

        // The roster seeds EMPTY and never lists the new host.
        let mut roster = next_conn(&mut conns).await;
        roster.hello("epoch-1", full_hub_capabilities()).await;
        roster.subscribed("sub-1", "epoch-1", json!([])).await;
        assert!(until(Duration::from_secs(10), || craze_source_snapshot(&src).live).await);

        // The create, on a connection of its own. Everything so far is
        // acknowledged first, so the nudge the create raises is its own: the
        // roster is quiet from here on.
        craze_source_snapshot(&src);
        let before_create = sink.pushes();
        let (created, ()) = tokio::join!(craze_create(&src, create_request("req-ghost")), async {
            let mut hub = next_conn(&mut conns).await;
            hub.hello("epoch-1", full_hub_capabilities()).await;
            let req = hub.expect("session.create").await;
            hub.reply(&req, created_result()).await;
        });
        let created = created.expect("the create answered");
        assert_eq!(created.session.id, CREATED);
        assert!(
            until(Duration::from_secs(5), || sink.pushes() > before_create).await,
            "the create's row reached the source and nothing nudged the phone"
        );
        assert_eq!(
            snap_ids(&craze_source_snapshot(&src)),
            [CREATED],
            "a created row is listed at once, before any roster has it"
        );

        // A lane on it, through this source, seeded.
        let lane = craze_lane_open(&src, CREATED.to_string())
            .await
            .expect("the created session's lane opens");
        let mut hub = next_conn(&mut conns).await;
        hub.splice(CREATED).await;
        hub.listed(host_session_row(&created_info(), json!({})))
            .await;
        hub.attached(attach_result(
            "s-1",
            &created_info(),
            ("INC-1", 1),
            Some(snapshot_at("INC-1", 1, json!({}))),
            None,
        ))
        .await;
        hub.synchronized("s-1", 1).await;
        assert!(
            until(Duration::from_secs(10), || lane_snapshot(&lane, None)
                .generation
                >= 1)
            .await,
            "the lane never seeded"
        );

        // Acknowledge everything so far, then the session ends.
        assert_eq!(snap_ids(&craze_source_snapshot(&src)), [CREATED]);
        let before = sink.pushes();
        hub.reset("s-1", "session_closed").await;
        assert!(
            until(Duration::from_secs(10), || lane_snapshot(&lane, None).ended).await,
            "the session's end never reached the lane"
        );
        assert!(
            until(Duration::from_secs(5), || sink.pushes() > before).await,
            "the created row left the source and nothing nudged the phone"
        );
        assert!(
            craze_source_snapshot(&src).rows.is_empty(),
            "the ended session's created row is gone from the snapshot"
        );

        lane_close(&lane);
        craze_source_close(&src);
        assert_eq!(live_counters().active_lanes, 0);
        assert_eq!(live_counters().active_craze_sources, 0);
        assert_eq!(live_counters().active_craze_forwarders, 0);
    }

    /// **The feed owns a create in flight** (plan 025 §3.7.2): closing the
    /// source cuts it short — no create holds a connection to a machine the
    /// phone has let go of — and the pending counter returns.
    #[tokio::test]
    async fn a_close_cuts_a_create_in_flight_short() {
        let _g = test_guard();
        let (dial, mut conns) = ScriptedDial::new();
        let src = open_on("mini3".to_string(), dial);
        let _roster = next_conn(&mut conns).await;

        let script = async {
            let mut hub = next_conn(&mut conns).await;
            hub.hello("epoch-1", full_hub_capabilities()).await;
            // Taken, and never answered.
            let _req = hub.expect("session.create").await;
            assert_eq!(live_counters().pending_craze_calls, 1);
            craze_source_close(&src);
            hub
        };
        let (answer, _hub) = tokio::time::timeout(Duration::from_secs(10), async {
            tokio::join!(craze_create(&src, create_request("req-cut")), script)
        })
        .await
        .expect("a create in flight outlived its source's close");
        assert!(
            matches!(answer, Err(BridgeLaneError::Unavailable { .. })),
            "a create cut short by a close: {answer:?}"
        );
        assert_eq!(live_counters().pending_craze_calls, 0);
        assert_eq!(live_counters().active_craze_sources, 0);
    }

    /// A closed source refuses everything that would dial — a lane, a create —
    /// quietly (`Unavailable`: a feed restarting, which a caller retries
    /// through the replacement), and counts nothing.
    #[tokio::test]
    async fn a_closed_source_refuses_lanes_and_calls() {
        let _g = test_guard();
        let (dial, _conns) = ScriptedDial::new();
        let src = open_on("mini3".to_string(), dial);
        craze_source_close(&src);
        let Err(err) = craze_lane_open(&src, CREATED.to_string()).await else {
            panic!("a closed source opened a lane");
        };
        assert!(
            matches!(err, BridgeLaneError::Unavailable { .. }),
            "transient — a lane racing its source's retirement retries: {err:?}"
        );
        let refused = craze_create_options(&src).await;
        assert!(
            matches!(refused, Err(BridgeLaneError::Unavailable { .. })),
            "{refused:?}"
        );
        assert_eq!(live_counters().active_lanes, 0);
        assert_eq!(live_counters().pending_craze_calls, 0);
    }

    /// Dart's note is a nudge of its own: the class reaches the snapshot
    /// without waiting for Rust's next frame, and the same note twice is no
    /// news.
    #[test]
    fn darts_note_raises_one_nudge() {
        let _g = test_guard();
        let (dial, _conns) = ScriptedDial::new();
        let src = open_on("mini3".to_string(), dial);
        let sink = CountingSink::new(false);
        assert!(spawn_forwarder(&src.inner, sink.push_fn()));
        craze_source_note_reach(
            &src,
            BridgeSourceOffline::TooOld,
            "Error: unknown flag: --hub".to_string(),
        );
        assert!(crate::api::testsupport::wait_until(
            Duration::from_secs(5),
            || sink.pushes() >= 1
        ));
        let snap = craze_source_snapshot(&src);
        assert_eq!(
            snap.offline,
            Some(BridgeCrazeOffline {
                cause: BridgeSourceOffline::TooOld,
                reason: "Error: unknown flag: --hub".to_string()
            })
        );
        let before = sink.pushes();
        craze_source_note_reach(
            &src,
            BridgeSourceOffline::TooOld,
            "Error: unknown flag: --hub".to_string(),
        );
        std::thread::sleep(Duration::from_millis(100));
        assert_eq!(sink.pushes(), before, "the same note twice is no news");
        craze_source_close(&src);
        assert_eq!(live_counters().active_craze_sources, 0);
    }

    /// One claim on the nudge stream; a claim on a closed source is refused
    /// and counted nowhere.
    #[test]
    fn a_second_nudge_claim_is_refused() {
        let _g = test_guard();
        let (dial, _conns) = ScriptedDial::new();
        let src = open_on("mini3".to_string(), dial);
        assert!(spawn_forwarder(
            &src.inner,
            CountingSink::new(false).push_fn()
        ));
        assert!(!spawn_forwarder(
            &src.inner,
            CountingSink::new(false).push_fn()
        ));
        assert_eq!(live_counters().active_craze_forwarders, 1);
        craze_source_close(&src);
        assert!(!spawn_forwarder(
            &src.inner,
            CountingSink::new(false).push_fn()
        ));
        assert_eq!(live_counters().active_craze_forwarders, 0);
        assert_eq!(live_counters().active_craze_sources, 0);
    }

    /// **Self-teardown**: a Dart consumer that cancelled the nudge stream
    /// without closing the source must not leave the roster pump holding a
    /// connection nobody reads.
    #[test]
    fn a_forwarder_whose_sink_is_gone_tears_the_source_down() {
        let _g = test_guard();
        let (dial, _conns) = ScriptedDial::new();
        let src = open_on("mini3".to_string(), dial);
        let sink = CountingSink::new(true);
        assert!(spawn_forwarder(&src.inner, sink.push_fn()));
        src.inner.touch();
        assert!(
            crate::api::testsupport::wait_until(Duration::from_secs(5), || {
                live_counters().active_craze_sources == 0
            }),
            "a failed push left the source open"
        );
        assert_eq!(live_counters().active_craze_forwarders, 0);
        craze_source_close(&src);
        assert_eq!(live_counters().active_craze_sources, 0);
    }

    /// `Drop` is the backstop: a handle Dart lets go of without closing still
    /// returns every counter.
    #[test]
    fn dropping_the_handle_tears_the_source_down() {
        let _g = test_guard();
        {
            let (dial, _conns) = ScriptedDial::new();
            let src = open_on("mini3".to_string(), dial);
            assert!(spawn_forwarder(
                &src.inner,
                CountingSink::new(false).push_fn()
            ));
            assert_eq!(live_counters().active_craze_sources, 1);
        }
        assert_eq!(live_counters().active_craze_sources, 0);
        assert_eq!(live_counters().active_craze_forwarders, 0);
    }

    /// The commands Dart execs are shed-core's, verbatim: the production
    /// ladder (with its exec PATH) and the jailed one (rungs 1–2 only) — never
    /// confused.
    #[test]
    fn the_commands_are_shed_cores_own() {
        assert_eq!(
            craze_remote_command(),
            shed_core::craze::bridge_hub_command()
        );
        let jailed = craze_jailed_bridge_argv();
        assert_eq!(jailed, shed_core::craze::bridge_hub_argv_jailed());
        assert_eq!(jailed[..2], ["sh", "-c"]);
        assert!(jailed[2].ends_with("exit 127") || jailed[2].contains("command not found"));
        assert!(
            !jailed[2].contains("/usr/local/bin"),
            "the jailed ladder reaches no absolute rung"
        );
        assert!(shed_craze::valid_request_id(&craze_new_request_id()));
    }
}
