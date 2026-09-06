import 'package:flutter/material.dart';

import '../rc/rc_ui.dart';
import '../src/rust/api/dto_rc.dart';
import '../theme/shed_colors.dart';

/// How a status string renders: the semantic tone (background/foreground), the dot
/// glyph, and whether the dot pulses (a shed/session that's actively coming up).
typedef StatusDisplay = ({ShedStatusTone tone, String dot, bool pulse});

/// Map a server-reported status string — a shed `status` *or* a session `rc.state`
/// — to its display. The single source of truth, mirroring the design's `stat()`
/// table verbatim, so the shed list, the cross-host Sheds view, and the cross-host
/// Sessions view can't drift. Unknown statuses fall back to the neutral idle tone.
StatusDisplay shedStatusTone(String status) => switch (status) {
  'running' ||
  'ready' ||
  'online' => (tone: ShedStatusTone.ok, dot: '●', pulse: false),
  // "starting" (and the create-time variants) pulse; "working"/"reconnecting" are
  // steady-warn.
  'starting' ||
  'creating' ||
  'provisioning' => (tone: ShedStatusTone.warn, dot: '◐', pulse: true),
  'working' ||
  'reconnecting' ||
  'needs-trust' ||
  'needs-auth' => (tone: ShedStatusTone.warn, dot: '◐', pulse: false),
  'stopped' ||
  'idle' ||
  'offline' => (tone: ShedStatusTone.idle, dot: '○', pulse: false),
  'error' || 'dead' => (tone: ShedStatusTone.err, dot: '▲', pulse: false),
  _ => (tone: ShedStatusTone.idle, dot: '○', pulse: false),
};

/// How a live [RcActivity] renders as a badge: tone + pulse + label — or null
/// when nothing should be shown. Reuses the shared [ShedStatusTone] system (so
/// the activity badge sits beside the lifecycle badge in the same visual
/// language) with an activity-specific mapping: `working` pulses in the ok tone
/// (actively producing), `needs_input` is a steady warn (waiting on the
/// operator), `needs_approval` is likewise a steady warn (blocked on a decision
/// rather than on text), `idle` is the quiet neutral tone, and `unknown`/absent
/// show no badge at all (indeterminate — the client never invents one).
typedef ActivityDisplay = ({ShedStatusTone tone, bool pulse, String label});

ActivityDisplay? rcActivityDisplay(
  BridgeRcActivity? activity,
) => switch (activity) {
  BridgeRcActivity.working => (
    tone: ShedStatusTone.ok,
    pulse: true,
    label: 'working',
  ),
  BridgeRcActivity.needsInput => (
    tone: ShedStatusTone.warn,
    pulse: false,
    label: 'needs input',
  ),
  // Blocked on an APPROVAL, not on a prompt (contract v2). Rendered in the
  // warn tone like needs-input because both mean "stopped, waiting for you",
  // but labelled distinctly: whether this phone can actually decide depends
  // on the kind's `approvals` capability, and calling it "needs input" would
  // promise a text box that may not be the answer.
  BridgeRcActivity.needsApproval => (
    tone: ShedStatusTone.warn,
    pulse: false,
    label: 'needs approval',
  ),
  BridgeRcActivity.idle => (
    tone: ShedStatusTone.idle,
    pulse: false,
    label: 'idle',
  ),
  BridgeRcActivity.unknown || null => null,
};

/// The activity badge to render for a session, honoring the "lifecycle trumps
/// activity" gate: null when [state] suppresses activity (needs-*/dead) or the
/// [activity] isn't renderable. Centralizes the gate so every activity-badge
/// site shares one rule.
ActivityDisplay? rcActivityBadge(
  BridgeRcState state,
  BridgeRcActivity? activity,
) => rcStatePermitsActivity(state) ? rcActivityDisplay(activity) : null;

/// The colour of a session card's left edge — what most wants your attention.
///
/// Precedence: a `dead` lifecycle is red; ANY lifecycle the badge renders as a
/// warning is amber, whether or not it suppresses activity — otherwise the edge
/// can contradict the badge sitting next to it. Only once the lifecycle is
/// unremarkable does activity decide: asking for a person outranks merely being
/// busy, and idle says nothing at all. Nothing worth saying returns null, and
/// the card renders without an edge.
///
/// One rule, shared by every card: the point of the edge is a COLUMN that reads
/// at a glance, and a column whose colours mean different things per row would
/// be worse than no colour at all.
Color? sessionRailColor(
  ShedColors shed,
  BridgeRcState state,
  BridgeRcActivity? activity, {
  bool stale = false,
}) {
  // A row we can no longer reach says so by being dimmed; colouring its edge
  // would assert something current about a machine we cannot see.
  if (stale) return null;
  if (state == BridgeRcState.dead) return shed.dotErr;
  // EVERY lifecycle the badge renders as a warning gets the warning edge, not
  // just the ones that suppress activity. `starting` and `reconnecting` permit
  // activity, so gating on `rcStatePermitsActivity` alone let a reconnecting
  // session show a GREEN edge beside an amber `reconnecting` badge — the card
  // contradicting itself, which is worse than either colour alone.
  if (shedStatusTone(state.wire).tone == ShedStatusTone.warn) {
    return shed.dotWarn;
  }
  return switch (activity) {
    BridgeRcActivity.needsInput ||
    BridgeRcActivity.needsApproval => shed.dotWarn,
    BridgeRcActivity.working => shed.dotOk,
    _ => null,
  };
}

/// Agent-kind wire string → accent color (the kind chip's colored left border and
/// the terminal `[kind]` label). Mirrors the design's `agent()` map. Reads raw
/// wire strings (not the [RcKind] enum) because `GET /api/sessions` reports the
/// kind as a string and the enum collapses unknown kinds to claude-broker. Unknown
/// kinds fall back to the neutral shell grey — **never** Claude — so a foreign
/// session can't masquerade as a Claude session.
Color kindColor(ShedColors shed, String kind) {
  final k = kind.toLowerCase();
  if (k.startsWith('claude')) return shed.kindClaude;
  if (k.startsWith('codex')) return shed.kindCodex;
  if (k == 'cursor') return shed.kindCursor;
  if (k == 'opencode') return shed.kindOpencode;
  return shed.kindShell;
}

/// A shed/host backend wire string → its badge colors + label, or null for an
/// unknown or runtime-less backend (no badge). Kept beside [kindColor] (the color
/// tokens live on [ShedColors]; the wire→label mapping lives here, with the other
/// status/kind mappers).
(Color bg, Color fg, String label)? runtimeBadge(
  ShedColors shed,
  String? backend,
) => switch (backend) {
  'vz' => (shed.runtimeVzBg, shed.runtimeVzFg, 'vz'),
  'firecracker' => (shed.runtimeFcBg, shed.runtimeFcFg, 'firecracker'),
  _ => null,
};
