//! **Machine hub → Dart `Stream`** (plan 012 S5, roadmap R4).
//!
//! A "machine" is a native host (not a shed VM) reached over SSH, running the
//! RC activity hub on its `127.0.0.1:1029`. Everything above "give me a local
//! port that reaches that hub" is shared Rust — the hub client, the snapshot,
//! the SSE feed, the reconnect/backoff — via `shed_app::machine`.
//!
//! ## The seam, and why it points the way it does
//!
//! Dart owns the transport, Rust owns everything above it:
//!
//! ```text
//!   Dart: ServerSocket on 127.0.0.1:<port>  ──dartssh2 forwardLocal──▶ machine:1029
//!   Rust: MachineHubWatcher(FixedPort(port)) ──plain HTTP/SSE──▶ 127.0.0.1:<port>
//! ```
//!
//! Rust never calls into Dart — it is handed a `u16` and dials loopback. That is
//! the same inverted shape this bridge already uses for one-shot RC exec (Rust
//! builds the argv, Dart runs it over dartssh2, Rust decodes the stdout), and it
//! is why a phone needs no Rust SSH client: `russh` in the shared core would be a
//! heavy dependency inside a workspace whose dependency-cleanliness is guarded,
//! and it is unproven on iOS/Android through FRB.
//!
//! **The port must stay stable across a re-establish.** When the phone changes
//! networks or wakes from a background, Dart re-dials the SSH connection
//! underneath the SAME listening socket; from Rust's side the port simply keeps
//! working, so a dropped tunnel is an ordinary reconnect ("the socket refused")
//! rather than a re-acquire protocol. `shed_app::machine::FixedPort` exists for
//! exactly this.
//!
//! ## Lifecycle
//!
//! The two-call shape and the locked teardown mirror [`super::watcher`] exactly —
//! see its module doc for the reasoning (start-races-stop, the synchronous stop
//! as the deterministic cancellation seam, `Drop` as the backstop). Divergences
//! are noted where they occur.

use std::sync::{Arc, Mutex};

use flutter_rust_bridge::frb;
use shed_app::machine::{FixedPort, MachineHubUpdate, MachineHubWatcher};
use tokio::sync::mpsc::UnboundedReceiver;

use crate::frb_generated::StreamSink;

use super::bridge_rt::bridge_rt;
use super::dto_rc::{BridgeRcEvent, BridgeRcMessagesPage, BridgeRcSession};

/// One update from a machine's hub.
///
/// Deliberately mirrors `shed_app::machine::MachineHubUpdate` rather than
/// flattening into the shed watcher's shape: a machine feed has no aggregate
/// stream and no per-shed filtering, so a `Snapshot` here is authoritative for
/// the WHOLE machine — which is what makes a reconnect a complete resync with no
/// replay protocol to negotiate. That property is what lets a phone simply stop
/// the watcher when it backgrounds and restart it on foreground.
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeMachineUpdate {
    /// The machine's full session list, as of this connection. Replaces
    /// whatever the consumer held; arrives on EVERY successful connect, and
    /// again whenever the feed mentions a session the snapshot did not cover.
    Snapshot { sessions: Vec<BridgeRcSession> },
    /// A live feed event.
    Event { event: BridgeRcEvent },
    /// The feed is not up: the tunnel is not there, the hub did not answer, or
    /// the stream ended. The watcher backs off and retries.
    ///
    /// **A normal state, not an error.** A machine that is asleep, off-network,
    /// or simply has no hub running is the everyday case; the UI renders its
    /// rows as last-known with a reason rather than failing.
    Down { reason: String },
}

struct WatcherInner {
    watcher: Option<MachineHubWatcher>,
    rx: Option<UnboundedReceiver<MachineHubUpdate>>,
    forwarder: Option<tokio::task::AbortHandle>,
    streaming: bool,
    stopped: bool,
}

/// An opaque handle to one machine's hub watcher.
#[frb(opaque)]
pub struct BridgeMachineWatcher {
    state: Arc<Mutex<WatcherInner>>,
}

impl Drop for BridgeMachineWatcher {
    fn drop(&mut self) {
        teardown(&self.state);
    }
}

/// The single teardown point, idempotent via `stopped`: abort the forwarder
/// (immediately, even parked on `recv`), then drop the watcher, which aborts its
/// reconnect loop.
fn teardown(state: &Arc<Mutex<WatcherInner>>) {
    let mut s = state.lock().unwrap_or_else(|e| e.into_inner());
    if s.stopped {
        return;
    }
    s.stopped = true;
    if let Some(f) = s.forwarder.take() {
        f.abort();
    }
    if let Some(w) = s.watcher.take() {
        w.stop();
    }
    s.rx = None;
}

/// Start watching the hub reachable on `127.0.0.1:<local_port>`.
///
/// `local_port` is the Dart-side tunnel's listening port (see the module doc).
/// `machine` names the machine for diagnostics only — nothing is keyed off it
/// here, because one watcher serves exactly one machine.
///
/// Does NOT dial anything itself: the watcher connects on its own schedule and
/// reports [`BridgeMachineUpdate::Down`] until it can, so a machine that is
/// asleep costs a caller nothing at construction time.
pub fn create_machine_watcher(machine: String, local_port: u16) -> BridgeMachineWatcher {
    let (watcher, rx) = MachineHubWatcher::spawn(
        bridge_rt().handle(),
        Arc::new(FixedPort(local_port)),
        machine,
    );
    BridgeMachineWatcher {
        state: Arc::new(Mutex::new(WatcherInner {
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
pub fn machine_watcher_events(
    handle: &BridgeMachineWatcher,
    sink: StreamSink<BridgeMachineUpdate>,
) {
    let rx = {
        let mut s = handle.state.lock().unwrap_or_else(|e| e.into_inner());
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
    let forwarder = bridge_rt().spawn(forward_loop(rx, sink));
    // Re-check `stopped`: if teardown won the race during the spawn, abort the
    // task we just started rather than leaving it running against a dead handle.
    let mut s = state.lock().unwrap_or_else(|e| e.into_inner());
    if s.stopped {
        forwarder.abort();
    } else {
        s.forwarder = Some(forwarder.abort_handle());
    }
}

/// Stop watching — the SYNCHRONOUS co-primary teardown (a Riverpod `onDispose`
/// calls this). `Drop` is the backstop.
pub fn stop_machine_watcher(handle: &BridgeMachineWatcher) {
    teardown(&handle.state);
}

async fn forward_loop(
    mut rx: UnboundedReceiver<MachineHubUpdate>,
    sink: StreamSink<BridgeMachineUpdate>,
) {
    while let Some(update) = rx.recv().await {
        let bridged = match update {
            MachineHubUpdate::Snapshot { sessions } => BridgeMachineUpdate::Snapshot {
                sessions: sessions
                    .into_iter()
                    // A machine session belongs to no shed and no server. The
                    // `host` slot carries the machine's ORIGIN handle so a
                    // unified list can key and label rows without inspecting
                    // `shed` — which is empty for every machine session, and
                    // would collide across two machines sharing a slug.
                    .map(|dto| {
                        let host = String::new();
                        shed_core::rc::RcSession::from_dto(dto, &host, "").into()
                    })
                    .collect(),
            },
            MachineHubUpdate::Event { event } => BridgeMachineUpdate::Event {
                event: event.into(),
            },
            MachineHubUpdate::Down { reason } => BridgeMachineUpdate::Down { reason },
        };
        // A failed send means Dart cancelled without calling stop — the backstop
        // for a consumer that vanished.
        if sink.add(bridged).is_err() {
            break;
        }
    }
}

// ---------------------------------------------------------------------------
// The control verbs (plan 012 S5b)
// ---------------------------------------------------------------------------
//
// These go over the SAME tunnel the feed does — the Dart side already owns a
// local port that reaches the machine's hub, so steering needs no second
// transport and no process spawn (which a phone cannot do anyway).
//
// **Every one is capability-gated on the far side**, and the UI must gate
// itself the same way off `kind_features` rather than off the kind: a `409
// not_supported` reaching a user as an error means the button should not have
// been offered. The error text carries the hub's own reason so a client can
// tell "this kind never can" from "not right now".

/// Start a turn on a machine session. Returns the turn id.
pub async fn machine_turn(local_port: u16, slug: String, text: String) -> Result<String, String> {
    client(local_port)?
        .turn(&slug, &text)
        .await
        .map_err(|e| e.to_string())
}

/// A page of a machine session's message feed.
///
/// The same `/v1/sessions/{slug}/messages` cursor a shed serves through its
/// server, read straight off the machine's hub over the tunnel — so the rich
/// per-session view a shed session gets renders identically for a machine. The
/// feed is where a person READS what an agent is doing; steering it without
/// that is guesswork, which is why this exists before the control verbs are
/// worth offering.
pub async fn machine_messages(
    local_port: u16,
    slug: String,
    since: u64,
) -> Result<BridgeRcMessagesPage, String> {
    client(local_port)?
        .messages(&slug, since)
        .await
        .map(Into::into)
        .map_err(|e| e.to_string())
}

/// Interrupt the running turn. `false` means nothing was running — a legitimate
/// answer, not a failure.
pub async fn machine_interrupt(local_port: u16, slug: String) -> Result<bool, String> {
    client(local_port)?
        .interrupt(&slug)
        .await
        .map_err(|e| e.to_string())
}

/// Send a line of input to a TUI-laned session (the keystroke path).
pub async fn machine_input(local_port: u16, slug: String, text: String) -> Result<(), String> {
    client(local_port)?
        .input(&slug, &text)
        .await
        .map_err(|e| e.to_string())
}

/// Answer a pending approval. `decision` is `allow` / `allow_always` / `deny`.
///
/// Only for a kind whose `approvals` capability is `"remote"`; a `"tui"` kind
/// reports approvals for INFORMATION only and must be answered in its terminal.
pub async fn machine_approve(
    local_port: u16,
    slug: String,
    id: String,
    decision: String,
) -> Result<String, String> {
    client(local_port)?
        .approve(&slug, &id, &decision)
        .await
        .map_err(|e| e.to_string())
}

/// Re-point a shed-core argv builder at a MACHINE's engine.
///
/// The shed-core builders take a single `bin` for argv[0] because in a shed the
/// engine is one binary (`shed-ext-rc`). On a machine it is a two-token prefix
/// (`<rc_bin> rc`), so argv[0] is replaced by the whole prefix — spliced, not
/// joined, so a path with a space stays ONE argv word under the quoter rather
/// than splitting into two.
///
/// Every machine-targeted one-shot must go through here. A builder used raw
/// runs the GUEST binary name on the machine, where it does not exist — which
/// fails silently for anything whose failure path is a degradation rather than
/// an error (the capability probe is exactly that).
fn machine_argv(rc_bin: String, build: impl FnOnce(&str) -> Vec<String>) -> Vec<String> {
    let entry = shed_core::config::MachineEntry {
        rc_bin: Some(rc_bin),
        ..Default::default()
    };
    let prefix = shed_core::machine::rc_prefix(&entry);
    let mut argv = build(prefix.last().expect("prefix is never empty"));
    argv.splice(0..1, prefix.iter().cloned());
    argv
}

/// Kill a session on a machine.
///
/// The one verb that does NOT go over the hub: the hub observes and steers, it
/// does not remove. A kill is the one-shot engine's `rc kill`, which the Dart
/// side runs over SSH exactly as it runs `list`/`create` for a shed — so it
/// takes the composed argv, not a port.
pub fn machine_kill_argv(rc_bin: String, slug: String) -> Vec<String> {
    machine_argv(rc_bin, |bin| shed_core::rc::kill_argv(bin, &slug))
}

/// `<rc_bin> rc list` on a machine — the CAPABILITY probe.
///
/// The list response carries the engine's capability envelope, and those
/// `kind_features` are what gate every control the UI offers. Without this the
/// probe runs the guest binary name, exits non-zero, and the client degrades to
/// observe-only — correct, safe, and completely invisible, which is why it went
/// unnoticed until a live machine had a steerable session on it.
pub fn machine_list_argv(rc_bin: String) -> Vec<String> {
    machine_argv(rc_bin, shed_core::rc::list_argv)
}

fn client(local_port: u16) -> Result<shed_core::hub_client::HubClient, String> {
    shed_core::hub_client::HubClient::loopback(local_port).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A machine's engine is `<rc_bin> rc <verb>`, NOT the guest binary the
    /// shed-core builders name in argv[0].
    ///
    /// This is pinned because getting it wrong fails SILENTLY for the capability
    /// probe: a probe that exits non-zero means "observe-only", which is a
    /// legitimate state, so the app worked perfectly with every control missing
    /// and nothing complained. It survived a green suite, a hermetic e2e, and a
    /// live watch — it only surfaced once a machine had a steerable session.
    #[test]
    fn every_machine_argv_carries_the_two_token_engine_prefix() {
        let bin = "/home/charliek/.local/bin/sx".to_string();

        let list = machine_list_argv(bin.clone());
        assert_eq!(&list[..2], &[bin.clone(), "rc".to_string()]);
        assert_eq!(list.last().unwrap(), "list");
        assert!(!list.iter().any(|a| a.contains("shed-ext-rc")));

        let kill = machine_kill_argv(bin.clone(), "abc123".to_string());
        assert_eq!(&kill[..2], &[bin, "rc".to_string()]);
        assert!(kill.iter().any(|a| a == "kill"));
        assert!(kill.iter().any(|a| a == "abc123"));
    }

    /// Spliced, not joined. A joined prefix would split a path containing a
    /// space into two words on the far side and run a binary that is not there.
    #[test]
    fn an_engine_path_with_a_space_stays_one_argv_word() {
        let argv = machine_list_argv("/opt/my tools/sx".to_string());
        assert_eq!(argv[0], "/opt/my tools/sx");
        assert_eq!(argv[1], "rc");
    }
}
