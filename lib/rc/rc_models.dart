/// RC Session Convention kind. Mirrors the guest's `rc.Kind`
/// (`internal/ext/rc/rc.go`) and the shared Rust client core `RcKind`
/// (`crates/shed-core/src/rc.rs`) — the same value set and the same
/// unknown-kind policy.
///
/// A recognized kind is one of the fixed set (claude-broker / claude-rc / codex /
/// opencode / cursor / shell). An UNRECOGNIZED wire value — e.g. a session
/// created by a newer client — is PRESERVED verbatim via [RcKind.other]
/// ([known] == false) under the unknown-kind policy: it renders neutrally
/// (name + state only, no claude URL/broker affordances) rather than collapsing
/// to `claude-broker`.
///
/// Not an `enum` precisely so the unknown case can carry its raw string.
class RcKind {
  const RcKind._(this.wire, {this.known = true});

  /// The on-wire string (the value stored in SHED_RC_KIND and passed to --kind).
  final String wire;

  /// False for a preserved-raw unknown/foreign kind — the neutral-render signal.
  final bool known;

  static const claudeBroker = RcKind._('claude-broker');
  static const claudeRc = RcKind._('claude-rc');
  static const codex = RcKind._('codex');
  static const opencode = RcKind._('opencode');
  static const cursor = RcKind._('cursor');
  static const shell = RcKind._('shell');

  /// Every recognized kind, in the pinned capabilities wire order.
  static const List<RcKind> values = [
    claudeBroker,
    claudeRc,
    codex,
    opencode,
    cursor,
    shell,
  ];

  /// The kinds a create form can offer for creation, in canonical order.
  /// `claude-broker` is URL-driven (not create-from-a-form) and an unknown kind
  /// is never creatable, so both are excluded. Capability gating narrows this
  /// further per shed. Mirrors the Rust core `RcKind::creatable()`.
  static const List<RcKind> creatable = [
    claudeRc,
    codex,
    opencode,
    cursor,
    shell,
  ];

  /// Decode a wire value, PRESERVING an unrecognized string as an unknown kind
  /// ([RcKind.other]) rather than collapsing to a default. Mirrors the Go
  /// `parseKind` / Rust `RcKind::from_wire`.
  static RcKind fromWire(String? s) {
    for (final k in values) {
      if (k.wire == s) return k;
    }
    return RcKind.other(s ?? '');
  }

  /// An unknown/foreign kind, its raw wire string preserved verbatim.
  factory RcKind.other(String raw) => RcKind._(raw, known: false);

  /// Whether this kind accepts a typed kickoff line (claude-rc/codex/opencode/
  /// cursor → a prompt, shell → a command). claude-broker's input is its remote
  /// URL, not the pane; an unknown kind is not promptable (no affordances).
  /// Mirrors `AcceptsTypedInput` / `accepts_typed_input`.
  bool get acceptsPrompt => known && this != claudeBroker;

  /// Whether this kind runs claude — i.e. one of the two claude kinds (and so
  /// gets claude's full `--permission-mode` set and URL affordances). NOT true
  /// for codex/cursor/opencode. Mirrors the guest's `IsClaudeKind`.
  bool get runsClaude => this == claudeBroker || this == claudeRc;

  /// Whether this kind carries an autonomy/permission posture: every known agent
  /// kind does; `shell` has none, and an unknown kind renders neutrally with
  /// none.
  bool get hasPermissionMode => known && this != shell;

  /// The tool token this kind's agent maps to under `capabilities.agents`, or
  /// null for a kind with no installable agent (`shell`) or an unknown kind.
  /// Mirrors the Rust core `RcKind::tool`.
  String? get tool => switch (wire) {
    'claude-rc' || 'claude-broker' => 'claude',
    'codex' => 'codex',
    'opencode' => 'opencode',
    'cursor' => 'cursor',
    _ => null, // shell / unknown — no agent to require
  };

  /// The per-agent login remediation surfaced for this kind's `needs-auth` state
  /// (what to run in a terminal to log in). Mirrors the guest's `AuthHintFor`
  /// and the Rust core `auth_hint`.
  String get authHint => switch (wire) {
    'claude-rc' || 'claude-broker' => 'run `claude` → /login',
    'codex' => 'run `codex` and complete login (`codex login`)',
    'opencode' => 'run `opencode auth login`',
    'cursor' => 'run `cursor-agent login`',
    _ => 'log in to the agent in a terminal',
  };

  @override
  bool operator ==(Object other) => other is RcKind && other.wire == wire;

  @override
  int get hashCode => wire.hashCode;

  @override
  String toString() => 'RcKind($wire)';
}

/// The create-time default kind (matches the guest's `DefaultKind`).
const RcKind defaultRcKind = RcKind.claudeRc;

/// Pane-derived liveness of a session. Never stored — shed-ext-rc classifies it
/// from a `capture-pane` on demand and reports it in the DTO.
enum RcState {
  starting('starting'),
  ready('ready'),
  reconnecting('reconnecting'),
  needsTrust('needs-trust'),
  needsAuth('needs-auth'),
  dead('dead');

  const RcState(this.wire);

  final String wire;

  /// Decode a wire value. An unknown state from a newer binary is treated as
  /// `starting` (transient) rather than `dead`, so a forward-compat session is
  /// never shown as gone.
  static RcState fromWire(String? s) {
    for (final st in RcState.values) {
      if (st.wire == s) return st;
    }
    return RcState.starting;
  }
}

/// One RC session as reported by the `shed-ext-rc` guest binary (the neutral,
/// target-agnostic DTO — see shed-extensions internal/rc `Session` and the
/// shared `rcSessionDtoSchema`). The app supplies the server/shed context, so the
/// wire `target` field is not modeled here. `state`/`url` are derived by the
/// binary and trusted as-is.
class RcSession {
  const RcSession({
    required this.slug,
    required this.tmuxSession,
    required this.displayName,
    required this.kind,
    required this.state,
    required this.managed,
    this.workdir,
    this.url,
    this.id,
    this.createdBy,
    this.createdAt,
    this.targetLabel,
  });

  final String slug;
  final String tmuxSession;
  final String displayName;
  final RcKind kind;
  final RcState state;

  /// True when SHED_RC_V was present (created under the convention v2).
  final bool managed;
  final String? workdir;
  final String? url;
  final String? id;
  final String? createdBy;
  final String? createdAt;
  final String? targetLabel;

  bool get isReady => state == RcState.ready;
  bool get hasUrl => url != null && url!.isNotEmpty;

  /// Decode a DTO object. [displayNameFallback] supplies a name when the session
  /// stored none (legacy/unmanaged); it receives the slug.
  factory RcSession.fromJson(
    Map<String, Object?> j, {
    String Function(String slug)? displayNameFallback,
  }) {
    final slug = (j['slug'] as String?) ?? '';
    final storedName = _str(j['display_name']);
    return RcSession(
      slug: slug,
      tmuxSession: (j['tmux_session'] as String?) ?? '',
      displayName:
          storedName ??
          displayNameFallback?.call(slug) ??
          (slug.isEmpty ? '?' : slug),
      kind: RcKind.fromWire(j['kind'] as String?),
      state: RcState.fromWire(j['state'] as String?),
      managed: j['managed'] == true,
      workdir: _str(j['workdir']),
      url: _str(j['url']),
      id: _str(j['id']),
      createdBy: _str(j['created_by']),
      createdAt: _str(j['created_at']),
      targetLabel: _str(j['target_label']),
    );
  }
}

/// Trim a value to a non-empty string, or null (the DTO omits unknown fields, but
/// be tolerant of an empty string sneaking through).
String? _str(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}
