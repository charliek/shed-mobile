import 'rc_models.dart';

/// The `shed-ext-rc capabilities` payload — also embedded per shed as
/// `rc_capabilities` in the GET /api/overview response. It tells a client which
/// kinds a shed offers, which agents are installed (and at what version), the
/// feature set, and per-kind UI hints. Mirrors the guest's `rc.Capabilities`
/// (`internal/ext/rc/capabilities.go`) and the Rust core `RcCapabilities`
/// (`crates/shed-core/src/rc.rs`).
///
/// Absence is tolerated at the call site: a stopped shed or an image that
/// predates multi-agent RC carries no capabilities block, so the field is null
/// and the create form falls back to its safe base (claude + shell).
class RcCapabilities {
  const RcCapabilities({
    required this.rcVersion,
    required this.kinds,
    required this.agents,
    required this.features,
    required this.kindFeatures,
  });

  /// Capability/protocol version (decoupled from SHED_RC_V). Currently 3.
  final int rcVersion;

  /// Every kind this binary offers (order matches the pinned wire contract).
  /// Unknown strings are preserved via [RcKind.other] (unknown-kind policy).
  final List<RcKind> kinds;

  /// Per-tool install probe, keyed by the tool token (`claude`, `codex`, …).
  final Map<String, AgentInfo> agents;

  /// Stable feature tokens (`generic-perm`, `plan-stdin`, `prompt-b64`, …).
  final List<String> features;

  /// Per-kind UI hints, keyed by the wire kind string.
  final Map<String, KindFeatures> kindFeatures;

  /// Whether [feature] is advertised (discovery, replacing error-string sniffing).
  bool hasFeature(String feature) => features.contains(feature);

  /// Whether a create form should OFFER [kind]: it is advertised in [kinds] AND
  /// its backing agent (if any) is installed. `shell` (no agent) is offered
  /// whenever advertised. Mirrors the Rust core `RcCapabilities::offers`.
  bool offers(RcKind kind) {
    if (!kinds.contains(kind)) return false;
    final tool = kind.tool;
    if (tool == null) return true; // shell / unknown — no agent to require
    return agents[tool]?.installed ?? false;
  }

  /// The creatable kinds this shed offers, in canonical create-form order — the
  /// gated list a launch UI renders (empty when nothing installed is advertised).
  /// Mirrors the Rust core `RcCapabilities::creatable_kinds`.
  List<RcKind> creatableKinds() => RcKind.creatable.where(offers).toList();

  /// Decode a capabilities block. Tolerant: absent/wrong-typed lists and maps
  /// decode to empty so a partial payload still parses.
  factory RcCapabilities.fromJson(Map<String, Object?> j) {
    final rawKinds = j['kinds'];
    final rawAgents = j['agents'];
    final rawFeatures = j['features'];
    final rawKindFeatures = j['kind_features'];

    final agents = <String, AgentInfo>{};
    if (rawAgents is Map<String, Object?>) {
      rawAgents.forEach((tool, v) {
        if (v is Map<String, Object?>) agents[tool] = AgentInfo.fromJson(v);
      });
    }
    final kindFeatures = <String, KindFeatures>{};
    if (rawKindFeatures is Map<String, Object?>) {
      rawKindFeatures.forEach((kind, v) {
        if (v is Map<String, Object?>) {
          kindFeatures[kind] = KindFeatures.fromJson(v);
        }
      });
    }
    return RcCapabilities(
      rcVersion: _int(j['rc_version']),
      kinds: <RcKind>[
        if (rawKinds is List)
          for (final k in rawKinds)
            if (k is String) RcKind.fromWire(k),
      ],
      agents: agents,
      features: <String>[
        if (rawFeatures is List)
          for (final f in rawFeatures)
            if (f is String) f,
      ],
      kindFeatures: kindFeatures,
    );
  }
}

/// One agent's install-probe result under [RcCapabilities.agents]. `version` is
/// null when the agent is not installed (or its version could not be read).
/// Mirrors the guest's `rc.AgentInfo`.
class AgentInfo {
  const AgentInfo({required this.installed, this.version});
  final bool installed;
  final String? version;

  factory AgentInfo.fromJson(Map<String, Object?> j) =>
      AgentInfo(installed: j['installed'] == true, version: _str(j['version']));
}

/// Per-kind UI hints from [RcCapabilities.kindFeatures]. Mirrors the guest's
/// `rc.KindFeatures`: [postInput] reports whether a typed line reaches the pane,
/// [approvals] is where approvals surface (v1 agents are TUI-only → `"tui"`).
class KindFeatures {
  const KindFeatures({required this.postInput, required this.approvals});
  final bool postInput;
  final String approvals;

  factory KindFeatures.fromJson(Map<String, Object?> j) => KindFeatures(
    postInput: j['post_input'] == true,
    approvals: _str(j['approvals']) ?? '',
  );
}

int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);

String? _str(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}
