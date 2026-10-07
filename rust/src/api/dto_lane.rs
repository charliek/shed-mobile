//! Bridge-owned **agent-lane** DTOs (plan 018 §3.9): the hand-written mirror of
//! [`shed_core::lane`]'s contract types, plus the two behaviours a client must
//! not re-derive.
//!
//! It is the sibling of [`super::dto_rc`] and follows its rules exactly, because
//! `shed_core::lane`'s own module doc names this file's job: *"shed-mobile
//! **hand-mirrors** every DTO here into Dart (the way `dto_rc.rs`/`rc_feed.dart`
//! already mirror [`shed_core::rc`]'s feed types)."* So a fielded enum becomes a
//! Dart sealed class, a plain enum becomes a plain Dart enum, and every field is
//! an owned `String`/`Option`/`Vec`/scalar.
//!
//! # The asymmetry is the contract, and here it is a matter of SHAPE
//!
//! `shed_core::lane`'s "unknown-value tolerance, applied ASYMMETRICALLY" rule
//! says stream/inbound types tolerate an unrecognized value and command/outbound
//! types reject one. On the wire that is a serde question. In a hand-mirrored
//! Rust↔Rust pair there is no decode step, so the same rule shows up as the
//! PRESENCE OR ABSENCE OF AN ESCAPE ARM:
//!
//! * **Tolerant, inbound**: [`BridgeLaneApprovalKind`],
//!   [`BridgeLaneApprovalStatus`], and plan 025's three — [`BridgeSourceOffline`],
//!   [`BridgeLaneProviderState`] and [`BridgeLanePromptOutcome`] — carry
//!   `Other { raw }` and preserve the raw wire string verbatim, exactly as
//!   [`super::dto_rc::BridgeRcKind`] does. An approval, an outage cause, a
//!   provider state or a prompt outcome minted by a newer agent renders
//!   neutrally instead of vanishing. Each is a fielded enum, so a Dart sealed
//!   class whose `other(raw)` case is the escape arm.
//! * **Strict, outbound**: [`BridgeLaneDecision`], [`BridgeSendMode`],
//!   [`BridgeLaneAnswer`], and plan 025's [`BridgeLaneSettingChange`] and
//!   [`BridgeLaneCreateRequest`] have NO escape arm at all. Dart cannot construct
//!   an unrecognized decision, mode, answer, setting change or create field —
//!   the mirror of "serde refuses it" is "the type does not admit it", which is
//!   a stronger guarantee than a runtime refusal and is what keeps a user's
//!   "allow" from becoming a silent no-op.
//! * [`BridgeLaneError`] is strict too, and for the reason the contract gives:
//!   the controller BRANCHES on it. That is also why it is a sealed enum with one
//!   case per [`LaneError`] variant — the [`super::error::BridgeError`] shape —
//!   rather than `roost.rs`'s `Result<_, String>`.
//!
//! # Two behaviours are exposed as functions, not re-derived
//!
//! [`lane_option_for`] and [`lane_status_is_pending`] exist so Dart mirrors the
//! contract's BEHAVIOUR by calling it. Both rules have a clause subtle enough
//! that an independent reading would not agree —
//! [`LaneApproval::option_for`]'s ambiguity refusal and its `Reject`-only
//! fallback, and `is_pending`'s "an `Other` status is NOT pending" — and both
//! are quoted at length in `shed_core::lane`. A Dart re-implementation would be
//! a third reading of prose that the crate exists to stop.
//!
//! # Two levels, one mirror (plan 025 §3.2)
//!
//! The contract split an agent into a SOURCE — a machine's sessions, what can
//! be created there, and creating one — and a session-scoped LANE. Both
//! levels' DTOs are mirrored here, in the commit that re-pinned onto the split
//! (CM2), even where no bridge function hands one over yet: the source half is
//! what the phone's craze source (CM3) and its create sheet (CM4) put on the
//! wire, and the settings change is what the settings sheet (CM6) sends.
//! Those types carry `#[frb(unignore)]` for the [`BridgeLaneSession`]
//! precedent this file set before: the codegen prunes a type no function
//! names, and mirroring the contract whole now keeps each later slice a
//! feature rather than a feature plus a codegen change.
//!
//! **Capabilities, settings and the session row ride the snapshot.** They are
//! per session and can change with an incarnation, so they are stream state
//! like activity (`shed_core::lane`'s module doc, "Capabilities and settings
//! ride the stream") — there is no capabilities getter on a lane to cache, and
//! [`BridgeLaneSnapshot`] carries the latest of each.
//!
//! # What is NOT here
//!
//! [`shed_core::lane::LaneEvent`] does not cross. It is folded in Rust by
//! [`shed_app::lane_view::LaneView`] and `Reset`/`Ready`/`Stale`/`Down`/
//! `Capabilities`/`Settings`/`Unknown` never reach Dart as frames — the phone
//! gets a nudge and pulls one atomic [`BridgeLaneSnapshot`]. A source's
//! `SourceEvent` will not cross either, for the same reason: the phone folds it
//! in Rust and reads a snapshot (CM3). `LaneHistory` does not cross: no phone
//! verb needs a page of transcript that is not already in the view.
//! `LaneSubscription`/`LaneStop` are handles, and handles stay in
//! [`super::lane`].

use flutter_rust_bridge::frb;
use shed_app::lane_view::LaneViewSnapshot;
use shed_core::lane::{
    LaneAnswer, LaneApproval, LaneApprovalKind, LaneApprovalOption, LaneApprovalStatus,
    LaneCapabilities, LaneChoice, LaneCreateOptions, LaneCreateRequest, LaneCreated, LaneDecision,
    LaneError, LanePromptOutcome, LaneProvider, LaneProviderState, LaneQuestion, LaneSession,
    LaneSetting, LaneSettingChange, LaneSettings, LaneUsage, SendMode, SourceCapabilities,
    SourceOffline,
};
use shed_core::roost::AgentLaneStamp;

use super::dto_rc::{BridgeRcActivity, BridgeRcFeedMessage};

// ---------------------------------------------------------------------------
// the stamp
// ---------------------------------------------------------------------------

/// Where a row's agent lane is and which adapter speaks to it (mirrors
/// `roost::AgentLaneStamp`) — the whole of what [`super::lane::lane_open`]
/// needs.
///
/// **`server_url` is the REPORTED url**, never a dial url. On a remote machine
/// the phone dials its own fixed loopback port instead (plan 018 §3.10), and the
/// two are never conflated.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAgentLaneStamp {
    /// The adapter token — `"opencode"` today. A kind this build has
    /// no adapter for is refused BY NAME
    /// ([`BridgeLaneError::UnsupportedLane`]), never silently rendered as no
    /// lane: `AgentLaneStamp`'s own doc makes that the client's obligation.
    pub kind: String,
    /// The AGENT's own session id — the address every lane verb takes.
    pub session_id: String,
    pub server_url: String,
}

impl From<AgentLaneStamp> for BridgeAgentLaneStamp {
    fn from(s: AgentLaneStamp) -> Self {
        BridgeAgentLaneStamp {
            kind: s.kind,
            session_id: s.session_id,
            server_url: s.server_url,
        }
    }
}

// ---------------------------------------------------------------------------
// sessions
// ---------------------------------------------------------------------------

/// One agent session as the contract sees it (mirrors `lane::LaneSession`).
///
/// `activity` is [`BridgeRcActivity`] rather than a parallel vocabulary, for the
/// contract's reason: a lane row has to sort into the same sessions view as an
/// RC row, and the app already renders that badge.
///
/// **Read `activity` for "is it running" and `pending_approvals` for "is it
/// blocked on me".** They are separate dimensions on purpose — the pinned
/// opencode mapping never emits `NeedsApproval`, so a client that keys its
/// blocked badge off `activity` alone misses every opencode approval.
///
/// It crosses on [`BridgeLaneSnapshot::session`] — the stream's LIVE row — and,
/// from the craze source on, as a machine's craze rows. It used to carry
/// `#[frb(unignore)]` because nothing returned one: before plan 025 the fold
/// projected only the session's `activity`. `shed_app::lane_view` now projects
/// the whole row, so the codegen reaches it through the snapshot.
///
/// The fields after `last_change_unix_ms` are plan 025's: what a craze roster
/// row says about a session beyond its activity. Every one is optional and
/// `None` on a row from an adapter that knows none of them (opencode's), and
/// each is the contract's own field, mirrored as it stands
/// (`shed_core::lane::LaneSession`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeLaneSession {
    pub id: String,
    pub title: String,
    pub cwd: String,
    pub activity: BridgeRcActivity,
    pub pending_approvals: u32,
    /// `true` when the adapter derived this ROW from a cheap or stale source (a
    /// roster poll rather than a live fold). Per-ROW, not per-producer
    /// (`lane`'s correction 7): opencode answers `true` from its roster and
    /// `false` from its watcher.
    pub approximate: bool,
    pub parent_id: Option<String>,
    pub last_change_unix_ms: Option<i64>,
    /// The agent provider driving the session (craze's `cursor`, `grok`, …);
    /// `None` where the adapter IS the provider (opencode).
    pub provider: Option<String>,
    /// The model the session runs, as the agent names it.
    pub model: Option<String>,
    /// What the session is doing right now, one line.
    pub doing: Option<String>,
    /// The oldest open approval's one-line summary — what the session is
    /// blocked on, for a row with no room for the approval itself.
    pub head_ask_summary: Option<String>,
    /// The head of the agent's last reply, one line.
    pub last_reply: Option<String>,
    /// Unix epoch milliseconds since the session has been in its current state.
    pub since_unix_ms: Option<i64>,
    /// How many clients are attached to the session right now.
    pub attached: Option<u32>,
    /// Why the session failed to start, when it did — shown as it is.
    pub start_error: Option<String>,
    /// The PROVIDER's own session id behind this row — the key a roost tab
    /// running the same session carries, and so the key a client folds that
    /// tab into this row by (plan 025 D4). Never an address any verb takes.
    pub provider_session_id: Option<String>,
    /// The agent's permission posture (craze's `"bypass"` | `"prompt"`) for the
    /// transcript header. An open string: a newer agent's posture renders as
    /// its own word.
    pub permission_mode: Option<String>,
    /// The roost tab this row was merged with — set ONLY by the client-side
    /// merge (plan 025 §3.6.3), never by a source or a lane.
    pub tab_id: Option<i64>,
}

impl From<LaneSession> for BridgeLaneSession {
    fn from(s: LaneSession) -> Self {
        BridgeLaneSession {
            id: s.id,
            title: s.title,
            cwd: s.cwd,
            activity: s.activity.into(),
            pending_approvals: s.pending_approvals,
            approximate: s.approximate,
            parent_id: s.parent_id,
            last_change_unix_ms: s.last_change_unix_ms,
            provider: s.provider,
            model: s.model,
            doing: s.doing,
            head_ask_summary: s.head_ask_summary,
            last_reply: s.last_reply,
            since_unix_ms: s.since_unix_ms,
            attached: s.attached,
            start_error: s.start_error,
            provider_session_id: s.provider_session_id,
            permission_mode: s.permission_mode,
            tab_id: s.tab_id,
        }
    }
}

/// The way back, field for field — for the one call that hands Dart's rows to
/// shared Rust: [`super::craze::craze_fold_plan`], whose rule
/// (`shed_app::craze_rows::fold_plan`) reads the contract's own row. Lossless:
/// every field is the contract's, mirrored as it stands.
impl From<BridgeLaneSession> for LaneSession {
    fn from(s: BridgeLaneSession) -> Self {
        LaneSession {
            id: s.id,
            title: s.title,
            cwd: s.cwd,
            activity: s.activity.into(),
            pending_approvals: s.pending_approvals,
            approximate: s.approximate,
            parent_id: s.parent_id,
            last_change_unix_ms: s.last_change_unix_ms,
            provider: s.provider,
            model: s.model,
            doing: s.doing,
            head_ask_summary: s.head_ask_summary,
            last_reply: s.last_reply,
            since_unix_ms: s.since_unix_ms,
            attached: s.attached,
            start_error: s.start_error,
            provider_session_id: s.provider_session_id,
            permission_mode: s.permission_mode,
            tab_id: s.tab_id,
        }
    }
}

// ---------------------------------------------------------------------------
// approvals
// ---------------------------------------------------------------------------

/// What KIND of thing is blocking on the human (mirrors
/// `lane::LaneApprovalKind`).
///
/// **Tolerant.** `Other { raw }` preserves an unrecognized wire kind verbatim —
/// the [`super::dto_rc::BridgeRcKind`] pattern — so an approval from a newer
/// agent renders neutrally (its raw kind shown, no kind-specific affordance)
/// rather than disappearing. A fielded enum → a Dart sealed class.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeLaneApprovalKind {
    Permission,
    Question,
    PlanApproval,
    McpElicitation,
    Other { raw: String },
}

impl From<LaneApprovalKind> for BridgeLaneApprovalKind {
    fn from(k: LaneApprovalKind) -> Self {
        match k {
            LaneApprovalKind::Permission => BridgeLaneApprovalKind::Permission,
            LaneApprovalKind::Question => BridgeLaneApprovalKind::Question,
            LaneApprovalKind::PlanApproval => BridgeLaneApprovalKind::PlanApproval,
            LaneApprovalKind::McpElicitation => BridgeLaneApprovalKind::McpElicitation,
            LaneApprovalKind::Other(raw) => BridgeLaneApprovalKind::Other { raw },
        }
    }
}

impl From<BridgeLaneApprovalKind> for LaneApprovalKind {
    fn from(k: BridgeLaneApprovalKind) -> Self {
        match k {
            BridgeLaneApprovalKind::Permission => LaneApprovalKind::Permission,
            BridgeLaneApprovalKind::Question => LaneApprovalKind::Question,
            BridgeLaneApprovalKind::PlanApproval => LaneApprovalKind::PlanApproval,
            BridgeLaneApprovalKind::McpElicitation => LaneApprovalKind::McpElicitation,
            BridgeLaneApprovalKind::Other { raw } => LaneApprovalKind::Other(raw),
        }
    }
}

/// Where an approval is in its life (mirrors `lane::LaneApprovalStatus`).
///
/// **Tolerant**, and it is the sharpest case of the rule: this value rides
/// INBOUND inside an approval, so a strict mirror would make one
/// `"status":"cancelled"` from a newer producer drop the whole approval — the
/// session still reading as blocked-on-you with no button to unblock it.
///
/// **Ask [`lane_status_is_pending`], never `!= Resolved`.** `Other` is
/// deliberately NOT pending; see that function.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeLaneApprovalStatus {
    Pending,
    Submitted,
    Resolved,
    Other { raw: String },
}

impl From<LaneApprovalStatus> for BridgeLaneApprovalStatus {
    fn from(s: LaneApprovalStatus) -> Self {
        match s {
            LaneApprovalStatus::Pending => BridgeLaneApprovalStatus::Pending,
            LaneApprovalStatus::Submitted => BridgeLaneApprovalStatus::Submitted,
            LaneApprovalStatus::Resolved => BridgeLaneApprovalStatus::Resolved,
            LaneApprovalStatus::Other(raw) => BridgeLaneApprovalStatus::Other { raw },
        }
    }
}

impl From<BridgeLaneApprovalStatus> for LaneApprovalStatus {
    fn from(s: BridgeLaneApprovalStatus) -> Self {
        match s {
            BridgeLaneApprovalStatus::Pending => LaneApprovalStatus::Pending,
            BridgeLaneApprovalStatus::Submitted => LaneApprovalStatus::Submitted,
            BridgeLaneApprovalStatus::Resolved => LaneApprovalStatus::Resolved,
            BridgeLaneApprovalStatus::Other { raw } => LaneApprovalStatus::Other(raw),
        }
    }
}

/// Whether this approval is still waiting on the human — **the only predicate a
/// client gates its answer affordance on**.
///
/// Exposed as a function rather than mirrored as a Dart `switch` because the
/// contract's answer for the case that matters is counter-intuitive:
/// [`BridgeLaneApprovalStatus::Other`] answers `false`. An unknown status is at
/// least as likely to be terminal (`cancelled`, `expired`) as live, so offering
/// buttons for it would post an answer the agent has stopped listening for. A
/// Dart re-derivation would very plausibly write `status != Resolved` and get
/// that backwards.
///
/// Sync: it is a `match` on a value Dart already holds.
#[frb(sync)]
pub fn lane_status_is_pending(status: BridgeLaneApprovalStatus) -> bool {
    LaneApprovalStatus::from(status).is_pending()
}

/// One selectable answer (mirrors `lane::LaneApprovalOption`).
///
/// **`id` is OPAQUE and `kind` is the semantics.** Round-trip the id; never
/// parse it. Anything that needs to know what an option MEANS reads `kind` — and
/// `kind` is a `String`, not an enum, because it is a stream value the contract
/// tolerates open: clients match the four known values
/// (`allow_once`/`allow_always`/`reject_once`/`reject_always`) and render
/// anything else as a plain button.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeLaneApprovalOption {
    pub id: String,
    pub label: String,
    pub description: Option<String>,
    pub kind: Option<String>,
}

impl From<LaneApprovalOption> for BridgeLaneApprovalOption {
    fn from(o: LaneApprovalOption) -> Self {
        BridgeLaneApprovalOption {
            id: o.id,
            label: o.label,
            description: o.description,
            kind: o.kind,
        }
    }
}

impl From<BridgeLaneApprovalOption> for LaneApprovalOption {
    fn from(o: BridgeLaneApprovalOption) -> Self {
        LaneApprovalOption {
            id: o.id,
            label: o.label,
            description: o.description,
            kind: o.kind,
        }
    }
}

/// A structured question inside an approval (mirrors `lane::LaneQuestion`).
///
/// `custom` permits free text, which travels back positionally in
/// [`BridgeLaneAnswer::Question::custom_text`]. The adapter REFUSES text aimed
/// at a question whose `custom` is false rather than dropping it, so a panel
/// gates the text field on this flag.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeLaneQuestion {
    /// The key this question's answer is filed under, when the agent files by
    /// key. gx sets it to the question's own TEXT; opencode files positionally
    /// and leaves it `None`. It is here so the key is VISIBLE, not so a client
    /// has to use it — answers stay positional and the adapter maps them.
    pub id: Option<String>,
    pub header: String,
    pub question: String,
    pub options: Vec<BridgeLaneApprovalOption>,
    pub multiple: bool,
    pub custom: bool,
}

impl From<LaneQuestion> for BridgeLaneQuestion {
    fn from(q: LaneQuestion) -> Self {
        BridgeLaneQuestion {
            id: q.id,
            header: q.header,
            question: q.question,
            options: q.options.into_iter().map(Into::into).collect(),
            multiple: q.multiple,
            custom: q.custom,
        }
    }
}

impl From<BridgeLaneQuestion> for LaneQuestion {
    fn from(q: BridgeLaneQuestion) -> Self {
        LaneQuestion {
            id: q.id,
            header: q.header,
            question: q.question,
            options: q.options.into_iter().map(Into::into).collect(),
            multiple: q.multiple,
            custom: q.custom,
        }
    }
}

/// One thing waiting on the human (mirrors `lane::LaneApproval`).
///
/// **Branch on `kind`, never on which list happens to be non-empty.** A
/// `Permission` puts the agent's offered options in `options` and leaves
/// `questions` empty; a `Question` puts the form in `questions` — each carrying
/// its OWN options and `custom` flag — and leaves `options` empty. Rendering the
/// wrong one yields an approval with no buttons.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeLaneApproval {
    pub id: String,
    /// The session this blocks. May be a DESCENDANT of the session the panel is
    /// open on — a child session's approval still blocks the parent's agent.
    pub session_id: String,
    pub kind: BridgeLaneApprovalKind,
    pub status: BridgeLaneApprovalStatus,
    pub title: String,
    pub detail: Option<String>,
    pub options: Vec<BridgeLaneApprovalOption>,
    pub questions: Vec<BridgeLaneQuestion>,
    /// The agent's own request payload, RAW JSON in a string (the FRB-mirror
    /// rule bars a `serde_json::Value`). It is what a client renders when `kind`
    /// is unknown, and the body [`BridgeLaneAnswer::Raw`] answers against.
    pub request_json: String,
    pub created_at_unix_ms: Option<i64>,
}

impl From<LaneApproval> for BridgeLaneApproval {
    fn from(a: LaneApproval) -> Self {
        BridgeLaneApproval {
            id: a.id,
            session_id: a.session_id,
            kind: a.kind.into(),
            status: a.status.into(),
            title: a.title,
            detail: a.detail,
            options: a.options.into_iter().map(Into::into).collect(),
            questions: a.questions.into_iter().map(Into::into).collect(),
            request_json: a.request_json,
            created_at_unix_ms: a.created_at_unix_ms,
        }
    }
}

impl From<BridgeLaneApproval> for LaneApproval {
    fn from(a: BridgeLaneApproval) -> Self {
        LaneApproval {
            id: a.id,
            session_id: a.session_id,
            kind: a.kind.into(),
            status: a.status.into(),
            title: a.title,
            detail: a.detail,
            options: a.options.into_iter().map(Into::into).collect(),
            questions: a.questions.into_iter().map(Into::into).collect(),
            request_json: a.request_json,
            created_at_unix_ms: a.created_at_unix_ms,
        }
    }
}

/// The offered option a [`BridgeLaneDecision`] selects — **by
/// [`BridgeLaneApprovalOption::kind`], never by id**.
///
/// This calls [`LaneApproval::option_for`], which is the contract's ONE
/// implementation of correction 3, so gx, opencode and this phone cannot each
/// re-derive the clauses differently. The clause that makes re-derivation a real
/// hazard: a live gx leader offers FIVE permission options of which TWO declare
/// `allow_once`, so an exact-kind match that is AMBIGUOUS answers `None` rather
/// than picking — under the original "first in offered order wins" rule a human
/// tapping "Allow once" would have silently turned prompting off for the whole
/// session. The `Reject` decision alone falls back to the first option whose
/// kind starts `reject`, because a refusal broader than asked for is safe in a
/// way a broader allow is not.
///
/// `None` is not an error: it means this decision cannot name an option on this
/// approval, and the panel should post [`BridgeLaneAnswer::Choice`] with the
/// exact offered id instead — which is unambiguous by construction and what a
/// capability-driven panel already does.
///
/// Sync, and it takes the approval BY VALUE: Dart is holding the approval from
/// its last snapshot, there is no lane to look it up on, and nothing here does
/// I/O.
#[frb(sync)]
pub fn lane_option_for(
    approval: BridgeLaneApproval,
    decision: BridgeLaneDecision,
) -> Option<BridgeLaneApprovalOption> {
    LaneApproval::from(approval)
        .option_for(decision.into())
        .cloned()
        .map(Into::into)
}

// ---------------------------------------------------------------------------
// answers — the strict half
// ---------------------------------------------------------------------------

/// The three SEMANTIC decisions a permission approval accepts, independent of
/// what the agent named its options (mirrors `lane::LaneDecision`).
///
/// **Strict**: a plain enum with no escape arm, because this is a
/// client→adapter COMMAND. The adapter resolves it through
/// [`lane_option_for`]'s rule and answers `bad_request` when nothing — or
/// several things — match.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeLaneDecision {
    AllowOnce,
    AllowAlways,
    Reject,
}

impl From<BridgeLaneDecision> for LaneDecision {
    fn from(d: BridgeLaneDecision) -> Self {
        match d {
            BridgeLaneDecision::AllowOnce => LaneDecision::AllowOnce,
            BridgeLaneDecision::AllowAlways => LaneDecision::AllowAlways,
            BridgeLaneDecision::Reject => LaneDecision::Reject,
        }
    }
}

impl From<LaneDecision> for BridgeLaneDecision {
    fn from(d: LaneDecision) -> Self {
        match d {
            LaneDecision::AllowOnce => BridgeLaneDecision::AllowOnce,
            LaneDecision::AllowAlways => BridgeLaneDecision::AllowAlways,
            LaneDecision::Reject => BridgeLaneDecision::Reject,
        }
    }
}

/// The answer to an approval (mirrors `lane::LaneAnswer`).
///
/// **Strict**, with no escape arm: an answer travels client→adapter, and an
/// unrecognized one is a command this build cannot honor. In a hand-mirrored
/// enum that strictness is structural — Dart has no way to spell a fifth case.
///
/// [`BridgeLaneAnswer::Question::answers`] is one inner list per question in
/// [`BridgeLaneApproval::questions`], each holding the option ids chosen for it
/// (one entry unless that question is `multiple`). Free text rides BESIDE it in
/// `custom_text`, positionally — never smuggled into `answers` as one more "id",
/// which is what left an adapter unable to tell a chosen label from something
/// typed.
///
/// `Choice` is the form a capability-driven panel sends: the exact offered id,
/// which is the only thing that can express a real agent's real menu.
/// `Permission` survives beside it as the semantic answer for a script or a
/// keyboard shortcut.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeLaneAnswer {
    Permission {
        decision: BridgeLaneDecision,
    },
    Choice {
        option_id: String,
    },
    Question {
        answers: Vec<Vec<String>>,
        /// Free text per question, positional like `answers`; `None` where the
        /// human typed nothing. Empty list = no free text anywhere.
        ///
        /// A `Vec<Option<String>>` — `List<String?>` in Dart — is the one
        /// genuinely awkward shape in this mirror, and it is load-bearing: a
        /// `None` and a `Some("")` are different answers, and flattening the
        /// hole would lose which question the text was for. The adapter refuses
        /// text aimed at a question whose `custom` is false, so a panel that
        /// gates its text field on [`BridgeLaneQuestion::custom`] never sends
        /// one that will be refused.
        custom_text: Vec<Option<String>>,
    },
    /// Decline the whole request — distinct from a permission's
    /// [`BridgeLaneDecision::Reject`], which is one option among three.
    Reject,
    /// A body the contract does not model, as raw JSON — the escape hatch for
    /// an unknown [`BridgeLaneApprovalKind`]. Note what it is NOT: an escape arm
    /// for an unknown ANSWER SHAPE. The four cases above are the whole
    /// vocabulary; this one carries a payload for a request kind, chosen
    /// deliberately by a client that read `request_json`.
    Raw {
        json: String,
    },
}

impl From<BridgeLaneAnswer> for LaneAnswer {
    fn from(a: BridgeLaneAnswer) -> Self {
        match a {
            BridgeLaneAnswer::Permission { decision } => LaneAnswer::Permission {
                decision: decision.into(),
            },
            BridgeLaneAnswer::Choice { option_id } => LaneAnswer::Choice { option_id },
            BridgeLaneAnswer::Question {
                answers,
                custom_text,
            } => LaneAnswer::Question {
                answers,
                custom_text,
            },
            BridgeLaneAnswer::Reject => LaneAnswer::Reject,
            BridgeLaneAnswer::Raw { json } => LaneAnswer::Raw { json },
        }
    }
}

impl From<LaneAnswer> for BridgeLaneAnswer {
    fn from(a: LaneAnswer) -> Self {
        match a {
            LaneAnswer::Permission { decision } => BridgeLaneAnswer::Permission {
                decision: decision.into(),
            },
            LaneAnswer::Choice { option_id } => BridgeLaneAnswer::Choice { option_id },
            LaneAnswer::Question {
                answers,
                custom_text,
            } => BridgeLaneAnswer::Question {
                answers,
                custom_text,
            },
            LaneAnswer::Reject => BridgeLaneAnswer::Reject,
            LaneAnswer::Raw { json } => BridgeLaneAnswer::Raw { json },
        }
    }
}

/// How a [`super::lane::lane_send`] is meant to land (mirrors `lane::SendMode`).
///
/// **Strict**, a plain enum: a send mode is a command, and degrading an unknown
/// one to a default would deliver the message with semantics the caller did not
/// ask for. Gate `Interject` on [`BridgeLaneCapabilities::interject`] — an
/// adapter that cannot do it answers `not_accepting`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeSendMode {
    /// "Accepted, and ordered after whatever is in flight." **Not a queue
    /// position** — the contract promises acceptance and ordering, nothing about
    /// where in a backlog the text sits.
    Queue,
    Interject,
}

impl From<BridgeSendMode> for SendMode {
    fn from(m: BridgeSendMode) -> Self {
        match m {
            BridgeSendMode::Queue => SendMode::Queue,
            BridgeSendMode::Interject => SendMode::Interject,
        }
    }
}

impl From<SendMode> for BridgeSendMode {
    fn from(m: SendMode) -> Self {
        match m {
            SendMode::Queue => BridgeSendMode::Queue,
            SendMode::Interject => BridgeSendMode::Interject,
        }
    }
}

// ---------------------------------------------------------------------------
// capabilities and the snapshot
// ---------------------------------------------------------------------------

/// What this SESSION can do, now (mirrors `lane::LaneCapabilities`) —
/// advertised, so the panel greys out an affordance instead of discovering the
/// refusal on a tap.
///
/// **Per session, and read from the snapshot, never cached at open** (plan 025
/// §3.2.1). Capabilities ride the lane's stream (`LaneEvent::Capabilities`, in
/// every seed before its `Ready` and again on change), so a craze session's can
/// change with its incarnation; [`BridgeLaneSnapshot::capabilities`] carries
/// the live generation's. opencode answers `{kind: "opencode", interject:
/// false, cancel: true, approvals: true, history_cursor: false, settings:
/// false, stop: false}` in every seed.
///
/// `create` left this type in plan 025 — creating is a machine-level act, and
/// it is [`BridgeSourceCapabilities::create`] now.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeLaneCapabilities {
    pub kind: String,
    pub interject: bool,
    pub cancel: bool,
    pub approvals: bool,
    /// The STREAM may resume from a cursor silently: a reconnect may leave no
    /// `Reset` behind, only a stale mark that a lone `Ready` clears. Since plan
    /// 025 it speaks for the stream alone — `history`'s cursor is advisory.
    /// Dart never counts brackets anyway (the fold is Rust's); it is here so a
    /// panel can know a "reconnecting…" banner may clear without a reseed.
    pub history_cursor: bool,
    /// The session has settings to show and change, and its snapshots carry
    /// [`BridgeLaneSnapshot::settings`].
    pub settings: bool,
    /// The session can be ended from this client (a Stop button).
    pub stop: bool,
}

impl From<LaneCapabilities> for BridgeLaneCapabilities {
    fn from(c: LaneCapabilities) -> Self {
        BridgeLaneCapabilities {
            kind: c.kind,
            interject: c.interject,
            cancel: c.cancel,
            approvals: c.approvals,
            history_cursor: c.history_cursor,
            settings: c.settings,
            stop: c.stop,
        }
    }
}

/// **The one thing Dart reads after a nudge** — a projection of
/// [`shed_app::lane_view::LaneViewSnapshot`], taken under ONE lock.
///
/// One value rather than two calls, because two reads would TEAR: a frame can
/// land between "give me the messages" and "give me the approvals", and the
/// panel would render a transcript and an approval set from different instants.
/// Reading it is also the NUDGE ACKNOWLEDGEMENT — it clears the dirty bit, which
/// is what makes a burst of a hundred frames one nudge rather than a hundred.
/// See [`super::lane::lane_snapshot`].
///
/// **`stale` is not `ended`** (plan 025 §3.2.4). `stale` is the banner: the
/// stream behind these rows is not live, for a reason. `ended` is the
/// lifecycle: the subscription ENDED, and it is the only thing Dart re-opens a
/// lane on. A silent resume sets `stale` and clears it again without ever
/// setting `ended`, and a client that re-opened on `stale` would throw away the
/// cursor that resume exists to keep.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeLaneSnapshot {
    /// Every row of the current generation, or just the rows after the cursor
    /// that was asked for. `full` says which.
    pub messages: Vec<BridgeRcFeedMessage>,
    /// `true` when `messages` is the WHOLE current generation and the reader
    /// should REPLACE what it holds; `false` when it is a delta to append.
    pub full: bool,
    pub activity: BridgeRcActivity,
    /// The session ROW as of the live generation — the stream's latest
    /// `Session`, `None` until a seed carrying one has completed. **This, not
    /// the row a lane was opened from, is the session's current state**: for a
    /// session opened the moment it was created, the open's row carries none
    /// of what the live stream says (its permission posture, plan 025 §3.6.5),
    /// so a header reads its facts from here once it is `Some`.
    pub session: Option<BridgeLaneSession>,
    /// The generation `messages` belong to — Rust's own counter, monotonic, and
    /// it moves only when a seed COMPLETES. A number that moved when one
    /// started would tell a client to discard the generation still on its
    /// screen.
    pub generation: u64,
    /// The banner: `Some(reason)` when the stream behind these rows is not live
    /// — the transport is gone and the adapter is retrying (a `Stale`), or the
    /// subscription ended (a `Down`). Cleared by the `Ready` that brings it
    /// back. **Not** a cue to re-open: see [`Self::ended`].
    pub stale: Option<String>,
    /// The lifecycle: `true` once the subscription ENDED (a `Down`), and only
    /// then. **"Ended, re-open me"** — the controller's cue to call
    /// [`super::lane::lane_open`] again (plan 018 §3.11), and the ONLY
    /// reconnect job Dart has: Rust owns every other retry, a silent resume
    /// included.
    pub ended: bool,
    /// What the session can do, as of the live generation — `None` until a
    /// seed carrying them has completed. A panel gates its affordances on this
    /// and on nothing it cached at open.
    pub capabilities: Option<BridgeLaneCapabilities>,
    /// The session's settings, as of the live generation; `None` when it has
    /// none to show (its capabilities say `settings: false`).
    pub settings: Option<BridgeLaneSettings>,
    /// The asks still waiting on the human, oldest first, id as the tiebreak.
    /// Pending only, by [`lane_status_is_pending`]'s rule.
    pub approvals: Vec<BridgeLaneApproval>,
}

impl BridgeLaneSnapshot {
    /// Project one [`LaneViewSnapshot`] — the fold's own output, so the phone
    /// and the desktop read the same truth.
    pub(crate) fn from_view(snap: LaneViewSnapshot) -> BridgeLaneSnapshot {
        BridgeLaneSnapshot {
            messages: snap.messages.into_iter().map(Into::into).collect(),
            full: snap.full,
            activity: snap.activity.into(),
            session: snap.session.map(Into::into),
            generation: snap.generation,
            stale: snap.stale,
            ended: snap.ended,
            capabilities: snap.capabilities.map(Into::into),
            settings: snap.settings.map(Into::into),
            approvals: snap.approvals.into_iter().map(Into::into).collect(),
        }
    }
}

// ---------------------------------------------------------------------------
// settings (the lane's half, plan 025 D7)
// ---------------------------------------------------------------------------

/// A session's settings, rendered generically (mirrors `lane::LaneSettings`):
/// the model and the models it can move to, the mode and the modes, the
/// model's own options, and how full its context is. Inbound.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeLaneSettings {
    /// The current model's id.
    pub model: Option<String>,
    /// The models a [`BridgeLaneSettingChange::Model`] can name, in the order a
    /// client shows them.
    pub models: Vec<BridgeLaneChoice>,
    /// The current mode's id.
    pub mode: Option<String>,
    pub modes: Vec<BridgeLaneChoice>,
    /// The current model's own options (an effort level, a fast mode, …).
    pub options: Vec<BridgeLaneSetting>,
    pub usage: Option<BridgeLaneUsage>,
}

impl From<LaneSettings> for BridgeLaneSettings {
    fn from(s: LaneSettings) -> Self {
        BridgeLaneSettings {
            model: s.model,
            models: s.models.into_iter().map(Into::into).collect(),
            mode: s.mode,
            modes: s.modes.into_iter().map(Into::into).collect(),
            options: s.options.into_iter().map(Into::into).collect(),
            usage: s.usage.map(Into::into),
        }
    }
}

/// One selectable value — a model, a mode, or one option's value (mirrors
/// `lane::LaneChoice`). `id` is opaque and round-tripped into a
/// [`BridgeLaneSettingChange`]; `name` is what a client shows.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeLaneChoice {
    pub id: String,
    pub name: String,
    /// The agent's own ordering hint, when it gives one (lower first).
    pub rank: Option<u32>,
    pub description: Option<String>,
}

impl From<LaneChoice> for BridgeLaneChoice {
    fn from(c: LaneChoice) -> Self {
        BridgeLaneChoice {
            id: c.id,
            name: c.name,
            rank: c.rank,
            description: c.description,
        }
    }
}

/// One of a model's options (mirrors `lane::LaneSetting`). `current` and each
/// value are strings, and `category` an open string, exactly as the contract
/// has them.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeLaneSetting {
    /// What [`BridgeLaneSettingChange::Config`]'s `id` names.
    pub id: String,
    pub name: String,
    pub category: String,
    pub current: String,
    pub values: Vec<BridgeLaneChoice>,
}

impl From<LaneSetting> for BridgeLaneSetting {
    fn from(s: LaneSetting) -> Self {
        BridgeLaneSetting {
            id: s.id,
            name: s.name,
            category: s.category,
            current: s.current,
            values: s.values.into_iter().map(Into::into).collect(),
        }
    }
}

/// How full the session's context is, when the agent says (mirrors
/// `lane::LaneUsage`). `u64`s, so Dart `BigInt`s.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeLaneUsage {
    pub context_tokens: Option<u64>,
    pub context_window: Option<u64>,
}

impl From<LaneUsage> for BridgeLaneUsage {
    fn from(u: LaneUsage) -> Self {
        BridgeLaneUsage {
            context_tokens: u.context_tokens,
            context_window: u.context_window,
        }
    }
}

/// One change to a session's settings (mirrors `lane::LaneSettingChange`) —
/// what the settings sheet sends (CM6).
///
/// **Strict**, with no escape arm: a change this build cannot name is a
/// command it cannot honour. `Config`, not `Option`, as the contract spells it.
///
/// `for_model` on `Config` is the model the client DISPLAYED the option for
/// (plan 025 Amendment A13): an adapter binds the change to it, so a session
/// that has already left that model refuses the change instead of applying an
/// option chosen for one model to another. `None` lets the adapter bind the
/// model its own fold shows.
#[frb(unignore)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeLaneSettingChange {
    /// Move to the model with this [`BridgeLaneChoice::id`].
    Model { id: String },
    /// Move to the mode with this [`BridgeLaneChoice::id`].
    Mode { id: String },
    /// Set the option [`BridgeLaneSetting::id`] to the value
    /// [`BridgeLaneChoice::id`].
    Config {
        id: String,
        value: String,
        for_model: Option<String>,
    },
}

impl From<BridgeLaneSettingChange> for LaneSettingChange {
    fn from(c: BridgeLaneSettingChange) -> Self {
        match c {
            BridgeLaneSettingChange::Model { id } => LaneSettingChange::Model { id },
            BridgeLaneSettingChange::Mode { id } => LaneSettingChange::Mode { id },
            BridgeLaneSettingChange::Config {
                id,
                value,
                for_model,
            } => LaneSettingChange::Config {
                id,
                value,
                for_model,
            },
        }
    }
}

impl From<LaneSettingChange> for BridgeLaneSettingChange {
    fn from(c: LaneSettingChange) -> Self {
        match c {
            LaneSettingChange::Model { id } => BridgeLaneSettingChange::Model { id },
            LaneSettingChange::Mode { id } => BridgeLaneSettingChange::Mode { id },
            LaneSettingChange::Config {
                id,
                value,
                for_model,
            } => BridgeLaneSettingChange::Config {
                id,
                value,
                for_model,
            },
        }
    }
}

// ---------------------------------------------------------------------------
// sources and creating (the machine's half, plan 025 D3/D5/D6)
// ---------------------------------------------------------------------------

/// What a source can do (mirrors `lane::SourceCapabilities`) — the
/// machine-level half of the capabilities: whether a create, and its options,
/// will be honoured on THIS source. A client hides the create sheet on a source
/// that says no rather than discovering the refusal on a tap.
#[frb(unignore)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSourceCapabilities {
    /// The same agent token [`BridgeLaneCapabilities::kind`] carries.
    pub kind: String,
    pub create: bool,
    pub create_options: bool,
}

impl From<SourceCapabilities> for BridgeSourceCapabilities {
    fn from(c: SourceCapabilities) -> Self {
        BridgeSourceCapabilities {
            kind: c.kind,
            create: c.create,
            create_options: c.create_options,
        }
    }
}

/// Why a source is offline (mirrors `lane::SourceOffline`).
///
/// **Tolerant**: `Other { raw }` preserves an unrecognized cause verbatim. What
/// each cause MEANS is the UI's to decide (`shed_core::lane`'s module doc,
/// "Sources"): `NotInstalled` is quiet — the machine simply has no such agent —
/// while `TooOld` asks the person to update it there.
#[frb(unignore)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeSourceOffline {
    NotInstalled,
    TooOld,
    Unreachable,
    Failed,
    Other { raw: String },
}

impl From<SourceOffline> for BridgeSourceOffline {
    fn from(o: SourceOffline) -> Self {
        match o {
            SourceOffline::NotInstalled => BridgeSourceOffline::NotInstalled,
            SourceOffline::TooOld => BridgeSourceOffline::TooOld,
            SourceOffline::Unreachable => BridgeSourceOffline::Unreachable,
            SourceOffline::Failed => BridgeSourceOffline::Failed,
            SourceOffline::Other(raw) => BridgeSourceOffline::Other { raw },
        }
    }
}

impl From<BridgeSourceOffline> for SourceOffline {
    fn from(o: BridgeSourceOffline) -> Self {
        match o {
            BridgeSourceOffline::NotInstalled => SourceOffline::NotInstalled,
            BridgeSourceOffline::TooOld => SourceOffline::TooOld,
            BridgeSourceOffline::Unreachable => SourceOffline::Unreachable,
            BridgeSourceOffline::Failed => SourceOffline::Failed,
            BridgeSourceOffline::Other { raw } => SourceOffline::Other(raw),
        }
    }
}

/// What a create can start on a machine (mirrors `lane::LaneCreateOptions`):
/// the providers and whether each can start, the default, and the directories
/// sessions last ran in. Providers keep the agent's own order (plan 025 D5: a
/// provider that cannot start is dimmed, not hidden).
#[frb(unignore)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeLaneCreateOptions {
    pub providers: Vec<BridgeLaneProvider>,
    /// May name a provider that is not listed or not ready — a client
    /// preselects it only when it is listed AND `Ready`.
    pub default_provider: Option<String>,
    /// Newest first.
    pub recent_dirs: Vec<String>,
}

impl From<LaneCreateOptions> for BridgeLaneCreateOptions {
    fn from(o: LaneCreateOptions) -> Self {
        BridgeLaneCreateOptions {
            providers: o.providers.into_iter().map(Into::into).collect(),
            default_provider: o.default_provider,
            recent_dirs: o.recent_dirs,
        }
    }
}

/// One provider a create can name (mirrors `lane::LaneProvider`).
#[frb(unignore)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeLaneProvider {
    /// What [`BridgeLaneCreateRequest::provider`] takes.
    pub id: String,
    pub label: String,
    pub state: BridgeLaneProviderState,
    /// Why it cannot start — present exactly when `state` is not `Ready`.
    pub reason: Option<String>,
    /// What to do about it, one line.
    pub fix: Option<String>,
}

impl From<LaneProvider> for BridgeLaneProvider {
    fn from(p: LaneProvider) -> Self {
        BridgeLaneProvider {
            id: p.id,
            label: p.label,
            state: p.state.into(),
            reason: p.reason,
            fix: p.fix,
        }
    }
}

/// Whether a provider can start here (mirrors `lane::LaneProviderState`).
///
/// **Tolerant**: `Other { raw }` preserves an unrecognized state, and a client
/// treats it as not ready — it cannot know the state permits a start.
#[frb(unignore)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeLaneProviderState {
    Ready,
    NeedsSetup,
    Unavailable,
    Other { raw: String },
}

impl From<LaneProviderState> for BridgeLaneProviderState {
    fn from(s: LaneProviderState) -> Self {
        match s {
            LaneProviderState::Ready => BridgeLaneProviderState::Ready,
            LaneProviderState::NeedsSetup => BridgeLaneProviderState::NeedsSetup,
            LaneProviderState::Unavailable => BridgeLaneProviderState::Unavailable,
            LaneProviderState::Other(raw) => BridgeLaneProviderState::Other { raw },
        }
    }
}

impl From<BridgeLaneProviderState> for LaneProviderState {
    fn from(s: BridgeLaneProviderState) -> Self {
        match s {
            BridgeLaneProviderState::Ready => LaneProviderState::Ready,
            BridgeLaneProviderState::NeedsSetup => LaneProviderState::NeedsSetup,
            BridgeLaneProviderState::Unavailable => LaneProviderState::Unavailable,
            BridgeLaneProviderState::Other { raw } => LaneProviderState::Other(raw),
        }
    }
}

/// A create, as the phone asks for it (mirrors `lane::LaneCreateRequest`) — a
/// provider, a directory and an optional first prompt, nothing else (plan 025
/// D6).
///
/// **Strict**: a plain struct with exactly the contract's fields, so Dart
/// cannot attach one the adapter would have to drop. `request_id` is reused
/// ONLY while the outcome of the create that carried it is unknown, and minted
/// fresh after any definite answer (plan 025 §3.8).
#[frb(unignore)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeLaneCreateRequest {
    /// Absolute, and existing on the machine.
    pub cwd: String,
    /// A [`BridgeLaneProvider::id`]; `None` for the agent's own default.
    pub provider: Option<String>,
    /// The first prompt; `None` creates an idle session.
    pub prompt: Option<String>,
    pub request_id: String,
}

impl From<BridgeLaneCreateRequest> for LaneCreateRequest {
    fn from(r: BridgeLaneCreateRequest) -> Self {
        LaneCreateRequest {
            cwd: r.cwd,
            provider: r.provider,
            prompt: r.prompt,
            request_id: r.request_id,
        }
    }
}

impl From<LaneCreateRequest> for BridgeLaneCreateRequest {
    fn from(r: LaneCreateRequest) -> Self {
        BridgeLaneCreateRequest {
            cwd: r.cwd,
            provider: r.provider,
            prompt: r.prompt,
            request_id: r.request_id,
        }
    }
}

/// What a create answered (mirrors `lane::LaneCreated`): the new session's row
/// and what became of its first prompt. The session exists whenever this is
/// returned — a refused or lost prompt is not a failed create.
#[frb(unignore)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeLaneCreated {
    pub session: BridgeLaneSession,
    pub prompt: BridgeLanePromptOutcome,
    /// Why the prompt was refused, or why its answer was lost.
    pub prompt_error: Option<String>,
}

impl From<LaneCreated> for BridgeLaneCreated {
    fn from(c: LaneCreated) -> Self {
        BridgeLaneCreated {
            session: c.session.into(),
            prompt: c.prompt.into(),
            prompt_error: c.prompt_error,
        }
    }
}

/// What became of a create's first prompt (mirrors `lane::LanePromptOutcome`).
///
/// **Tolerant**: `Other { raw }` preserves an unrecognized outcome. `Unknown`
/// is a KNOWN outcome — the prompt was sent and its answer was lost, so the
/// session may be working on it — and is not the escape arm.
#[frb(unignore)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeLanePromptOutcome {
    None,
    Accepted,
    Unknown,
    Refused,
    Other { raw: String },
}

impl From<LanePromptOutcome> for BridgeLanePromptOutcome {
    fn from(o: LanePromptOutcome) -> Self {
        match o {
            LanePromptOutcome::None => BridgeLanePromptOutcome::None,
            LanePromptOutcome::Accepted => BridgeLanePromptOutcome::Accepted,
            LanePromptOutcome::Unknown => BridgeLanePromptOutcome::Unknown,
            LanePromptOutcome::Refused => BridgeLanePromptOutcome::Refused,
            LanePromptOutcome::Other(raw) => BridgeLanePromptOutcome::Other { raw },
        }
    }
}

impl From<BridgeLanePromptOutcome> for LanePromptOutcome {
    fn from(o: BridgeLanePromptOutcome) -> Self {
        match o {
            BridgeLanePromptOutcome::None => LanePromptOutcome::None,
            BridgeLanePromptOutcome::Accepted => LanePromptOutcome::Accepted,
            BridgeLanePromptOutcome::Unknown => LanePromptOutcome::Unknown,
            BridgeLanePromptOutcome::Refused => LanePromptOutcome::Refused,
            BridgeLanePromptOutcome::Other { raw } => LanePromptOutcome::Other(raw),
        }
    }
}

// ---------------------------------------------------------------------------
// errors
// ---------------------------------------------------------------------------

/// What a lane op can fail with — one case per [`LaneError`] variant, plus the
/// two failures the contract has no variant for because they are not the
/// adapter's.
///
/// A **sealed enum**, the [`super::error::BridgeError`] shape rather than
/// `roost.rs`'s `Result<_, String>`, because the controller BRANCHES on it:
/// `UnknownSession`/`UnknownApproval`/`Already*` are "your view is stale,
/// refetch", `Unauthorized` and `NotAccepting` are "that affordance should not
/// have been offered", `Unavailable` is QUIET (render stale, keep the row), and
/// `Failed` is the loud residue. A string would make every one of those a
/// substring test.
///
/// Strict, like the contract's own: an error code this build does not know is
/// [`BridgeLaneError::Failed`]'s job, carried as text by whoever mapped the
/// wire.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeLaneError {
    /// The agent demanded a credential this build cannot supply.
    Unauthorized,
    /// The agent rejected the request and said why — ITS message, kept whole.
    BadRequest { msg: String },
    UnknownSession,
    UnknownApproval,
    /// An answer is already in flight (the optimistic `Submitted` state). A
    /// double-tap, not an error to surface loudly.
    AlreadySubmitted,
    AlreadyResolved,
    NotAccepting,
    /// Nothing to talk to: the agent is not running, the dial was refused, the
    /// tunnel is down. **Quiet** — render an unreachable row with this reason,
    /// not an error dialog. The string names what was tried.
    Unavailable { msg: String },
    /// Anything else that went wrong on the wire, kept whole.
    Failed { msg: String },
    /// There is no lane here: this handle is closed, or the row carries no
    /// stamp. Carries a message because the two cases read differently to a
    /// user, and neither is the adapter's.
    NoLane { msg: String },
    /// The row DOES carry a lane and this build has no adapter for its kind.
    ///
    /// Distinct from [`BridgeLaneError::NoLane`] on purpose: `NoLane` is a
    /// permanent property of the row and a client renders no affordance for it,
    /// while this one means "there IS something here and I cannot speak to it" —
    /// which a NEWER build may well be able to. `AgentLaneStamp`'s doc makes
    /// refusing by name the client's obligation for exactly that reason.
    UnsupportedLane { kind: String },
}

impl From<LaneError> for BridgeLaneError {
    fn from(e: LaneError) -> Self {
        match e {
            LaneError::Unauthorized => BridgeLaneError::Unauthorized,
            LaneError::BadRequest(msg) => BridgeLaneError::BadRequest { msg },
            LaneError::UnknownSession => BridgeLaneError::UnknownSession,
            LaneError::UnknownApproval => BridgeLaneError::UnknownApproval,
            LaneError::AlreadySubmitted => BridgeLaneError::AlreadySubmitted,
            LaneError::AlreadyResolved => BridgeLaneError::AlreadyResolved,
            LaneError::NotAccepting => BridgeLaneError::NotAccepting,
            LaneError::Unavailable(msg) => BridgeLaneError::Unavailable { msg },
            LaneError::Failed(msg) => BridgeLaneError::Failed { msg },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    use shed_core::lane::option_kind;
    use shed_core::rc::{RcActivity, RcFeedMessage};

    /// Every `LaneApprovalKind` the wire can produce, plus an unrecognized one.
    fn kind_cases() -> Vec<LaneApprovalKind> {
        vec![
            LaneApprovalKind::Permission,
            LaneApprovalKind::Question,
            LaneApprovalKind::PlanApproval,
            LaneApprovalKind::McpElicitation,
            LaneApprovalKind::Other("elicitation_v9".to_string()),
        ]
    }

    fn status_cases() -> Vec<LaneApprovalStatus> {
        vec![
            LaneApprovalStatus::Pending,
            LaneApprovalStatus::Submitted,
            LaneApprovalStatus::Resolved,
            LaneApprovalStatus::Other("cancelled".to_string()),
        ]
    }

    fn option(id: &str, kind: Option<&str>) -> LaneApprovalOption {
        LaneApprovalOption {
            id: id.to_string(),
            label: format!("label for {id}"),
            description: Some(format!("why {id}")),
            kind: kind.map(str::to_string),
        }
    }

    fn approval(options: Vec<LaneApprovalOption>) -> LaneApproval {
        LaneApproval {
            id: "per_1".to_string(),
            session_id: "ses_a".to_string(),
            kind: LaneApprovalKind::Permission,
            status: LaneApprovalStatus::Pending,
            title: "run id -un".to_string(),
            detail: Some("in /home/shed".to_string()),
            options,
            questions: Vec::new(),
            request_json: r#"{"tool":"bash"}"#.to_string(),
            created_at_unix_ms: Some(1_700_000_000_000),
        }
    }

    /// **The tolerant half.** Every wire-producible kind and status survives the
    /// round trip, and an unrecognized value survives WITH ITS RAW STRING — the
    /// property that makes an approval from a newer agent render neutrally
    /// instead of vanishing.
    #[test]
    fn tolerant_enums_round_trip_and_preserve_an_unknown_value() {
        for original in kind_cases() {
            let bridged: BridgeLaneApprovalKind = original.clone().into();
            let back: LaneApprovalKind = bridged.clone().into();
            assert_eq!(back, original, "kind lost its identity on the round trip");
            // Negative control: the raw string must be CARRIED, not dropped or
            // coerced into a known arm.
            if let LaneApprovalKind::Other(raw) = &original {
                assert_eq!(
                    bridged,
                    BridgeLaneApprovalKind::Other { raw: raw.clone() },
                    "an unknown kind must cross as Other{{raw}}, verbatim"
                );
                assert_eq!(back.as_str(), raw, "the raw wire string was rewritten");
            }
        }

        for original in status_cases() {
            let bridged: BridgeLaneApprovalStatus = original.clone().into();
            let back: LaneApprovalStatus = bridged.clone().into();
            assert_eq!(back, original, "status lost its identity on the round trip");
            if let LaneApprovalStatus::Other(raw) = &original {
                assert_eq!(
                    bridged,
                    BridgeLaneApprovalStatus::Other { raw: raw.clone() },
                    "an unknown status must cross as Other{{raw}}, verbatim"
                );
            }
        }
    }

    /// `is_pending` is exposed rather than re-derived because its answer for
    /// `Other` is the counter-intuitive one. This is the assertion a Dart
    /// `status != resolved` would fail.
    #[test]
    fn only_pending_is_pending_and_an_unknown_status_is_not() {
        assert!(lane_status_is_pending(BridgeLaneApprovalStatus::Pending));
        assert!(!lane_status_is_pending(BridgeLaneApprovalStatus::Submitted));
        assert!(!lane_status_is_pending(BridgeLaneApprovalStatus::Resolved));
        assert!(
            !lane_status_is_pending(BridgeLaneApprovalStatus::Other {
                raw: "cancelled".to_string()
            }),
            "an unknown status must NOT offer an answer affordance: it is at \
             least as likely to be terminal as live"
        );
    }

    /// The whole approval — nested options, nested questions, an unknown kind
    /// and an unknown status all at once — survives both directions.
    #[test]
    fn an_approval_round_trips_whole() {
        let original = LaneApproval {
            kind: LaneApprovalKind::Other("mcp_elicitation_v2".to_string()),
            status: LaneApprovalStatus::Other("expired".to_string()),
            options: vec![
                option("allow-once", Some(option_kind::ALLOW_ONCE)),
                option("numbered-4", None),
            ],
            questions: vec![LaneQuestion {
                id: Some("Which branch?".to_string()),
                header: "branch".to_string(),
                question: "Which branch?".to_string(),
                options: vec![option("main", None), option("dev", None)],
                multiple: true,
                custom: true,
            }],
            ..approval(Vec::new())
        };
        let bridged: BridgeLaneApproval = original.clone().into();
        assert_eq!(LaneApproval::from(bridged), original);
    }

    /// **The strict half, as a table.** Every outbound value round-trips, and the
    /// strictness is STRUCTURAL: these enums have no escape arm, so the
    /// exhaustive matches in the `From` impls are the compiler's proof that Dart
    /// cannot spell a value the adapter would have to refuse.
    #[test]
    fn strict_commands_round_trip_with_no_escape_arm() {
        for original in [
            LaneDecision::AllowOnce,
            LaneDecision::AllowAlways,
            LaneDecision::Reject,
        ] {
            let bridged: BridgeLaneDecision = original.into();
            assert_eq!(LaneDecision::from(bridged), original);
        }
        for original in [SendMode::Queue, SendMode::Interject] {
            let bridged: BridgeSendMode = original.into();
            assert_eq!(SendMode::from(bridged), original);
        }
        for original in [
            LaneAnswer::Permission {
                decision: LaneDecision::AllowAlways,
            },
            LaneAnswer::Choice {
                option_id: "enable-always-approve".to_string(),
            },
            LaneAnswer::Question {
                answers: vec![vec!["yes".to_string()], Vec::new()],
                custom_text: vec![None, Some("  because I said so  ".to_string())],
            },
            LaneAnswer::Reject,
            LaneAnswer::Raw {
                json: r#"{"outcome":"weird"}"#.to_string(),
            },
        ] {
            let bridged: BridgeLaneAnswer = original.clone().into();
            assert_eq!(LaneAnswer::from(bridged), original);
        }
    }

    /// `custom_text` is the shape most likely to be quietly flattened on the way
    /// across, and the hole is the payload: a `None` at position 0 with a `Some`
    /// at position 1 says "the text is for question TWO". Asserted on the
    /// mirror itself so a future edit that zips the two vectors fails here.
    #[test]
    fn positional_free_text_keeps_its_holes() {
        let bridged = BridgeLaneAnswer::Question {
            answers: vec![vec!["a".to_string()]],
            custom_text: vec![None, Some(String::new()), Some("third".to_string())],
        };
        let LaneAnswer::Question {
            answers,
            custom_text,
        } = LaneAnswer::from(bridged)
        else {
            panic!("a Question answer must cross as a Question answer");
        };
        assert_eq!(answers, vec![vec!["a".to_string()]]);
        assert_eq!(
            custom_text,
            vec![None, Some(String::new()), Some("third".to_string())],
            "an empty string and a hole are different answers"
        );
    }

    /// [`lane_option_for`] must mirror the contract's BEHAVIOUR, ambiguity
    /// refusal and `Reject` fallback included — the two clauses a Dart
    /// re-derivation would get wrong.
    ///
    /// The five-option table is the real one, read off a live gx leader.
    #[test]
    fn option_for_matches_the_contracts_own_rule() {
        let real_gx = approval(vec![
            option("enable-always-approve", Some(option_kind::ALLOW_ONCE)),
            option("allow-always-command", Some(option_kind::ALLOW_ALWAYS)),
            option("allow-once", Some(option_kind::ALLOW_ONCE)),
            option("reject-once", Some(option_kind::REJECT_ONCE)),
            option("reject-always-command", Some(option_kind::REJECT_ALWAYS)),
        ]);
        let bridged: BridgeLaneApproval = real_gx.clone().into();

        // TWO options declare allow_once, so the decision cannot say which the
        // human meant. Refusing is the whole point of correction 3: under
        // "first in offered order wins" this would have selected
        // `enable-always-approve` and turned prompting off for the session.
        assert!(
            lane_option_for(bridged.clone(), BridgeLaneDecision::AllowOnce).is_none(),
            "an AMBIGUOUS allow_once must refuse, not pick"
        );
        assert_eq!(
            lane_option_for(bridged.clone(), BridgeLaneDecision::AllowAlways).map(|o| o.id),
            Some("allow-always-command".to_string())
        );
        assert_eq!(
            lane_option_for(bridged, BridgeLaneDecision::Reject).map(|o| o.id),
            Some("reject-once".to_string())
        );

        // The `Reject`-only fallback: no `reject_once` at all, so the first
        // option whose kind starts `reject` is still refusable.
        let only_reject_always: BridgeLaneApproval = approval(vec![
            option("allow-once", Some(option_kind::ALLOW_ONCE)),
            option("nope", Some(option_kind::REJECT_ALWAYS)),
        ])
        .into();
        assert_eq!(
            lane_option_for(only_reject_always.clone(), BridgeLaneDecision::Reject).map(|o| o.id),
            Some("nope".to_string()),
            "an agent offering only reject_always must still be refusable"
        );
        // Negative control for the asymmetry: there is NO matching fallback for
        // the allow decisions. Upgrading an "allow once" into an "allow always"
        // is precisely the bug the contract exists to prevent.
        assert!(
            lane_option_for(only_reject_always, BridgeLaneDecision::AllowAlways).is_none(),
            "an allow decision must never fall back to a broader allow"
        );

        // An option with NO kind never matches: an absent kind means "this
        // agent states no semantics", and guessing one from the id is the
        // id-sniffing option_for exists to replace.
        let kindless: BridgeLaneApproval = approval(vec![option("p-1", None)]).into();
        assert!(lane_option_for(kindless.clone(), BridgeLaneDecision::AllowOnce).is_none());
        assert!(lane_option_for(kindless, BridgeLaneDecision::Reject).is_none());
    }

    /// A session row with EVERY field set, each to a value no other field of
    /// its type shares — so a mapping that swapped two same-typed fields, or
    /// dropped one to its default, cannot pass.
    fn full_session() -> LaneSession {
        LaneSession {
            id: "ses_a".to_string(),
            title: "fix the thing".to_string(),
            cwd: "/home/shed/proj".to_string(),
            activity: RcActivity::NeedsApproval,
            pending_approvals: 3,
            approximate: true,
            parent_id: Some("ses_root".to_string()),
            last_change_unix_ms: Some(42),
            provider: Some("cursor".to_string()),
            model: Some("composer-2".to_string()),
            doing: Some("reading main.go".to_string()),
            head_ask_summary: Some("run go test?".to_string()),
            last_reply: Some("done: 3 files".to_string()),
            since_unix_ms: Some(43),
            attached: Some(2),
            start_error: Some("no API key".to_string()),
            provider_session_id: Some("prov-77".to_string()),
            permission_mode: Some("bypass".to_string()),
            tab_id: Some(9),
        }
    }

    /// The session row, the capabilities row and the stamp are flat mirrors;
    /// this pins the field-for-field mapping so a reordered struct literal
    /// cannot swap two same-typed fields silently.
    #[test]
    fn the_flat_rows_map_field_for_field() {
        let session = full_session();
        let bridged: BridgeLaneSession = session.clone().into();
        assert_eq!(bridged.id, session.id);
        assert_eq!(bridged.title, session.title);
        assert_eq!(bridged.cwd, session.cwd);
        assert_eq!(bridged.activity, BridgeRcActivity::NeedsApproval);
        assert_eq!(bridged.pending_approvals, 3);
        assert!(bridged.approximate);
        assert_eq!(bridged.parent_id.as_deref(), Some("ses_root"));
        assert_eq!(bridged.last_change_unix_ms, Some(42));
        // Plan 025's row facts — every one of them, because a craze row that
        // lost one would render a session with no model, no ask summary or no
        // permission posture, and nothing would say a field was dropped.
        assert_eq!(bridged.provider.as_deref(), Some("cursor"));
        assert_eq!(bridged.model.as_deref(), Some("composer-2"));
        assert_eq!(bridged.doing.as_deref(), Some("reading main.go"));
        assert_eq!(bridged.head_ask_summary.as_deref(), Some("run go test?"));
        assert_eq!(bridged.last_reply.as_deref(), Some("done: 3 files"));
        assert_eq!(bridged.since_unix_ms, Some(43));
        assert_eq!(bridged.attached, Some(2));
        assert_eq!(bridged.start_error.as_deref(), Some("no API key"));
        assert_eq!(bridged.provider_session_id.as_deref(), Some("prov-77"));
        assert_eq!(bridged.permission_mode.as_deref(), Some("bypass"));
        assert_eq!(bridged.tab_id, Some(9));
        // And an opencode-shaped row — none of them known — crosses with every
        // one `None`, not with a default invented on the way.
        let bare: BridgeLaneSession = LaneSession {
            id: "ses_b".to_string(),
            ..LaneSession::default()
        }
        .into();
        assert_eq!(bare.provider, None);
        assert_eq!(bare.permission_mode, None);
        assert_eq!(bare.attached, None);
        assert_eq!(bare.tab_id, None);

        // Each flag set to the opposite of its neighbour, so a swap shows.
        let caps: BridgeLaneCapabilities = LaneCapabilities {
            kind: "craze".to_string(),
            interject: true,
            cancel: false,
            approvals: true,
            history_cursor: false,
            settings: true,
            stop: false,
        }
        .into();
        assert_eq!(
            caps,
            BridgeLaneCapabilities {
                kind: "craze".to_string(),
                interject: true,
                cancel: false,
                approvals: true,
                history_cursor: false,
                settings: true,
                stop: false,
            }
        );
        let flipped: BridgeLaneCapabilities = LaneCapabilities {
            kind: "opencode".to_string(),
            interject: false,
            cancel: true,
            approvals: false,
            history_cursor: true,
            settings: false,
            stop: true,
        }
        .into();
        assert!(!flipped.interject && flipped.cancel && !flipped.approvals);
        assert!(flipped.history_cursor && !flipped.settings && flipped.stop);

        let stamp: BridgeAgentLaneStamp = AgentLaneStamp {
            kind: "opencode".to_string(),
            session_id: "ses_a".to_string(),
            server_url: "http://127.0.0.1:4096".to_string(),
        }
        .into();
        assert_eq!(stamp.kind, "opencode");
        assert_eq!(stamp.session_id, "ses_a");
        assert_eq!(stamp.server_url, "http://127.0.0.1:4096");
    }

    /// Every [`LaneError`] variant gets its own case — the property the
    /// controller's `switch` depends on. An exhaustive match on the way in is
    /// the compiler's half; this is the half that proves no two variants
    /// collapse onto one case.
    #[test]
    fn every_lane_error_variant_has_its_own_case() {
        let mapped: Vec<BridgeLaneError> = vec![
            LaneError::Unauthorized,
            LaneError::BadRequest("no such option".to_string()),
            LaneError::UnknownSession,
            LaneError::UnknownApproval,
            LaneError::AlreadySubmitted,
            LaneError::AlreadyResolved,
            LaneError::NotAccepting,
            LaneError::Unavailable("gx on mini3".to_string()),
            LaneError::Failed("503 from something".to_string()),
        ]
        .into_iter()
        .map(BridgeLaneError::from)
        .collect();

        assert_eq!(
            mapped,
            vec![
                BridgeLaneError::Unauthorized,
                BridgeLaneError::BadRequest {
                    msg: "no such option".to_string()
                },
                BridgeLaneError::UnknownSession,
                BridgeLaneError::UnknownApproval,
                BridgeLaneError::AlreadySubmitted,
                BridgeLaneError::AlreadyResolved,
                BridgeLaneError::NotAccepting,
                BridgeLaneError::Unavailable {
                    msg: "gx on mini3".to_string()
                },
                BridgeLaneError::Failed {
                    msg: "503 from something".to_string()
                },
            ]
        );
        // Negative control: nine inputs, nine DISTINCT outputs. A mapping that
        // folded two variants together would pass the vec comparison above only
        // if it were also rewritten, so count distinctness separately.
        let mut seen = mapped.clone();
        seen.dedup();
        assert_eq!(seen.len(), 9, "two LaneError variants collapsed onto one");
    }

    fn choice(id: &str) -> LaneChoice {
        LaneChoice {
            id: id.to_string(),
            name: format!("name of {id}"),
            rank: Some(id.len() as u32),
            description: Some(format!("about {id}")),
        }
    }

    fn settings() -> LaneSettings {
        LaneSettings {
            model: Some("m-fast".to_string()),
            models: vec![choice("m-fast"), choice("m-deep")],
            mode: Some("plan".to_string()),
            modes: vec![choice("plan"), choice("agent")],
            options: vec![LaneSetting {
                id: "effort".to_string(),
                name: "Effort".to_string(),
                category: "thought_level".to_string(),
                current: "high".to_string(),
                values: vec![choice("low"), choice("high")],
            }],
            usage: Some(LaneUsage {
                context_tokens: Some(12_000),
                context_window: Some(200_000),
            }),
        }
    }

    /// **The snapshot is a projection of the fold's own output and nothing
    /// else** — every field of it, plan 025's four included.
    ///
    /// `stale` and `ended` are set to DIFFERENT answers on purpose (a stale
    /// view that has not ended — a silent resume in progress): a projection
    /// that derived one from the other would fail here, and that derivation is
    /// exactly the bug the split exists to stop — a client that re-opened on
    /// `stale` would throw away the cursor the resume is using.
    #[test]
    fn the_snapshot_projects_the_folds_output() {
        let view = LaneViewSnapshot {
            messages: vec![RcFeedMessage {
                seq: 7,
                role: "assistant".to_string(),
                msg_type: "text".to_string(),
                text: Some("hi".to_string()),
                ..RcFeedMessage::default()
            }],
            full: false,
            activity: RcActivity::Working,
            session: Some(full_session()),
            generation: 3,
            stale: Some("reconnecting".to_string()),
            ended: false,
            capabilities: Some(LaneCapabilities {
                kind: "craze".to_string(),
                interject: true,
                cancel: true,
                approvals: true,
                history_cursor: true,
                settings: true,
                stop: true,
            }),
            settings: Some(settings()),
            approvals: vec![approval(vec![option("allow-once", None)])],
        };
        let snap = BridgeLaneSnapshot::from_view(view);
        assert_eq!(snap.messages.len(), 1);
        assert_eq!(snap.messages[0].seq, 7);
        assert_eq!(snap.messages[0].text.as_deref(), Some("hi"));
        assert!(!snap.full);
        assert_eq!(snap.activity, BridgeRcActivity::Working);
        assert_eq!(snap.generation, 3);
        assert_eq!(snap.stale.as_deref(), Some("reconnecting"));
        assert!(
            !snap.ended,
            "a stale view that has not ended must not read as ended"
        );
        assert_eq!(snap.session, Some(full_session().into()));
        let caps = snap.capabilities.expect("the live capabilities cross");
        assert_eq!(caps.kind, "craze");
        assert!(caps.settings && caps.stop);
        assert_eq!(snap.settings, Some(settings().into()));
        assert_eq!(snap.approvals.len(), 1);
        assert_eq!(snap.approvals[0].id, "per_1");

        // The other half: an ENDED view, with nothing seeded yet — no row, no
        // capabilities, no settings — crosses as exactly that, not as a
        // default row or an all-false capabilities record a panel would
        // render as "can do nothing".
        let ended = BridgeLaneSnapshot::from_view(LaneViewSnapshot {
            messages: Vec::new(),
            full: true,
            activity: RcActivity::Unknown,
            session: None,
            generation: 0,
            stale: Some("unknown_session".to_string()),
            ended: true,
            capabilities: None,
            settings: None,
            approvals: Vec::new(),
        });
        assert!(ended.ended);
        assert_eq!(ended.stale.as_deref(), Some("unknown_session"));
        assert_eq!(ended.session, None);
        assert_eq!(ended.capabilities, None);
        assert_eq!(ended.settings, None);
    }

    /// The settings tree maps whole: the current model and mode, every choice
    /// in order with its rank and description, the option with its own values,
    /// and the usage `u64`s.
    #[test]
    fn settings_map_field_for_field() {
        let bridged: BridgeLaneSettings = settings().into();
        assert_eq!(bridged.model.as_deref(), Some("m-fast"));
        assert_eq!(
            bridged
                .models
                .iter()
                .map(|c| c.id.as_str())
                .collect::<Vec<_>>(),
            ["m-fast", "m-deep"],
            "the agent's order is the display order"
        );
        assert_eq!(bridged.models[1].name, "name of m-deep");
        assert_eq!(bridged.models[1].rank, Some(6));
        assert_eq!(
            bridged.models[1].description.as_deref(),
            Some("about m-deep")
        );
        assert_eq!(bridged.mode.as_deref(), Some("plan"));
        assert_eq!(bridged.modes[1].id, "agent");
        let effort = &bridged.options[0];
        assert_eq!(effort.id, "effort");
        assert_eq!(effort.name, "Effort");
        assert_eq!(effort.category, "thought_level");
        assert_eq!(effort.current, "high");
        assert_eq!(effort.values[0].id, "low");
        assert_eq!(
            bridged.usage,
            Some(BridgeLaneUsage {
                context_tokens: Some(12_000),
                context_window: Some(200_000),
            })
        );
        // Nothing to show is nothing, not a fabricated empty usage.
        let empty: BridgeLaneSettings = LaneSettings::default().into();
        assert_eq!(empty.model, None);
        assert!(empty.models.is_empty() && empty.options.is_empty());
        assert_eq!(empty.usage, None);
    }

    /// **plan 025's three tolerant enums, the approval kinds' rule**: every
    /// wire-producible value survives the round trip, and an unrecognized one
    /// crosses as `Other { raw }` with its string verbatim — so an outage
    /// cause, a provider state or a prompt outcome from a newer agent renders
    /// neutrally instead of failing the value it rides in.
    #[test]
    fn plan_025s_tolerant_enums_round_trip_and_preserve_an_unknown_value() {
        for original in [
            SourceOffline::NotInstalled,
            SourceOffline::TooOld,
            SourceOffline::Unreachable,
            SourceOffline::Failed,
            SourceOffline::Other("rate_limited".to_string()),
        ] {
            let bridged: BridgeSourceOffline = original.clone().into();
            assert_eq!(SourceOffline::from(bridged.clone()), original);
            if let SourceOffline::Other(raw) = &original {
                assert_eq!(bridged, BridgeSourceOffline::Other { raw: raw.clone() });
            }
        }
        // The two causes the UI branches on must not collapse onto each other
        // or onto the neutral arm: `NotInstalled` is quiet, `TooOld` asks for
        // an update.
        assert_eq!(
            BridgeSourceOffline::from(SourceOffline::from_wire("too_old")),
            BridgeSourceOffline::TooOld
        );
        assert_eq!(
            BridgeSourceOffline::from(SourceOffline::from_wire("not_installed")),
            BridgeSourceOffline::NotInstalled
        );

        for original in [
            LaneProviderState::Ready,
            LaneProviderState::NeedsSetup,
            LaneProviderState::Unavailable,
            LaneProviderState::Other("quota".to_string()),
        ] {
            let bridged: BridgeLaneProviderState = original.clone().into();
            assert_eq!(LaneProviderState::from(bridged.clone()), original);
            if let LaneProviderState::Other(raw) = &original {
                assert_eq!(bridged, BridgeLaneProviderState::Other { raw: raw.clone() });
            }
        }

        for original in [
            LanePromptOutcome::None,
            LanePromptOutcome::Accepted,
            LanePromptOutcome::Unknown,
            LanePromptOutcome::Refused,
            LanePromptOutcome::Other("deferred".to_string()),
        ] {
            let bridged: BridgeLanePromptOutcome = original.clone().into();
            assert_eq!(LanePromptOutcome::from(bridged.clone()), original);
            if let LanePromptOutcome::Other(raw) = &original {
                assert_eq!(bridged, BridgeLanePromptOutcome::Other { raw: raw.clone() });
            }
        }
        // `Unknown` is a KNOWN outcome (the answer was lost), never the escape
        // arm — a client that read it as "unrecognized" would drop the retry
        // the create sheet offers for exactly that case.
        assert_eq!(
            BridgeLanePromptOutcome::from(LanePromptOutcome::from_wire("unknown")),
            BridgeLanePromptOutcome::Unknown
        );
    }

    /// **plan 025's two strict commands**: a setting change (all three kinds,
    /// and `Config` both with and without the model it was displayed for —
    /// Amendment A13) and a create request round-trip exactly, field for field.
    #[test]
    fn plan_025s_strict_commands_round_trip() {
        for original in [
            LaneSettingChange::Model {
                id: "m-deep".to_string(),
            },
            LaneSettingChange::Mode {
                id: "plan".to_string(),
            },
            LaneSettingChange::Config {
                id: "effort".to_string(),
                value: "high".to_string(),
                for_model: Some("m-fast".to_string()),
            },
            LaneSettingChange::Config {
                id: "effort".to_string(),
                value: "low".to_string(),
                for_model: None,
            },
        ] {
            let bridged: BridgeLaneSettingChange = original.clone().into();
            assert_eq!(LaneSettingChange::from(bridged), original);
        }
        // The displayed model reaches the contract — the guard A13 exists for
        // cannot fire on a value the mirror dropped.
        let sent = LaneSettingChange::from(BridgeLaneSettingChange::Config {
            id: "effort".to_string(),
            value: "high".to_string(),
            for_model: Some("m-fast".to_string()),
        });
        assert_eq!(
            serde_json::to_value(&sent).expect("a change serializes"),
            serde_json::json!({
                "kind": "config", "id": "effort", "value": "high", "for_model": "m-fast"
            })
        );

        for original in [
            LaneCreateRequest {
                cwd: "/home/shed/proj".to_string(),
                provider: Some("cursor".to_string()),
                prompt: Some("fix the build".to_string()),
                request_id: "req-1".to_string(),
            },
            LaneCreateRequest {
                cwd: "/home/shed".to_string(),
                provider: None,
                prompt: None,
                request_id: "req-2".to_string(),
            },
        ] {
            let bridged: BridgeLaneCreateRequest = original.clone().into();
            assert_eq!(LaneCreateRequest::from(bridged), original);
        }
    }

    /// The source half maps whole: the source's capabilities, the create
    /// options in the agent's own order (a provider that cannot start keeps its
    /// place, its reason and its fix), and a create's answer with its row.
    #[test]
    fn the_source_half_maps_field_for_field() {
        let caps: BridgeSourceCapabilities = SourceCapabilities {
            kind: "craze".to_string(),
            create: true,
            create_options: false,
        }
        .into();
        assert_eq!(
            caps,
            BridgeSourceCapabilities {
                kind: "craze".to_string(),
                create: true,
                create_options: false,
            }
        );

        let options: BridgeLaneCreateOptions = LaneCreateOptions {
            providers: vec![
                LaneProvider {
                    id: "native".to_string(),
                    label: "Native".to_string(),
                    state: LaneProviderState::Ready,
                    reason: None,
                    fix: None,
                },
                LaneProvider {
                    id: "cursor".to_string(),
                    label: "Cursor".to_string(),
                    state: LaneProviderState::NeedsSetup,
                    reason: Some("not logged in".to_string()),
                    fix: Some("run cursor-agent login".to_string()),
                },
            ],
            default_provider: Some("cursor".to_string()),
            recent_dirs: vec!["/home/shed/b".to_string(), "/home/shed/a".to_string()],
        }
        .into();
        assert_eq!(
            options
                .providers
                .iter()
                .map(|p| p.id.as_str())
                .collect::<Vec<_>>(),
            ["native", "cursor"],
            "a provider that cannot start is dimmed, not dropped or reordered"
        );
        let cursor = &options.providers[1];
        assert_eq!(cursor.label, "Cursor");
        assert_eq!(cursor.state, BridgeLaneProviderState::NeedsSetup);
        assert_eq!(cursor.reason.as_deref(), Some("not logged in"));
        assert_eq!(cursor.fix.as_deref(), Some("run cursor-agent login"));
        assert_eq!(options.default_provider.as_deref(), Some("cursor"));
        assert_eq!(options.recent_dirs, ["/home/shed/b", "/home/shed/a"]);

        let created: BridgeLaneCreated = LaneCreated {
            session: full_session(),
            prompt: LanePromptOutcome::Refused,
            prompt_error: Some("busy".to_string()),
        }
        .into();
        assert_eq!(created.session, full_session().into());
        assert_eq!(created.prompt, BridgeLanePromptOutcome::Refused);
        assert_eq!(created.prompt_error.as_deref(), Some("busy"));
    }
}
