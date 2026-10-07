import '../src/rust/api/dto_lane.dart';
import '../src/rust/api/lane.dart';

/// How a craze session's lane is opened — by its machine's craze source, on
/// the row's hostId. Production is `MachineFeed.openCrazeLane`.
typedef CrazeLaneOpen = Future<BridgeLane> Function(String hostId);

/// One open lane, as [LaneController] holds it — deliberately opaque.
///
/// The controller never touches a `BridgeLane`: it holds a handle it got from a
/// [LaneSource] and hands the same handle back for every verb. That is what
/// makes the controller's whole lifecycle — the open order, the generation
/// fence, the backoff, the reconciliation — testable in a plain `flutter test`
/// with no native library loaded.
abstract interface class LaneHandle {}

/// **The bridge, as one interface** (plan 018 §3.11).
///
/// Every lane call Dart makes, in one place, so a widget test can stub them.
/// The production implementation is [BridgeLaneSource] and is a pure
/// pass-through — there is no logic here to get wrong, which is the point: the
/// logic is in [LaneController], and the seam exists so that logic can be
/// exercised without FRB.
///
/// Note what is NOT here: anything that folds. Dart pulls one atomic snapshot
/// and merges it by the `full` flag; the fold is Rust's (`shed_app::lane_view`).
abstract interface class LaneSource {
  Future<LaneHandle> open(BridgeLaneSpec spec);

  /// Open a CRAZE session's lane: [open] is the machine feed's
  /// (`MachineFeed.openCrazeLane` — the lane its craze source opens on the
  /// row's hostId, plan 025 §3.7.2), and the answer is the same [LaneHandle]
  /// every other verb here takes. No spec and no forward: a craze lane reaches
  /// its session through the source's own dial.
  Future<LaneHandle> openCraze(CrazeLaneOpen open, String hostId);

  /// One `true` per "something changed, take a snapshot". A second call on the
  /// same handle is refused Rust-side rather than splitting the nudges.
  Stream<bool> nudges(LaneHandle handle);

  /// **The one read**, and the nudge acknowledgement: sync, atomic, and it
  /// clears the dirty bit. `sinceSeq` null asks for the whole generation.
  ///
  /// It is also where the session's capabilities, settings and live row are
  /// read: they ride the lane's stream (plan 025 §3.2.1), so there is no
  /// separate capabilities call to cache at open. It keeps answering after
  /// [close], with the last view.
  BridgeLaneSnapshot snapshot(LaneHandle handle, BigInt? sinceSeq);

  Future<void> send(
    LaneHandle handle, {
    required String text,
    required BridgeSendMode mode,
  });

  Future<void> cancel(LaneHandle handle);

  Future<void> answer(
    LaneHandle handle, {
    required String approvalId,
    required BridgeLaneAnswer answer,
  });

  /// Synchronous teardown. Idempotent; Rust's `Drop` is the backstop.
  void close(LaneHandle handle);
}

/// The production [LaneSource]: the generated FRB functions, unadorned.
class BridgeLaneSource implements LaneSource {
  const BridgeLaneSource();

  @override
  Future<LaneHandle> open(BridgeLaneSpec spec) async =>
      _BridgeLaneHandle(await laneOpen(spec: spec));

  @override
  Future<LaneHandle> openCraze(CrazeLaneOpen open, String hostId) async =>
      _BridgeLaneHandle(await open(hostId));

  @override
  Stream<bool> nudges(LaneHandle handle) => laneNudges(lane: _lane(handle));

  @override
  BridgeLaneSnapshot snapshot(LaneHandle handle, BigInt? sinceSeq) =>
      laneSnapshot(lane: _lane(handle), sinceSeq: sinceSeq);

  @override
  Future<void> send(
    LaneHandle handle, {
    required String text,
    required BridgeSendMode mode,
  }) => laneSend(lane: _lane(handle), text: text, mode: mode);

  @override
  Future<void> cancel(LaneHandle handle) => laneCancel(lane: _lane(handle));

  @override
  Future<void> answer(
    LaneHandle handle, {
    required String approvalId,
    required BridgeLaneAnswer answer,
  }) => laneAnswer(lane: _lane(handle), approvalId: approvalId, answer: answer);

  @override
  void close(LaneHandle handle) {
    final lane = _lane(handle);
    laneClose(lane: lane);
    // The sync close is the teardown (it aborts the pump and the forwarder);
    // dropping the opaque afterwards releases this side's Arc explicitly rather
    // than waiting on the finalizer — the `shedClientProvider` precedent. Both
    // are idempotent, and `Drop` remains the backstop for either.
    if (!lane.isDisposed) lane.dispose();
  }

  static BridgeLane _lane(LaneHandle handle) =>
      (handle as _BridgeLaneHandle).lane;
}

class _BridgeLaneHandle implements LaneHandle {
  _BridgeLaneHandle(this.lane);

  final BridgeLane lane;
}
