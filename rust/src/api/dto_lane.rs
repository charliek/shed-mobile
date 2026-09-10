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
//! * **Tolerant, inbound**: [`BridgeLaneApprovalKind`] and
//!   [`BridgeLaneApprovalStatus`] carry `Other { raw }` and preserve the raw wire
//!   string verbatim, exactly as [`super::dto_rc::BridgeRcKind`] does. An
//!   approval minted by a newer agent renders neutrally instead of vanishing.
//! * **Strict, outbound**: [`BridgeLaneDecision`], [`BridgeSendMode`] and
//!   [`BridgeLaneAnswer`] have NO escape arm at all. Dart cannot construct an
//!   unrecognized decision, mode or answer — the mirror of "serde refuses it" is
//!   "the type does not admit it", which is a stronger guarantee than a runtime
//!   refusal and is what keeps a user's "allow" from becoming a silent no-op.
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
//! # What is NOT here
//!
//! [`shed_core::lane::LaneEvent`] does not cross. It is folded in Rust by
//! [`shed_app::lane_view::LaneView`] and `Reset`/`Ready`/`Down`/`Unknown` never
//! reach Dart at all — the phone gets a nudge and pulls one atomic
//! [`BridgeLaneSnapshot`]. `LaneHistory` does not cross either: no phone verb
//! needs a page of transcript that is not already in the view.
//! `LaneSubscription`/`LaneStop` are handles, and handles stay in
//! [`super::lane`].

use flutter_rust_bridge::frb;
use shed_app::lane_view::LaneViewSnapshot;
use shed_core::lane::{
    LaneAnswer, LaneApproval, LaneApprovalKind, LaneApprovalOption, LaneApprovalStatus,
    LaneCapabilities, LaneDecision, LaneError, LaneQuestion, LaneSession, SendMode,
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
/// two are never conflated: a gx discovery record is matched against THIS one.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAgentLaneStamp {
    /// The adapter token — `"opencode"` or `"gx"` today. A kind this build has
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
/// `#[frb(unignore)]` because **no `pub` bridge function takes or returns one
/// yet**, and the codegen prunes an unreferenced type. It is mirrored anyway
/// because it is part of the contract §3.9 pins, and because the reason nothing
/// returns one is a property of the FOLD, not a decision about the row:
/// `shed_app::lane_view::LaneViewSnapshot` projects only the session's
/// `activity`, so the phone's snapshot has nowhere to carry the rest. Marking it
/// keeps the Dart mirror complete for the row-level verbs that follow instead of
/// making the next slice a codegen change as well as a feature.
#[frb(unignore)]
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

/// What this adapter can actually do (mirrors `lane::LaneCapabilities`) —
/// advertised, so the panel greys out an affordance instead of discovering the
/// refusal on a tap.
///
/// opencode answers
/// `{kind: "opencode", interject: false, create: true, cancel: true, approvals: true, history_cursor: false}`;
/// gx answers the same with `interject` and `history_cursor` true. Those are
/// exactly the two flags a UI branches on, which is why the flags exist.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeLaneCapabilities {
    pub kind: String,
    pub interject: bool,
    pub create: bool,
    pub cancel: bool,
    pub approvals: bool,
    /// The adapter honors a history cursor — and therefore a **silent resume**
    /// is possible on its stream: a reconnect may leave no trace at all. It is
    /// why Dart must not count brackets to count connections; it never sees them
    /// anyway (the fold is Rust's).
    pub history_cursor: bool,
}

impl From<LaneCapabilities> for BridgeLaneCapabilities {
    fn from(c: LaneCapabilities) -> Self {
        BridgeLaneCapabilities {
            kind: c.kind,
            interject: c.interject,
            create: c.create,
            cancel: c.cancel,
            approvals: c.approvals,
            history_cursor: c.history_cursor,
        }
    }
}

/// **The one thing Dart reads after a nudge** — a projection of
/// [`shed_app::lane_view::LaneViewSnapshot`] plus the two bridge-level flags,
/// taken under ONE lock.
///
/// One value rather than two calls, because two reads would TEAR: a frame can
/// land between "give me the messages" and "give me the approvals", and the
/// panel would render a transcript and an approval set from different instants.
/// Reading it is also the NUDGE ACKNOWLEDGEMENT — it clears the dirty bit, which
/// is what makes a burst of a hundred frames one nudge rather than a hundred.
/// See [`super::lane::lane_snapshot`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeLaneSnapshot {
    /// Every row of the current generation, or just the rows after the cursor
    /// that was asked for. `full` says which.
    pub messages: Vec<BridgeRcFeedMessage>,
    /// `true` when `messages` is the WHOLE current generation and the reader
    /// should REPLACE what it holds; `false` when it is a delta to append.
    pub full: bool,
    pub activity: BridgeRcActivity,
    /// The generation `messages` belong to — Rust's own counter, monotonic, and
    /// it moves only when a seed COMPLETES. A number that moved when one
    /// started would tell a client to discard the generation still on its
    /// screen.
    pub generation: u64,
    /// `Some(reason)` when the transport is gone and these rows are the last
    /// complete generation. **"Stale, re-open me"** — the controller's cue to
    /// call [`super::lane::lane_open`] again (plan 018 §3.11), and the ONLY
    /// reconnect job Dart has: Rust owns every other retry.
    pub stale: Option<String>,
    /// The asks still waiting on the human, oldest first, id as the tiebreak.
    /// Pending only, by [`lane_status_is_pending`]'s rule.
    pub approvals: Vec<BridgeLaneApproval>,
    /// **The gx credential ask.** `true` when a leader restarted mid-pin and the
    /// adapter needs a FRESH discovery to continue: the controller re-runs
    /// [`super::lane::gx_probe_remote_command`] over the machine's SSH client
    /// and hands the bytes to
    /// [`super::lane::lane_refresh_credentials`]. Pinning then resumes in place
    /// — no `Down`, no re-open, generation and ring intact.
    pub needs_credentials: bool,
}

impl BridgeLaneSnapshot {
    /// Project one [`LaneViewSnapshot`] — the fold's own output, so the phone
    /// and the desktop read the same truth — with the bridge flag stamped on.
    pub(crate) fn from_view(snap: LaneViewSnapshot, needs_credentials: bool) -> BridgeLaneSnapshot {
        BridgeLaneSnapshot {
            messages: snap.messages.into_iter().map(Into::into).collect(),
            full: snap.full,
            activity: snap.activity.into(),
            generation: snap.generation,
            stale: snap.stale,
            approvals: snap.approvals.into_iter().map(Into::into).collect(),
            needs_credentials,
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

    /// The session row, the capabilities row and the stamp are flat mirrors;
    /// this pins the field-for-field mapping so a reordered struct literal
    /// cannot swap two same-typed fields silently.
    #[test]
    fn the_flat_rows_map_field_for_field() {
        let session = LaneSession {
            id: "ses_a".to_string(),
            title: "fix the thing".to_string(),
            cwd: "/home/shed/proj".to_string(),
            activity: RcActivity::NeedsApproval,
            pending_approvals: 3,
            approximate: true,
            parent_id: Some("ses_root".to_string()),
            last_change_unix_ms: Some(42),
        };
        let bridged: BridgeLaneSession = session.clone().into();
        assert_eq!(bridged.id, session.id);
        assert_eq!(bridged.title, session.title);
        assert_eq!(bridged.cwd, session.cwd);
        assert_eq!(bridged.activity, BridgeRcActivity::NeedsApproval);
        assert_eq!(bridged.pending_approvals, 3);
        assert!(bridged.approximate);
        assert_eq!(bridged.parent_id.as_deref(), Some("ses_root"));
        assert_eq!(bridged.last_change_unix_ms, Some(42));

        let caps: BridgeLaneCapabilities = LaneCapabilities {
            kind: "gx".to_string(),
            interject: true,
            create: true,
            cancel: true,
            approvals: true,
            history_cursor: true,
        }
        .into();
        assert_eq!(caps.kind, "gx");
        assert!(caps.interject && caps.create && caps.cancel && caps.approvals);
        assert!(caps.history_cursor);

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

    /// The snapshot is a projection of the fold's own output and nothing else —
    /// the bridge adds exactly one field.
    #[test]
    fn the_snapshot_projects_the_folds_output_and_one_flag() {
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
            generation: 3,
            stale: Some("unknown_session".to_string()),
            approvals: vec![approval(vec![option("allow-once", None)])],
        };
        let snap = BridgeLaneSnapshot::from_view(view, true);
        assert_eq!(snap.messages.len(), 1);
        assert_eq!(snap.messages[0].seq, 7);
        assert_eq!(snap.messages[0].text.as_deref(), Some("hi"));
        assert!(!snap.full);
        assert_eq!(snap.activity, BridgeRcActivity::Working);
        assert_eq!(snap.generation, 3);
        assert_eq!(snap.stale.as_deref(), Some("unknown_session"));
        assert_eq!(snap.approvals.len(), 1);
        assert_eq!(snap.approvals[0].id, "per_1");
        assert!(snap.needs_credentials);
    }
}
