import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import 'duplex_pump.dart';

/// Opens one forwarded channel to `127.0.0.1:<remotePort>` on the far side.
///
/// The seam that makes [LaneForward] testable without an sshd: dartssh2's
/// `SSHForwardChannel` is only ever handed out by a live [SSHClient]. See
/// [DuplexChannel].
typedef LaneDial = Future<DuplexChannel> Function(int remotePort);

/// **A local port that reaches `127.0.0.1:<remotePort>` on a machine** — the
/// phone's `ssh -L`, for an agent lane's HTTP/SSE server.
///
/// The same shape as `RoostTunnel`, over a `direct-tcpip` channel instead of an
/// exec, and for the same reason: the shared Rust core is handed nothing but a
/// local port and does everything above it (the HTTP client, the SSE
/// subscription, the reconnect/backoff). Both are [PortListener]s, so the
/// plan-012 invariant — **the local port is fixed for this forward's life**,
/// and a dropped link is re-dialled underneath it on the next accepted
/// connection — is one implementation, not two.
///
/// [close] frees the port and every live channel but **never** the [SSHClient]:
/// the machine's feed owns that, and a lane's forward is one of several things
/// riding it.
class LaneForward {
  LaneForward._(this._listener, this.remotePort);

  final PortListener _listener;

  /// The port on the machine's own loopback that this forward reaches.
  final int remotePort;

  /// The local port to hand to Rust. Fixed for this forward's life.
  int get port => _listener.port;

  /// Whether the forward has been closed (its port is no longer served).
  bool get isClosed => _listener.isClosed;

  /// Open a forward to [remotePort] on the machine [connect] reaches.
  ///
  /// [connect] is called once per accepted local connection — that is what lets
  /// a phone that changed networks recover without the local port moving.
  static Future<LaneForward> open({
    required Future<SSHClient> Function() connect,
    required int remotePort,
  }) {
    return openWithDial(
      dial: (port) async {
        final client = await connect();
        // Loopback on the FAR side: an agent's server binds the machine's own
        // 127.0.0.1, which is exactly why it needs forwarding to be reachable.
        return _SshForward(await client.forwardLocal('127.0.0.1', port));
      },
      remotePort: remotePort,
    );
  }

  /// [open] with the SSH half replaced. See [LaneDial].
  @visibleForTesting
  static Future<LaneForward> openWithDial({
    required LaneDial dial,
    required int remotePort,
  }) async {
    final listener = await PortListener.bind(
      dial: () => dial(remotePort),
      log: (message) {
        if (kDebugMode) {
          debugPrint('LaneForward[:$remotePort] $message');
        }
      },
    );
    return LaneForward._(listener, remotePort);
  }

  /// Close the forward: stop accepting, tear down every live channel, free the
  /// port. Idempotent. Does NOT close the SSH connection — see the class
  /// comment.
  Future<void> close() => _listener.close();
}

/// A borrowed [LaneForward] — what a lane holds instead of the forward itself.
///
/// The forward is shared: two screens on two sessions of the same agent server
/// reach the same `(machine, remotePort)` and must not open two of them. So a
/// lane is given a lease, and [release] is the only thing it may do with it —
/// the last release closes the forward, and every early return in the lane's
/// open path therefore has exactly one obligation.
class LaneForwardLease {
  LaneForwardLease._(this._registry, this._slot, this.port);

  final ForwardRegistry _registry;
  final _ForwardSlot _slot;

  /// The LOCAL port to hand to Rust. Fixed for the forward's life, so it is
  /// safe to keep across a reconnect.
  final int port;

  bool _released = false;

  /// The far-side port this lease reaches.
  int get remotePort => _slot.remotePort;

  /// Whether this lease still names a live forward.
  ///
  /// False once [release] has been called, and also once the machine's feed has
  /// torn down — a lane that finds an invalid lease must re-acquire rather than
  /// keep writing into a port that no longer reaches the machine.
  bool get isValid => !_released && !_slot.detached;

  /// Give the forward back. Idempotent; the last release closes it.
  Future<void> release() async {
    if (_released) return;
    _released = true;
    await _registry._release(_slot);
  }
}

/// One `(machine, remotePort)` forward, plus who wants it.
class _ForwardSlot {
  _ForwardSlot(this.remotePort);

  final int remotePort;

  /// The shared open. Every acquire in the same generation awaits THIS future,
  /// which is what makes the registry single-flight.
  late final Future<LaneForward> opening;

  /// Leases outstanding **plus acquires still in flight**. Counting the
  /// in-flight ones is what gives a forward nobody ended up wanting somebody to
  /// close it: the acquire that started the dial gives its own count back on
  /// the way out, whether it hands over a lease or throws.
  int users = 0;

  /// Set once [opening] succeeds; nulled by [ForwardRegistry._closeNow], so a
  /// close cannot happen twice.
  LaneForward? forward;

  /// Set when this slot stops being the registry's — it has been closed, its
  /// open failed, or the feed tore down. Invalidates every lease on it.
  bool detached = false;
}

/// **Refcounted, single-flight forwards, keyed by remote port.**
///
/// Owned by a machine's feed (its forwards ride that one `SSHClient`) and
/// separated from it for the same reason `DialDedupe` and `releaseIfStopped`
/// are: the bookkeeping is where the bugs live, and a feed cannot be built in a
/// unit test — it dials a real SSH client and holds an FRB opaque handle — while
/// the bookkeeping has nothing to do with what is being opened. With a fake
/// [openForward] every race below is testable; see
/// `test/ssh/lane_forward_test.dart`.
///
/// The rules, all four of which fail silently if they are wrong:
///
/// * **Single-flight.** The slot is inserted BEFORE the first await, so two
///   acquires that land in the same turn share one open. Two forwards on one
///   port means two listeners, two SSH channels and a Rust client talking to
///   whichever one it happened to be handed.
/// * **Refcounted.** [acquire] counts a user before it awaits; the last
///   [LaneForwardLease.release] closes the forward. A lease that outlives its
///   holder is a port left listening on a phone in someone's pocket.
/// * **A failed open leaves nothing behind.** The slot is removed and the error
///   reaches every waiter — a poisoned slot would make every later acquire on
///   that port await a future that already failed.
/// * **A teardown during the open still closes it.** There is nothing to close
///   while the dial is in flight, so the slot is detached and the acquire that
///   started the dial closes the forward when it lands — an abandoned acquire
///   still runs, so that holds even if its caller walked away. [closeAll]
///   deliberately does not wait for it: that would put an SSH dial's whole
///   connect timeout inside a feed teardown.
class ForwardRegistry {
  ForwardRegistry({required this.openForward});

  /// Opens one forward to a remote port. The seam: production hands over
  /// [LaneForward.open] bound to the feed's `_connect`, a test hands over
  /// anything.
  final Future<LaneForward> Function(int remotePort) openForward;

  final Map<int, _ForwardSlot> _slots = <int, _ForwardSlot>{};

  /// How many forwards are open or opening. Diagnostics and tests only.
  @visibleForTesting
  int get liveForwards => _slots.length;

  /// Borrow the forward for [remotePort], opening it if nobody else has.
  ///
  /// Throws whatever the open threw (the SSH dial's own failure, so the caller
  /// can tell "the machine is asleep" from "nothing is listening on that
  /// port"), and a [StateError] if the feed tore down while it was opening.
  Future<LaneForwardLease> acquire(int remotePort) async {
    var slot = _slots[remotePort];
    if (slot == null) {
      // Inserted before the first await: an await here and the acquire beside
      // us would see an empty map and open a second forward.
      final fresh = _ForwardSlot(remotePort);
      _slots[remotePort] = fresh;
      // `sync` so a seam that throws synchronously still lands as a failed
      // future the handlers below can clean up after, rather than escaping with
      // a half-built slot left in the map.
      final opening = Future<LaneForward>.sync(() => openForward(remotePort));
      fresh.opening = opening;
      unawaited(
        opening.then<void>(
          // Recorded, never acted on. Closing a forward is [_release]'s job,
          // and every slot has at least the acquire that created it awaiting
          // this future — so a forward that lands into a torn-down registry is
          // closed by that acquire's own give-back below, even if its caller
          // walked away. A second close here would be a second path to the
          // same place, and the two would have to agree forever.
          (forward) => fresh.forward = forward,
          onError: (Object _) {
            // The waiters all see the error through `opening`; what must not
            // survive is the slot, or the next acquire on this port would await
            // a future that has already failed.
            _detach(fresh);
          },
        ),
      );
      slot = fresh;
    }
    final pending = slot;
    pending.users++;
    try {
      final forward = await pending.opening;
      if (pending.detached) {
        // A teardown won the race, so nobody may hold this. The give-back in
        // the catch below is what closes the forward the dial just landed —
        // this is the only path there when the teardown ran first.
        throw StateError('the machine feed was stopped');
      }
      return LaneForwardLease._(this, pending, forward.port);
    } catch (_) {
      await _release(pending);
      rethrow;
    }
  }

  /// Close every forward and invalidate every lease. Idempotent.
  ///
  /// A forward still opening has nothing to close yet, so it is detached here
  /// and closed by the acquire that started it, once the dial lands — teardown
  /// must not block on an SSH dial that may take as long as the connect
  /// timeout.
  Future<void> closeAll() async {
    final slots = _slots.values.toList();
    _slots.clear();
    await Future.wait(slots.map(_closeNow));
  }

  Future<void> _release(_ForwardSlot slot) async {
    if (slot.users > 0) slot.users--;
    if (slot.users > 0) return;
    // Nothing to close: this release came from an acquire whose open FAILED (or
    // whose slot was torn down under it), which is the only way the count can
    // reach zero with no forward — a lease cannot exist before the open lands,
    // so a release can never arrive while the dial is still in flight.
    if (slot.forward == null) return;
    await _closeNow(slot);
  }

  Future<void> _closeNow(_ForwardSlot slot) async {
    _detach(slot);
    final forward = slot.forward;
    slot.forward = null;
    await forward?.close();
  }

  void _detach(_ForwardSlot slot) {
    slot.detached = true;
    // Only if it is still OURS: a later acquire may already have replaced it.
    if (identical(_slots[slot.remotePort], slot)) {
      _slots.remove(slot.remotePort);
    }
  }
}

/// Production [DuplexChannel]: one dartssh2 `direct-tcpip` channel.
class _SshForward implements DuplexChannel {
  _SshForward(this._channel);

  final SSHForwardChannel _channel;

  @override
  StreamSink<List<int>> get sink => _channel.sink;

  @override
  Stream<Uint8List> get stream => _channel.stream;

  /// A forwarded TCP channel has no diagnostic band — see [DuplexChannel.stderr]
  /// for why that is null rather than an empty stream.
  @override
  Stream<Uint8List>? get stderr => null;

  @override
  Future<void> get done => _channel.done;

  /// Waits for the remote to close too (dartssh2's documented behaviour), which
  /// is why [DuplexPump] bounds it and falls back to [destroy].
  @override
  Future<void> close() => _channel.close();

  @override
  void destroy() => _channel.destroy();
}
