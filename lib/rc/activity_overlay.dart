import '../src/rust/api/dto_rc.dart';
import '../src/rust/api/watcher.dart';

/// The live overlay a session card merges over its base overview snapshot: the
/// last activity/state/message the rc-events stream reported, plus the latest
/// feed seq (which the watch view watches to trigger a targeted /messages fetch).
/// Absent fields fall through to the base session.
///
/// The FOLD and the blocking-state suppression now live in Rust
/// (`RcEventsWatcher` → the bridge forwarder), so Dart only wraps the delivered
/// [BridgeOverlayEntry] snapshot for `(shed, slug)` lookup. Immutable + value
/// equality so a Riverpod `.select` on `lookup(...)` only rebuilds on a real
/// change. `lastSeq` stays the bridge's `BigInt` end-to-end (the feed seq is a
/// u64; narrowing to a Dart `int` was lossy on 32-bit and pointless — the watch
/// screen compares it against `BigInt` cursors directly).
class LiveActivity {
  const LiveActivity({
    this.activity,
    this.state,
    this.lastMessage,
    this.lastSeq,
  });

  final BridgeRcActivity? activity;
  final BridgeRcState? state;
  final String? lastMessage;
  final BigInt? lastSeq;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveActivity &&
          runtimeType == other.runtimeType &&
          activity == other.activity &&
          state == other.state &&
          lastMessage == other.lastMessage &&
          lastSeq == other.lastSeq;

  @override
  int get hashCode =>
      activity.hashCode ^
      state.hashCode ^
      lastMessage.hashCode ^
      lastSeq.hashCode;
}

/// A host's live-activity overlay: a `(shed, slug)` → [LiveActivity] lookup built
/// from the bridge's folded [BridgeOverlayEntry] snapshot. The watcher (Rust)
/// owns the folding + degrading-event drops + suppression; this is a thin
/// immutable Dart wrapper the UI reads via [lookup].
class ActivityOverlay {
  ActivityOverlay(List<BridgeOverlayEntry> entries)
    : _byKey = {for (final e in entries) (e.shed, e.slug): e};

  final Map<(String, String), BridgeOverlayEntry> _byKey;

  /// The empty overlay every consumer starts on (before the first event, or on a
  /// server that doesn't advertise rc-events).
  static final ActivityOverlay empty = ActivityOverlay(const []);

  /// The live patch for `(shed, slug)`, or null when the overlay holds none (the
  /// card falls through to its base overview snapshot).
  LiveActivity? lookup(String shed, String slug) {
    final e = _byKey[(shed, slug)];
    if (e == null) return null;
    return LiveActivity(
      activity: e.activity,
      state: e.state,
      lastMessage: e.lastMessage,
      lastSeq: e.lastSeq,
    );
  }
}
