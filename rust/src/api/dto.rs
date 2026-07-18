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
    DiskEntry, DiskSize, DiskTotals, Overview, OverviewServer, OverviewShed, Session, SessionRC,
    Shed, ShedImage, ShedStatus, SystemDiskUsage,
};

use super::dto_rc::{BridgeRcCapabilities, BridgeRcSession};

/// A shed's lifecycle status (mirrors `ShedStatus`; an unknown wire value folds
/// to `Unknown`). A plain fieldless enum → a plain Dart enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeShedStatus {
    Running,
    Stopped,
    Starting,
    Error,
    Unknown,
}

impl From<ShedStatus> for BridgeShedStatus {
    fn from(s: ShedStatus) -> Self {
        match s {
            ShedStatus::Running => BridgeShedStatus::Running,
            ShedStatus::Stopped => BridgeShedStatus::Stopped,
            ShedStatus::Starting => BridgeShedStatus::Starting,
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
        }
    }
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
    pub capabilities: Option<BridgeRcCapabilities>,
}

impl From<OverviewShed> for BridgeOverviewShed {
    fn from(o: OverviewShed) -> Self {
        BridgeOverviewShed {
            shed: o.shed.into(),
            sessions: o.sessions.into_iter().map(Into::into).collect(),
            capabilities: o.capabilities.map(Into::into),
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
            active_namespaces: vec!["ns1".into(), "ns2".into()],
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
            active_namespaces: vec![],
        };
        let be = BridgeShed::from(empty);
        assert_eq!(be.cpus, None);
        assert_eq!(be.backend, None);
        assert!(be.active_namespaces.is_empty());
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
        // The overview `sheds[]` element carries the shed's own fields at the
        // TOP level (decoded via `overview_shed_record`), a `sessions[]` list
        // whose rows carry an `rc` block (the slug is derived from the `rc-`
        // tmux name), and an optional `rc_capabilities` map.
        let v: serde_json::Value = serde_json::from_str(
            r#"{
                "server": {"version":"0.8.0","features":["overview","rc-events"]},
                "df": {"server_name":"mini3","totals":{}},
                "sheds": [
                    {"name":"proj","status":"running",
                     "sessions":[{"name":"rc-cdx",
                                  "rc":{"kind":"claude-rc","state":"ready","managed":true,"activity":"working"}}],
                     "rc_capabilities":{"rc_version":1}}
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
        assert!(b.sheds[0].capabilities.is_some());
        assert_eq!(b.warnings, vec!["one degraded"]);
    }
}
