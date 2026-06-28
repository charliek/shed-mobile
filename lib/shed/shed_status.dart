import 'package:flutter/material.dart';

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
