//! Bridge-owned DTOs for the shed read/write plane (plan §3.6).
//!
//! These are defined LOCALLY (not re-exported from shed-core) with explicit
//! `From<shed_core::…>` conversions, so FRB marshals small, mirrored structs
//! rather than parsing shed-core's third-party types. Each has an exhaustive
//! conversion test covering every enum variant, nullable field, timestamp, and
//! `u64`/`i64` field (FRB's numeric-marshalling edge).
//!
//! The rc-domain DTOs live in [`super::dto_rc`]; the overview cluster below
//! references them.

use shed_core::models::{
    CloudCounts, CloudUsage, DiskEntry, DiskSize, DiskTotals, Overview, OverviewServer,
    OverviewShed, Session, SessionRC, Shed, ShedCloud, ShedCloudLease, ShedImage, ShedStatus,
    SystemDiskUsage, DEFAULT_LEASE_WARN_S, MAX_EXTEND_HOURS,
};
use shed_lane::time::rfc3339_unix_ms;

use super::dto_rc::BridgeRcSession;

/// A shed's lifecycle status (mirrors `ShedStatus`; an unknown wire value folds
/// to `Unknown`). A plain fieldless enum → a plain Dart enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeShedStatus {
    Running,
    Stopped,
    Starting,
    /// A stop in progress; only a backend with an asynchronous lifecycle
    /// (remote) sends it.
    Stopping,
    Error,
    Unknown,
}

impl From<ShedStatus> for BridgeShedStatus {
    fn from(s: ShedStatus) -> Self {
        match s {
            ShedStatus::Running => BridgeShedStatus::Running,
            ShedStatus::Stopped => BridgeShedStatus::Stopped,
            ShedStatus::Starting => BridgeShedStatus::Starting,
            ShedStatus::Stopping => BridgeShedStatus::Stopping,
            ShedStatus::Error => BridgeShedStatus::Error,
            ShedStatus::Unknown => BridgeShedStatus::Unknown,
        }
    }
}

/// One shed (mirrors `models::Shed`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeShed {
    pub host: String,
    pub name: String,
    pub status: BridgeShedStatus,
    pub backend: Option<String>,
    pub repo: Option<String>,
    pub image: Option<String>,
    pub image_digest: Option<String>,
    pub local_dir: Option<String>,
    pub ip_address: Option<String>,
    pub cpus: Option<i64>,
    pub memory_mb: Option<i64>,
    pub created_at: Option<String>,
    pub started_at: Option<String>,
    pub active_namespaces: Vec<String>,
    /// A cloud shed's machine (plan 041): `Some` on every record of a remote
    /// server with leases, `None` on every other shed.
    pub cloud: Option<BridgeShedCloud>,
    /// The hours of this shed's extend whose outcome is not known (every send
    /// ended with no answer), `None` when there is none. While it is set the
    /// bridge refuses every extend of the shed unsent
    /// ([`BridgeExtendOutcome::Pending`]); it clears once a listing shows whether
    /// the lease moved (`crate::extend_book`). Filled by the client's listings.
    pub extend_unknown_hours: Option<u32>,
}

impl From<Shed> for BridgeShed {
    fn from(s: Shed) -> Self {
        BridgeShed {
            host: s.host,
            name: s.name,
            status: s.status.into(),
            backend: s.backend,
            repo: s.repo,
            image: s.image,
            image_digest: s.image_digest,
            local_dir: s.local_dir,
            ip_address: s.ip_address,
            cpus: s.cpus,
            memory_mb: s.memory_mb,
            created_at: s.created_at,
            started_at: s.started_at,
            active_namespaces: s.active_namespaces,
            cloud: s.cloud.map(Into::into),
            extend_unknown_hours: None,
        }
    }
}

/// A cloud shed's machine as the account service reported it (mirrors
/// `models::ShedCloud`; times verbatim, a missing member at its default).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeShedCloud {
    /// Which cloud, for display; absent until the service answered.
    pub provider: Option<String>,
    /// The size's catalog name ("" when not said).
    pub size_name: String,
    /// vCPUs and memory, 0 when not said.
    pub cpus: i64,
    pub memory_mb: i64,
    pub disk_gb: i64,
    /// The image the machine was made from ("" when not said).
    pub image: String,
    pub created_at: String,
    pub started_at: Option<String>,
    pub stopped_at: Option<String>,
    /// `None` while the lease is unknown (the service has not answered yet).
    pub lease: Option<BridgeShedLease>,
}

impl From<ShedCloud> for BridgeShedCloud {
    fn from(c: ShedCloud) -> Self {
        BridgeShedCloud {
            provider: c.provider,
            size_name: c.size.name,
            cpus: c.size.cpus,
            memory_mb: c.size.memory_mb,
            disk_gb: c.disk_gb,
            image: c.image,
            created_at: c.created_at,
            started_at: c.started_at,
            stopped_at: c.stopped_at,
            lease: c.lease.map(Into::into),
        }
    }
}

/// When the account service deletes a cloud shed's machine and how far it may be
/// extended (mirrors `models::ShedCloudLease`), with the times already parsed and
/// the extend presets already clipped to the cap, so the UI only compares with
/// its clock.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeShedLease {
    /// When the machine is deleted, verbatim ("" when not said).
    pub expires_at: String,
    /// [`Self::expires_at`] in unix milliseconds; `None` when it does not parse
    /// (the lease is then shown unknown and offers no extend).
    pub expires_at_ms: Option<i64>,
    /// The cap no extend goes past, verbatim ("" when not said).
    pub max_expires_at: String,
    /// [`Self::max_expires_at`] in unix milliseconds, when it parses.
    pub max_expires_at_ms: Option<i64>,
    /// Whether the server said an extend would be accepted now.
    pub extendable: bool,
    /// How long before the end (seconds) the time left is shown amber: the
    /// server's `warn_s`, or its 2 h default when absent; 0 means never.
    pub warn_s: i64,
    /// The most hours an extend may ask for: the whole hours between the end and
    /// the cap, at most 720. 0 when no extend is offered (not extendable, or a
    /// time that does not parse).
    pub extend_max_h: i64,
    /// The server's presets, each clipped to [`Self::extend_max_h`], deduplicated
    /// and ascending; empty when no extend is offered. (`u32`, not `i64`: hours
    /// are at most 720, and FRB's `Vec<i64>` decode does not type-check in Dart.)
    pub extend_presets_h: Vec<u32>,
}

impl From<ShedCloudLease> for BridgeShedLease {
    fn from(l: ShedCloudLease) -> Self {
        let end = rfc3339_unix_ms(&l.expires_at);
        let cap = rfc3339_unix_ms(&l.max_expires_at);
        let extend_max_h = match (end, cap) {
            (Some(end), Some(cap)) if l.extendable => {
                ((cap - end) / 3_600_000).clamp(0, MAX_EXTEND_HOURS)
            }
            _ => 0,
        };
        let mut extend_presets_h: Vec<u32> = if extend_max_h > 0 {
            l.presets_h
                .iter()
                .filter(|&&h| h >= 1)
                .filter_map(|&h| u32::try_from(h.min(extend_max_h)).ok())
                .collect()
        } else {
            Vec::new()
        };
        extend_presets_h.sort_unstable();
        extend_presets_h.dedup();
        BridgeShedLease {
            expires_at: l.expires_at,
            expires_at_ms: end,
            max_expires_at: l.max_expires_at,
            max_expires_at_ms: cap,
            extendable: l.extendable,
            warn_s: l.warn_s.unwrap_or(DEFAULT_LEASE_WARN_S),
            extend_max_h,
            extend_presets_h,
        }
    }
}

/// One scope of `GET /api/cloud/usage` (mirrors `models::CloudCounts`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeCloudCounts {
    pub machines: i64,
    pub running: i64,
    pub stopped: i64,
    pub max: i64,
}

impl From<CloudCounts> for BridgeCloudCounts {
    fn from(c: CloudCounts) -> Self {
        BridgeCloudCounts {
            machines: c.machines,
            running: c.running,
            stopped: c.stopped,
            max: c.max,
        }
    }
}

/// `GET /api/cloud/usage` (mirrors `models::CloudUsage`): `person` is `None` for
/// a caller who is not a person of the account service (a local admin).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeCloudUsage {
    pub person: Option<BridgeCloudCounts>,
    pub org: BridgeCloudCounts,
}

impl From<CloudUsage> for BridgeCloudUsage {
    fn from(u: CloudUsage) -> Self {
        BridgeCloudUsage {
            person: u.person.map(Into::into),
            org: u.org.into(),
        }
    }
}

/// What `BridgeClient.extend` did. Every arm's words are fixed, never the
/// server's message.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeExtendOutcome {
    /// The lease moved: the shed as the server answered it.
    Extended { shed: BridgeShed },
    /// Refused (or never sent): `code` and `reason` from the API error ("" when
    /// none), its status, and the fixed words to show.
    Refused {
        code: String,
        reason: String,
        status: Option<u16>,
        words: String,
    },
    /// Sent, but shed-core could not say whether it was applied (no reply or a
    /// 5xx on every send, a 2xx whose shed could not be read): the lease may or
    /// may not have moved. The shed's Extend stays unavailable until a listing
    /// shows which.
    Unknown { hours: u32, words: String },
    /// Not sent: an earlier extend of this shed is in flight or its outcome is
    /// not known yet.
    Pending { words: String },
}

/// One image (mirrors `models::ShedImage`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeShedImage {
    pub name: String,
    pub docker_ref: Option<String>,
    pub alias: Option<String>,
    pub is_default: bool,
    pub cached: bool,
    pub in_use: bool,
    pub digest: Option<String>,
    pub source: Option<String>,
    pub size_bytes: i64,
}

impl From<ShedImage> for BridgeShedImage {
    fn from(i: ShedImage) -> Self {
        BridgeShedImage {
            name: i.name,
            docker_ref: i.docker_ref,
            alias: i.alias,
            is_default: i.is_default,
            cached: i.cached,
            in_use: i.in_use,
            digest: i.digest,
            source: i.source,
            size_bytes: i.size_bytes,
        }
    }
}

/// A logical/physical byte pair (mirrors `models::DiskSize`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeDiskSize {
    pub logical_bytes: i64,
    pub physical_bytes: i64,
}

impl From<DiskSize> for BridgeDiskSize {
    fn from(d: DiskSize) -> Self {
        BridgeDiskSize {
            logical_bytes: d.logical_bytes,
            physical_bytes: d.physical_bytes,
        }
    }
}

/// One image/shed/orphan disk row (mirrors `models::DiskEntry`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeDiskEntry {
    pub name: String,
    pub docker_ref: Option<String>,
    pub size: BridgeDiskSize,
}

impl From<DiskEntry> for BridgeDiskEntry {
    fn from(e: DiskEntry) -> Self {
        BridgeDiskEntry {
            name: e.name,
            docker_ref: e.docker_ref,
            size: e.size.into(),
        }
    }
}

/// The per-category totals (mirrors `models::DiskTotals`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeDiskTotals {
    pub images: BridgeDiskSize,
    pub sheds: BridgeDiskSize,
    pub snapshots: BridgeDiskSize,
    pub orphans: BridgeDiskSize,
    pub all: BridgeDiskSize,
}

impl From<DiskTotals> for BridgeDiskTotals {
    fn from(t: DiskTotals) -> Self {
        BridgeDiskTotals {
            images: t.images.into(),
            sheds: t.sheds.into(),
            snapshots: t.snapshots.into(),
            orphans: t.orphans.into(),
            all: t.all.into(),
        }
    }
}

/// `GET /api/system/df` (mirrors `models::SystemDiskUsage`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSystemDiskUsage {
    pub server_name: Option<String>,
    pub backend: Option<String>,
    pub images: Vec<BridgeDiskEntry>,
    pub sheds: Vec<BridgeDiskEntry>,
    pub orphans: Vec<BridgeDiskEntry>,
    pub totals: BridgeDiskTotals,
}

impl From<SystemDiskUsage> for BridgeSystemDiskUsage {
    fn from(d: SystemDiskUsage) -> Self {
        BridgeSystemDiskUsage {
            server_name: d.server_name,
            backend: d.backend,
            images: d.images.into_iter().map(Into::into).collect(),
            sheds: d.sheds.into_iter().map(Into::into).collect(),
            orphans: d.orphans.into_iter().map(Into::into).collect(),
            totals: d.totals.into(),
        }
    }
}

/// The rc display subset inside a [`BridgeSession`] (mirrors `models::SessionRC`;
/// raw wire strings, not the enriched rc model).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSessionRc {
    pub kind: Option<String>,
    pub state: Option<String>,
    pub managed: bool,
    pub display_name: Option<String>,
    pub url: Option<String>,
    pub created_by: Option<String>,
    pub activity: Option<String>,
    pub activity_at: Option<String>,
    pub last_message: Option<String>,
}

impl From<SessionRC> for BridgeSessionRc {
    fn from(r: SessionRC) -> Self {
        BridgeSessionRc {
            kind: r.kind,
            state: r.state,
            managed: r.managed,
            display_name: r.display_name,
            url: r.url,
            created_by: r.created_by,
            activity: r.activity,
            activity_at: r.activity_at,
            last_message: r.last_message,
        }
    }
}

/// One `GET /api/sheds/{name}/sessions` row (mirrors `models::Session`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSession {
    pub name: String,
    pub shed_name: String,
    pub server_name: Option<String>,
    pub created_at: Option<String>,
    pub attached: bool,
    pub window_count: i64,
    pub rc: Option<BridgeSessionRc>,
}

impl From<Session> for BridgeSession {
    fn from(s: Session) -> Self {
        BridgeSession {
            name: s.name,
            shed_name: s.shed_name,
            server_name: s.server_name,
            created_at: s.created_at,
            attached: s.attached,
            window_count: s.window_count,
            rc: s.rc.map(Into::into),
        }
    }
}

/// The server block of an overview (mirrors `models::OverviewServer`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeOverviewServer {
    pub version: String,
    pub features: Vec<String>,
}

impl From<OverviewServer> for BridgeOverviewServer {
    fn from(s: OverviewServer) -> Self {
        BridgeOverviewServer {
            version: s.version,
            features: s.features,
        }
    }
}

/// One shed-with-its-rc-sessions overview row (mirrors `models::OverviewShed`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeOverviewShed {
    pub shed: BridgeShed,
    pub sessions: Vec<BridgeRcSession>,
}

impl From<OverviewShed> for BridgeOverviewShed {
    fn from(o: OverviewShed) -> Self {
        BridgeOverviewShed {
            shed: o.shed.into(),
            sessions: o.sessions.into_iter().map(Into::into).collect(),
        }
    }
}

/// `GET /api/overview` (mirrors `models::Overview`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeOverview {
    pub server: BridgeOverviewServer,
    pub df: Option<BridgeSystemDiskUsage>,
    pub sheds: Vec<BridgeOverviewShed>,
    pub warnings: Vec<String>,
}

impl From<Overview> for BridgeOverview {
    fn from(o: Overview) -> Self {
        BridgeOverview {
            server: o.server.into(),
            df: o.df.map(Into::into),
            sheds: o.sheds.into_iter().map(Into::into).collect(),
            warnings: o.warnings,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shed_status_all_variants() {
        for (raw, want) in [
            (ShedStatus::Running, BridgeShedStatus::Running),
            (ShedStatus::Stopped, BridgeShedStatus::Stopped),
            (ShedStatus::Starting, BridgeShedStatus::Starting),
            (ShedStatus::Stopping, BridgeShedStatus::Stopping),
            (ShedStatus::Error, BridgeShedStatus::Error),
            (ShedStatus::Unknown, BridgeShedStatus::Unknown),
        ] {
            assert_eq!(BridgeShedStatus::from(raw), want);
        }
    }

    #[test]
    fn shed_nullable_and_i64_fields_round_trip() {
        // A fully-populated shed: every Option is Some, both i64s carry a large
        // value (FRB numeric edge), the namespaces vec is non-empty.
        let s = Shed {
            host: "mini3".into(),
            name: "proj".into(),
            status: ShedStatus::Running,
            backend: Some("firecracker".into()),
            repo: Some("git@x:proj".into()),
            image: Some("img".into()),
            image_digest: Some("sha256:deadbeef".into()),
            local_dir: Some("/home/shed/proj".into()),
            ip_address: Some("10.0.0.5".into()),
            cpus: Some(8),
            memory_mb: Some(16_384),
            created_at: Some("2026-01-01T00:00:00Z".into()),
            started_at: Some("2026-01-02T00:00:00Z".into()),
            status_reason: Some("capacity".into()),
            active_namespaces: vec!["ns1".into(), "ns2".into()],
            cloud: None,
        };
        let b = BridgeShed::from(s.clone());
        assert_eq!(b.host, "mini3");
        assert_eq!(b.status, BridgeShedStatus::Running);
        assert_eq!(b.cpus, Some(8));
        assert_eq!(b.memory_mb, Some(16_384));
        assert_eq!(b.created_at.as_deref(), Some("2026-01-01T00:00:00Z"));
        assert_eq!(b.active_namespaces, vec!["ns1", "ns2"]);

        // The all-absent variant: every Option None, empty vec.
        let empty = Shed {
            host: String::new(),
            name: "x".into(),
            status: ShedStatus::Unknown,
            backend: None,
            repo: None,
            image: None,
            image_digest: None,
            local_dir: None,
            ip_address: None,
            cpus: None,
            memory_mb: None,
            created_at: None,
            started_at: None,
            status_reason: None,
            active_namespaces: vec![],
            cloud: None,
        };
        let be = BridgeShed::from(empty);
        assert_eq!(be.cpus, None);
        assert_eq!(be.backend, None);
        assert!(be.active_namespaces.is_empty());
    }

    /// A cloud shed's lease: times parsed, presets clipped to the whole hours
    /// left to the cap (deduplicated, ascending), the warning time defaulted.
    #[test]
    fn cloud_lease_presets_clip_to_the_cap() {
        let shed = |lease: serde_json::Value| -> BridgeShed {
            let s: Shed = serde_json::from_value(serde_json::json!({
                "name": "w", "backend": "remote",
                "cloud": {"provider": "gce",
                          "size": {"name": "standard", "cpus": 2, "memory_mb": 8192},
                          "disk_gb": 50, "image": "shed-full", "created_at": "2026-11-26T06:00:00Z",
                          "lease": lease},
            }))
            .unwrap();
            s.into()
        };
        let b = shed(serde_json::json!({
            "expires_at": "2026-11-26T10:00:00Z", "max_expires_at": "2026-11-27T06:30:00Z",
            "extendable": true, "presets_h": [48, 6, 12, 24, 0, -3],
        }));
        let c = b.cloud.expect("cloud");
        assert_eq!(
            (c.size_name.as_str(), c.cpus, c.memory_mb),
            ("standard", 2, 8192)
        );
        assert_eq!(c.provider.as_deref(), Some("gce"));
        let l = c.lease.expect("lease");
        assert_eq!(l.expires_at_ms, Some(1_795_687_200_000));
        assert_eq!(l.extend_max_h, 20, "20 whole hours to the cap");
        assert_eq!(l.extend_presets_h, vec![6, 12, 20]);
        assert_eq!(l.warn_s, DEFAULT_LEASE_WARN_S);
        assert_eq!(b.extend_unknown_hours, None);

        // Not extendable, or a time that does not parse: nothing offered.
        for lease in [
            serde_json::json!({"expires_at": "2026-11-26T10:00:00Z",
                "max_expires_at": "2026-11-27T10:00:00Z", "extendable": false,
                "presets_h": [6], "warn_s": 0}),
            serde_json::json!({"expires_at": "soon",
                "max_expires_at": "2026-11-27T10:00:00Z", "extendable": true,
                "presets_h": [6], "warn_s": 0}),
        ] {
            let l = shed(lease).cloud.unwrap().lease.unwrap();
            assert_eq!(l.extend_max_h, 0);
            assert!(l.extend_presets_h.is_empty());
            assert_eq!(l.warn_s, 0);
        }
    }

    #[test]
    fn usage_converts_with_and_without_a_person() {
        let u: CloudUsage = serde_json::from_str(
            r#"{"person":{"machines":2,"running":1,"stopped":1,"max":4},
                "org":{"machines":7,"running":5,"stopped":2,"max":10}}"#,
        )
        .unwrap();
        let b = BridgeCloudUsage::from(u);
        assert_eq!(b.person.map(|p| (p.machines, p.max)), Some((2, 4)));
        assert_eq!(b.org.machines, 7);
        let u: CloudUsage =
            serde_json::from_str(r#"{"person":null,"org":{"machines":7,"max":10}}"#).unwrap();
        assert_eq!(BridgeCloudUsage::from(u).person, None);
    }

    #[test]
    fn image_bool_and_i64_fields() {
        let i = ShedImage {
            name: "ubuntu".into(),
            docker_ref: Some("ghcr.io/x:v1".into()),
            alias: Some("default".into()),
            is_default: true,
            cached: true,
            in_use: false,
            digest: Some("sha256:abc".into()),
            source: Some("pull".into()),
            size_bytes: 9_999_999_999,
        };
        let b = BridgeShedImage::from(i);
        assert!(b.is_default);
        assert!(b.cached);
        assert!(!b.in_use);
        assert_eq!(b.size_bytes, 9_999_999_999);
        assert_eq!(b.alias.as_deref(), Some("default"));
    }

    #[test]
    fn disk_usage_cluster_round_trips() {
        let df = SystemDiskUsage {
            server_name: Some("mini3".into()),
            backend: Some("firecracker".into()),
            images: vec![DiskEntry {
                name: "img".into(),
                docker_ref: Some("ref".into()),
                size: DiskSize {
                    logical_bytes: 100,
                    physical_bytes: 80,
                },
            }],
            sheds: vec![],
            orphans: vec![DiskEntry {
                name: "?".into(),
                docker_ref: None,
                size: DiskSize {
                    logical_bytes: 5,
                    physical_bytes: 5,
                },
            }],
            totals: DiskTotals {
                images: DiskSize {
                    logical_bytes: 100,
                    physical_bytes: 80,
                },
                sheds: DiskSize::default(),
                snapshots: DiskSize::default(),
                orphans: DiskSize {
                    logical_bytes: 5,
                    physical_bytes: 5,
                },
                all: DiskSize {
                    logical_bytes: 105,
                    physical_bytes: 85,
                },
            },
        };
        let b = BridgeSystemDiskUsage::from(df);
        assert_eq!(b.server_name.as_deref(), Some("mini3"));
        assert_eq!(b.images.len(), 1);
        assert_eq!(b.images[0].size.logical_bytes, 100);
        assert!(b.sheds.is_empty());
        assert_eq!(b.orphans[0].docker_ref, None);
        assert_eq!(b.totals.all.logical_bytes, 105);
    }

    #[test]
    fn session_with_and_without_rc() {
        let with_rc = Session {
            name: "rc-cdx".into(),
            shed_name: "proj".into(),
            server_name: Some("mini3".into()),
            created_at: Some("2026-01-01T00:00:00Z".into()),
            attached: true,
            window_count: 3,
            rc: Some(SessionRC {
                kind: Some("claude-rc".into()),
                state: Some("ready".into()),
                managed: true,
                display_name: Some("My Session".into()),
                url: None,
                created_by: Some("shed-mobile/1".into()),
                activity: Some("working".into()),
                activity_at: Some("2026-01-01T00:01:00Z".into()),
                last_message: Some("hello".into()),
            }),
        };
        let b = BridgeSession::from(with_rc);
        assert!(b.attached);
        assert_eq!(b.window_count, 3);
        let rc = b.rc.expect("rc present");
        assert_eq!(rc.kind.as_deref(), Some("claude-rc"));
        assert!(rc.managed);
        assert_eq!(rc.activity.as_deref(), Some("working"));

        let plain = Session {
            name: "shell".into(),
            shed_name: "proj".into(),
            server_name: None,
            created_at: None,
            attached: false,
            window_count: 0,
            rc: None,
        };
        assert!(BridgeSession::from(plain).rc.is_none());
    }

    #[test]
    fn overview_nested_clusters() {
        // Reuse shed-core's tolerant JSON decoder to build a realistic overview,
        // then assert the conversion preserves the nested structure + df.
        //
        // **This is the PRE-0.9.0 shape, kept deliberately.** The RC hub retired
        // in S6, so a 0.9.0 server's `sessions[]` rows carry no `rc` block and
        // the whole `rc_capabilities` map is gone from the wire (see
        // `overview_0_9_0_rows_are_not_sessions` below). An OLD server on the
        // other end still answers this way, and shed-core still decodes it — so
        // the bridge conversion is pinned against the richer payload.
        let v: serde_json::Value = serde_json::from_str(
            r#"{
                "server": {"version":"0.8.0","features":["overview","rc-events"]},
                "df": {"server_name":"mini3","totals":{}},
                "sheds": [
                    {"name":"proj","status":"running",
                     "sessions":[{"name":"rc-cdx",
                                  "rc":{"kind":"claude-rc","state":"ready","managed":true,"activity":"working"}}]}
                ],
                "warnings": ["one degraded"]
            }"#,
        )
        .unwrap();
        let ov = Overview::from_value(&v);
        let b = BridgeOverview::from(ov);
        assert_eq!(b.server.version, "0.8.0");
        assert!(b.server.features.contains(&"rc-events".to_string()));
        assert!(b.df.is_some());
        assert_eq!(b.sheds.len(), 1);
        assert_eq!(b.sheds[0].shed.name, "proj");
        assert_eq!(b.sheds[0].shed.status, BridgeShedStatus::Running);
        assert_eq!(b.sheds[0].sessions.len(), 1);
        assert_eq!(b.sheds[0].sessions[0].slug, "cdx");
        assert_eq!(
            b.sheds[0].sessions[0].activity,
            Some(super::super::dto_rc::BridgeRcActivity::Working)
        );
        assert_eq!(b.warnings, vec!["one degraded"]);
    }

    #[test]
    fn overview_0_9_0_rows_are_not_sessions() {
        // A 0.9.0 server's overview: `features` no longer advertises `rc-events`,
        // and a `sessions[]` row is a PLAIN TMUX row with no `rc` block
        // (`internal/config/types.go`'s `Session` after S6). shed-core surfaces
        // only rc-enriched rows, so the shed contributes no sessions at all —
        // which is exactly why the phone reads a shed's agent sessions from its
        // roost-session now, not from here.
        let v: serde_json::Value = serde_json::from_str(
            r#"{
                "server": {"version":"0.9.0","features":["overview"]},
                "sheds": [
                    {"name":"proj","status":"running",
                     "sessions":[{"name":"default","shed_name":"proj","attached":false}]}
                ]
            }"#,
        )
        .unwrap();
        let b = BridgeOverview::from(Overview::from_value(&v));
        assert_eq!(b.sheds.len(), 1, "the shed itself still lists");
        assert!(
            b.sheds[0].sessions.is_empty(),
            "a plain tmux row is not an agent session"
        );
        assert!(!b.server.features.contains(&"rc-events".to_string()));
    }
}
