/// RC Session Convention v2 kind. `<tool>-<mode>` so the model can grow to other
/// agents later; `shell` is tool-agnostic. Mirrors shed-extensions internal/rc
/// `Kind` and the shared `rcKindSchema`.
///   claudeRc      – interactive `claude` REPL with `/rc`
///   claudeBroker  – the `claude remote-control` multiplexer/broker
///   shell         – plain login bash
enum RcKind {
  claudeBroker('claude-broker'),
  claudeRc('claude-rc'),
  shell('shell');

  const RcKind(this.wire);

  /// The on-wire string (the value stored in SHED_RC_KIND and passed to --kind).
  final String wire;

  /// Decode a wire value. An unrecognized/foreign kind reads as the
  /// legacy/unmanaged fallback (`claude-broker`), never dropping the session —
  /// deliberately different from [defaultRcKind] (the create-time default).
  static RcKind fromWire(String? s) {
    for (final k in RcKind.values) {
      if (k.wire == s) return k;
    }
    return RcKind.claudeBroker;
  }

  /// Whether this kind accepts a typed kickoff line (claude-rc → a prompt,
  /// shell → a command). claude-broker's input is the remote URL, not the pane.
  bool get acceptsPrompt => this != RcKind.claudeBroker;

  /// Whether this kind runs claude (and so can surface trust/auth states).
  bool get runsClaude => this != RcKind.shell;
}

/// The create-time default kind (matches shared `DEFAULT_RC_KIND`).
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
