//! **A machine's `roost-session` → Dart `Stream`** (plan 013 S3m, the Roost
//! Pivot's first milestone).
//!
//! This replaces `api/machine.rs`, which read the same machines through the RC
//! activity hub. The hub inferred an agent's state by watching its tmux pane;
//! roost's agent adapters *report* it, so the four agent axes (`shell_state`,
//! `agent_lifecycle`, `ownership`, `has_notification`) arrive as first-class
//! wire fields and the client's job shrinks to rendering them.
//!
//! ## The seam, and why it points the way it does
//!
//! Unchanged from the hub path, deliberately — this is a re-point, not a
//! re-architecture:
//!
//! ```text
//!   Dart: ServerSocket on 127.0.0.1:<port> ──dartssh2 execute──▶ roost-session client-bridge
//!   Rust: RoostWatcher(LabelledPort(port)) ──roost IPC (JSON lines)──▶ 127.0.0.1:<port>
//! ```
//!
//! Rust never calls into Dart: it is handed a `u16` and dials loopback. What
//! changed is only what is on the far side of that port — roost's session socket
//! rather than the hub's HTTP/SSE — and Dart is told what to exec by
//! [`roost_remote_command`], never by composing anything itself.
//!
//! **The port must stay stable across a re-establish** (the plan-012 invariant).
//! When the phone changes networks or wakes from the background, Dart re-dials
//! the SSH connection underneath the SAME listening socket; from Rust's side the
//! port simply keeps working, so a dropped tunnel is an ordinary reconnect
//! ("the socket refused") rather than a re-acquire protocol.
//! [`shed_app::roost::LabelledPort`] is that reach — `FixedPort` with the
//! machine's name attached, so a failure message reads in the vocabulary the
//! user typed.
//!
//! ## Everything runs on `bridge_rt`
//!
//! Every async entry point here hands its work to the persistent runtime via
//! [`on_bridge_rt`], and that is load-bearing rather than tidy: a loopback-TCP
//! [`Conn`][shed_core::roost::Conn] owns a `copy_bidirectional` pump task, so a
//! connection built on FRB's per-call executor would lose its pump the moment
//! that call returned. A held connection — the watcher's, and the peek's — must
//! live on a runtime that outlives the call that made it.
//!
//! ## Lifecycle
//!
//! The two-call shape and the locked teardown mirror [`super::watcher`] exactly
//! — see its module doc for the reasoning (start-races-stop, the synchronous
//! stop as the deterministic cancellation seam, `Drop` as the backstop).
//! Divergences are noted where they occur.

use std::future::Future;
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex};

use flutter_rust_bridge::frb;
use roost_ipc::messages::{Project, Tab, TabDumpResult, TabOpenParams};
use shed_app::machine::FixedPort;
use shed_app::roost::{LabelledPort, RoostPeek, RoostUpdate, RoostWatcher};
use shed_core::rc::RcKind;
use shed_core::roost::RoostSession;
use tokio::sync::mpsc::UnboundedReceiver;

use crate::frb_generated::StreamSink;

use super::bridge_rt::{bridge_rt, ACTIVE_FORWARDERS, ACTIVE_WATCHERS};
use super::dto_rc::{BridgeRcCapabilities, BridgeRcSession};

// ---------------------------------------------------------------------------
// the watcher
// ---------------------------------------------------------------------------

/// One update from a machine's `roost-session`.
///
/// Two members, not three: roost's inventory is read whole on every poll, so
/// there is no patch stream to fold and no partial update to reconcile. A
/// `Snapshot` is authoritative for the WHOLE machine — which is what makes a
/// reconnect a complete resync with no replay protocol to negotiate, and what
/// lets a phone simply stop the watcher when it backgrounds and restart it on
/// foreground.
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeRoostUpdate {
    /// The machine's full agent-owned tab list, as of this poll. Replaces
    /// whatever the consumer held.
    ///
    /// `revision` is roost's commit counter — an in-process number that RESETS
    /// when the daemon restarts, which is why it is reported rather than
    /// compared here: the watcher already fences on `(session_id, revision)` per
    /// connection, and a consumer that treats a smaller number as stale would
    /// go blind for the rest of that daemon's life. `None` only from a socket
    /// that publishes no fence.
    Snapshot {
        sessions: Vec<BridgeRcSession>,
        revision: Option<u64>,
    },
    /// The session is not readable: the tunnel is not there, nothing is
    /// listening, the thing on the other end is not a roost-session, or a
    /// request failed. The watcher backs off and retries.
    ///
    /// **A normal state, not an error.** A machine that is asleep, off-network,
    /// or simply runs no roost-session is the everyday case; the UI renders its
    /// rows as last-known with a reason rather than failing.
    Down { reason: String },
}

struct RoostWatcherInner {
    watcher: Option<RoostWatcher>,
    rx: Option<UnboundedReceiver<RoostUpdate>>,
    forwarder: Option<tokio::task::AbortHandle>,
    streaming: bool,
    stopped: bool,
}

/// An opaque handle to one machine's roost watcher.
#[frb(opaque)]
pub struct BridgeRoostWatcher {
    state: Arc<Mutex<RoostWatcherInner>>,
}

impl Drop for BridgeRoostWatcher {
    fn drop(&mut self) {
        teardown(&self.state);
    }
}

/// The SINGLE teardown/decrement point, idempotent via `stopped`: abort the
/// forwarder (immediately, even parked on `recv`), drop the watcher (which
/// aborts its poll loop and closes the held connection), and decrement each
/// counter exactly once — only for resources that were actually counted.
fn teardown(state: &Arc<Mutex<RoostWatcherInner>>) {
    let mut s = state.lock().unwrap_or_else(|e| e.into_inner());
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

/// Claim the watcher's receiver, once. `None` means the handle is torn down or
/// something already took it — a second stream on one handle would silently
/// split the updates between two consumers.
fn claim_rx(state: &Arc<Mutex<RoostWatcherInner>>) -> Option<UnboundedReceiver<RoostUpdate>> {
    let mut s = state.lock().unwrap_or_else(|e| e.into_inner());
    if s.stopped || s.streaming {
        return None;
    }
    let rx = s.rx.take()?;
    s.streaming = true;
    Some(rx)
}

/// Start watching the `roost-session` reachable on `127.0.0.1:<local_port>`.
///
/// `local_port` is the `RoostTunnel`'s listening port (`lib/ssh/roost_tunnel.dart`
/// — see the module doc). `machine` is the machine's name, and unlike the hub
/// path it is NOT diagnostics-only: it is stamped on every row as the
/// inventory's `host_label` (what a client turns into `origin: "machine:<name>"`)
/// and it names the reach in a failure message.
///
/// Does NOT dial anything itself: the watcher connects on its own schedule and
/// reports [`BridgeRoostUpdate::Down`] until it can, so a machine that is asleep
/// costs a caller nothing at construction time.
pub fn create_roost_watcher(machine: String, local_port: u16) -> BridgeRoostWatcher {
    let (watcher, rx) = RoostWatcher::spawn(
        bridge_rt().handle(),
        Arc::new(LabelledPort::new(machine.clone(), local_port)),
        machine,
    );
    ACTIVE_WATCHERS.fetch_add(1, Ordering::SeqCst);
    BridgeRoostWatcher {
        state: Arc::new(Mutex::new(RoostWatcherInner {
            watcher: Some(watcher),
            rx: Some(rx),
            forwarder: None,
            streaming: false,
            stopped: false,
        })),
    }
}

/// Stream this machine's updates. Claims the receiver, so a second call on the
/// same handle is a no-op rather than a silent split of the stream.
pub fn roost_watcher_events(handle: &BridgeRoostWatcher, sink: StreamSink<BridgeRoostUpdate>) {
    let Some(rx) = claim_rx(&handle.state) else {
        return;
    };
    let state = handle.state.clone();
    let forwarder = bridge_rt().spawn(forward_loop(rx, sink, state.clone()));
    // Re-check `stopped`: if teardown won the race during the spawn, abort the
    // task we just started and do NOT count it — the decrement already happened.
    let mut s = state.lock().unwrap_or_else(|e| e.into_inner());
    if s.stopped {
        forwarder.abort();
    } else {
        s.forwarder = Some(forwarder.abort_handle());
        ACTIVE_FORWARDERS.fetch_add(1, Ordering::SeqCst);
    }
}

/// Stop watching — the SYNCHRONOUS co-primary teardown (a Riverpod `onDispose`
/// calls this). `Drop` is the backstop.
pub fn stop_roost_watcher(handle: &BridgeRoostWatcher) {
    teardown(&handle.state);
}

/// Drain `rx`, map each update, push it to the Dart sink — and SELF-TEAR-DOWN
/// when the loop ends, exactly as [`super::watcher::forward_loop`] does.
///
/// That last part is the whole reason `state` is passed in. The loop ends either
/// because the watcher's channel closed (teardown already ran) or because
/// `sink.add` failed — and the second case is a Dart consumer that cancelled the
/// stream WITHOUT calling [`stop_roost_watcher`]. Without the teardown here the
/// forwarder would exit while the [`RoostWatcher`] kept polling its held
/// connection forever with nobody reading it. `teardown` is idempotent, so the
/// later sync stop / `Drop` still costs exactly one decrement of each counter.
async fn forward_loop(
    mut rx: UnboundedReceiver<RoostUpdate>,
    sink: StreamSink<BridgeRoostUpdate>,
    state: Arc<Mutex<RoostWatcherInner>>,
) {
    while let Some(update) = rx.recv().await {
        // A failed send means Dart cancelled without calling stop — the backstop
        // for a consumer that vanished.
        if sink.add(bridge_update(update)).is_err() {
            break;
        }
    }
    teardown(&state);
}

/// The whole Rust→Dart mapping, as a pure function so it is testable without a
/// `StreamSink` (which only the generated Dart-facing glue can construct).
fn bridge_update(update: RoostUpdate) -> BridgeRoostUpdate {
    match update {
        RoostUpdate::Snapshot(inventory) => BridgeRoostUpdate::Snapshot {
            sessions: inventory
                .sessions
                .iter()
                .map(BridgeRcSession::from_roost)
                .collect(),
            revision: inventory.revision,
        },
        RoostUpdate::Down { reason } => BridgeRoostUpdate::Down { reason },
    }
}

// ---------------------------------------------------------------------------
// one-shots
// ---------------------------------------------------------------------------
//
// Every one dials, calls, and hangs up. Over SSH that is a fresh remote exec per
// call, which is the honest cost of a one-shot and exactly why the watcher and
// the peek hold their connections instead.
//
// M1's control surface is deliberately two verbs. `roost_capabilities()`
// advertises `post_input: false`, `approvals: "none"`, `interrupt: false` — so
// the app's existing per-feature gates hide steer/interrupt/approve with no new
// UI conditionals, and nothing here can be called for a thing roost cannot do.

/// `tab.close` — end a tab. It leaves `tab.list` entirely, so the row
/// disappears on the next poll rather than turning into a dead card.
pub async fn roost_tab_close(local_port: u16, tab_id: i64) -> Result<(), String> {
    on_bridge_rt(async move { shed_app::roost::tab_close(&FixedPort(local_port), tab_id).await })
        .await
}

/// `tab.open` — start `kind`'s agent in a fresh tab at `workdir`, and get back
/// the row for it.
///
/// The argv is [`shed_app::roost::launch_argv`]'s and nothing else (plan 013
/// §4: prompts and permission modes are a later slice). An unrecognized kind —
/// or a kind roost has no launch recipe for, `shell` and `grok` included — is
/// refused BY NAME here rather than opening an empty tab somebody has to notice
/// and close.
///
/// `project_id: 0` asks roost for its default project; `cols`/`rows` are left at
/// zero so roost picks its own initial geometry (the phone never renders this
/// tab's terminal — the peek re-reads whatever size roost chose).
///
/// **The returned row's kind is the kind that was ASKED for, not the one roost
/// reports.** A freshly opened tab has no `ownership` yet — the adapter claims
/// it a moment later, when the agent starts reporting — so
/// [`RoostSession::to_rc_dto`] would map it to `shell` and the card would render
/// as a bare terminal until the next poll corrected it. Substituting the
/// requested kind makes the optimistic card right immediately, and the poll that
/// follows replaces it with roost's own answer either way.
pub async fn roost_tab_open(
    local_port: u16,
    machine: String,
    kind: String,
    workdir: String,
) -> Result<BridgeRcSession, String> {
    let rc_kind = RcKind::from_wire(&kind);
    let argv =
        shed_app::roost::launch_argv(&rc_kind).ok_or_else(|| format!("unknown kind: {kind}"))?;
    let label = machine.clone();
    let tab = on_bridge_rt(async move {
        shed_app::roost::tab_open(
            &LabelledPort::new(label, local_port),
            TabOpenParams {
                project_id: 0,
                cwd: workdir,
                argv,
                cols: 0,
                rows: 0,
                title: String::new(),
            },
        )
        .await
    })
    .await?;
    Ok(opened_row(&machine, &rc_kind, &tab))
}

/// Map the `Tab` a `tab.open` returned onto a row, with the requested kind
/// substituted (see [`roost_tab_open`]).
fn opened_row(machine: &str, kind: &RcKind, tab: &Tab) -> BridgeRcSession {
    // `RoostSession::from_tab` takes the LISTING project, because on the
    // `tab.list` path the nesting is what says which project a tab is in. A
    // `tab.open` reply carries no project at all, so the tab's own `project_id`
    // is the whole of what is known — the name is only a card label and the
    // next poll supplies it.
    let project = Project {
        id: tab.project_id,
        name: String::new(),
        cwd: String::new(),
        position: 0,
        created_at: 0,
        tabs: Vec::new(),
    };
    let session = RoostSession::from_tab(machine, &project, tab);
    let mut dto = session.to_rc_dto();
    dto.kind = kind.clone();
    BridgeRcSession::from_roost_dto(&session, dto)
}

// ---------------------------------------------------------------------------
// the peek
// ---------------------------------------------------------------------------

/// One `tab.dump` frame: the tab's visible viewport as text.
///
/// The cursor is flattened into three fields rather than carried as a nested
/// optional struct — FRB would render that as a second Dart class whose only
/// job is to hold three primitives, and the peek screen reads all three
/// together. `cursor_visible` is `false` when roost reported no cursor at all,
/// which is the same thing to a renderer that only highlights a visible one.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTabDump {
    pub cols: u32,
    pub rows: u32,
    pub cursor_row: Option<u32>,
    pub cursor_col: Option<u32>,
    pub cursor_visible: bool,
    /// One entry per visible row, trailing blanks trimmed by roost.
    pub rows_text: Vec<String>,
}

impl From<TabDumpResult> for BridgeTabDump {
    fn from(dump: TabDumpResult) -> Self {
        BridgeTabDump {
            cols: dump.cols,
            rows: dump.rows,
            cursor_row: dump.cursor.as_ref().map(|c| c.row),
            cursor_col: dump.cursor.as_ref().map(|c| c.col),
            cursor_visible: dump.cursor.is_some_and(|c| c.visible),
            rows_text: dump.rows_text,
        }
    }
}

/// A held connection for repeatedly dumping one tab — the read-only terminal
/// affordance (roost R3 lands attach; until then there is none).
///
/// It holds ONE connection for the peek's whole life because the alternative is
/// a remote `ssh` exec per frame, and the peek refreshes on a timer.
#[frb(opaque)]
pub struct BridgeRoostPeek {
    /// `None` once closed. A `tokio` mutex rather than a `std` one because the
    /// dump is awaited while it is held.
    inner: Arc<tokio::sync::Mutex<Option<RoostPeek>>>,
}

impl Drop for BridgeRoostPeek {
    fn drop(&mut self) {
        close_peek(&self.inner);
    }
}

/// Dial and hold, for a peek loop on `tab_id`.
///
/// The tab is not validated here — the first [`roost_peek_dump`] is what says
/// whether it exists — so opening a peek costs exactly one round trip.
pub async fn roost_peek_open(local_port: u16, tab_id: i64) -> Result<BridgeRoostPeek, String> {
    let peek =
        on_bridge_rt(async move { RoostPeek::open(Arc::new(FixedPort(local_port)), tab_id).await })
            .await?;
    Ok(BridgeRoostPeek {
        inner: Arc::new(tokio::sync::Mutex::new(Some(peek))),
    })
}

/// One frame, over the held connection.
pub async fn roost_peek_dump(handle: &BridgeRoostPeek) -> Result<BridgeTabDump, String> {
    let inner = handle.inner.clone();
    on_bridge_rt(async move {
        let mut guard = inner.lock().await;
        let peek = guard
            .as_mut()
            .ok_or_else(|| "the peek is closed".to_string())?;
        peek.dump()
            .await
            .map(BridgeTabDump::from)
            .map_err(|e| e.to_string())
    })
    .await
}

/// Close the peek and drop its connection. Idempotent; `Drop` is the backstop.
pub fn roost_peek_close(handle: &BridgeRoostPeek) {
    close_peek(&handle.inner);
}

/// Take the held connection, synchronously when nothing is using it.
///
/// Dropping the [`RoostPeek`] is the whole of closing one: `tab.dump` is
/// lease-free and stateless, so there is no server-side state an explicit close
/// could release. When a dump is in flight the lock is held and cannot be taken
/// from a synchronous caller, so the take is deferred onto `bridge_rt` — the
/// connection then dies the instant that dump returns, which is as early as it
/// could possibly die anyway.
fn close_peek(inner: &Arc<tokio::sync::Mutex<Option<RoostPeek>>>) {
    if let Ok(mut guard) = inner.try_lock() {
        drop(guard.take());
        return;
    }
    let inner = inner.clone();
    bridge_rt().spawn(async move {
        drop(inner.lock().await.take());
    });
}

// ---------------------------------------------------------------------------
// the two constants Dart needs
// ---------------------------------------------------------------------------

/// The command the Dart tunnel execs on the far side, verbatim.
///
/// **Dart composes no part of it.** It is roost's own resolver chain ending in
/// `exec roost-session client-bridge`, and it is opaque on purpose: which
/// candidate path wins, and how the chain is quoted, is roost's contract with
/// itself. Handing Dart the finished string is what keeps the phone out of the
/// argv-composition business entirely (shed's `tests/machine-transport` owns
/// that contract for everything that is still composed).
///
/// It reads this process's own `ROOST_TEST_MODE`, so a shipped app always emits
/// the shipped chain.
#[frb(sync)]
pub fn roost_remote_command() -> String {
    roost_ipc::ssh::remote_command()
}

/// The capabilities a roost-backed machine advertises.
///
/// **Synthesized, not probed** — roost is a terminal multiplexer with agent
/// adapters, not shed's guest agent, so there is no `shed-ext-rc capabilities`
/// to ask. `shed-core` states the contract honestly instead: for M1 a roost row
/// can be listed, launched and closed, and nothing else. Every feature the RC
/// hub used to offer for a machine (feed, typed input, approvals, interrupt) is
/// `false`/empty here, which is what makes the app's existing per-feature gates
/// hide those controls with no new UI conditionals.
///
/// `attach` is `native-remote`: the terminal belongs to roost, so the phone's
/// affordance is the read-only [`roost_peek_dump`] peek, never a tmux attach.
///
/// Sync because it is a constant — there is no host to ask, and making the UI
/// await a round trip that does not exist would gate the controls on nothing.
#[frb(sync)]
pub fn roost_capabilities() -> BridgeRcCapabilities {
    shed_app::roost::roost_capabilities().into()
}

// ---------------------------------------------------------------------------
// the runtime hop
// ---------------------------------------------------------------------------

/// Run `fut` on the persistent bridge runtime and await its result.
///
/// Lifted from [`super::client`]'s `run`, for its reason plus one of this
/// module's own:
///
/// * **Abort-on-drop.** Dropping a `JoinHandle` DETACHES the task, so an FRB
///   future dropped mid-await (Dart cancelled the call) would leave a roost
///   request — and its connection — running to its own timeout. The guard holds
///   the `AbortHandle` and fires on drop; it is disarmed only after a successful
///   join.
/// * **The pump.** A loopback-TCP `Conn` spawns a `copy_bidirectional` task, and
///   `tokio::spawn` binds it to whatever runtime is current. On FRB's per-call
///   executor that runtime goes away with the call — so every connection this
///   module makes is made from `bridge_rt`, whether or not it is held.
///
/// A join failure (task panic/abort) becomes an ordinary error rather than a
/// panic propagating across the FFI boundary.
async fn on_bridge_rt<T, F>(fut: F) -> Result<T, String>
where
    F: Future<Output = Result<T, String>> + Send + 'static,
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
        Err(e) => Err(format!("bridge task join error: {e}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use shed_core::roost::testing::{ownership, FakeRoost};
    use std::sync::Once;
    use std::time::Duration;

    use crate::api::bridge_rt::live_counters;
    use crate::api::dto_rc::{BridgeRcActivity, BridgeRcKind};
    use crate::api::testsupport::test_guard;

    /// The watcher's poll cadence is 2 s in production and read ONCE per spawn
    /// from the environment. Set it here — once, never unset — so a test that
    /// waits for the second snapshot waits milliseconds instead of seconds.
    fn fast_polling() {
        static ONCE: Once = Once::new();
        ONCE.call_once(|| std::env::set_var("SHED_ROOST_POLL_MS", "25"));
    }

    /// Wait for one update, or fail with a message rather than hanging the suite.
    async fn next_update(rx: &mut UnboundedReceiver<RoostUpdate>, what: &str) -> BridgeRoostUpdate {
        let update = tokio::time::timeout(Duration::from_secs(10), rx.recv())
            .await
            .unwrap_or_else(|_| panic!("timed out waiting for {what}"))
            .unwrap_or_else(|| panic!("the watcher ended before {what}"));
        bridge_update(update)
    }

    /// **The leak contract**: create bumps both counters, teardown returns both,
    /// and a second stop is a no-op rather than a second decrement.
    ///
    /// A double-decrement is the failure that matters — the counters are `u64`,
    /// so one would wrap to 18446744073709551615 and every later leak assertion
    /// would pass for the wrong reason.
    #[test]
    fn creating_and_stopping_a_watcher_leaves_the_counters_where_it_found_them() {
        let _g = test_guard();
        fast_polling();
        let before = live_counters();

        let handle = create_roost_watcher("mini3".into(), 1);
        assert_eq!(live_counters().active_watchers, before.active_watchers + 1);

        stop_roost_watcher(&handle);
        let after = live_counters();
        assert_eq!(after.active_watchers, before.active_watchers);
        assert_eq!(after.active_forwarders, before.active_forwarders);

        // Idempotent: the sync stop and `Drop` are co-primary, so teardown runs
        // at least twice for every watcher the app ever makes.
        stop_roost_watcher(&handle);
        drop(handle);
        let settled = live_counters();
        assert_eq!(settled.active_watchers, before.active_watchers);
        assert_eq!(settled.active_forwarders, before.active_forwarders);
    }

    /// **The end-to-end read**: a real [`RoostWatcher`] against a real socket,
    /// through the real mapping.
    ///
    /// The fake answers from roost's own vendored golden vectors, so the shapes
    /// asserted here cannot drift away from the shapes roost publishes. Its one
    /// tab starts as a plain shell — and a plain shell is NOT a session (a roost
    /// user with fifteen terminals must not get fifteen cards), so the first
    /// snapshot is empty. Claiming it for opencode, with the axes the shed spike
    /// recorded live inside the `roost-m1` VM, is what turns it into one row.
    #[tokio::test]
    async fn a_claimed_tab_becomes_one_mapped_row_over_the_loopback_port() {
        let _g = test_guard();
        fast_polling();
        let fake = FakeRoost::start().await;

        let handle = create_roost_watcher("mini3".into(), fake.tcp_port());
        let mut rx = claim_rx(&handle.state).expect("the receiver is claimable once");
        // A second claim must find nothing — otherwise two consumers would each
        // get half the updates.
        assert!(claim_rx(&handle.state).is_none());

        // A shell tab is not a session row.
        match next_update(&mut rx, "the first snapshot").await {
            BridgeRoostUpdate::Snapshot { sessions, revision } => {
                assert!(
                    sessions.is_empty(),
                    "an unowned shell tab must not be a card: {sessions:?}"
                );
                assert_eq!(revision, Some(42), "the vendored vector's revision");
            }
            other => panic!("expected a snapshot, got {other:?}"),
        }

        // The opencode adapter claims it (values recorded from the live spike).
        fake.set_tab_axes(
            5,
            "finished",
            Some(ownership(
                "opencode",
                "ses_f85010d7effexVvTJ1mRHZkDqL",
                "session_idle",
                1788769939,
            )),
            true,
        );

        // The revision changed, so the next poll publishes — and it publishes
        // ONE row, mapped.
        let sessions = loop {
            match next_update(&mut rx, "the claimed snapshot").await {
                BridgeRoostUpdate::Snapshot { sessions, .. } if !sessions.is_empty() => {
                    break sessions
                }
                BridgeRoostUpdate::Snapshot { .. } => continue,
                other => panic!("expected a snapshot, got {other:?}"),
            }
        };
        assert_eq!(sessions.len(), 1);
        let row = &sessions[0];
        assert_eq!(row.slug, "5", "the row's identity is roost's tab id");
        assert_eq!(row.tab_id, Some(5));
        assert_eq!(row.kind, BridgeRcKind::Opencode);
        assert_eq!(
            row.activity,
            Some(BridgeRcActivity::Idle),
            "finished → idle"
        );
        assert!(row.attention, "has_notification is the attention dot");
        assert_eq!(
            row.rc_id.as_deref(),
            Some("ses_f85010d7effexVvTJ1mRHZkDqL"),
            "the AGENT's own session id, not roost's tab id"
        );

        stop_roost_watcher(&handle);
    }

    /// A kind roost has no launch recipe for is refused BY NAME, before any
    /// connection is attempted — so the failure names the mistake instead of
    /// timing out against a machine that was never the problem.
    #[tokio::test]
    async fn opening_a_tab_for_an_unlaunchable_kind_is_refused_by_name() {
        for kind in ["gpt-next", "shell", "grok", "claude-broker", ""] {
            // Port 1 is deliberately dead: reaching it would mean the kind check
            // did not happen first.
            let err = roost_tab_open(1, "mini3".into(), kind.to_string(), "/home/shed".into())
                .await
                .expect_err("an unlaunchable kind must not open a tab");
            assert!(
                err.starts_with("unknown kind:"),
                "kind {kind:?} gave {err:?}"
            );
            assert!(
                err.contains(kind),
                "the message must name the kind: {err:?}"
            );
        }

        // The control: a launchable kind gets PAST the check and fails on the
        // transport instead, so the test above is not passing vacuously.
        let err = roost_tab_open(1, "mini3".into(), "opencode".into(), "/home/shed".into())
            .await
            .expect_err("nothing is listening on port 1");
        assert!(!err.starts_with("unknown kind:"), "{err}");
    }

    /// The remote command is roost's, whole, and it ends where it must.
    #[test]
    fn the_remote_command_execs_the_client_bridge() {
        let command = roost_remote_command();
        assert!(!command.is_empty());
        assert!(
            command.contains("client-bridge"),
            "the tunnel must exec roost's bridge subcommand: {command}"
        );
    }

    /// The capabilities a roost host advertises, as the app's gates read them:
    /// the attach affordance is `native-remote` (→ the peek, never a tmux
    /// attach) and the steering features every hub kind had are off.
    #[test]
    fn roost_capabilities_advertise_a_native_remote_attach_and_no_steering() {
        let caps = roost_capabilities();
        let opencode = caps
            .kind_features
            .get("opencode")
            .expect("opencode is a roost kind");
        assert_eq!(opencode.attach, "native-remote");
        assert!(!opencode.post_input);
        assert!(!opencode.interrupt);
        assert_eq!(opencode.approvals, "none");
        assert!(caps.kinds.contains(&BridgeRcKind::Opencode));
        // contract v2 is what tells a client to READ `attach` rather than assume
        // tmux — without it the gate would fall back to the old behaviour.
        assert_eq!(caps.rc_version, 2);
        assert!(caps.features.iter().any(|f| f == "contract-v2"));
    }
}
