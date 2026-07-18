import 'dart:math';

import '../core/app_version.dart';
import '../src/rust/api/dto_rc.dart';

/// UI-only helpers, constants, and display mappings that live on the generated
/// bridge RC types ([BridgeRcKind]/[BridgeRcState]/[BridgeRcActivity]/
/// [BridgeRcCapabilities]) — the parts with no Rust home. The wire↔enum mapping
/// and the predicates below mirror `shed_core::rc` (`crates/shed-core/src/rc.rs`)
/// and the guest's `rc.Kind`/`rc.State`/`rc.Activity`; the permission-mode sets
/// mirror `shed_core::rc`'s `GENERIC_PERMISSION_MODES`/`CLAUDE_EXTRA_MODES`/
/// `DEFAULT_RC_PERMISSION_MODE` (and are what the create-form dropdown OFFERS).
/// The permission-mode *validation authority* is Rust: `create_invocation`
/// (behind `rcCreateInvocation`) runs `validate_permission_mode`, so an invalid
/// mode is rejected there, not here — these sets only gate what the UI presents.

// ---- RcKind ---------------------------------------------------------------

extension BridgeRcKindUi on BridgeRcKind {
  /// The on-wire string (stored in SHED_RC_KIND / passed to `--kind`). An
  /// unknown kind preserves its raw value verbatim (unknown-kind policy).
  String get wire => switch (this) {
    BridgeRcKind_ClaudeRc() => 'claude-rc',
    BridgeRcKind_ClaudeBroker() => 'claude-broker',
    BridgeRcKind_Codex() => 'codex',
    BridgeRcKind_Opencode() => 'opencode',
    BridgeRcKind_Cursor() => 'cursor',
    BridgeRcKind_Shell() => 'shell',
    BridgeRcKind_Other(:final raw) => raw,
  };

  /// False for a preserved-raw unknown/foreign kind — the neutral-render signal.
  bool get known => this is! BridgeRcKind_Other;

  /// Whether this kind accepts a typed kickoff line (claude-rc/codex/opencode/
  /// cursor → a prompt, shell → a command). claude-broker's input is its remote
  /// URL, not the pane; an unknown kind is not promptable. Mirrors
  /// `RcKind::accepts_typed_input`.
  bool get acceptsPrompt => known && this is! BridgeRcKind_ClaudeBroker;

  /// Whether this kind runs claude (one of the two claude kinds → claude's full
  /// `--permission-mode` set + URL affordances). Mirrors `RcKind::runs_claude`.
  bool get runsClaude =>
      this is BridgeRcKind_ClaudeRc || this is BridgeRcKind_ClaudeBroker;

  /// Whether this kind carries an autonomy/permission posture: every known agent
  /// kind does; `shell` has none, and an unknown kind renders neutrally with
  /// none. Mirrors `RcKind::has_permission_mode`.
  bool get hasPermissionMode => known && this is! BridgeRcKind_Shell;

  /// The tool token this kind's agent maps to under `capabilities.agents`, or
  /// null for a kind with no installable agent (`shell`) or an unknown kind.
  /// Mirrors `RcKind::tool`.
  String? get tool => switch (wire) {
    'claude-rc' || 'claude-broker' => 'claude',
    'codex' => 'codex',
    'opencode' => 'opencode',
    'cursor' => 'cursor',
    _ => null,
  };

  /// The per-agent login remediation for this kind's `needs-auth` state. Mirrors
  /// the guest's `AuthHintFor` and `shed_core::rc::auth_hint`.
  String get authHint => switch (wire) {
    'claude-rc' || 'claude-broker' => 'run `claude` → /login',
    'codex' => 'run `codex` and complete login (`codex login`)',
    'opencode' => 'run `opencode auth login`',
    'cursor' => 'run `cursor-agent login`',
    _ => 'log in to the agent in a terminal',
  };
}

/// The create-time default kind (matches the guest's `DefaultKind`).
const BridgeRcKind defaultRcKind = BridgeRcKind.claudeRc();

/// Every recognized kind, in the pinned capabilities wire order. Mirrors the
/// Rust core `RcKind` variant set.
const List<BridgeRcKind> rcKindValues = [
  BridgeRcKind.claudeBroker(),
  BridgeRcKind.claudeRc(),
  BridgeRcKind.codex(),
  BridgeRcKind.opencode(),
  BridgeRcKind.cursor(),
  BridgeRcKind.shell(),
];

/// The kinds a create form can offer for creation, in canonical order.
/// `claude-broker` is URL-driven (not create-from-a-form) and an unknown kind is
/// never creatable, so both are excluded. Mirrors `RcKind::creatable`.
const List<BridgeRcKind> rcCreatableKinds = [
  BridgeRcKind.claudeRc(),
  BridgeRcKind.codex(),
  BridgeRcKind.opencode(),
  BridgeRcKind.cursor(),
  BridgeRcKind.shell(),
];

/// Decode a wire value, PRESERVING an unrecognized string as an unknown kind
/// (`BridgeRcKind.other`). Mirrors `RcKind::from_wire`.
BridgeRcKind bridgeRcKindFromWire(String? s) {
  for (final k in rcKindValues) {
    if (k.wire == s) return k;
  }
  return BridgeRcKind.other(raw: s ?? '');
}

// ---- RcState / RcActivity -------------------------------------------------

extension BridgeRcStateUi on BridgeRcState {
  /// The on-wire string (`ready`/`needs-trust`/…). Mirrors `RcState::as_str`.
  String get wire => switch (this) {
    BridgeRcState.starting => 'starting',
    BridgeRcState.ready => 'ready',
    BridgeRcState.reconnecting => 'reconnecting',
    BridgeRcState.needsTrust => 'needs-trust',
    BridgeRcState.needsAuth => 'needs-auth',
    BridgeRcState.dead => 'dead',
  };
}

extension BridgeRcActivityUi on BridgeRcActivity {
  /// The on-wire string (`working`/`needs_input`/…). Mirrors `RcActivity::as_str`.
  String get wire => switch (this) {
    BridgeRcActivity.working => 'working',
    BridgeRcActivity.needsInput => 'needs_input',
    BridgeRcActivity.idle => 'idle',
    BridgeRcActivity.unknown => 'unknown',
  };
}

/// Whether a lifecycle [state] permits showing the live activity dimension. The
/// server already drops activity for needs-trust/needs-auth/dead (lifecycle
/// trumps activity); the client mirrors that gate (`RcState::permits_activity`)
/// so it never invents — or leaves stale — an activity a blocking state hides.
bool rcStatePermitsActivity(BridgeRcState state) => switch (state) {
  BridgeRcState.needsTrust ||
  BridgeRcState.needsAuth ||
  BridgeRcState.dead => false,
  _ => true,
};

// ---- Capabilities ---------------------------------------------------------

extension BridgeRcCapabilitiesUi on BridgeRcCapabilities {
  /// Whether [feature] is advertised (discovery, replacing error-string sniffing).
  bool hasFeature(String feature) => features.contains(feature);

  /// Whether a create form should OFFER [kind]: advertised in [kinds] AND its
  /// backing agent (if any) is installed. `shell` (no agent) is offered whenever
  /// advertised. Mirrors `RcCapabilities::offers`.
  bool offers(BridgeRcKind kind) {
    if (!kinds.contains(kind)) return false;
    final tool = kind.tool;
    if (tool == null) return true;
    return agents[tool]?.installed ?? false;
  }

  /// The creatable kinds this shed offers, in canonical create-form order.
  /// Mirrors `RcCapabilities::creatable_kinds`.
  List<BridgeRcKind> creatableKinds() =>
      rcCreatableKinds.where(offers).toList();
}

extension BridgeRcKindFeaturesUi on BridgeRcKindFeatures {
  /// Whether feed input is gated (`input == "gated"`) — the watch view's input
  /// bar is only ever enabled for a gated kind waiting for input.
  bool get inputGated => input == 'gated';
}

// ---- permission modes -----------------------------------------------------

/// The generic permission tri-state accepted by EVERY kind and mapped per agent
/// by shed-ext-rc (the VM is already the sandbox). Mirrors the guest's
/// `genericPermModes` and `shed_core::rc::GENERIC_PERMISSION_MODES`.
const Set<String> rcGenericPermissionModes = {'default', 'auto', 'skip'};

/// claude's historical `--permission-mode` values, accepted on top of the
/// generic tri-state by the claude kinds ONLY. Mirrors the claude spec's
/// `ExtraModes` and `shed_core::rc::CLAUDE_EXTRA_MODES`.
const Set<String> rcClaudeExtraModes = {
  'acceptEdits',
  'plan',
  'dontAsk',
  'bypassPermissions',
};

/// Every mode a claude kind accepts (generic tri-state + historical set) — also
/// the claude-only create-form dropdown set when the target shed's capabilities
/// are PRESENT. The union of the two component sets, so it can't drift.
const Set<String> rcPermissionModes = {
  ...rcGenericPermissionModes,
  ...rcClaudeExtraModes,
};

/// The claude modes every SHIPPED binary accepts — the pre-generic-perm
/// historical set. The generic `skip` is NEW: an old shed-ext-rc rejects it, so
/// the create form offers only this set when the target shed's capabilities are
/// ABSENT (an old image that can't advertise generic-perm).
const Set<String> rcClaudeHistoricalModes = {
  'default',
  'auto',
  ...rcClaudeExtraModes,
};

/// The permission modes valid for [kind]: the full claude set for the claude
/// kinds, else the generic tri-state. Mirrors `shed_core::rc::permission_modes_for`.
Set<String> permissionModesFor(BridgeRcKind kind) =>
    kind.runsClaude ? rcPermissionModes : rcGenericPermissionModes;

/// The create-time default permission mode. `auto` keeps a session running
/// autonomously; it is a member of both sets, so it is valid for every agent
/// kind. Mirrors `shed_core::rc::DEFAULT_RC_PERMISSION_MODE`.
const String defaultRcPermissionMode = 'auto';

// ---- provenance + slug ----------------------------------------------------

/// Stable tool identifier for SHED_RC_CREATED_BY (must not contain '/').
const String rcToolName = 'shed-mobile';

/// `<tool>/<version>` provenance stored as SHED_RC_CREATED_BY at create time.
/// Supplied to the bridge create builder so the wire value carries the version
/// (the Rust side deliberately owns no version constant).
const String rcCreatedBy = '$rcToolName/$kAppVersion';

/// Slug alphabet without visually-confusable characters (no l/i/o/0/1), so a
/// short slug survives being read off a screen or typed. Port of rc.ts genSlug.
const String _slugAlphabet = 'abcdefghjkmnpqrstuvwxyz23456789';

/// A 6-char slug. [rng] is injectable for deterministic tests; production uses a
/// secure RNG (slugs aren't a secret, but it gives a clean uniform draw).
String genSlug([Random? rng]) {
  final r = rng ?? Random.secure();
  final b = StringBuffer();
  for (var i = 0; i < 6; i += 1) {
    b.write(_slugAlphabet[r.nextInt(_slugAlphabet.length)]);
  }
  return b.toString();
}
