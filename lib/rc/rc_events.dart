import 'dart:convert';

import '../core/sse_parser.dart';
import '../core/text_sanitize.dart';
import 'rc_models.dart';

/// The server-side aggregate rc activity stream (`GET /api/rc/events`, SSE). One
/// stream a client subscribes to for live rc activity across every shed on a
/// host. Each upstream hub envelope has its `shed` field server-filled; the
/// synthetic `hub.unavailable` / `shed.stopped` events are server-minted (a
/// guest hub can't spoof them). Mirrors the envelopes in `internal/api/rcevents.go`.
///
/// SSE here is best-effort notification, not durable delivery: on reconnect the
/// client refetches snapshots (overview / messages) rather than replaying.

/// A parsed rc event. The forwarded payload fields (slug/activity/seq/…) are
/// guest-controlled and treated as untrusted; `shed` is server-corrected.
sealed class RcEvent {
  const RcEvent();

  /// The host (shed name) an event pertains to — server-filled on every event.
  String get shed;
}

/// `event: activity.changed` — a session's live activity (and lifecycle state)
/// moved. `data: {shed, slug, activity, activity_at, state}`, plus an optional
/// `last_message` (the sanitized preview that rides with the activity
/// dimension) when the hub includes it — decoded tolerantly so a card's
/// subtitle can patch live alongside the badge instead of waiting for an
/// overview refetch.
class RcActivityChanged extends RcEvent {
  const RcActivityChanged({
    required this.shed,
    required this.slug,
    this.activity,
    this.activityAt,
    this.state,
    this.lastMessage,
  });
  @override
  final String shed;
  final String slug;
  final RcActivity? activity;
  final String? activityAt;
  final RcState? state;
  final String? lastMessage;
}

/// `event: session.updated` — a session was created/killed or its lifecycle
/// changed. `data: {shed, slug, session}`. The nested `session` is the display
/// subset; we extract the activity/state/last_message dimensions from it. An
/// absent/null `session` means the session is GONE (a kill) — [removed] is set
/// and the overlay drops its patch entirely.
class RcSessionUpdated extends RcEvent {
  const RcSessionUpdated({
    required this.shed,
    required this.slug,
    this.activity,
    this.state,
    this.lastMessage,
    this.removed = false,
  });
  @override
  final String shed;
  final String slug;
  final RcActivity? activity;
  final RcState? state;
  final String? lastMessage;

  /// True when the event carried no session body (the session was killed):
  /// the overlay must remove the (shed, slug) patch, not merge stale fields.
  final bool removed;
}

/// `event: message.appended` — a new feed message landed. `data: {shed, slug,
/// seq}`. Notification only: the body comes from a targeted /messages fetch, so
/// fan-out stays tiny and drop-safe.
class RcMessageAppended extends RcEvent {
  const RcMessageAppended({
    required this.shed,
    required this.slug,
    required this.seq,
  });
  @override
  final String shed;
  final String slug;
  final int seq;
}

/// `event: hub.unavailable` — a shed's upstream hub connection dropped; that
/// host's live activity is stale until it reconnects.
class RcHubUnavailable extends RcEvent {
  const RcHubUnavailable(this.shed);
  @override
  final String shed;
}

/// `event: shed.stopped` — a shed left candidacy (stopped/deleted); its reader
/// tore down.
class RcShedStopped extends RcEvent {
  const RcShedStopped(this.shed);
  @override
  final String shed;
}

/// Decode one SSE record into a typed [RcEvent], or null for an unknown event
/// name, a non-object data payload, or a payload missing its required keys (so a
/// malformed frame is dropped, never rendered).
RcEvent? parseRcEvent(SseRawEvent e) {
  final data = _tryObj(e.data);
  if (data == null) return null;
  final shed = _str(data['shed']);
  final slug = _str(data['slug']);
  switch (e.event) {
    case 'activity.changed':
      if (shed == null || slug == null) return null;
      return RcActivityChanged(
        shed: shed,
        slug: slug,
        // Tolerant read (_str, never a raw cast): a malformed guest frame with
        // a non-string value must be dropped/nulled, not thrown — a throw here
        // would kill the SSE stream and turn one bad frame into a reconnect
        // storm.
        activity: RcActivity.fromWire(_str(data['activity'])),
        activityAt: _str(data['activity_at']),
        state: _state(data['state']),
        lastMessage: _cleanMsg(data['last_message']),
      );
    case 'session.updated':
      if (shed == null || slug == null) return null;
      final sess = data['session'];
      // No session body = the session is gone (killed): signal removal so the
      // overlay drops the patch instead of retaining every stale field.
      if (sess is! Map<String, Object?>) {
        return RcSessionUpdated(shed: shed, slug: slug, removed: true);
      }
      return RcSessionUpdated(
        shed: shed,
        slug: slug,
        activity: RcActivity.fromWire(_str(sess['activity'])),
        state: _state(sess['state']),
        lastMessage: _cleanMsg(sess['last_message']),
      );
    case 'message.appended':
      if (shed == null || slug == null) return null;
      final seq = data['seq'];
      if (seq is! num) return null;
      return RcMessageAppended(shed: shed, slug: slug, seq: seq.toInt());
    case 'hub.unavailable':
      if (shed == null) return null;
      return RcHubUnavailable(shed);
    case 'shed.stopped':
      if (shed == null) return null;
      return RcShedStopped(shed);
    default:
      return null;
  }
}

/// The (shed, slug) identity a live patch is keyed by across a host.
typedef RcSessionKey = ({String shed, String slug});

/// The live overlay a session card merges over its base overview snapshot: the
/// last activity/state/message the SSE stream reported, plus the latest feed seq
/// (which the watch view watches to trigger a targeted /messages fetch). Absent
/// fields fall through to the base session.
class LiveActivity {
  const LiveActivity({
    this.activity,
    this.state,
    this.lastMessage,
    this.lastSeq,
  });
  final RcActivity? activity;
  final RcState? state;
  final String? lastMessage;
  final int? lastSeq;
}

/// A host's live-activity overlay: a map of (shed, slug) → [LiveActivity],
/// folded from the SSE event stream. Immutable — [apply] returns a new overlay
/// so Riverpod `.select` sees a fresh value. Degrading events (hub.unavailable /
/// shed.stopped) drop that shed's patches so cards fall back to the last
/// overview snapshot rather than showing stale live badges.
class ActivityOverlay {
  const ActivityOverlay(this.patches);
  final Map<RcSessionKey, LiveActivity> patches;

  static const ActivityOverlay empty = ActivityOverlay(
    <RcSessionKey, LiveActivity>{},
  );

  LiveActivity? lookup(String shed, String slug) =>
      patches[(shed: shed, slug: slug)];

  ActivityOverlay apply(RcEvent ev) {
    switch (ev) {
      case RcActivityChanged():
        final key = (shed: ev.shed, slug: ev.slug);
        final prev = patches[key];
        return _with(
          key,
          _suppressed(
            LiveActivity(
              activity: ev.activity,
              state: ev.state ?? prev?.state,
              // A payload-carried preview supersedes the held one — this is
              // what lets the card's subtitle update live with the badge.
              lastMessage: ev.lastMessage ?? prev?.lastMessage,
              lastSeq: prev?.lastSeq,
            ),
          ),
        );
      case RcSessionUpdated():
        final key = (shed: ev.shed, slug: ev.slug);
        // A kill (no session body) removes the patch entirely — merging over a
        // gone session would keep stale live fields alive forever.
        if (ev.removed) return _dropKey(key);
        final prev = patches[key];
        return _with(
          key,
          _suppressed(
            LiveActivity(
              activity: ev.activity ?? prev?.activity,
              state: ev.state ?? prev?.state,
              lastMessage: ev.lastMessage ?? prev?.lastMessage,
              lastSeq: prev?.lastSeq,
            ),
          ),
        );
      case RcMessageAppended():
        final key = (shed: ev.shed, slug: ev.slug);
        final prev = patches[key];
        return _with(
          key,
          LiveActivity(
            activity: prev?.activity,
            state: prev?.state,
            lastMessage: prev?.lastMessage,
            lastSeq: ev.seq,
          ),
        );
      case RcHubUnavailable():
        return _dropShed(ev.shed);
      case RcShedStopped():
        return _dropShed(ev.shed);
    }
  }

  /// The whole-dimension suppression rule, mirroring the Go server's
  /// `DisplayActivity` + `toSessionRC`: a blocking lifecycle state
  /// (needs-trust/needs-auth/dead) drops activity AND last_message — a stale
  /// last_message on a dead/gated row would present pre-death context as
  /// current. The state itself (and lastSeq) is retained.
  LiveActivity _suppressed(LiveActivity v) {
    final st = v.state;
    if (st == null || rcStatePermitsActivity(st)) return v;
    return LiveActivity(state: st, lastSeq: v.lastSeq);
  }

  ActivityOverlay _with(RcSessionKey key, LiveActivity v) =>
      ActivityOverlay({...patches, key: v});

  ActivityOverlay _dropKey(RcSessionKey key) {
    if (!patches.containsKey(key)) return this;
    final next = {...patches}..remove(key);
    return ActivityOverlay(next);
  }

  ActivityOverlay _dropShed(String shed) {
    if (!patches.keys.any((k) => k.shed == shed)) return this;
    return ActivityOverlay({
      for (final e in patches.entries)
        if (e.key.shed != shed) e.key: e.value,
    });
  }
}

RcState? _state(Object? v) =>
    v is String && v.isNotEmpty ? RcState.fromWire(v) : null;

/// Tolerant last-message read: non-string → null, plus a client-side strip of
/// Unicode format characters (bidi overrides etc.) the hub does not remove.
String? _cleanMsg(Object? v) {
  final s = _str(v);
  if (s == null) return null;
  final t = stripFormatChars(s).trim();
  return t.isEmpty ? null : t;
}

Map<String, Object?>? _tryObj(String s) {
  try {
    final d = jsonDecode(s);
    return d is Map<String, Object?> ? d : null;
  } on FormatException {
    return null;
  }
}

String? _str(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}
