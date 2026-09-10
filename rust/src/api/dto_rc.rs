//! Bridge-owned rc-domain DTOs (plan §3.6): the enriched session model, the
//! capabilities cluster, the feed page, and the rc-event variants — each mapped
//! from its `shed_core::rc` / `shed_core::rc_events` source.
//!
//! FRB 2.13 renders the fielded enums here — [`BridgeRcKind`] (its `Other(String)`
//! arm) and [`BridgeRcEvent`] (five data-carrying variants) — as Dart 3 **sealed
//! classes**, so the app switches on them exhaustively. The plain enums
//! ([`BridgeRcState`], [`BridgeRcActivity`]) render as plain Dart enums.

use std::collections::HashMap;

use shed_core::rc::{
    RcActivity, RcAgentInfo, RcCapabilities, RcFeedMessage, RcKind, RcKindFeatures, RcMessagesPage,
    RcSession, RcSessionDto, RcState,
};
use shed_core::rc_events::RcEvent;
use shed_core::roost::RoostSession;

/// The kind of agent a session runs (mirrors `rc::RcKind`, unknown-kind policy
/// preserved via `Other`). A fielded enum → a Dart sealed class.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeRcKind {
    ClaudeRc,
    ClaudeBroker,
    Codex,
    Opencode,
    Cursor,
    /// grok's `gx` agent **with a remote lane bound** — the row shed promotes
    /// once a roost tab's `gx.remote` metadata key appears (plan 017). roost
    /// never says `gx`; its adapter reports `source: "grok"` either way.
    Gx,
    /// grok's `gx` agent with **no** lane: status through roost, no transcript.
    /// Lane-less by design, not a degraded `Gx`.
    Grok,
    Shell,
    /// An unrecognized wire kind, raw string preserved.
    Other { raw: String },
}

impl From<RcKind> for BridgeRcKind {
    fn from(k: RcKind) -> Self {
        match k {
            RcKind::ClaudeRc => BridgeRcKind::ClaudeRc,
            RcKind::ClaudeBroker => BridgeRcKind::ClaudeBroker,
            RcKind::Codex => BridgeRcKind::Codex,
            RcKind::Opencode => BridgeRcKind::Opencode,
            RcKind::Cursor => BridgeRcKind::Cursor,
            RcKind::Gx => BridgeRcKind::Gx,
            RcKind::Grok => BridgeRcKind::Grok,
            RcKind::Shell => BridgeRcKind::Shell,
            RcKind::Other(raw) => BridgeRcKind::Other { raw },
        }
    }
}

/// A pane-derived lifecycle state (mirrors `rc::RcState`). Plain enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeRcState {
    Starting,
    Ready,
    Reconnecting,
    NeedsTrust,
    NeedsAuth,
    Dead,
}

impl From<RcState> for BridgeRcState {
    fn from(s: RcState) -> Self {
        match s {
            RcState::Starting => BridgeRcState::Starting,
            RcState::Ready => BridgeRcState::Ready,
            RcState::Reconnecting => BridgeRcState::Reconnecting,
            RcState::NeedsTrust => BridgeRcState::NeedsTrust,
            RcState::NeedsAuth => BridgeRcState::NeedsAuth,
            RcState::Dead => BridgeRcState::Dead,
        }
    }
}

/// A session's live work dimension (mirrors `rc::RcActivity`). Plain enum;
/// an unknown wire token folds to `Unknown` (no `Other` arm, by design).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeRcActivity {
    Working,
    NeedsInput,
    /// The session is blocked on an approval (contract v2). Distinct from
    /// `NeedsInput`: the agent is not waiting for a prompt, it is waiting for a
    /// DECISION — and whether the phone can make that decision depends on the
    /// kind's `approvals` capability (`remote` = steerable here, `tui` =
    /// informational, open the TUI). Rendering must key on `kind_features`,
    /// never on the kind.
    NeedsApproval,
    Idle,
    Unknown,
}

impl From<RcActivity> for BridgeRcActivity {
    fn from(a: RcActivity) -> Self {
        match a {
            RcActivity::Working => BridgeRcActivity::Working,
            RcActivity::NeedsInput => BridgeRcActivity::NeedsInput,
            RcActivity::NeedsApproval => BridgeRcActivity::NeedsApproval,
            RcActivity::Idle => BridgeRcActivity::Idle,
            RcActivity::Unknown => BridgeRcActivity::Unknown,
        }
    }
}

/// One agent's install-probe result (mirrors `rc::RcAgentInfo`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRcAgentInfo {
    pub installed: bool,
    pub version: Option<String>,
}

impl From<RcAgentInfo> for BridgeRcAgentInfo {
    fn from(a: RcAgentInfo) -> Self {
        BridgeRcAgentInfo {
            installed: a.installed,
            version: a.version,
        }
    }
}

/// Per-kind UI hints (mirrors `rc::RcKindFeatures`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRcKindFeatures {
    pub post_input: bool,
    /// `"remote"` = the hub can RESOLVE an approval from here; `"tui"` = the
    /// rows are informational and the decision must be made in the session's
    /// terminal; `"none"` = there is no approval surface a shed client can
    /// reach at all (every roost kind, which answers approvals inside its own
    /// tab). A client that offers an approve button for a `"tui"` kind produces
    /// a `409 not_supported` the user cannot act on — this field is the whole
    /// reason the contract carries capabilities. Branch on `== "remote"`; the
    /// other two are equally "don't offer it".
    pub approvals: String,
    pub watch: bool,
    /// `"turn"` = accepts a structured turn; `"gated"`/`"line"` = keystrokes
    /// only.
    pub input: String,
    /// contract v2: which feed this kind carries — `"messages"` (a normalized
    /// message feed), `"activity"` (an activity dimension and no message feed:
    /// every roost kind), or `"none"` (no signal at all: the guest hub's codex
    /// and cursor rows). Empty means the producer predates v2.
    ///
    /// It describes the MESSAGE feed only. No client gates its activity chip on
    /// it — the chip reads the row's own `activity` — which is why the same two
    /// kinds answer `"none"` through the guest hub and `"activity"` through
    /// roost.
    pub feed: String,
    /// contract v2: whether a running turn can be interrupted.
    pub interrupt: bool,
    /// contract v2: how the session is attachable — `"tmux"` (attach a pane) or
    /// `"native-remote"` (the terminal belongs to roost; a client reaches it
    /// with its own affordance, here the read-only `tab.dump` peek, or not at
    /// all). Empty means pre-v2, which means `"tmux"`.
    pub attach: String,
}

impl From<RcKindFeatures> for BridgeRcKindFeatures {
    fn from(f: RcKindFeatures) -> Self {
        BridgeRcKindFeatures {
            post_input: f.post_input,
            approvals: f.approvals,
            watch: f.watch,
            input: f.input,
            feed: f.feed,
            interrupt: f.interrupt,
            attach: f.attach,
        }
    }
}

/// The `capabilities` payload (mirrors `rc::RcCapabilities`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRcCapabilities {
    pub rc_version: i64,
    pub kinds: Vec<BridgeRcKind>,
    pub agents: HashMap<String, BridgeRcAgentInfo>,
    pub features: Vec<String>,
    pub kind_features: HashMap<String, BridgeRcKindFeatures>,
}

impl From<RcCapabilities> for BridgeRcCapabilities {
    fn from(c: RcCapabilities) -> Self {
        BridgeRcCapabilities {
            rc_version: c.rc_version,
            kinds: c.kinds.into_iter().map(Into::into).collect(),
            agents: c.agents.into_iter().map(|(k, v)| (k, v.into())).collect(),
            features: c.features,
            kind_features: c
                .kind_features
                .into_iter()
                .map(|(k, v)| (k, v.into()))
                .collect(),
        }
    }
}

/// The enriched session the app renders (mirrors `rc::RcSession`).
///
/// **No `tmux_session`** (plan 013 S3m). It was the pane handle the terminal
/// attached to, and roost owns the terminal now: a roost row has no tmux session
/// to name, and the attach affordance is gated on `kind_features.attach`
/// (`native-remote` → the read-only `tab.dump` peek) rather than on the presence
/// of a tmux name. The field still exists on the WIRE — `shed-ext-rc list` emits
/// it unconditionally and shed-core's `RcSessionDto` still parses it — it simply
/// stops crossing into Dart.
///
/// The two roost-only fields ([`attention`](Self::attention),
/// [`tab_id`](Self::tab_id)) do not exist on `RcSessionDto` and are stamped here
/// instead: the shared wire DTO gains no field for roost (plan 013 §3.2), so the
/// ~11 struct-literal sites and the Go↔Rust parity goldens stay untouched.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRcSession {
    pub host: String,
    pub shed: String,
    pub slug: String,
    pub display_name: String,
    pub workdir: Option<String>,
    pub kind: BridgeRcKind,
    pub state: BridgeRcState,
    pub url: Option<String>,
    pub rc_id: Option<String>,
    pub created_by: Option<String>,
    pub created_at: Option<String>,
    pub target_label: Option<String>,
    pub activity: Option<BridgeRcActivity>,
    pub activity_at: Option<String>,
    pub last_message: Option<String>,
    pub managed: bool,
    /// roost's `has_notification`, for a roost-sourced row; `false` for every
    /// shed row.
    ///
    /// **Sticky, and therefore its own affordance** — roost clears it on UI
    /// focus or an explicit `tab.clear_notification`, and shed never clears it.
    /// It is an attention *dot* on the card, NOT an activity state: folding it
    /// into "needs you" would leave a card asking for attention long after the
    /// thing that asked for it was dealt with.
    pub attention: bool,
    /// roost's tab id, for a roost-sourced row; `None` for every shed row.
    ///
    /// The handle `tab.close` / `tab.dump` address the tab by. It is also the
    /// row's [`slug`](Self::slug) rendered as a string — carried separately and
    /// typed so a caller never has to parse one back out.
    pub tab_id: Option<i64>,
}

impl From<RcSession> for BridgeRcSession {
    /// The SHED path: `attention` and `tab_id` are absent, because a
    /// `shed-ext-rc` row has neither. A roost row goes through
    /// [`BridgeRcSession::from_roost`], which stamps both.
    fn from(s: RcSession) -> Self {
        BridgeRcSession {
            host: s.host,
            shed: s.shed,
            slug: s.slug,
            display_name: s.display_name,
            workdir: s.workdir,
            kind: s.kind.into(),
            state: s.state.into(),
            url: s.url,
            rc_id: s.rc_id,
            created_by: s.created_by,
            created_at: s.created_at,
            target_label: s.target_label,
            activity: s.activity.map(Into::into),
            activity_at: s.activity_at,
            last_message: s.last_message,
            managed: s.managed,
            attention: false,
            tab_id: None,
        }
    }
}

impl BridgeRcSession {
    /// The ROOST path: one agent-owned roost tab, as the card the app already
    /// renders.
    ///
    /// The body of the row comes from [`RoostSession::to_rc_dto`] — the ONE
    /// mapping, in `shed-core`, that every shed client shares — so a roost row
    /// and a shed row differ in where they came from and in nothing else.
    /// `attention` and `tab_id` are then stamped from the `RoostSession`,
    /// because they have no place on the shared DTO.
    pub(crate) fn from_roost(session: &RoostSession) -> BridgeRcSession {
        BridgeRcSession::from_roost_dto(session, session.to_rc_dto())
    }

    /// [`from_roost`](Self::from_roost) with the DTO supplied, for the one
    /// caller that must adjust a cell before enrichment (`roost_tab_open`, which
    /// substitutes the kind it just launched — see its doc).
    pub(crate) fn from_roost_dto(session: &RoostSession, dto: RcSessionDto) -> BridgeRcSession {
        // Empty host AND empty shed, exactly as the retired machine path did: a
        // roost row belongs to no shed and no shed-server, and Dart keys and
        // labels it by the MACHINE's own `origin` (`machine:<name>`), which it
        // already holds. Putting the machine name in `host` here would invent a
        // second, divergent identity for the same row.
        let mut row = BridgeRcSession::from(RcSession::from_dto(dto, "", ""));
        row.attention = session.attention;
        row.tab_id = Some(session.tab_id);
        row
    }
}

/// The neutral `shed-ext-rc list` row (mirrors `rc::RcSessionDto`). Distinct
/// from [`BridgeRcSession`] — this is the pre-enrichment binary output the Dart
/// runner captures then hands back to the bridge decoder.
///
/// `tmux_session` is dropped here for the same reason it is dropped from
/// [`BridgeRcSession`] (plan 013 S3m): the wire still carries it and shed-core
/// still parses it, it simply stops crossing into Dart.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRcSessionDto {
    pub slug: String,
    pub kind: BridgeRcKind,
    pub state: BridgeRcState,
    pub managed: bool,
    pub display_name: Option<String>,
    pub workdir: Option<String>,
    pub url: Option<String>,
    pub id: Option<String>,
    pub created_by: Option<String>,
    pub created_at: Option<String>,
    pub target_label: Option<String>,
    pub activity: Option<BridgeRcActivity>,
    pub activity_at: Option<String>,
    pub last_message: Option<String>,
}

impl From<RcSessionDto> for BridgeRcSessionDto {
    fn from(d: RcSessionDto) -> Self {
        BridgeRcSessionDto {
            slug: d.slug,
            kind: d.kind.into(),
            state: d.state.into(),
            managed: d.managed,
            display_name: d.display_name,
            workdir: d.workdir,
            url: d.url,
            id: d.id,
            created_by: d.created_by,
            created_at: d.created_at,
            target_label: d.target_label,
            activity: d.activity.map(Into::into),
            activity_at: d.activity_at,
            last_message: d.last_message,
        }
    }
}

/// A feed message's tool block (mirrors `rc::RcFeedTool`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRcFeedTool {
    pub name: Option<String>,
    pub detail: Option<String>,
}

/// One normalized feed message (mirrors `rc::RcFeedMessage`). `seq` is `u64`
/// (an FRB numeric edge — it marshals as Dart `BigInt`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRcFeedMessage {
    pub seq: u64,
    pub ts: Option<String>,
    pub role: String,
    pub msg_type: String,
    pub text: Option<String>,
    pub tool: Option<BridgeRcFeedTool>,
}

impl From<RcFeedMessage> for BridgeRcFeedMessage {
    fn from(m: RcFeedMessage) -> Self {
        BridgeRcFeedMessage {
            seq: m.seq,
            ts: m.ts,
            role: m.role,
            msg_type: m.msg_type,
            text: m.text,
            tool: m.tool.map(|t| BridgeRcFeedTool {
                name: t.name,
                detail: t.detail,
            }),
        }
    }
}

/// A page of the feed (mirrors `rc::RcMessagesPage`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRcMessagesPage {
    pub messages: Vec<BridgeRcFeedMessage>,
    pub truncated: bool,
}

impl From<RcMessagesPage> for BridgeRcMessagesPage {
    fn from(p: RcMessagesPage) -> Self {
        BridgeRcMessagesPage {
            messages: p.messages.into_iter().map(Into::into).collect(),
            truncated: p.truncated,
        }
    }
}

/// A decoded rc-events frame (mirrors `rc_events::RcEvent`, all five variants).
/// A fielded enum → a Dart sealed class.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeRcEvent {
    ActivityChanged {
        shed: String,
        slug: String,
        activity: Option<BridgeRcActivity>,
        activity_at: Option<String>,
        state: Option<BridgeRcState>,
        last_message: Option<String>,
    },
    SessionUpdated {
        shed: String,
        slug: String,
        activity: Option<BridgeRcActivity>,
        state: Option<BridgeRcState>,
        last_message: Option<String>,
        /// The session's lane (contract v2), carried verbatim when the hub sends
        /// one. `None` on a removal, and on a hub that predates the field.
        /// Additive: a consumer that ignores it behaves exactly as before.
        lane: Option<String>,
        removed: bool,
    },
    MessageAppended {
        shed: String,
        slug: String,
        seq: u64,
    },
    HubUnavailable {
        shed: String,
    },
    ShedStopped {
        shed: String,
    },
}

impl From<RcEvent> for BridgeRcEvent {
    fn from(e: RcEvent) -> Self {
        match e {
            RcEvent::ActivityChanged {
                shed,
                slug,
                activity,
                activity_at,
                state,
                last_message,
            } => BridgeRcEvent::ActivityChanged {
                shed,
                slug,
                activity: activity.map(Into::into),
                activity_at,
                state: state.map(Into::into),
                last_message,
            },
            RcEvent::SessionUpdated {
                shed,
                slug,
                activity,
                state,
                last_message,
                lane,
                removed,
            } => BridgeRcEvent::SessionUpdated {
                shed,
                slug,
                activity: activity.map(Into::into),
                state: state.map(Into::into),
                last_message,
                lane,
                removed,
            },
            RcEvent::MessageAppended { shed, slug, seq } => {
                BridgeRcEvent::MessageAppended { shed, slug, seq }
            }
            RcEvent::HubUnavailable { shed } => BridgeRcEvent::HubUnavailable { shed },
            RcEvent::ShedStopped { shed } => BridgeRcEvent::ShedStopped { shed },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rc_kind_all_variants_incl_other() {
        for (raw, want) in [
            (RcKind::ClaudeRc, BridgeRcKind::ClaudeRc),
            (RcKind::ClaudeBroker, BridgeRcKind::ClaudeBroker),
            (RcKind::Codex, BridgeRcKind::Codex),
            (RcKind::Opencode, BridgeRcKind::Opencode),
            (RcKind::Cursor, BridgeRcKind::Cursor),
            // Without these two rows every gx/grok row would cross the bridge as
            // `Other { raw: "gx" }` and render neutrally — the failure the
            // unknown-kind policy is designed to make survivable, and therefore
            // the one that would go unnoticed.
            (RcKind::Gx, BridgeRcKind::Gx),
            (RcKind::Grok, BridgeRcKind::Grok),
            (RcKind::Shell, BridgeRcKind::Shell),
        ] {
            assert_eq!(BridgeRcKind::from(raw), want);
        }
        // The wire spellings, decoded through the core's own parser.
        assert_eq!(BridgeRcKind::from(RcKind::from_wire("gx")), BridgeRcKind::Gx);
        assert_eq!(
            BridgeRcKind::from(RcKind::from_wire("grok")),
            BridgeRcKind::Grok
        );
        assert_eq!(
            BridgeRcKind::from(RcKind::Other("weird".into())),
            BridgeRcKind::Other { raw: "weird".into() }
        );
        // Unknown wire strings preserve their raw value (unknown-kind policy).
        assert_eq!(
            BridgeRcKind::from(RcKind::from_wire("gpt-next")),
            BridgeRcKind::Other { raw: "gpt-next".into() }
        );
    }

    #[test]
    fn rc_state_all_variants() {
        for (raw, want) in [
            (RcState::Starting, BridgeRcState::Starting),
            (RcState::Ready, BridgeRcState::Ready),
            (RcState::Reconnecting, BridgeRcState::Reconnecting),
            (RcState::NeedsTrust, BridgeRcState::NeedsTrust),
            (RcState::NeedsAuth, BridgeRcState::NeedsAuth),
            (RcState::Dead, BridgeRcState::Dead),
        ] {
            assert_eq!(BridgeRcState::from(raw), want);
        }
    }

    #[test]
    fn rc_activity_all_variants() {
        for (raw, want) in [
            (RcActivity::Working, BridgeRcActivity::Working),
            (RcActivity::NeedsInput, BridgeRcActivity::NeedsInput),
            (RcActivity::Idle, BridgeRcActivity::Idle),
            (RcActivity::Unknown, BridgeRcActivity::Unknown),
        ] {
            assert_eq!(BridgeRcActivity::from(raw), want);
        }
    }

    #[test]
    fn capabilities_maps_and_nested_convert() {
        let mut agents = HashMap::new();
        agents.insert(
            "claude".to_string(),
            RcAgentInfo {
                installed: true,
                version: Some("1.2.3".into()),
            },
        );
        agents.insert(
            "codex".to_string(),
            RcAgentInfo {
                installed: false,
                version: None,
            },
        );
        let mut kf = HashMap::new();
        kf.insert(
            "codex".to_string(),
            RcKindFeatures {
                post_input: true,
                approvals: "tui".into(),
                watch: true,
                input: "gated".into(),
                // contract v2: the feed/steer affordances the client renders off.
                feed: "messages".into(),
                interrupt: false,
                attach: "tmux".into(),
            },
        );
        let caps = RcCapabilities {
            rc_version: 2,
            kinds: vec![RcKind::ClaudeRc, RcKind::Shell, RcKind::Other("x".into())],
            agents,
            features: vec!["watch".into()],
            kind_features: kf,
        };
        let b = BridgeRcCapabilities::from(caps);
        assert_eq!(b.rc_version, 2);
        assert_eq!(b.kinds.len(), 3);
        assert_eq!(
            b.kinds[2],
            BridgeRcKind::Other { raw: "x".into() }
        );
        assert!(b.agents["claude"].installed);
        assert_eq!(b.agents["claude"].version.as_deref(), Some("1.2.3"));
        assert!(!b.agents["codex"].installed);
        assert_eq!(b.agents["codex"].version, None);
        assert!(b.kind_features["codex"].watch);
        assert_eq!(b.kind_features["codex"].input, "gated");
    }

    #[test]
    fn rc_session_nullable_and_activity() {
        // Enriched via from_dto so workdir gets its default fill + host/shed inject.
        let dto = RcSessionDto {
            slug: "cdx".into(),
            tmux_session: "rc-cdx".into(),
            kind: RcKind::ClaudeRc,
            state: RcState::Ready,
            managed: true,
            display_name: None,
            workdir: Some("/home/shed/proj".into()),
            url: Some("https://claude.ai/x".into()),
            id: Some("SESS".into()),
            created_by: Some("shed-mobile/1".into()),
            created_at: Some("2026-01-01T00:00:00Z".into()),
            target_label: Some("proj".into()),
            lane: None,
            pending_approvals: None,
            activity: Some(RcActivity::Working),
            activity_at: Some("2026-01-01T00:01:00Z".into()),
            last_message: Some("building".into()),
        };
        let enriched = RcSession::from_dto(dto, "mini3", "proj");
        let b = BridgeRcSession::from(enriched);
        assert_eq!(b.host, "mini3");
        assert_eq!(b.shed, "proj");
        assert_eq!(b.slug, "cdx");
        assert_eq!(b.kind, BridgeRcKind::ClaudeRc);
        assert_eq!(b.state, BridgeRcState::Ready);
        assert_eq!(b.activity, Some(BridgeRcActivity::Working));
        assert_eq!(b.rc_id.as_deref(), Some("SESS"));
        assert!(b.managed);
        // display_name fallback = "<shed>/<slug>".
        assert_eq!(b.display_name, "proj/cdx");
        // A SHED row carries neither roost field — they are stamped only by
        // `from_roost`, and a card must not show an attention dot for a session
        // that has no notion of one.
        assert!(!b.attention);
        assert_eq!(b.tab_id, None);
    }

    /// A roost row is the shared `to_rc_dto()` mapping plus exactly two stamps.
    ///
    /// The assertions that matter are the ones a shed row cannot make:
    /// `attention` crosses (it is the whole attention affordance), `tab_id`
    /// crosses typed (it is what `tab.close`/`tab.dump` address), and
    /// `host`/`shed` stay EMPTY — Dart keys a machine row by the machine's own
    /// `origin`, so anything here would be a second identity for the same row.
    #[test]
    fn a_roost_row_carries_attention_and_the_tab_id() {
        use shed_core::roost::RoostSession;

        let tab = serde_json::from_value::<roost_ipc::messages::Tab>(serde_json::json!({
            "id": "4",
            "project_id": "2",
            "title": "OC | Pong reply request",
            "cwd": "/home/shed/oc-work",
            "state": "idle",
            "has_notification": true,
            "is_active": true,
            "user_titled": false,
            "position": 1,
            "created_at": 1788769906_i64,
            "last_active": 1788769906_i64,
            "hook_active": true,
            "shell_state": "unknown",
            "agent_lifecycle": "finished",
            "ownership": {
                "source": "opencode",
                "session_id": "ses_f85010d7effexVvTJ1mRHZkDqL",
                "last_event_at": 1788769939_i64,
                "detail": "session_idle",
                "metadata": {}
            }
        }))
        .expect("the shed-recorded opencode tab decodes");
        let project = roost_ipc::messages::Project {
            id: 2,
            name: "Roost".into(),
            cwd: "/home/shed".into(),
            position: 0,
            created_at: 1788769854,
            tabs: Vec::new(),
        };
        let session = RoostSession::from_tab("mini3", &project, &tab);

        let row = BridgeRcSession::from_roost(&session);
        assert!(row.attention, "has_notification must reach the card");
        assert_eq!(row.tab_id, Some(4));
        assert_eq!(row.slug, "4");
        assert_eq!(row.kind, BridgeRcKind::Opencode);
        assert_eq!(row.activity, Some(BridgeRcActivity::Idle));
        assert_eq!(row.display_name, "OC | Pong reply request");
        assert_eq!(row.workdir.as_deref(), Some("/home/shed/oc-work"));
        // The agent's OWN session id, not roost's tab id.
        assert_eq!(row.rc_id.as_deref(), Some("ses_f85010d7effexVvTJ1mRHZkDqL"));
        assert_eq!(row.host, "");
        assert_eq!(row.shed, "");
    }

    #[test]
    fn feed_page_u64_seq_round_trips() {
        // Large u64 seq (FRB BigInt marshalling edge) + a tool block + a text-only.
        let page = RcMessagesPage::from_value(&serde_json::json!({
            "messages": [
                {"seq": 9007199254740993_u64, "role":"assistant","type":"tool_use",
                 "tool":{"name":"bash","detail":"ls"}},
                {"seq": 2, "role":"user","type":"text","text":"hi"}
            ],
            "truncated": true
        }));
        let b = BridgeRcMessagesPage::from(page);
        assert!(b.truncated);
        assert_eq!(b.messages.len(), 2);
        assert_eq!(b.messages[0].seq, 9007199254740993);
        assert_eq!(b.messages[0].msg_type, "tool_use");
        let tool = b.messages[0].tool.as_ref().expect("tool");
        assert_eq!(tool.name.as_deref(), Some("bash"));
        assert_eq!(b.messages[1].text.as_deref(), Some("hi"));
        assert!(b.messages[1].tool.is_none());
    }

    #[test]
    fn rc_event_all_five_variants() {
        let act = BridgeRcEvent::from(RcEvent::ActivityChanged {
            shed: "proj".into(),
            slug: "cdx".into(),
            activity: Some(RcActivity::Working),
            activity_at: Some("t".into()),
            state: Some(RcState::Ready),
            last_message: Some("m".into()),
        });
        assert!(matches!(
            act,
            BridgeRcEvent::ActivityChanged { ref shed, ref activity, .. }
                if shed == "proj" && *activity == Some(BridgeRcActivity::Working)
        ));

        let upd = BridgeRcEvent::from(RcEvent::SessionUpdated {
            shed: "proj".into(),
            slug: "cdx".into(),
            activity: None,
            state: None,
            last_message: None,
            lane: None,
            removed: true,
        });
        assert!(matches!(
            upd,
            BridgeRcEvent::SessionUpdated { removed: true, .. }
        ));

        // u64 seq preserved through the event conversion.
        let msg = BridgeRcEvent::from(RcEvent::MessageAppended {
            shed: "proj".into(),
            slug: "cdx".into(),
            seq: 4_294_967_296,
        });
        assert!(matches!(
            msg,
            BridgeRcEvent::MessageAppended { seq: 4_294_967_296, .. }
        ));

        assert!(matches!(
            BridgeRcEvent::from(RcEvent::HubUnavailable { shed: "proj".into() }),
            BridgeRcEvent::HubUnavailable { .. }
        ));
        assert!(matches!(
            BridgeRcEvent::from(RcEvent::ShedStopped { shed: "proj".into() }),
            BridgeRcEvent::ShedStopped { .. }
        ));
    }
}
