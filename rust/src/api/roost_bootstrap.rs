//! **Putting a `roost-session` on a machine, from the phone** (plan 020 §3.8,
//! commit C-M2).
//!
//! The choreography is not here and must never be re-implemented here. It is
//! [`shed_core::roost::bootstrap`]'s two sans-IO machines — [`ProbeMachine`] and
//! [`InstallMachine`] — which perform no I/O at all: they yield a
//! [`Step`] and consume an [`Outcome`], and the caller owns every socket,
//! subprocess and timer. The desktop drives the whole loop in Rust over an `ssh`
//! ControlMaster. A phone has no `ssh` binary, so this module drives the same
//! machines over **two** transports at once.
//!
//! ## The split, which is the whole design (§3.8, pinned)
//!
//! > `ProbeMachine` and `InstallMachine` are driven on the Rust side over
//! > `bridge_rt`; Dart executes `Step::Exec` through dartssh2 and Rust executes
//! > `Step::Call` / `Step::Hooks` over the existing loopback `Conn`.
//!
//! So the FRB boundary carries **only `Exec` steps and the finished answer**:
//!
//! ```text
//!   Dart ── roost_bootstrap_begin ─────────────▶ Rust: machine.begin()
//!                                                     ↻ absorb Call / Hooks
//!                                                       over Conn::tcp_loopback
//!   Dart ◀── BridgeBootstrapStep::Exec ────────────────┘
//!   Dart: run it over dartssh2
//!   Dart ── roost_bootstrap_feed_exec ─────────▶ Rust: machine.feed(Outcome::Exec)
//!                                                     ↻ absorb Call / Hooks
//!   Dart ◀── Exec | Probed | Installed | Failed ───────┘
//! ```
//!
//! A `Call`'s params and a `Call`'s answer are `serde_json::Value` — roost's own
//! message schema, not shed's. `bootstrap`'s module doc calls them "the
//! exception that proves" the FRB-mirror rule, precisely because they never
//! cross: re-mirroring roost's wire shapes into Dart for a value Dart never
//! looks at would be inventing a second copy of somebody else's schema.
//!
//! ## The FRB-mirror rule, absolute (`crates/CLAUDE.md`)
//!
//! Every DTO below is owned `String` / `Option` / `Vec` / scalars. No
//! `serde_json::Value`, no `HashMap`, no borrowed lifetimes. A fielded Rust enum
//! becomes a Dart sealed class, a plain one a plain Dart enum, each with an
//! explicit `From` and an exhaustive conversion test — the house pattern in
//! [`super::dto_lane`].
//!
//! ## The one thing Dart has that Rust cannot see: why the reach failed
//!
//! `session.identify` failing is not one state but three, and telling them apart
//! is what the whole plan matrix turns on: a session answered, a `roost-session`
//! is installed and not running, or there is none at all. The wire cannot say
//! which — a loopback port whose far-side exec died at 127 looks exactly like
//! one whose exec died saying `client-bridge: no session`. On the desktop the
//! classification is read off the transport shed itself owns
//! (`RoostReach::last_error`). **On the phone Dart owns the transport**, so
//! Dart is the only layer that can classify, and [`roost_bootstrap_note_reach`]
//! is where it hands the classification over. A handle that is never told
//! reports `transport`, and the machine then reports the probe as *failed*
//! rather than guessing at a cheerful "not installed" — roost's rule, kept.
//!
//! ## Lifecycle
//!
//! The house shape ([`super::lane`], [`super::roost`]): one `Arc<Mutex<Inner>>`,
//! one idempotent [`teardown`], a `#[frb(sync)]` close a Riverpod `onDispose`
//! calls, `Drop` as the backstop, and a leak counter
//! ([`ACTIVE_ROOST_BOOTSTRAPS`]) a test asserts returns to zero.
//!
//! The machine itself is **checked out** of the lock for the duration of a
//! drive rather than locked across the awaits inside it, so the synchronous
//! close never has to wait for a remote round trip. A drive that is dropped
//! mid-flight (Dart cancelled the call, so `joined_on_bridge_rt` aborted the
//! task) puts the machine back through [`MachineGuard`]'s own `Drop` — which is
//! sound because `begin` and `feed` are *idempotent in their step*: both compute
//! the step for the current state rather than return one they stashed, so
//! [`roost_bootstrap_begin`] doubles as "re-read the step I am owed".
//!
//! A close that lands while a drive holds the machine is noticed at that drive's
//! next **step boundary** ([`bump_steps`]), which every absorbed step passes
//! through: the drive stops there rather than dialling the loopback port again,
//! and refuses rather than handing back a step for a handle Dart has already
//! disposed of. The same boundary is why Dart's reach note is spent only on an
//! outcome that is actually about to reach the machine (see [`classify`]).
//!
//! **The rule that follows, for the Dart side: after a cancelled call, RE-READ
//! with [`roost_bootstrap_begin`] — never re-send the outcome.** The symmetry
//! above is about computing a step, and `feed` does one thing more than compute:
//! it CONSUMES the outcome and advances the state. A cancellation that lands
//! after the machine advanced but before Dart saw the answer leaves a machine
//! that is already past that step, so feeding the same outcome again would
//! advance it a second time on one exec — a probe that skips a rung, or an
//! install that takes a later stage's branch. Nothing here can tell the two
//! apart, because an outcome carries no identity; the re-read is what makes the
//! distinction unnecessary.

use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex, MutexGuard};

use flutter_rust_bridge::frb;
use serde_json::Value;

use shed_core::roost::bootstrap::{
    self, reach_code, wire_agent_hooks, BootstrapFailure, CallError, HooksError, HooksResult,
    HooksSkip, Identity, InstallMachine, InstallRequest, Installed, Outcome, Plan, Probe,
    ProbeMachine, ProbeOutcome, SessionIdentity, SessionState, Source, SourceEnv, SourceHandle,
    SourcePreview, Stage, Stdin, Step,
};
use shed_core::roost::{Conn, RoostError};

use super::bridge_rt::{joined_on_bridge_rt, ACTIVE_ROOST_BOOTSTRAPS};
use super::roost::BridgeReachKind;

/// The `client` shed-mobile sends on `session.set_agent_hooks`.
///
/// roost files it as the `by` of the state entry in
/// `~/.config/roost/agent-hooks.json` on the host, so a user can ask which of
/// their clients wired these hooks last. It is a constant rather than an
/// argument because it identifies *this build*, not the call — a client label
/// Dart could choose would be a client label a bug could mislabel.
///
/// **Two senders, one definition.** The install wires the hooks once, here; the
/// watcher re-sends them on every cycle it connects
/// (`super::roost::watcher_options`, plan 020 §3.3). Both read this constant,
/// so the phone cannot end up filed under two names — and Dart supplies neither.
pub(super) const CLIENT_LABEL: &str = "shed-mobile";

/// How many steps one handle is allowed before the drive calls it a loop.
///
/// `shed_app::roost::BootstrapRunner`'s number, for its reason: an install is
/// about twenty steps and a probe about five, so anything past this is a machine
/// cycling rather than a slow host. Counted across the whole handle and not per
/// call, because the phone's loop is spread over many FRB round trips and a
/// per-call bound would bound nothing.
const MAX_STEPS: usize = 64;

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

/// The sentence every verb refuses a closed handle with, composed once: two call
/// sites and two tests read it, so a second copy is a second thing to keep in
/// step.
fn closed_err(target: &str) -> String {
    format!("the bootstrap of {target} is closed")
}

// ---------------------------------------------------------------------------
// what to bootstrap
// ---------------------------------------------------------------------------

/// **What the phone is about to bootstrap** — a mobile-side DTO with no twin in
/// shed, because the three things it carries only exist together on a phone.
///
/// `local_port` is the piece the desktop has no equivalent for: shed-mobile's
/// reach is a loopback port Dart already pointed at the machine's
/// `roost-session` (`lib/ssh/roost_tunnel.dart`), and it is what every
/// [`Step::Call`] and [`Step::Hooks`] this module absorbs dials. Rust never
/// opens an SSH connection of its own — the phone holds exactly one `SSHClient`
/// per machine and the bootstrap rides it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RoostHostTarget {
    /// The grammar token a roost host is addressed by — `mini3`,
    /// `roost:popos/p019-a`. It is what every copy string names, and it is
    /// hashed into the probe's fingerprint, so it must be the name the user
    /// typed rather than a display variant of it.
    pub target: String,
    /// The loopback port that fronts this host's `roost-session`, or the port a
    /// tunnel is listening on that *would* front one. Nothing is dialled until a
    /// step needs it.
    pub local_port: u16,
    /// roost's `BootstrapOptions::jail_fs_root`. **`false` in production.**
    ///
    /// `true` only in a hermetic lane, where it prefixes the candidate ladder's
    /// absolute rungs with `${ROOST_BOOTSTRAP_FS_ROOT}` so a test about a cold
    /// host cannot find the developer's own `/usr/bin/roost-session`. It is a
    /// field rather than an environment read for the reason shed-core gives: a
    /// variable meant for a test lane must never steer which binary a shipped
    /// app execs.
    pub jail_fs_root: bool,
}

// ---------------------------------------------------------------------------
// the mirrored DTOs
// ---------------------------------------------------------------------------

/// What a `roost-session` binary on the far side says it is (mirrors
/// [`Identity`]).
///
/// shed's compatibility rule is `session_protocol` and only that — it does not
/// build roost, so `libghostty_build` is carried for the copy and never
/// compared.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBootstrapIdentity {
    pub app_version: String,
    pub session_protocol: u32,
    pub libghostty_build: String,
}

impl From<Identity> for BridgeBootstrapIdentity {
    fn from(i: Identity) -> Self {
        BridgeBootstrapIdentity {
            app_version: i.app_version,
            session_protocol: i.session_protocol,
            libghostty_build: i.libghostty_build,
        }
    }
}

/// What a *running* session says it is (mirrors [`SessionIdentity`]) — the same
/// three fields plus the two that identify the daemon instance.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBootstrapSessionIdentity {
    pub app_version: String,
    pub session_protocol: u32,
    pub libghostty_build: String,
    /// roost's own id for this daemon incarnation. It changes on restart, which
    /// is why it is part of the consent fingerprint.
    pub session_id: String,
    pub started_at: String,
}

impl From<SessionIdentity> for BridgeBootstrapSessionIdentity {
    fn from(i: SessionIdentity) -> Self {
        BridgeBootstrapSessionIdentity {
            app_version: i.app_version,
            session_protocol: i.session_protocol,
            libghostty_build: i.libghostty_build,
            session_id: i.session_id,
            started_at: i.started_at,
        }
    }
}

/// What the probe concluded about the binaries on the far side (mirrors
/// [`ProbeOutcome`]).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeBootstrapProbeOutcome {
    /// A binary shed can talk to, at `path`.
    Compatible {
        path: String,
        identity: BridgeBootstrapIdentity,
    },
    /// A `roost-session` is there and shed cannot talk to it. `identity` is
    /// `None` when it would not identify itself at all — a build older than the
    /// `identify` subcommand. Both answers imply the same offer; the distinction
    /// is for copy, not for routing.
    Mismatch {
        path: String,
        identity: Option<BridgeBootstrapIdentity>,
    },
    /// No rung of the ladder exists.
    Missing,
}

impl From<ProbeOutcome> for BridgeBootstrapProbeOutcome {
    fn from(outcome: ProbeOutcome) -> Self {
        match outcome {
            ProbeOutcome::Compatible { path, identity } => {
                BridgeBootstrapProbeOutcome::Compatible {
                    path,
                    identity: identity.into(),
                }
            }
            ProbeOutcome::Mismatch { path, identity } => BridgeBootstrapProbeOutcome::Mismatch {
                path,
                identity: identity.map(Into::into),
            },
            ProbeOutcome::Missing => BridgeBootstrapProbeOutcome::Missing,
        }
    }
}

/// Whether anything is *serving* over there, which the on-disk probe cannot
/// answer (mirrors [`SessionState`]).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeBootstrapSessionState {
    /// A session answered `session.identify`. Its protocol may or may not be
    /// shed's — the plan is what turns on that, not this.
    Running {
        identity: BridgeBootstrapSessionIdentity,
    },
    /// A `roost-session` is installed and is not running.
    NoSession,
    /// The reach fell off the end of the ladder.
    NotInstalled,
}

impl From<SessionState> for BridgeBootstrapSessionState {
    fn from(state: SessionState) -> Self {
        match state {
            SessionState::Running { identity } => BridgeBootstrapSessionState::Running {
                identity: identity.into(),
            },
            SessionState::NoSession => BridgeBootstrapSessionState::NoSession,
            SessionState::NotInstalled => BridgeBootstrapSessionState::NotInstalled,
        }
    }
}

/// The row this host lands on (mirrors [`Plan`]) — what the consent sheet offers
/// and what an install will actually do.
///
/// The sixth plan-matrix row ("there is no source, so there is no button at
/// all") is deliberately not a variant: a plan is what the *host* implies, and
/// whether shed has bytes to send is what the source ladder implies
/// ([`roost_bootstrap_source_preview`]). The sheet overlays the second on the
/// first.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeBootstrapPlan {
    /// Nothing is there. Install, then start.
    Install {
        /// Where it will land, when the remote reported a `$HOME`.
        dest: Option<String>,
    },
    /// Something is there that shed cannot talk to. Back it up, replace it,
    /// then start.
    Update {
        /// The rung that would be shadowed — informational; an install always
        /// lands on rung 1.
        path: String,
        incumbent: Option<BridgeBootstrapIdentity>,
        /// The incumbent speaks a **newer** protocol than this build, so this is
        /// a downgrade wearing an update's clothes. The sheet says so rather
        /// than letting the user find out afterwards.
        replaces_newer: bool,
        dest: Option<String>,
    },
    /// A binary shed can talk to is there and nothing is serving. Just start it.
    Start { path: String },
    /// A session shed can talk to is already serving. Nothing to do.
    UpToDate {
        identity: BridgeBootstrapSessionIdentity,
    },
    /// A session is serving and shed cannot talk to it.
    ///
    /// **Pin P6: reported, never stopped and never restarted.** Somebody is
    /// using that session. `message` is the sentence the card shows, naming the
    /// command *they* would run; the client offers no button.
    Report { protocol: u32, message: String },
}

impl From<Plan> for BridgeBootstrapPlan {
    fn from(plan: Plan) -> Self {
        match plan {
            Plan::Install { dest } => BridgeBootstrapPlan::Install { dest },
            Plan::Update {
                path,
                incumbent,
                replaces_newer,
                dest,
            } => BridgeBootstrapPlan::Update {
                path,
                incumbent: incumbent.map(Into::into),
                replaces_newer,
                dest,
            },
            Plan::Start { path } => BridgeBootstrapPlan::Start { path },
            Plan::UpToDate { identity } => BridgeBootstrapPlan::UpToDate {
                identity: identity.into(),
            },
            Plan::Report { protocol, message } => BridgeBootstrapPlan::Report { protocol, message },
        }
    }
}

/// One read-only look at a host, and the row it lands on (mirrors [`Probe`]).
///
/// **Nothing here changed anything**, which is what makes it safe to run before
/// the consent sheet — and why the sheet can carry [`fingerprint`](Self::fingerprint)
/// as the thing the install re-checks.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBootstrapProbe {
    pub target: String,
    pub outcome: BridgeBootstrapProbeOutcome,
    /// `amd64` or `arm64` — roost's release spelling, and the argument
    /// [`roost_bootstrap_source_preview`] takes.
    pub arch: String,
    /// The remote's own `$HOME`, verbatim and untrimmed.
    pub home: String,
    pub session: BridgeBootstrapSessionState,
    /// Every ladder rung that exists and is executable, in ladder order.
    pub candidates: Vec<String>,
    /// What the user consents against, and what
    /// [`roost_bootstrap_install`] re-checks. Opaque to Dart: pass it back
    /// unchanged.
    pub fingerprint: String,
    /// Where an install would land. `None` when the remote reported no `$HOME`.
    pub install_dest: Option<String>,
    /// The row this probe lands on. Computed here rather than by a second Dart
    /// call, because [`Plan::for_probe`] also needs the target and a client that
    /// passed the wrong one would silently get the wrong sentence.
    pub plan: BridgeBootstrapPlan,
    /// Whether acting on [`plan`](Self::plan) needs bytes — i.e. whether
    /// [`roost_bootstrap_install`] has to resolve a source. Pass it straight
    /// back to that call.
    pub needs_source: bool,
    /// Whether acting on [`plan`](Self::plan) does anything at all. `false` for
    /// `UpToDate` and for `Report`, which is pin P6's row.
    pub actionable: bool,
}

impl BridgeBootstrapProbe {
    /// The probe, plus the plan its target implies.
    ///
    /// A method rather than a `From`, because [`Plan::for_probe`] takes the
    /// target and a `Probe` does not carry one.
    fn from_probe(target: &str, probe: Probe) -> BridgeBootstrapProbe {
        let plan = Plan::for_probe(target, &probe);
        BridgeBootstrapProbe {
            target: target.to_string(),
            install_dest: probe.install_dest(),
            needs_source: plan.needs_source(),
            actionable: plan.actionable(),
            plan: plan.into(),
            outcome: probe.outcome.into(),
            arch: probe.arch,
            home: probe.home,
            session: probe.session.into(),
            candidates: probe.candidates,
            fingerprint: probe.fingerprint,
        }
    }
}

/// Which rung of the source ladder the bytes would come from (mirrors
/// [`Source`]).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeBootstrapSource {
    /// The file `ROOST_SESSION_INSTALL_BIN` names. **On a phone this is the only
    /// live rung** — there is no sibling beside a Flutter app and the release
    /// pin is `None` — which is why every mobile acceptance criterion names it.
    Override { path: String },
    /// The `roost-session` beside this client. Desktop-on-Linux only.
    Sibling { path: String },
    /// A release asset, to be downloaded and checksum-verified.
    Asset { base: String, version: String },
    /// Nothing applies. The button is replaced by the sentence in
    /// [`BridgeBootstrapSourcePreview::describe`].
    None,
}

impl From<Source> for BridgeBootstrapSource {
    fn from(source: Source) -> Self {
        match source {
            Source::Override { path } => BridgeBootstrapSource::Override { path },
            Source::Sibling { path } => BridgeBootstrapSource::Sibling { path },
            Source::Asset { base, version } => BridgeBootstrapSource::Asset { base, version },
            Source::None => BridgeBootstrapSource::None,
        }
    }
}

/// What the consent sheet says about where the bytes will come from (mirrors
/// [`SourcePreview`]).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBootstrapSourcePreview {
    /// The rung the ladder will try first.
    pub source: BridgeBootstrapSource,
    /// Where it lands if `source` turns out not to be usable — only ever set for
    /// the sibling rung, whose local `identify` a preview deliberately does not
    /// run.
    pub fallback: Option<BridgeBootstrapSource>,
    /// Rungs the ladder will not try, and why. One of these names the client's
    /// own architecture when it differs from the remote's, because "shed won't
    /// use the roost-session next to it" is baffling without it.
    pub skipped: Vec<String>,
    /// Whether the plan matrix gets a button at all.
    pub available: bool,
    /// The sheet's "from where" line, rendered by shed-core so a card cannot
    /// promise one origin in wording the log then reports differently.
    pub describe: String,
}

impl BridgeBootstrapSourcePreview {
    /// A method rather than a `From`, because both of the rendered strings need
    /// the target.
    fn from_preview(target: &str, preview: SourcePreview) -> BridgeBootstrapSourcePreview {
        BridgeBootstrapSourcePreview {
            available: preview.available(),
            describe: preview.describe(target),
            source: preview.source.into(),
            fallback: preview.fallback.map(Into::into),
            skipped: preview.skipped,
        }
    }
}

/// One agent the host did not act on, and why (mirrors [`HooksSkip`]).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBootstrapHooksSkip {
    pub agent: String,
    pub reason: String,
}

impl From<HooksSkip> for BridgeBootstrapHooksSkip {
    fn from(s: HooksSkip) -> Self {
        BridgeBootstrapHooksSkip {
            agent: s.agent,
            reason: s.reason,
        }
    }
}

/// One agent the host tried to wire and could not. Reported, never swallowed
/// (mirrors [`HooksError`]).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBootstrapHooksError {
    pub agent: String,
    pub error: String,
}

impl From<HooksError> for BridgeBootstrapHooksError {
    fn from(e: HooksError) -> Self {
        BridgeBootstrapHooksError {
            agent: e.agent,
            error: e.error,
        }
    }
}

/// What `session.set_agent_hooks` came to (mirrors [`HooksResult`]).
///
/// **Nothing shed does edits a dotfile.** shed asks; the host's own
/// `roost-session` writes, under its own `$HOME`, with roost's own installer.
/// A failure here is never fatal to the bootstrap — the install worked, the
/// session is up, the host is readable, and a missing enrichment is not worth
/// throwing that away.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBootstrapHooks {
    /// What shed sent as `client` — always [`CLIENT_LABEL`] from this app.
    pub client_label: String,
    /// roost's **first-announcement** list: the agents this host has wired and
    /// never told any client about. Not "what this call wrote", so an empty
    /// `wired` is not a failure.
    pub wired: Vec<String>,
    pub refreshed: Vec<String>,
    pub removed: Vec<String>,
    pub skipped: Vec<BridgeBootstrapHooksSkip>,
    /// Per-agent failures. Partial success is the normal case and is shown.
    pub errors: Vec<BridgeBootstrapHooksError>,
    /// The call itself failed. Never fatal.
    pub error: Option<String>,
    /// Whether the op actually ran — `error.is_none()`, computed here so Dart
    /// does not restate a rule that changed once already (protocol 4's live
    /// lease was a third outcome; at 5 there is no such thing).
    pub applied: bool,
}

impl From<HooksResult> for BridgeBootstrapHooks {
    fn from(result: HooksResult) -> Self {
        BridgeBootstrapHooks {
            applied: result.applied(),
            client_label: result.client_label,
            wired: result.wired,
            refreshed: result.refreshed,
            removed: result.removed,
            skipped: result.skipped.into_iter().map(Into::into).collect(),
            errors: result.errors.into_iter().map(Into::into).collect(),
            error: result.error,
        }
    }
}

/// What an install came to (mirrors [`Installed`]).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBootstrapInstalled {
    pub target: String,
    /// The plan the machine's own re-probe settled on, which is what actually
    /// happened rather than what was consented to.
    pub plan: BridgeBootstrapPlan,
    /// Where a binary was written, when one was.
    pub dest: Option<String>,
    /// `roost-session start`'s readiness line, when a start ran.
    pub verdict: Option<String>,
    /// Who answered the post-start `session.identify`.
    pub session: Option<BridgeBootstrapSessionIdentity>,
    /// A warning about what the remote's `PATH` will actually resolve — an
    /// install that landed somewhere a login shell will not find first.
    pub path_warning: Option<String>,
    /// A warning about a backup that could not be discarded.
    pub backup_warning: Option<String>,
    /// The hook wiring, when the install got that far. `None` means it was never
    /// attempted, which is not the same as a failure.
    pub hooks: Option<BridgeBootstrapHooks>,
}

impl From<Installed> for BridgeBootstrapInstalled {
    fn from(installed: Installed) -> Self {
        BridgeBootstrapInstalled {
            target: installed.target,
            plan: installed.plan.into(),
            dest: installed.dest,
            verdict: installed.verdict,
            session: installed.session.map(Into::into),
            path_warning: installed.path_warning,
            backup_warning: installed.backup_warning,
            hooks: installed.hooks.map(Into::into),
        }
    }
}

/// Where a bootstrap stopped (mirrors [`Stage`]). A plain enum — every variant
/// is fieldless, so it crosses as a plain Dart enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeBootstrapStage {
    /// Looking at the far side — the exec, its output, or its shape.
    Probe,
    /// The far side is not Linux.
    UnsupportedOs,
    /// The far side's architecture has no build.
    UnsupportedArch,
    /// The host changed between the consent sheet and the install.
    Fingerprint,
    /// There were no bytes to install.
    Source,
    /// A session shed cannot talk to is serving, and pin P6 says shed reports it
    /// rather than touching it. A refusal, not a fault: the client should not
    /// have offered a button.
    Report,
    /// Deciding the destination and staging a temporary beside it.
    Prepare,
    /// Sending the binary.
    Stream,
    /// Asking the *staged* file who it is, before anything is replaced.
    Verify,
    /// Putting it in place.
    Commit,
    /// Asking the *installed* file who it is.
    PostCommit,
    /// `roost-session start`.
    Start,
    /// Asking the session that came up who it is.
    PostStart,
    /// Wiring the host's agent hooks. Never fatal.
    Hooks,
}

impl From<Stage> for BridgeBootstrapStage {
    fn from(stage: Stage) -> Self {
        match stage {
            Stage::Probe => BridgeBootstrapStage::Probe,
            Stage::UnsupportedOs => BridgeBootstrapStage::UnsupportedOs,
            Stage::UnsupportedArch => BridgeBootstrapStage::UnsupportedArch,
            Stage::Fingerprint => BridgeBootstrapStage::Fingerprint,
            Stage::Source => BridgeBootstrapStage::Source,
            Stage::Report => BridgeBootstrapStage::Report,
            Stage::Prepare => BridgeBootstrapStage::Prepare,
            Stage::Stream => BridgeBootstrapStage::Stream,
            Stage::Verify => BridgeBootstrapStage::Verify,
            Stage::Commit => BridgeBootstrapStage::Commit,
            Stage::PostCommit => BridgeBootstrapStage::PostCommit,
            Stage::Start => BridgeBootstrapStage::Start,
            Stage::PostStart => BridgeBootstrapStage::PostStart,
            Stage::Hooks => BridgeBootstrapStage::Hooks,
        }
    }
}

/// A bootstrap that stopped, and what to tell the person who asked for it
/// (mirrors [`BootstrapFailure`]).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBootstrapFailure {
    pub stage: BridgeBootstrapStage,
    /// One user-facing sentence — or two. Never a `Debug` rendering.
    pub message: String,
    /// After a post-commit failure: was an incumbent put back? `None` where the
    /// question does not arise. "Your old roost-session is back" and "the new
    /// one is still there, go look at it" are different instructions.
    pub restored: Option<bool>,
    /// A stable kebab name for [`stage`](Self::stage), so a log line and an
    /// analytics label do not have to restate the table.
    pub stage_code: String,
}

impl From<BootstrapFailure> for BridgeBootstrapFailure {
    fn from(failure: BootstrapFailure) -> Self {
        BridgeBootstrapFailure {
            stage_code: failure.stage.as_str().to_string(),
            stage: failure.stage.into(),
            message: failure.message,
            restored: failure.restored,
        }
    }
}

// ---------------------------------------------------------------------------
// the step protocol
// ---------------------------------------------------------------------------

/// What a [`BridgeBootstrapStep::Exec`] is fed on stdin (mirrors [`Stdin`]).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeBootstrapStdin {
    /// Nothing at all — the child must see an immediate EOF. A runner that never
    /// closes stdin hangs the step until its budget expires.
    Empty,
    /// A script, for a remote `/bin/sh -s`. Write it, then close stdin.
    ///
    /// It arrives as data and is never re-parsed by anything, however many
    /// apostrophes a path on the far side has — which is the whole reason roost
    /// composes scripts this way instead of quoting them into a command line.
    Bytes { bytes: Vec<u8> },
    /// The verified descriptor, streamed. Pull it with
    /// [`bootstrap_source_read`] until it answers empty, writing each chunk and
    /// closing stdin at EOF.
    ///
    /// **Never a path, and there is none to hand over**: the bytes shed hashed
    /// and the bytes shed sends have to be the same bytes, and a path re-opened
    /// between those two moments is a different file.
    Source {
        /// How many bytes there are, for a progress line.
        len: u64,
        /// Where they came from — the same sentence the consent sheet showed.
        origin: String,
        /// The hex sha256 the ladder verified, when there was a published one to
        /// verify against.
        sha256: Option<String>,
    },
}

impl From<Stdin> for BridgeBootstrapStdin {
    fn from(stdin: Stdin) -> Self {
        match stdin {
            Stdin::Empty => BridgeBootstrapStdin::Empty,
            Stdin::Bytes(bytes) => BridgeBootstrapStdin::Bytes { bytes },
            Stdin::Source(source) => BridgeBootstrapStdin::Source {
                len: source.len(),
                origin: source.origin().to_string(),
                sha256: source.sha256().map(str::to_string),
            },
        }
    }
}

/// What Dart must do next, or the answer.
///
/// **Only three of the machines' four step kinds are here**, and that is §3.8's
/// pinned split rather than an omission: `Call` and `Hooks` are performed in
/// Rust over the loopback [`Conn`] before this value is produced, so the only
/// step that ever reaches Dart is the one that needs an SSH exec. The three
/// terminal arms are [`Step::Done`] flattened — a `Done` wrapper around a
/// `Result` would have cost Dart two nested switches to learn one thing.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeBootstrapStep {
    /// Run `command` on the far side the way a remote shell would run it, then
    /// answer with [`roost_bootstrap_feed_exec`].
    ///
    /// **`command` is opaque and is never quoted.** It is roost's own
    /// composition — either `/bin/sh -s` with the script on stdin, or one of
    /// roost's self-contained `sh -c '…'` words the far side's login shell
    /// parses itself. It travels like `roostRemoteCommand()`: verbatim, never
    /// through a quoter of Dart's.
    Exec {
        command: String,
        stdin: BridgeBootstrapStdin,
        /// How long this step may take, in milliseconds. Every one of shed-core's
        /// budgets is seconds-to-minutes, so it fits an `int` on the Dart side
        /// rather than costing a `BigInt` at every call.
        budget_ms: u32,
        /// Keep at most this many bytes of stdout, from the **head** — the
        /// answers that matter are NUL-delimited records at the start.
        stdout_cap: u32,
        /// `false` for a [`BridgeBootstrapStdin::Source`] step: `tee` echoes
        /// every byte it is fed, and buffering a 10 MiB binary back into memory
        /// to look at a stdout nothing reads would be absurd. Discard it, do not
        /// merely cap it.
        capture_stdout: bool,
        /// Keep at most this many bytes of stderr, from the **tail** — the
        /// opposite end from `stdout_cap`, because one line of it reaches the
        /// user and the useful line is the last one.
        ///
        /// **Carried rather than left to the runner to invent.** shed-core's
        /// `Step::Exec` does not name a stderr cap — it is the client's choice,
        /// and the desktop makes its own ([`STDERR_TAIL_CAP`], 4 KiB, private to
        /// `shed-app`). A Dart runner with no value here would pick a second
        /// number, and the two clients would then truncate the same failure
        /// differently for no reason anybody could find later. So the number
        /// crosses with the other two caps, from [`STDERR_TAIL_CAP`] below.
        stderr_cap: u32,
    },
    /// **Terminal.** The probe finished. Nothing was changed on the far side.
    Probed { probe: BridgeBootstrapProbe },
    /// **Terminal.** The install finished.
    Installed { installed: BridgeBootstrapInstalled },
    /// **Terminal.** Either machine stopped, having already run whatever undo
    /// steps it was entitled to. A failure arrives here and never as a
    /// short-circuit, which is what lets the install roll back before it reports.
    Failed { failure: BridgeBootstrapFailure },
}

/// The step, normalized across the two machines so one drive loop serves both —
/// and split along §3.8's line, which is why there are only three arms.
///
/// [`ProbeMachine`] yields `Step<Result<Probe, _>>` and [`InstallMachine`]
/// yields `Step<Result<Installed, _>>`; the three work variants say nothing
/// about whose result they are on the way to, so only the terminal arm differs.
///
/// [`Ready`](Self::Ready) is everything the drive loop hands straight to Dart —
/// an exec and the three terminal answers alike — and the other two arms are
/// exactly what Rust absorbs itself. The pinned split is therefore the shape of
/// this enum rather than a rule the loop has to remember.
enum DriveStep {
    /// Nothing left for Rust to do with this step: return it.
    Ready(BridgeBootstrapStep),
    Call {
        op: String,
        params: Value,
    },
    Hooks {
        client_label: String,
    },
}

/// How much of stderr a runner keeps, from the tail — 4 KiB.
///
/// Mirrors `shed-app`'s own `STDERR_TAIL_CAP` (`crates/shed-app/src/roost.rs:1953`),
/// which is private, so this is a deliberate copy rather than a reuse. It rides
/// out on every [`BridgeBootstrapStep::Exec`] so the Dart runner never invents a
/// second number; if shed-app's ever moves, the two are meant to move together.
const STDERR_TAIL_CAP: u32 = 4 * 1024;

fn normalize<T>(
    step: Step<Result<T, BootstrapFailure>>,
    done: impl FnOnce(T) -> BridgeBootstrapStep,
) -> DriveStep {
    match step {
        Step::Exec {
            command,
            stdin,
            budget,
            stdout_cap,
            capture_stdout,
        } => DriveStep::Ready(BridgeBootstrapStep::Exec {
            command,
            stdin: stdin.into(),
            budget_ms: narrow(budget.as_millis()),
            stdout_cap: narrow(stdout_cap),
            capture_stdout,
            stderr_cap: STDERR_TAIL_CAP,
        }),
        Step::Call { op, params } => DriveStep::Call { op, params },
        Step::Hooks { client_label } => DriveStep::Hooks { client_label },
        Step::Done(Ok(value)) => DriveStep::Ready(done(value)),
        Step::Done(Err(failure)) => DriveStep::Ready(BridgeBootstrapStep::Failed {
            failure: failure.into(),
        }),
    }
}

/// Saturating, because a budget or a cap that did not fit would otherwise wrap
/// to a *smaller* number and silently shorten the step it bounds.
///
/// Generic over the source width so a caller never has to widen with an `as`
/// cast first — the whole point is to make the lossy conversion explicit, and a
/// cast in front of it is a second, silent one.
fn narrow<T: TryInto<u32>>(value: T) -> u32 {
    value.try_into().unwrap_or(u32::MAX)
}

// ---------------------------------------------------------------------------
// the handle
// ---------------------------------------------------------------------------

/// Which machine this handle drives. One handle type rather than two, because
/// the lifecycle, the leak counter and the drive loop are identical and only the
/// terminal arm differs.
enum Machine {
    Probe(Box<ProbeMachine>),
    Install(Box<InstallMachine>),
}

impl Machine {
    /// Take one step: `None` begins, `Some` feeds. One verb rather than two,
    /// because both machines' `begin` and `feed` return the same step type and
    /// only the terminal arm differs — so a separate `begin` would be this
    /// `match` again with each terminal arm written a second time.
    ///
    /// `target` is the handle's own copy: [`ProbeMachine`] keeps its target
    /// private, and [`Plan::for_probe`] needs one.
    fn advance(&mut self, outcome: Option<Outcome>, target: &str) -> DriveStep {
        match self {
            Machine::Probe(m) => normalize(
                match outcome {
                    None => m.begin(),
                    Some(outcome) => m.feed(outcome),
                },
                |probe| BridgeBootstrapStep::Probed {
                    probe: BridgeBootstrapProbe::from_probe(target, probe),
                },
            ),
            Machine::Install(m) => normalize(
                match outcome {
                    None => m.begin(),
                    Some(outcome) => m.feed(outcome),
                },
                |installed| BridgeBootstrapStep::Installed {
                    installed: installed.into(),
                },
            ),
        }
    }
}

struct Inner {
    /// `None` while a drive is in flight (checked out by [`MachineGuard`]) or
    /// once the handle is closed. [`closed`](Self::closed) says which, so there
    /// is no third flag: `machine.is_none() && !closed` **is** "in flight".
    machine: Option<Machine>,
    /// The single-shot teardown latch: the counter is decremented exactly once.
    closed: bool,
    /// Steps computed so far. See [`MAX_STEPS`].
    steps: usize,
    /// The classification Dart's transport last recorded, consumed by the next
    /// failed [`Step::Call`]. See the module doc and
    /// [`roost_bootstrap_note_reach`].
    reach: Option<CallError>,
    target: String,
    port: u16,
    /// The install's verified descriptor — the machine's **own** clone, taken
    /// through [`InstallMachine::source`], so [`bootstrap_source_read`] and the
    /// stream step read the same open file.
    source: Option<SourceHandle>,
    /// Whether a source call has the stream claimed. The single-reader latch —
    /// see [`claim_source`].
    reading: bool,
}

/// One bootstrap of one host: a machine, the loopback port its wire steps dial,
/// and the descriptor its stream step sends.
///
/// Opaque because none of that can cross FRB. Dart drives it with
/// [`roost_bootstrap_begin`] / [`roost_bootstrap_feed_exec`] and ends it with
/// [`roost_bootstrap_close`].
#[frb(opaque)]
pub struct BridgeRoostBootstrap {
    state: Arc<Mutex<Inner>>,
}

impl Drop for BridgeRoostBootstrap {
    fn drop(&mut self) {
        teardown(&self.state);
    }
}

/// The SINGLE teardown/decrement point, idempotent via `closed`: drop the
/// machine (and with it the open source descriptor) and decrement the counter
/// exactly once.
///
/// The counter discipline is [`super::lane`]'s, and it matters for its reason:
/// the counters are `u64`, so a double-decrement would wrap to `u64::MAX` and
/// every later leak assertion would pass for the wrong reason.
///
/// **The counter counts live HANDLES, not open descriptors, and the ordering
/// below is deliberate.** The decrement happens here even though a drive may
/// still have the machine checked out and an in-flight
/// [`bootstrap_source_read`] may still hold a [`SourceHandle`] clone — so for
/// the moment it takes those to drop, the counter can read zero with the
/// descriptor still open. That is the trade the single-decrement-point design
/// buys, and it is the right one: after `close` the handle is dead by the
/// caller's own action, and one place decrementing exactly once under the
/// `closed` latch is what makes the counter trustworthy at all. The
/// descriptor's lifetime is bounded by the things that hold it instead — a
/// drive stops at its next step boundary ([`bump_steps`]) and drops the machine
/// with it, and a read releases its clone when the call returns.
fn teardown(state: &Arc<Mutex<Inner>>) {
    let mut s = lock(state);
    if s.closed {
        return;
    }
    s.closed = true;
    // A drive in flight has the machine checked out; its guard sees `closed` and
    // drops it rather than putting it back.
    drop(s.machine.take());
    drop(s.source.take());
    ACTIVE_ROOST_BOOTSTRAPS.fetch_sub(1, Ordering::SeqCst);
}

/// The machine, out of the lock for the duration of one drive — and back in it
/// however the drive ends, including an abort.
///
/// See the module doc: restoring an aborted machine is sound because `begin` and
/// `feed` are idempotent in their step, so the work that was in flight is simply
/// asked for again — by RE-READING it with [`roost_bootstrap_begin`], never by
/// re-sending the outcome, which would advance the machine twice on one exec.
///
/// It carries the handle's two immutable host facts as well, read under the same
/// lock that took the machine, so a drive touches [`Inner`] only to count its
/// steps.
struct MachineGuard {
    state: Arc<Mutex<Inner>>,
    machine: Option<Machine>,
    target: String,
    port: u16,
}

impl MachineGuard {
    fn advance(&mut self, outcome: Option<Outcome>) -> DriveStep {
        let target = &self.target;
        self.machine
            .as_mut()
            .expect("the guard holds its machine until it is dropped")
            .advance(outcome, target)
    }
}

impl Drop for MachineGuard {
    fn drop(&mut self) {
        let mut s = lock(&self.state);
        let machine = self.machine.take();
        if !s.closed {
            s.machine = machine;
        }
    }
}

fn check_out(state: &Arc<Mutex<Inner>>) -> Result<MachineGuard, String> {
    let mut s = lock(state);
    if s.closed {
        return Err(closed_err(&s.target));
    }
    // Past the `closed` check, an absent machine can only be one that another
    // drive has out.
    let machine = s.machine.take().ok_or_else(|| {
        format!(
            "a bootstrap step for {} is already in flight — drive one step at a time",
            s.target
        )
    })?;
    Ok(MachineGuard {
        machine: Some(machine),
        target: s.target.clone(),
        port: s.port,
        state: state.clone(),
    })
}

/// **The step boundary**: refuse a handle that was closed under this drive, then
/// count the step and refuse past [`MAX_STEPS`].
///
/// [`check_out`] reads `closed` once, at the top, and a drive then spends most
/// of its life awaiting a wire call — so this is the only place an in-flight
/// drive can notice that [`roost_bootstrap_close`] ran underneath it. It is
/// called before every [`MachineGuard::advance`], which is what bounds the two
/// harms: no further `Call`/`Hooks` is dialled over the loopback port after the
/// close, and no step is computed for a handle Dart has already disposed of.
///
/// It is also why the reach note is classified *after* this check and never
/// before it — see [`drive_on_rt`].
fn bump_steps(state: &Arc<Mutex<Inner>>) -> Result<(), String> {
    still_open(state)?;
    let mut s = lock(state);
    s.steps += 1;
    if s.steps > MAX_STEPS {
        return Err(format!(
            "{}: the bootstrap did not finish in {MAX_STEPS} steps",
            s.target
        ));
    }
    Ok(())
}

/// Refuse a closed handle, with the same sentence every other verb uses.
///
/// Two call sites, for two different harms. At the step boundary
/// ([`bump_steps`]) it stops the wire. On the way OUT of the drive it stops a
/// step reaching Dart for a handle the caller has already disposed of — which is
/// the worse of the two: Dart would run that `Exec` on the far side, and for an
/// install past its commit step that is a remote mutation after close.
fn still_open(state: &Arc<Mutex<Inner>>) -> Result<(), String> {
    let s = lock(state);
    if s.closed {
        return Err(closed_err(&s.target));
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// building one
// ---------------------------------------------------------------------------

/// The ONE place a handle comes into being, and therefore the one place the
/// leak counter is bumped — the mirror of [`teardown`] being the one place it is
/// returned.
fn handle(
    host: RoostHostTarget,
    machine: Machine,
    source: Option<SourceHandle>,
) -> BridgeRoostBootstrap {
    ACTIVE_ROOST_BOOTSTRAPS.fetch_add(1, Ordering::SeqCst);
    BridgeRoostBootstrap {
        state: Arc::new(Mutex::new(Inner {
            machine: Some(machine),
            closed: false,
            steps: 0,
            reach: None,
            target: host.target,
            port: host.local_port,
            source,
            reading: false,
        })),
    }
}

/// **One read-only look at a host**: what platform it is, what `roost-session`
/// binaries are on it, and whether one is serving.
///
/// Nothing here writes, starts or stops anything, which is what makes it safe to
/// run *before* the consent sheet — and why the sheet can carry the returned
/// [`BridgeBootstrapProbe::fingerprint`] as the thing the install re-checks.
///
/// Nothing is dialled at construction: drive it with [`roost_bootstrap_begin`].
pub fn roost_bootstrap_probe(host: RoostHostTarget) -> BridgeRoostBootstrap {
    let machine = ProbeMachine::new(host.target.clone(), host.jail_fs_root);
    handle(host, Machine::Probe(Box::new(machine)), None)
}

/// **Install (or update, or merely start) a `roost-session`**, in roost's order:
/// re-probe, prepare, stream, verify the staged file, commit, re-verify the
/// committed file, discard the backup — and only then start.
///
/// `fingerprint` is the consented probe's; the machine re-probes first and
/// refuses if the host moved. `needs_source` is that probe's
/// [`BridgeBootstrapProbe::needs_source`] — when it is `true` the source ladder
/// is climbed here, **before** the handle exists, so a host is never touched by
/// an install that had no bytes to send.
///
/// `scratch_dir` is used by the release-asset rung alone (a fresh directory it
/// creates, fills and removes), and that rung's pin is `None` today, so on a
/// phone it is never read. It is an argument rather than `std::env::temp_dir()`
/// because Android has no `/tmp`.
pub async fn roost_bootstrap_install(
    host: RoostHostTarget,
    fingerprint: String,
    arch: String,
    needs_source: bool,
    scratch_dir: String,
) -> Result<BridgeRoostBootstrap, BridgeBootstrapFailure> {
    install_with(
        SourceEnv::from_env(),
        host,
        fingerprint,
        arch,
        needs_source,
        scratch_dir,
    )
    .await
}

/// The install with its ladder environment **injected rather than read**, which
/// is shed-core's own rule for [`SourceEnv`] and the only way the rung the phone
/// actually uses — the override — is testable without mutating process-global
/// state every other test in the binary also sees.
async fn install_with(
    env: SourceEnv,
    host: RoostHostTarget,
    fingerprint: String,
    arch: String,
    needs_source: bool,
    scratch_dir: String,
) -> Result<BridgeRoostBootstrap, BridgeBootstrapFailure> {
    let source = if needs_source {
        let target = host.target.clone();
        let scratch = std::path::PathBuf::from(scratch_dir);
        let resolved =
            joined_on_bridge_rt(
                async move { bootstrap::resolve(&env, &target, &arch, &scratch).await },
            )
            .await
            .map_err(|e| {
                BootstrapFailure::new(Stage::Source, format!("resolving the source: {e}"))
            })?;
        Some(resolved?)
    } else {
        None
    };

    let machine = InstallMachine::new(
        InstallRequest {
            target: host.target.clone(),
            jail_fs_root: host.jail_fs_root,
            fingerprint,
            client_label: CLIENT_LABEL.to_string(),
        },
        source,
    );
    // The machine's OWN clone, which is the point: whatever `sha256` says was
    // checked is what `bootstrap_source_read` streams.
    let source = machine.source();
    Ok(handle(host, Machine::Install(Box::new(machine)), source))
}

// ---------------------------------------------------------------------------
// driving it
// ---------------------------------------------------------------------------

/// **The first step — and the way to re-read the one you are owed.**
///
/// Both machines compute their step from their current state rather than stash
/// one, so calling this after a drive was cancelled mid-flight asks for exactly
/// the same thing again.
pub async fn roost_bootstrap_begin(
    handle: &BridgeRoostBootstrap,
) -> Result<BridgeBootstrapStep, String> {
    drive(handle.state.clone(), None).await
}

/// **Report what the far side did with a [`BridgeBootstrapStep::Exec`]**, and
/// get the next step.
///
/// `exit` is `None` when the budget expired, the transport died, or the far side
/// closed without a status — and shed-core's rule is that `None` is a **failure**.
/// The one exception belongs to the runner, which is the only layer that can
/// tell the three apart: a runner whose transport reported a *clean* EOF, for a
/// step whose stdout it read to the end, passes `exit: Some(0)`.
///
/// `stdout` is empty for a step that asked for no capture, and capped at the
/// step's `stdout_cap` from the head. `stderr_tail` is the **tail** of stderr,
/// because that is where a diagnosis is: a login banner comes first and the
/// error last.
pub async fn roost_bootstrap_feed_exec(
    handle: &BridgeRoostBootstrap,
    exit: Option<i32>,
    stdout: Vec<u8>,
    stderr_tail: String,
) -> Result<BridgeBootstrapStep, String> {
    drive(
        handle.state.clone(),
        Some(Outcome::Exec {
            exit,
            stdout,
            stderr_tail,
        }),
    )
    .await
}

/// Advance the machine until it wants an SSH exec or has an answer, performing
/// every `Call` and `Hooks` on the way there.
async fn drive(
    state: Arc<Mutex<Inner>>,
    outcome: Option<Outcome>,
) -> Result<BridgeBootstrapStep, String> {
    // On `bridge_rt` for the reason every held connection here is: a loopback
    // `Conn` owns a `copy_bidirectional` pump task, and FRB's per-call executor
    // goes away with the call that made it.
    match joined_on_bridge_rt(drive_on_rt(state, outcome)).await {
        Ok(result) => result,
        Err(e) => Err(format!("bridge task join error: {e}")),
    }
}

async fn drive_on_rt(
    state: Arc<Mutex<Inner>>,
    outcome: Option<Outcome>,
) -> Result<BridgeBootstrapStep, String> {
    let mut guard = check_out(&state)?;
    let port = guard.port;

    bump_steps(&state)?;
    let mut step = guard.advance(outcome);
    loop {
        // Every arm Rust can absorb feeds its outcome straight back in; the one
        // that is `Ready` is the one Dart owns.
        //
        // The step boundary sits at the TOP of each absorbing arm rather than
        // after the `match`, because two things have to happen between a wire
        // call answering and its outcome reaching the machine, in this order:
        // notice a handle that was closed while the call was in flight, and only
        // then spend Dart's reach note on the outcome that is actually about to
        // be fed. A `?` between the note and the feed would spend a note on a
        // failure the machine never sees.
        let absorbed = match step {
            DriveStep::Ready(ready) => {
                // The last gate before a step crosses to Dart.
                still_open(&state)?;
                return Ok(ready);
            }
            DriveStep::Call { op, params } => {
                let answered = perform_call(port, &op, params).await;
                bump_steps(&state)?;
                // Nothing fallible stands between here and `advance`, so the
                // note is spent exactly when the outcome it explains is
                // consumed.
                Outcome::Call(answered.map_err(|failure| classify(&state, failure)))
            }
            DriveStep::Hooks { client_label } => {
                let result = perform_hooks(port, &client_label).await;
                bump_steps(&state)?;
                Outcome::Hooks(result)
            }
        };
        step = guard.advance(Some(absorbed));
    }
}

/// One wire call over the loopback `Conn` — **raw and ungated**, because the
/// machine owns the protocol gate: a protocol-2 session has to arrive as an
/// answer so pin P6's "report it, never restart it" row can be produced at all.
///
/// A connection per call rather than one held across the drive, for the reason
/// the desktop gives: the steps before a post-start identify have just started a
/// daemon, so the port this dials fronts something that did not exist when the
/// machine began.
async fn perform_call(port: u16, op: &str, params: Value) -> Result<Value, CallFailure> {
    let mut conn = match Conn::tcp_loopback(port).await {
        Ok(conn) => conn,
        Err(e) => return Err(CallFailure::Transport(e.to_string())),
    };
    match conn.call_raw(op, params).await {
        Ok(value) => Ok(value),
        // A refusal the session minted is the session's answer, never the
        // transport's — it must not be overwritten by a stale reach note.
        Err(RoostError::Server { code, message }) => {
            Err(CallFailure::Answered(CallError::new(code, message)))
        }
        Err(other) => Err(CallFailure::Transport(other.to_string())),
    }
}

/// A wire call that did not answer, carried **unclassified** back to the drive
/// loop.
///
/// The classification is deliberately not done here: a reach note is spent by
/// the act of classifying, and [`drive_on_rt`] is the only place that knows the
/// outcome is about to reach the machine. Carrying the failure this far keeps
/// the spend and the feed one event.
enum CallFailure {
    /// A refusal the session itself minted — its answer, not the transport's,
    /// and therefore never a note's to explain.
    Answered(CallError),
    /// The transport, which is the only thing a reach note is about.
    Transport(String),
}

/// A failed call, classified by whatever Dart's transport last recorded.
///
/// The note is **consumed**, which is the mobile shape of the desktop's
/// generation watermark: a record already used to explain one failure must never
/// be read again and presented as a fresh reason for a different one. Its
/// converse matters just as much, and is why this is called where it is: a note
/// spent on an outcome the machine never saw would leave the retry — the
/// module doc's re-read with [`roost_bootstrap_begin`] — with nothing to explain
/// the same failure with, and it would then be reported as `transport`, which is
/// exactly the mislabelling the note exists to prevent.
fn classify(state: &Arc<Mutex<Inner>>, failure: CallFailure) -> CallError {
    match failure {
        CallFailure::Answered(answered) => answered,
        CallFailure::Transport(fallback) => match lock(state).reach.take() {
            Some(noted) => noted,
            None => CallError::new("transport", fallback),
        },
    }
}

/// `session.set_agent_hooks`, over that same connection kind — the **first**
/// send for a session shed has just started.
async fn perform_hooks(port: u16, client_label: &str) -> HooksResult {
    match Conn::tcp_loopback(port).await {
        Ok(mut conn) => wire_agent_hooks(&mut conn, client_label).await,
        Err(e) => HooksResult {
            client_label: client_label.to_string(),
            error: Some(e.to_string()),
            ..HooksResult::default()
        },
    }
}

/// **Tell Rust why the loopback reach is not answering**, from the layer that
/// knows.
///
/// Dart owns the SSH transport, so Dart is the only side that ever sees the far
/// end's exit 127 or its `client-bridge: no session` on stderr. Without this the
/// probe's one `session.identify` could only ever come back as "the probe could
/// not be completed", and the phone could never offer an install or a start.
///
/// The mapping is `shed_app::roost`'s, one for one: [`BridgeReachKind::NotInstalled`]
/// and [`BridgeReachKind::NoSession`] become roost's own kebab codes, and the
/// other two become `transport` — which the machine reads as "the probe could
/// not be completed" rather than as a state of the far side. A runner that
/// cannot classify simply does not call this, and the machine reports the probe
/// as failed rather than guessing.
///
/// The note is held until the next failed call consumes it; a later note
/// replaces an unconsumed one.
#[frb(sync)]
pub fn roost_bootstrap_note_reach(
    handle: &BridgeRoostBootstrap,
    kind: BridgeReachKind,
    message: String,
) {
    let code = match kind {
        BridgeReachKind::NotInstalled => reach_code::NOT_INSTALLED,
        BridgeReachKind::NoSession => reach_code::NO_SESSION,
        BridgeReachKind::Unreachable | BridgeReachKind::Other => "transport",
    };
    lock(&handle.state).reach = Some(CallError::new(code, message));
}

/// End the bootstrap — the SYNCHRONOUS co-primary teardown (a Riverpod
/// `onDispose` calls this). Idempotent; `Drop` is the backstop.
///
/// It drops the machine and the open source descriptor. A drive already in
/// flight finishes the one wire call it is inside and then stops at the next
/// step boundary, answering with the same "is closed" refusal every other verb
/// gives: no further call is dialled over the loopback port, and **no step is
/// handed back** for a handle Dart has already disposed of. That second half is
/// the one that matters — a returned step is a step a runner would still
/// execute on the far side, and for an install past its commit step that is a
/// remote mutation after close.
#[frb(sync)]
pub fn roost_bootstrap_close(handle: &BridgeRoostBootstrap) {
    teardown(&handle.state);
}

// ---------------------------------------------------------------------------
// the source
// ---------------------------------------------------------------------------

/// **Read the next chunk of the verified descriptor**, at most `max` bytes. An
/// empty answer is EOF.
///
/// This is how a [`BridgeBootstrapStdin::Source`] step is fed, and the reason
/// Dart is handed no path: the bytes shed hashed and the bytes shed sends have
/// to be the same bytes, and a path re-opened between those two moments is a
/// different file. The descriptor is the install machine's own
/// ([`InstallMachine::source`]), so there is exactly one of them.
///
/// **One reader at a time**: a second call while one is in flight is refused by
/// name rather than served, for the same reason the drive loop refuses a second
/// step — see [`claim_source`]. **And `max` must be at least 1**: zero would
/// read zero bytes and answer empty, which is this stream's EOF, so a caller
/// that computed a zero-length chunk would stop mid-binary believing it was
/// done.
///
/// Not an `async fn`, deliberately, though Dart still sees a `Future`: the read
/// is a blocking `read(2)`, and FRB puts a plain `fn` on its BLOCKING worker
/// pool while an `async fn` would park a reactor worker inside the syscall —
/// once per chunk, so about a hundred and sixty times for a 10 MiB install.
pub fn bootstrap_source_read(handle: &BridgeRoostBootstrap, max: u32) -> Result<Vec<u8>, String> {
    if max == 0 {
        return Err(
            "a source read must ask for at least one byte: an empty answer is this stream's EOF"
                .to_string(),
        );
    }
    let reader = claim_source(&handle.state)?;
    reader
        .source
        .read_chunk(max as usize)
        .map_err(|e| format!("reading the roost-session source: {e}"))
}

/// **Go back to the start of the descriptor.**
///
/// The machine never needs it — the stream phase runs once — but a runner that
/// re-sends a stream step after a transport failure does, and a re-send that
/// picked up where the last read stopped would put a truncated binary on the far
/// side that the staged verify would then have to catch.
///
/// It takes the same single-reader claim [`bootstrap_source_read`] does, so a
/// rewind can never land in the middle of a read that is already in flight.
///
/// Blocking, and therefore not `async`, for the reason
/// [`bootstrap_source_read`] gives.
pub fn bootstrap_source_rewind(handle: &BridgeRoostBootstrap) -> Result<(), String> {
    let reader = claim_source(&handle.state)?;
    reader
        .source
        .rewind()
        .map_err(|e| format!("rewinding the roost-session source: {e}"))
}

/// The source stream, claimed for the duration of one call and released on drop.
///
/// **The stream is single-reader, and the bridge enforces it rather than
/// assuming it.** The drive loop already refuses a second concurrent step
/// instead of trusting the caller to drive one at a time; the byte stream needs
/// the same discipline for a stronger reason. `read_chunk` advances ONE
/// descriptor, and FRB puts these calls on a blocking worker POOL — so two Dart
/// futures in flight at once would each be handed a different, correct-looking
/// chunk in an order neither side can put back, and a `rewind` racing a read
/// would re-send bytes already sent. What comes out of the far side then is not
/// the file that was hashed, which is the one promise this whole path makes.
///
/// A refusal is the right answer rather than a queue: a runner that issued two
/// reads at once has a bug, and serialising it silently would ship the reordered
/// stream anyway.
struct SourceReader {
    state: Arc<Mutex<Inner>>,
    source: SourceHandle,
}

impl Drop for SourceReader {
    fn drop(&mut self) {
        lock(&self.state).reading = false;
    }
}

fn claim_source(state: &Arc<Mutex<Inner>>) -> Result<SourceReader, String> {
    let mut s = lock(state);
    if s.closed {
        return Err(closed_err(&s.target));
    }
    let source = s
        .source
        .clone()
        .ok_or_else(|| format!("the bootstrap of {} streams no source", s.target))?;
    if s.reading {
        return Err(format!(
            "a source call for {} is already in flight — stream one chunk at a time",
            s.target
        ));
    }
    s.reading = true;
    Ok(SourceReader {
        state: state.clone(),
        source,
    })
}

/// **Which rung the bytes would come from**, decided without running or fetching
/// anything — the consent sheet's "from where" line.
///
/// `arch` is [`BridgeBootstrapProbe::arch`]. Sync because it is a handful of
/// environment reads, one `readlink` of this executable's own path, and a
/// `match`; nothing here opens a file or a socket.
#[frb(sync)]
pub fn roost_bootstrap_source_preview(
    target: String,
    arch: String,
) -> BridgeBootstrapSourcePreview {
    source_preview(&SourceEnv::from_env(), &target, &arch)
}

/// The ladder read with its environment **injected rather than read**, which is
/// shed-core's own rule for this: the precedence between the rungs is the thing
/// worth testing and it is not testable against process-global state every other
/// test in the binary also sees.
fn source_preview(env: &SourceEnv, target: &str, arch: &str) -> BridgeBootstrapSourcePreview {
    BridgeBootstrapSourcePreview::from_preview(target, bootstrap::preview(env, target, arch))
}

#[cfg(test)]
mod tests {
    use super::*;

    use std::future::Future;
    use std::path::PathBuf;
    use std::task::Context;
    use std::time::Duration;

    use shed_core::roost::testing::FakeRoost;

    use crate::api::bridge_rt::live_counters;
    use crate::api::testsupport::{noop_waker, test_guard, unique, wait_until};

    const TARGET: &str = "roost:popos/p020-m";

    fn host(port: u16) -> RoostHostTarget {
        RoostHostTarget {
            target: TARGET.to_string(),
            local_port: port,
            jail_fs_root: true,
        }
    }

    /// roost's discovery answer for a COLD host: NUL-delimited `os`, `arch` and
    /// `$HOME`, and then — because no ladder rung exists — nothing.
    ///
    /// A warm host appends one more field per rung, but no test here wants one:
    /// the cold shape is the one that sends the machine straight to its single
    /// `Step::Call`, which is what every test below is really about.
    fn cold_discovery() -> Vec<u8> {
        let mut out = Vec::new();
        for field in ["Linux", "x86_64", "/home/shed"] {
            out.extend_from_slice(field.as_bytes());
            out.push(0);
        }
        out
    }

    fn ok(stdout: Vec<u8>) -> (Option<i32>, Vec<u8>, String) {
        (Some(0), stdout, String::new())
    }

    /// Answer the exec step Dart was handed, and unwrap the next one. The
    /// `expect` is on the drive *answering*; whether the answer is an exec is
    /// each test's own assertion ([`exec_command`], [`probed`]).
    async fn feed(
        handle: &BridgeRoostBootstrap,
        answer: (Option<i32>, Vec<u8>, String),
    ) -> BridgeBootstrapStep {
        roost_bootstrap_feed_exec(handle, answer.0, answer.1, answer.2)
            .await
            .expect("the drive answered")
    }

    /// A per-test temporary directory. `ScratchDir` is `pub(crate)` to
    /// shed-core, so this is the same few lines rather than a dependency on
    /// somebody else's private helper — and it is deliberately NOT cleaned up by
    /// a `Drop`, because a leftover under `temp_dir()` costs nothing and a
    /// cleanup that ran while a descriptor was still open would hide exactly the
    /// bug these tests are about.
    ///
    /// The pid keeps two concurrent `cargo test` runs apart; the crate's own
    /// [`unique`] keeps two tests within one run apart.
    fn scratch(what: &str) -> PathBuf {
        let path = std::env::temp_dir().join(unique(&format!(
            "shed-mobile-bootstrap-{what}-{}",
            std::process::id()
        )));
        let _ = std::fs::remove_dir_all(&path);
        std::fs::create_dir_all(&path).expect("a scratch dir");
        path
    }

    fn exec_command(step: &BridgeBootstrapStep) -> &str {
        match step {
            BridgeBootstrapStep::Exec { command, .. } => command,
            other => panic!("expected an exec step, got {other:?}"),
        }
    }

    fn probed(step: BridgeBootstrapStep) -> BridgeBootstrapProbe {
        match step {
            BridgeBootstrapStep::Probed { probe } => probe,
            other => panic!("expected the probe's answer, got {other:?}"),
        }
    }

    /// A port nothing is listening on: bind one and drop it.
    fn dead_port() -> u16 {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").expect("an ephemeral port");
        listener.local_addr().expect("its address").port()
    }

    /// The unclassified transport failure a dead reach produces, for the tests
    /// that call [`classify`] directly.
    fn transport(fallback: &str) -> CallFailure {
        CallFailure::Transport(fallback.to_string())
    }

    /// **A loopback listener that accepts and answers nothing**, so a test can
    /// be *inside* an absorbed wire call at a known moment rather than hoping a
    /// sleep lands there.
    ///
    /// [`Conn::tcp_loopback`] performs no handshake and `call_raw` then waits
    /// for a reply frame, so an accepted-and-ignored connection parks the drive
    /// exactly where the close and cancel races live. [`stop`](Self::stop) drops
    /// every held connection, which is what makes that parked call fail — on the
    /// test's schedule.
    ///
    /// Plain `std` threads and sockets rather than tokio: the drive runs on
    /// `bridge_rt`, so the rig must be drivable from a `#[test]` that polls a
    /// future by hand as readily as from a `#[tokio::test]`.
    struct StallingRoost {
        port: u16,
        accepts: Arc<std::sync::atomic::AtomicUsize>,
        stopping: Arc<std::sync::atomic::AtomicBool>,
        listening: Option<std::thread::JoinHandle<()>>,
    }

    impl StallingRoost {
        fn start() -> StallingRoost {
            let listener = std::net::TcpListener::bind("127.0.0.1:0").expect("an ephemeral port");
            let port = listener.local_addr().expect("its address").port();
            listener
                .set_nonblocking(true)
                .expect("a non-blocking listener");
            let accepts = Arc::new(std::sync::atomic::AtomicUsize::new(0));
            let stopping = Arc::new(std::sync::atomic::AtomicBool::new(false));
            let counted = accepts.clone();
            let asked_to_stop = stopping.clone();
            let listening = std::thread::spawn(move || {
                // Held, never read and never written: holding them is what keeps
                // the drive parked, and dropping them is what ends it.
                let mut held = Vec::new();
                while !asked_to_stop.load(Ordering::SeqCst) {
                    match listener.accept() {
                        Ok((stream, _)) => {
                            counted.fetch_add(1, Ordering::SeqCst);
                            held.push(stream);
                        }
                        Err(_) => std::thread::sleep(Duration::from_millis(2)),
                    }
                }
            });
            StallingRoost {
                port,
                accepts,
                stopping,
                listening: Some(listening),
            }
        }

        /// How many connections the loopback port has taken. A wire call made
        /// after a close would show up here.
        fn accepts(&self) -> usize {
            self.accepts.load(Ordering::SeqCst)
        }

        /// Stop listening and drop every held connection: the parked call fails,
        /// and the port is dead for anything that dials it afterwards.
        fn stop(&mut self) {
            self.stopping.store(true, Ordering::SeqCst);
            if let Some(listening) = self.listening.take() {
                let _ = listening.join();
            }
        }
    }

    impl Drop for StallingRoost {
        fn drop(&mut self) {
            self.stop();
        }
    }

    /// Answer the probe's first exec, leaving the machine one feed away from the
    /// ONE step Rust absorbs — the `session.identify` that dials the port.
    ///
    /// The drive that reaches that call is then the test's own, because every
    /// test below is about what happens to it *while it is in flight*.
    async fn up_to_the_wire_call(handle: &BridgeRoostBootstrap) {
        roost_bootstrap_begin(handle).await.expect("the first step");
        feed(handle, ok(cold_discovery())).await;
    }

    /// The feed that sends the machine to its wire call: `command -v` found
    /// nothing, so there is no ladder rung and the next step is the call.
    fn the_feed_that_dials(
        handle: &BridgeRoostBootstrap,
    ) -> impl std::future::Future<Output = Result<BridgeBootstrapStep, String>> + '_ {
        roost_bootstrap_feed_exec(handle, Some(1), Vec::new(), String::new())
    }

    /// Drive a probe of a COLD host all the way to its answer: the discovery
    /// exec, then the `command -v` that finds nothing.
    ///
    /// That shape is the one that matters — no ladder rung means the machine
    /// goes straight to its one `Step::Call`, so whatever comes back here is
    /// proof Rust absorbed it. The crux test spells these three steps out
    /// instead of calling this, because asserting *on* them is its whole point.
    async fn probe_cold_host(handle: &BridgeRoostBootstrap) -> BridgeBootstrapStep {
        roost_bootstrap_begin(handle).await.expect("the first step");
        feed(handle, ok(cold_discovery())).await;
        feed(handle, (Some(1), Vec::new(), String::new())).await
    }

    // -- the DTO mirror --------------------------------------------------

    /// **Every [`Stage`] gets its own case.** The stage is what a progress line
    /// and a failure sheet branch on, so a mapping that collapsed two would
    /// report a stream failure as a commit failure — and the kebab code that
    /// rides beside it would then disagree with the enum.
    #[test]
    fn every_stage_crosses_the_bridge_with_its_own_case() {
        let cases = [
            (Stage::Probe, BridgeBootstrapStage::Probe, "probe"),
            (
                Stage::UnsupportedOs,
                BridgeBootstrapStage::UnsupportedOs,
                "unsupported-os",
            ),
            (
                Stage::UnsupportedArch,
                BridgeBootstrapStage::UnsupportedArch,
                "unsupported-arch",
            ),
            (
                Stage::Fingerprint,
                BridgeBootstrapStage::Fingerprint,
                "fingerprint",
            ),
            (Stage::Source, BridgeBootstrapStage::Source, "source"),
            (Stage::Report, BridgeBootstrapStage::Report, "report"),
            (Stage::Prepare, BridgeBootstrapStage::Prepare, "prepare"),
            (Stage::Stream, BridgeBootstrapStage::Stream, "stream"),
            (Stage::Verify, BridgeBootstrapStage::Verify, "verify"),
            (Stage::Commit, BridgeBootstrapStage::Commit, "commit"),
            (
                Stage::PostCommit,
                BridgeBootstrapStage::PostCommit,
                "post-commit",
            ),
            (Stage::Start, BridgeBootstrapStage::Start, "start"),
            (
                Stage::PostStart,
                BridgeBootstrapStage::PostStart,
                "post-start",
            ),
            (Stage::Hooks, BridgeBootstrapStage::Hooks, "hooks"),
        ];
        let mut seen = std::collections::BTreeSet::new();
        for (from, want, code) in cases {
            let failure: BridgeBootstrapFailure =
                BootstrapFailure::new(from, "it did not work").into();
            assert_eq!(failure.stage, want, "{from:?} did not cross as {want:?}");
            assert_eq!(failure.stage_code, code, "{from:?}'s kebab name");
            assert!(seen.insert(format!("{want:?}")), "{want:?} used twice");
        }
        assert_eq!(seen.len(), 14, "every stage has a case of its own");
    }

    /// **Every [`ProbeOutcome`] and [`SessionState`] variant crosses whole**,
    /// including the `Mismatch` whose identity is absent — a `roost-session` too
    /// old to have an `identify` subcommand is a real host, and collapsing it
    /// onto `Missing` would offer an install that silently overwrites somebody's
    /// binary instead of an update that backs it up.
    #[test]
    fn the_probe_enums_cross_variant_for_variant() {
        let identity = Identity {
            app_version: "0.0.19".into(),
            session_protocol: 5,
            libghostty_build: "ghostty-f2d5758f".into(),
        };

        assert_eq!(
            BridgeBootstrapProbeOutcome::from(ProbeOutcome::Compatible {
                path: "/usr/bin/roost-session".into(),
                identity: identity.clone(),
            }),
            BridgeBootstrapProbeOutcome::Compatible {
                path: "/usr/bin/roost-session".into(),
                identity: BridgeBootstrapIdentity {
                    app_version: "0.0.19".into(),
                    session_protocol: 5,
                    libghostty_build: "ghostty-f2d5758f".into(),
                },
            }
        );
        assert_eq!(
            BridgeBootstrapProbeOutcome::from(ProbeOutcome::Mismatch {
                path: "/usr/bin/roost-session".into(),
                identity: None,
            }),
            BridgeBootstrapProbeOutcome::Mismatch {
                path: "/usr/bin/roost-session".into(),
                identity: None,
            }
        );
        assert_eq!(
            BridgeBootstrapProbeOutcome::from(ProbeOutcome::Missing),
            BridgeBootstrapProbeOutcome::Missing
        );

        let session = SessionIdentity {
            app_version: "0.0.19".into(),
            session_protocol: 5,
            libghostty_build: "ghostty-f2d5758f".into(),
            session_id: "sess-1".into(),
            started_at: "2026-09-13T00:00:00Z".into(),
        };
        assert_eq!(
            BridgeBootstrapSessionState::from(SessionState::Running {
                identity: session.clone()
            }),
            BridgeBootstrapSessionState::Running {
                identity: BridgeBootstrapSessionIdentity {
                    app_version: "0.0.19".into(),
                    session_protocol: 5,
                    libghostty_build: "ghostty-f2d5758f".into(),
                    session_id: "sess-1".into(),
                    started_at: "2026-09-13T00:00:00Z".into(),
                },
            }
        );
        assert_eq!(
            BridgeBootstrapSessionState::from(SessionState::NoSession),
            BridgeBootstrapSessionState::NoSession
        );
        assert_eq!(
            BridgeBootstrapSessionState::from(SessionState::NotInstalled),
            BridgeBootstrapSessionState::NotInstalled
        );
    }

    /// **Every [`Plan`] variant keeps its own arm and its own fields.** The plan
    /// is what the sheet offers, so a collapsed arm is an install offered where
    /// pin P6 forbids one.
    #[test]
    fn every_plan_row_crosses_with_its_fields() {
        let incumbent = Identity {
            app_version: "0.0.19".into(),
            session_protocol: 9,
            libghostty_build: "newer".into(),
        };
        let session = SessionIdentity {
            app_version: "0.0.19".into(),
            session_protocol: 5,
            libghostty_build: "ghostty".into(),
            session_id: "sess-1".into(),
            started_at: "now".into(),
        };

        assert_eq!(
            BridgeBootstrapPlan::from(Plan::Install {
                dest: Some("/home/shed/.local/bin/roost-session".into())
            }),
            BridgeBootstrapPlan::Install {
                dest: Some("/home/shed/.local/bin/roost-session".into())
            }
        );
        assert_eq!(
            BridgeBootstrapPlan::from(Plan::Update {
                path: "/usr/bin/roost-session".into(),
                incumbent: Some(incumbent),
                replaces_newer: true,
                dest: None,
            }),
            BridgeBootstrapPlan::Update {
                path: "/usr/bin/roost-session".into(),
                incumbent: Some(BridgeBootstrapIdentity {
                    app_version: "0.0.19".into(),
                    session_protocol: 9,
                    libghostty_build: "newer".into(),
                }),
                replaces_newer: true,
                dest: None,
            },
            "replaces_newer is what tells a downgrade from an update"
        );
        assert_eq!(
            BridgeBootstrapPlan::from(Plan::Start {
                path: "/usr/bin/roost-session".into()
            }),
            BridgeBootstrapPlan::Start {
                path: "/usr/bin/roost-session".into()
            }
        );
        assert!(matches!(
            BridgeBootstrapPlan::from(Plan::UpToDate { identity: session }),
            BridgeBootstrapPlan::UpToDate { .. }
        ));
        assert_eq!(
            BridgeBootstrapPlan::from(Plan::Report {
                protocol: 4,
                message: "speaks protocol 4".into(),
            }),
            BridgeBootstrapPlan::Report {
                protocol: 4,
                message: "speaks protocol 4".into(),
            }
        );
    }

    /// **Every [`Source`] rung crosses**, and the preview carries the rendered
    /// sentence rather than letting Dart compose one.
    ///
    /// The override rung is the one that matters on a phone: there is no sibling
    /// beside a Flutter app and the release pin is `None`, so it is the only live
    /// source mobile has.
    #[test]
    fn every_source_rung_crosses_and_the_preview_carries_its_sentence() {
        for (from, want) in [
            (
                Source::Override {
                    path: "/tmp/rs".into(),
                },
                BridgeBootstrapSource::Override {
                    path: "/tmp/rs".into(),
                },
            ),
            (
                Source::Sibling {
                    path: "/opt/rs".into(),
                },
                BridgeBootstrapSource::Sibling {
                    path: "/opt/rs".into(),
                },
            ),
            (
                Source::Asset {
                    base: "https://example.test".into(),
                    version: "0.0.20".into(),
                },
                BridgeBootstrapSource::Asset {
                    base: "https://example.test".into(),
                    version: "0.0.20".into(),
                },
            ),
            (Source::None, BridgeBootstrapSource::None),
        ] {
            assert_eq!(BridgeBootstrapSource::from(from.clone()), want, "{from:?}");
        }

        // The override rung, with the environment injected rather than read.
        let env = SourceEnv {
            install_bin: Some(PathBuf::from("/tmp/roost-session")),
            ..SourceEnv::default()
        };
        let preview = source_preview(&env, TARGET, "arm64");
        assert_eq!(
            preview.source,
            BridgeBootstrapSource::Override {
                path: "/tmp/roost-session".into()
            }
        );
        assert!(preview.available, "an override rung is a button");
        assert!(
            preview.describe.contains("ROOST_SESSION_INSTALL_BIN"),
            "the sentence names the variable the user set: {}",
            preview.describe
        );

        // Nothing set at all: no sibling on a phone, and the release pin is
        // `None`, so the sheet gets a sentence instead of a button.
        let bare = source_preview(&SourceEnv::default(), TARGET, "arm64");
        assert_eq!(bare.source, BridgeBootstrapSource::None);
        assert!(!bare.available);
        assert!(
            bare.describe.contains(TARGET) && bare.describe.contains("left untouched"),
            "rung 4's sentence says what was not done: {}",
            bare.describe
        );
    }

    /// The hooks result crosses field for field, and `applied` is computed here
    /// rather than restated in Dart.
    #[test]
    fn the_hooks_result_crosses_field_for_field() {
        let result = HooksResult {
            client_label: CLIENT_LABEL.to_string(),
            wired: vec!["codex".into()],
            refreshed: vec!["claude".into()],
            removed: vec!["cursor".into()],
            skipped: vec![HooksSkip {
                agent: "grok".into(),
                reason: "no config directory".into(),
            }],
            errors: vec![HooksError {
                agent: "opencode".into(),
                error: "permission denied".into(),
            }],
            error: None,
        };
        let bridged: BridgeBootstrapHooks = result.into();
        assert_eq!(bridged.client_label, "shed-mobile");
        assert_eq!(bridged.wired, vec!["codex".to_string()]);
        assert_eq!(bridged.refreshed, vec!["claude".to_string()]);
        assert_eq!(bridged.removed, vec!["cursor".to_string()]);
        assert_eq!(bridged.skipped[0].agent, "grok");
        assert_eq!(bridged.skipped[0].reason, "no config directory");
        assert_eq!(bridged.errors[0].agent, "opencode");
        assert_eq!(bridged.errors[0].error, "permission denied");
        assert!(
            bridged.applied,
            "per-agent errors are partial success, not a failed call"
        );

        let failed: BridgeBootstrapHooks = HooksResult {
            client_label: CLIENT_LABEL.to_string(),
            error: Some("the connection went away".into()),
            ..HooksResult::default()
        }
        .into();
        assert!(!failed.applied);
    }

    // -- the lifecycle ---------------------------------------------------

    /// **The leak contract**: creating bumps the counter, teardown returns it,
    /// and a second close is a no-op rather than a second decrement.
    ///
    /// A double-decrement is the failure that matters — the counter is `u64`, so
    /// one would wrap to 18446744073709551615 and every later leak assertion
    /// would pass for the wrong reason.
    #[test]
    fn creating_and_closing_a_bootstrap_leaves_the_counter_where_it_found_it() {
        let _g = test_guard();
        let before = live_counters().active_roost_bootstraps;

        let handle = roost_bootstrap_probe(host(1));
        assert_eq!(live_counters().active_roost_bootstraps, before + 1);

        roost_bootstrap_close(&handle);
        assert_eq!(live_counters().active_roost_bootstraps, before);

        // Idempotent: the sync close and `Drop` are co-primary, so teardown runs
        // at least twice for every handle the app ever makes.
        roost_bootstrap_close(&handle);
        drop(handle);
        assert_eq!(live_counters().active_roost_bootstraps, before);
    }

    /// `Drop` alone returns the counter, for a handle Dart never closed.
    #[test]
    fn dropping_a_bootstrap_is_the_backstop() {
        let _g = test_guard();
        let before = live_counters().active_roost_bootstraps;
        drop(roost_bootstrap_probe(host(1)));
        assert_eq!(live_counters().active_roost_bootstraps, before);
    }

    /// A closed handle refuses every verb by name instead of panicking or
    /// hanging.
    #[tokio::test]
    async fn a_closed_handle_refuses_by_name() {
        let _g = test_guard();
        let handle = roost_bootstrap_probe(host(1));
        roost_bootstrap_close(&handle);

        let error = roost_bootstrap_begin(&handle).await.unwrap_err();
        assert!(error.contains("is closed"), "{error}");
        let error = bootstrap_source_read(&handle, 16).unwrap_err();
        assert!(error.contains("is closed"), "{error}");
    }

    /// A probe streams no source, and says so rather than answering an empty
    /// chunk — which a runner would read as EOF and treat as a zero-byte binary.
    #[tokio::test]
    async fn a_probe_has_no_source_to_read() {
        let _g = test_guard();
        let handle = roost_bootstrap_probe(host(1));
        let error = bootstrap_source_read(&handle, 16).unwrap_err();
        assert!(error.contains("streams no source"), "{error}");
    }

    // -- the source ------------------------------------------------------

    /// **Every stdin shape crosses, and the streamed one hands over no path.**
    ///
    /// That last clause is the whole of [`Stdin::Source`]'s own doc — the bytes
    /// shed hashed and the bytes shed sends have to be the same bytes — so the
    /// crossing is asserted to carry the descriptor's *description* and nothing
    /// a runner could re-open.
    #[test]
    fn every_stdin_shape_crosses_and_the_source_hands_over_no_path() {
        assert_eq!(
            BridgeBootstrapStdin::from(Stdin::Empty),
            BridgeBootstrapStdin::Empty
        );
        assert_eq!(
            BridgeBootstrapStdin::from(Stdin::Bytes(b"#!/bin/sh\nexit 0\n".to_vec())),
            BridgeBootstrapStdin::Bytes {
                bytes: b"#!/bin/sh\nexit 0\n".to_vec()
            }
        );

        let dir = scratch("stdin");
        let path = dir.join("roost-session");
        std::fs::write(&path, b"0123456789").expect("the fixture binary");
        let file = std::fs::File::open(&path).expect("opening it");
        let crossed = BridgeBootstrapStdin::from(Stdin::Source(SourceHandle::from_open_file(
            "the roost-session beside this app",
            file,
            10,
            Some("abc123".to_string()),
        )));
        assert_eq!(
            crossed,
            BridgeBootstrapStdin::Source {
                len: 10,
                origin: "the roost-session beside this app".to_string(),
                sha256: Some("abc123".to_string()),
            }
        );
        let rendered = format!("{crossed:?}");
        assert!(
            !rendered.contains(path.to_str().expect("a utf-8 fixture path")),
            "a streamed source must hand Dart no path to re-open: {rendered}"
        );
    }

    /// **The override rung end to end**: the ladder opens the file, the machine
    /// keeps the descriptor, and Dart pulls the same bytes back through
    /// [`bootstrap_source_read`] — then [`bootstrap_source_rewind`] puts it back
    /// to the start so a re-sent stream step cannot ship a truncated binary.
    ///
    /// The environment is injected, so nothing here touches `std::env` — and the
    /// override is the rung that matters, because it is the only live one on a
    /// phone.
    #[tokio::test]
    async fn an_install_streams_the_overridden_bytes_and_rewinds() {
        let _g = test_guard();
        let before = live_counters().active_roost_bootstraps;

        let dir = scratch("install");
        let bin = dir.join("roost-session");
        std::fs::write(&bin, b"roost-session-bytes").expect("the fixture binary");

        let handle = install_with(
            SourceEnv {
                install_bin: Some(bin.clone()),
                ..SourceEnv::default()
            },
            host(1),
            "fingerprint-from-the-consented-probe".into(),
            "arm64".into(),
            true,
            dir.join("scratch").display().to_string(),
        )
        .await
        .expect("the override rung resolves");
        assert_eq!(live_counters().active_roost_bootstraps, before + 1);

        // Chunked, the way a runner streams it.
        let mut streamed = Vec::new();
        loop {
            let chunk = bootstrap_source_read(&handle, 4).expect("a chunk");
            if chunk.is_empty() {
                break;
            }
            assert!(chunk.len() <= 4, "a chunk is capped at what was asked for");
            streamed.extend_from_slice(&chunk);
        }
        assert_eq!(streamed, b"roost-session-bytes");

        bootstrap_source_rewind(&handle).expect("the rewind");
        let again = bootstrap_source_read(&handle, 64).expect("a chunk");
        assert_eq!(
            again, b"roost-session-bytes",
            "a rewind must put a re-sent stream back at byte zero"
        );

        roost_bootstrap_close(&handle);
        assert_eq!(live_counters().active_roost_bootstraps, before);
    }

    /// An install handle whose source is the override rung, holding `bytes`.
    async fn install_streaming(what: &str, bytes: &[u8]) -> BridgeRoostBootstrap {
        let dir = scratch(what);
        let bin = dir.join("roost-session");
        std::fs::write(&bin, bytes).expect("the fixture binary");
        install_with(
            SourceEnv {
                install_bin: Some(bin),
                ..SourceEnv::default()
            },
            host(1),
            "fingerprint-from-the-consented-probe".into(),
            "arm64".into(),
            true,
            dir.join("scratch").display().to_string(),
        )
        .await
        .expect("the override rung resolves")
    }

    /// **The stream is single-reader, and a second caller is refused rather than
    /// served.**
    ///
    /// The contract is that the bytes sent are exactly the bytes that were
    /// hash-verified, in order — and `read_chunk` advances ONE descriptor, on
    /// FRB's blocking worker POOL. Two calls in flight at once would each be
    /// handed a different, correct-looking chunk in an order neither the bridge
    /// nor Dart can put back, and a `rewind` landing inside a read would re-send
    /// bytes already sent. The second thread here is the second worker, and both
    /// of its calls must come back refused by name.
    ///
    /// The claim is released when the call that holds it returns, so the stream
    /// is whole afterwards — asserted byte for byte, which is the property all
    /// of this is for.
    #[tokio::test]
    async fn a_source_call_in_flight_refuses_a_second_reader_and_a_rewind() {
        let _g = test_guard();
        let handle = install_streaming("single-reader", b"roost-session-bytes").await;

        {
            // The claim one in-flight `bootstrap_source_read` holds.
            let _reading = claim_source(&handle.state).expect("the first reader");
            std::thread::scope(|threads| {
                threads.spawn(|| {
                    let refused = bootstrap_source_read(&handle, 4)
                        .expect_err("a second reader must not be served");
                    assert!(refused.contains("one chunk at a time"), "{refused}");
                    let refused = bootstrap_source_rewind(&handle)
                        .expect_err("a rewind must not land inside a read");
                    assert!(refused.contains("one chunk at a time"), "{refused}");
                });
            });
        }

        // Released — and what a serial runner then pulls is the file, in order.
        let mut streamed = Vec::new();
        loop {
            let chunk = bootstrap_source_read(&handle, 4).expect("a chunk");
            if chunk.is_empty() {
                break;
            }
            streamed.extend_from_slice(&chunk);
        }
        assert_eq!(streamed, b"roost-session-bytes");

        roost_bootstrap_close(&handle);
    }

    /// **`max == 0` is refused, not answered empty.**
    ///
    /// An empty answer is this stream's EOF, so a zero-byte read would tell a
    /// runner the binary ended — at byte zero, or halfway through. The far side
    /// would then be handed a truncated file that only the staged verify catches.
    #[tokio::test]
    async fn a_zero_byte_source_read_is_refused_rather_than_read_as_eof() {
        let _g = test_guard();
        let handle = install_streaming("zero-max", b"roost-session-bytes").await;

        let refused = bootstrap_source_read(&handle, 0).expect_err("0 is not a chunk size");
        assert!(refused.contains("at least one byte"), "{refused}");
        assert!(
            refused.contains("EOF"),
            "it says what 0 would be read as: {refused}"
        );

        // And the stream is untouched by the refusal: still at byte zero.
        assert_eq!(
            bootstrap_source_read(&handle, 5).expect("a chunk"),
            b"roost"
        );

        roost_bootstrap_close(&handle);
    }

    /// A plan that needs no bytes resolves no source at all — nothing is opened,
    /// and nothing is downloaded, for a `Start`.
    #[tokio::test]
    async fn a_start_only_install_resolves_no_source() {
        let _g = test_guard();
        let handle = install_with(
            SourceEnv::default(),
            host(1),
            "fingerprint".into(),
            "arm64".into(),
            false,
            "/nonexistent/scratch".into(),
        )
        .await
        .expect("a start needs no bytes");
        let error = bootstrap_source_read(&handle, 16).unwrap_err();
        assert!(error.contains("streams no source"), "{error}");
        roost_bootstrap_close(&handle);
    }

    /// A plan that needs bytes and has none fails **before the handle exists**,
    /// so a host is never touched by an install with nothing to send. The
    /// sentence is shed-core's, word for word.
    #[tokio::test]
    async fn an_install_with_no_source_refuses_before_it_has_a_handle() {
        let _g = test_guard();
        // A `match` rather than `expect_err`: the Ok side is an opaque FRB
        // handle with no `Debug`, by construction.
        let failure = match install_with(
            SourceEnv::default(),
            host(1),
            "fingerprint".into(),
            "arm64".into(),
            true,
            "/nonexistent/scratch".into(),
        )
        .await
        {
            Err(failure) => failure,
            Ok(_) => panic!("no rung can supply these bytes, so no handle may exist"),
        };
        assert_eq!(failure.stage, BridgeBootstrapStage::Source);
        assert_eq!(failure.stage_code, "source");
        assert!(
            failure.message.contains(TARGET) && failure.message.contains("left untouched"),
            "{}",
            failure.message
        );
    }

    // -- the split drive loop, which is the whole point ------------------

    /// **THE CRUX.** Dart is handed `Exec` steps and nothing else; the machine's
    /// one `Step::Call` is performed in Rust, over the loopback port, against a
    /// real `roost-session`.
    ///
    /// The host here is cold — the discovery answer names no ladder rung — which
    /// is exactly the shape that runs the probe's two execs and then asks
    /// `session.identify`. If that call ever crossed the bridge the loop below
    /// would hand Dart a third exec (or hang), and the fake would record no
    /// connection at all.
    #[tokio::test]
    async fn the_drive_hands_dart_execs_and_answers_the_wire_call_itself() {
        let _g = test_guard();
        let fake = FakeRoost::start().await;
        let handle = roost_bootstrap_probe(host(fake.tcp_port()));

        // 1. discovery — `/bin/sh -s` with roost's script on stdin.
        let step = roost_bootstrap_begin(&handle)
            .await
            .expect("the first step");
        let BridgeBootstrapStep::Exec {
            command,
            stdin,
            budget_ms,
            stdout_cap,
            capture_stdout,
            stderr_cap,
        } = &step
        else {
            panic!("expected an exec, got {step:?}")
        };
        assert_eq!(command.as_str(), bootstrap::SH_STDIN);
        assert!(
            matches!(stdin, BridgeBootstrapStdin::Bytes { bytes } if !bytes.is_empty()),
            "the script crosses as bytes, never as a path: {stdin:?}"
        );
        assert_eq!(*budget_ms, 30_000, "PROBE_BUDGET, in milliseconds");
        assert_eq!(*stdout_cap, 64 * 1024, "PROBE_STDOUT_CAP");
        // The cap the runner does NOT get to invent. If shed-app's own
        // STDERR_TAIL_CAP moves, this is the line that says the two drifted.
        assert_eq!(*stderr_cap, 4 * 1024, "STDERR_TAIL_CAP");
        assert!(capture_stdout);

        // 2. the remote shell's own `command -v` — a self-contained command, not
        //    a script on stdin.
        let step = feed(&handle, ok(cold_discovery())).await;
        let command = exec_command(&step);
        assert_ne!(command, bootstrap::SH_STDIN);
        assert!(
            command.contains("roost-session"),
            "the path check asks about roost-session: {command}"
        );

        // 3. `command -v` found nothing — and the next thing is the ANSWER, not a
        //    third exec: Rust absorbed `session.identify` against the fake.
        let probe = probed(feed(&handle, (Some(1), Vec::new(), String::new())).await);

        assert_eq!(probe.target, TARGET);
        assert_eq!(
            probe.arch, "amd64",
            "x86_64 maps to roost's release spelling"
        );
        assert_eq!(probe.home, "/home/shed");
        assert_eq!(probe.outcome, BridgeBootstrapProbeOutcome::Missing);
        assert!(
            matches!(probe.session, BridgeBootstrapSessionState::Running { .. }),
            "the fake answered session.identify over the loopback port: {:?}",
            probe.session
        );
        assert!(
            matches!(probe.plan, BridgeBootstrapPlan::UpToDate { .. }),
            "a protocol-5 session that is already serving is nothing to do: {:?}",
            probe.plan
        );
        assert!(!probe.needs_source);
        assert!(!probe.actionable);
        assert!(!probe.fingerprint.is_empty());

        roost_bootstrap_close(&handle);
    }

    /// **Pin P6 crosses the bridge.** A session serving a protocol shed cannot
    /// talk to is reported — a `Report` row with the sentence naming both
    /// numbers — and never a `Start`, an `Update` or an `Install`.
    #[tokio::test]
    async fn a_mismatched_session_comes_back_as_report_and_no_button() {
        let _g = test_guard();
        let fake = FakeRoost::start().await;
        fake.set_session_protocol(4);
        let handle = roost_bootstrap_probe(host(fake.tcp_port()));

        let probe = probed(probe_cold_host(&handle).await);
        match &probe.plan {
            BridgeBootstrapPlan::Report { protocol, message } => {
                assert_eq!(*protocol, 4);
                assert!(message.contains('4') && message.contains('5'), "{message}");
            }
            other => panic!("pin P6 wants a Report row, got {other:?}"),
        }
        assert!(!probe.actionable, "a Report offers no button");

        roost_bootstrap_close(&handle);
    }

    /// **The reach note is what makes the three-way answer possible.** With
    /// nothing listening on the port, the absorbed `session.identify` fails —
    /// and what the probe reports turns entirely on what Dart recorded about its
    /// own transport.
    #[tokio::test]
    async fn dart_s_reach_note_decides_the_three_way_probe_answer() {
        let _g = test_guard();
        let dead = dead_port();

        for (kind, want) in [
            (
                BridgeReachKind::NotInstalled,
                BridgeBootstrapSessionState::NotInstalled,
            ),
            (
                BridgeReachKind::NoSession,
                BridgeBootstrapSessionState::NoSession,
            ),
        ] {
            let handle = roost_bootstrap_probe(host(dead));
            roost_bootstrap_note_reach(&handle, kind, "the far side said so".into());

            let probe = probed(probe_cold_host(&handle).await);
            assert_eq!(probe.session, want, "{kind:?}");
        }

        // And with NO note the probe FAILS rather than guessing — roost's rule,
        // and the reason `transport` is the fallthrough instead of a cheerful
        // "not installed".
        let handle = roost_bootstrap_probe(host(dead));
        match probe_cold_host(&handle).await {
            BridgeBootstrapStep::Failed { failure } => {
                assert_eq!(failure.stage, BridgeBootstrapStage::Probe);
                assert!(failure.message.contains("transport"), "{}", failure.message);
            }
            other => panic!("an unclassified reach must not become a state, got {other:?}"),
        }
    }

    /// A note is spent on the failure it explains and never read twice — the
    /// mobile shape of the desktop's generation watermark.
    #[test]
    fn a_reach_note_is_consumed_by_the_failure_it_explains() {
        let _g = test_guard();
        let handle = roost_bootstrap_probe(host(1));
        roost_bootstrap_note_reach(
            &handle,
            BridgeReachKind::NoSession,
            "client-bridge: no session".into(),
        );

        let first = classify(&handle.state, transport("the socket refused"));
        assert_eq!(first.code, reach_code::NO_SESSION);
        assert_eq!(first.message, "client-bridge: no session");

        let second = classify(&handle.state, transport("the socket refused"));
        assert_eq!(
            second.code, "transport",
            "a spent note must not explain a second, different failure"
        );
        assert_eq!(second.message, "the socket refused");
    }

    /// **A session's own refusal is never a note's to explain.** The note stays
    /// unspent, because the failure it is about did not happen.
    #[test]
    fn a_session_minted_refusal_is_not_classified_by_the_note() {
        let _g = test_guard();
        let handle = roost_bootstrap_probe(host(1));
        roost_bootstrap_note_reach(
            &handle,
            BridgeReachKind::NoSession,
            "client-bridge: no session".into(),
        );

        let answered = classify(
            &handle.state,
            CallFailure::Answered(CallError::new("unknown-op", "no such op")),
        );
        assert_eq!(answered.code, "unknown-op");
        assert_eq!(answered.message, "no such op");
        assert_eq!(
            classify(&handle.state, transport("the socket refused")).code,
            reach_code::NO_SESSION,
            "the note was not spent on a refusal the session itself minted"
        );
    }

    /// `Unreachable` and `Other` are not actionable states of the far side, so
    /// they arrive as `transport` and the machine reports a failed probe.
    #[test]
    fn an_unactionable_reach_kind_is_transport() {
        let _g = test_guard();
        for kind in [BridgeReachKind::Unreachable, BridgeReachKind::Other] {
            let handle = roost_bootstrap_probe(host(1));
            roost_bootstrap_note_reach(&handle, kind, "the tunnel died".into());
            assert_eq!(
                classify(&handle.state, transport("unused")).code,
                "transport",
                "{kind:?}"
            );
        }
    }

    /// **shed-mobile's client label reaches the host.** The desktop's label is
    /// pinned by shed's own tests; this is the only thing that pins mobile's,
    /// and it is the field roost files as the `by` of the state entry.
    #[tokio::test]
    async fn the_hooks_call_sends_shed_mobile_as_its_client() {
        let fake = FakeRoost::start().await;

        let result = perform_hooks(fake.tcp_port(), CLIENT_LABEL).await;
        assert!(result.applied(), "{:?}", result.error);
        assert_eq!(result.client_label, "shed-mobile");

        let calls = fake.agent_hooks_calls();
        assert_eq!(calls.len(), 1, "one call, no retry loop: {calls:?}");
        assert_eq!(calls[0]["client"], "shed-mobile");
        assert_eq!(calls[0]["mode"], "auto");
        assert_eq!(
            calls[0]["skip"],
            serde_json::json!([]),
            "shed never asks a host to skip an agent"
        );
        assert!(
            calls[0].get("lease").is_none(),
            "the lease retired at session protocol 5: {:?}",
            calls[0]
        );
    }

    /// A hooks call that cannot even connect is reported, never fatal, and keeps
    /// the label so the sheet can still say who was asking.
    #[tokio::test]
    async fn a_hooks_call_that_cannot_connect_is_reported_not_fatal() {
        let result = perform_hooks(dead_port(), CLIENT_LABEL).await;
        assert!(!result.applied());
        assert_eq!(result.client_label, "shed-mobile");
        assert!(result.error.is_some());
    }

    // -- the races: close, cancel, and the note in between ---------------

    /// **Closing during a drive aborts it; it does not hand Dart a step.**
    ///
    /// The drive is parked inside its absorbed `session.identify` when
    /// [`roost_bootstrap_close`] runs, which is the whole race: the entry check
    /// in [`check_out`] is long past, and without a check at the step boundary
    /// the drive would carry on — dialling the loopback port again for every
    /// step it has left, and finally returning a step for a handle Dart has
    /// already disposed of. Dart would then EXECUTE that step on the far side;
    /// for an install past its commit step that is a remote mutation after
    /// close.
    ///
    /// The refusal is the same sentence every other verb gives, so a Riverpod
    /// `onDispose` race reads as a disposal rather than as a bootstrap failure.
    #[tokio::test]
    async fn closing_during_a_drive_refuses_instead_of_answering_with_a_step() {
        let _g = test_guard();
        let before = live_counters().active_roost_bootstraps;
        let mut roost = StallingRoost::start();
        let handle = roost_bootstrap_probe(host(roost.port));
        roost_bootstrap_note_reach(
            &handle,
            BridgeReachKind::NoSession,
            "client-bridge: no session".into(),
        );
        up_to_the_wire_call(&handle).await;

        let drive = the_feed_that_dials(&handle);
        let close_underneath_it = async {
            assert!(
                wait_until(Duration::from_secs(10), || roost.accepts() == 1),
                "the drive never got as far as its wire call"
            );
            roost_bootstrap_close(&handle);
            // Only now does the parked call end, so the close is unambiguously
            // mid-flight rather than merely mid-drive.
            roost.stop();
        };
        let (answer, ()) = tokio::join!(drive, close_underneath_it);

        let error = answer.expect_err("a closed handle must not be handed a step");
        assert!(error.contains("is closed"), "{error}");
        assert_eq!(
            roost.accepts(),
            1,
            "the in-flight call and no other: nothing was dialled after the close"
        );
        assert_eq!(
            live_counters().active_roost_bootstraps,
            before,
            "the close still returned the counter, and the aborted drive dropped the machine"
        );
        assert!(
            lock(&handle.state).reach.is_some(),
            "an outcome the machine never saw must not spend Dart's reach note"
        );
    }

    /// The gate on the way OUT of a drive — the one that keeps a computed step
    /// from reaching Dart for a handle already disposed of.
    ///
    /// [`bump_steps`] fires first for any close that lands during a wire call,
    /// which is what the race above exercises end to end; this pins the narrower
    /// window the return gate is for — a close that lands after the last step
    /// boundary, while the step itself is being computed. That window is
    /// synchronous, so forcing a close into it would take a test-only hook
    /// inside the drive loop; the gate is what is worth pinning.
    #[test]
    fn the_way_out_of_a_drive_is_gated_on_the_handle_still_being_open() {
        let _g = test_guard();
        let handle = roost_bootstrap_probe(host(1));
        still_open(&handle.state).expect("an open handle");

        roost_bootstrap_close(&handle);
        let error = still_open(&handle.state).expect_err("a closed handle");
        assert_eq!(error, closed_err(TARGET));
    }

    /// **A cancelled drive leaves the note for the re-read that follows it.**
    ///
    /// This is the module doc's rule under the conditions it was written for:
    /// Dart cancelled the call, so `joined_on_bridge_rt` aborted the task and
    /// [`MachineGuard`]'s `Drop` put the machine back. The retry RE-READS with
    /// [`roost_bootstrap_begin`] — and what it must get back is the step the
    /// machine is owed, classified by the note Dart left, not a `transport`
    /// failure because the note went with the cancelled drive. That mislabelling
    /// is the exact thing [`roost_bootstrap_note_reach`] exists to prevent, and
    /// a probe that reports `transport` cannot offer an install at all.
    #[tokio::test]
    async fn a_cancelled_drive_keeps_the_note_for_the_re_read() {
        let _g = test_guard();
        let mut roost = StallingRoost::start();
        let handle = roost_bootstrap_probe(host(roost.port));
        roost_bootstrap_note_reach(
            &handle,
            BridgeReachKind::NoSession,
            "client-bridge: no session".into(),
        );
        up_to_the_wire_call(&handle).await;

        // The FRB cancellation shape (see `testsupport::noop_waker`): poll the
        // call's future once to start it, then drop it while it is parked.
        let mut cancelled = Box::pin(the_feed_that_dials(&handle));
        let waker = noop_waker();
        let mut cx = Context::from_waker(&waker);
        assert!(cancelled.as_mut().poll(&mut cx).is_pending());
        assert!(
            wait_until(Duration::from_secs(10), || roost.accepts() == 1),
            "the drive never got as far as its wire call"
        );
        drop(cancelled);
        assert!(
            wait_until(Duration::from_secs(10), || lock(&handle.state)
                .machine
                .is_some()),
            "the aborted drive's guard never put the machine back"
        );

        // The reach is gone now, so the re-read's own call fails — and Dart's
        // note is what says why.
        roost.stop();
        let probe = probed(roost_bootstrap_begin(&handle).await.expect("the re-read"));
        assert_eq!(
            probe.session,
            BridgeBootstrapSessionState::NoSession,
            "the re-read must still be explained by the note the cancelled drive did not spend"
        );

        roost_bootstrap_close(&handle);
    }

    /// **A note is never spent by an outcome the machine never saw.**
    ///
    /// The deterministic version of the same property: the step budget runs out
    /// between the failed wire call and the feed, so the outcome is dropped on
    /// the floor. Classifying before that boundary would burn the note on a
    /// failure nothing was ever told about — and the note is single-shot, so
    /// there is no second one to explain the next.
    #[tokio::test]
    async fn a_note_outlives_an_outcome_the_machine_never_saw() {
        let _g = test_guard();
        let handle = roost_bootstrap_probe(host(dead_port()));
        roost_bootstrap_note_reach(
            &handle,
            BridgeReachKind::NoSession,
            "client-bridge: no session".into(),
        );

        // Two steps to get here, then re-reads until one step of budget is left:
        // enough for the drive below to reach its wire call, and not enough to
        // feed what the call answers back in.
        up_to_the_wire_call(&handle).await;
        for _ in 0..(MAX_STEPS - 3) {
            roost_bootstrap_begin(&handle).await.expect("a re-read");
        }
        let error = the_feed_that_dials(&handle)
            .await
            .expect_err("the budget must stop this drive");
        assert!(
            error.contains(&format!("did not finish in {MAX_STEPS} steps")),
            "{error}"
        );

        let unspent = classify(&handle.state, transport("the socket refused"));
        assert_eq!(
            unspent.code,
            reach_code::NO_SESSION,
            "the note must still be there to explain the failure the machine never heard about"
        );
        assert_eq!(unspent.message, "client-bridge: no session");
    }

    /// The step budget bounds the whole handle, not one call — a runner that
    /// re-read its step forever would otherwise spin a remote exec as fast as
    /// the loop can run.
    #[tokio::test]
    async fn the_step_budget_bounds_the_whole_handle() {
        let _g = test_guard();
        let handle = roost_bootstrap_probe(host(1));
        let mut refusal = None;
        for _ in 0..(MAX_STEPS + 2) {
            if let Err(error) = roost_bootstrap_begin(&handle).await {
                refusal = Some(error);
                break;
            }
        }
        let error = refusal.expect("the budget must stop a runner that never answers");
        assert!(
            error.contains(&format!("did not finish in {MAX_STEPS} steps")),
            "{error}"
        );
    }
}
