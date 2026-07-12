import 'package:flutter/material.dart';

import '../rc/rc_models.dart';
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
/// operator), `idle` is the quiet neutral tone, and `unknown`/absent show no
/// badge at all (indeterminate — the client never invents one).
typedef ActivityDisplay = ({ShedStatusTone tone, bool pulse, String label});

ActivityDisplay? rcActivityDisplay(RcActivity? activity) => switch (activity) {
  RcActivity.working => (
    tone: ShedStatusTone.ok,
    pulse: true,
    label: 'working',
  ),
  RcActivity.needsInput => (
    tone: ShedStatusTone.warn,
    pulse: false,
    label: 'needs input',
  ),
  RcActivity.idle => (tone: ShedStatusTone.idle, pulse: false, label: 'idle'),
  RcActivity.unknown || null => null,
};

/// The activity badge to render for a session, honoring the "lifecycle trumps
/// activity" gate: null when [state] suppresses activity (needs-*/dead) or the
/// [activity] isn't renderable. Centralizes the gate so every activity-badge
/// site shares one rule.
ActivityDisplay? rcActivityBadge(RcState state, RcActivity? activity) =>
    rcStatePermitsActivity(state) ? rcActivityDisplay(activity) : null;

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
