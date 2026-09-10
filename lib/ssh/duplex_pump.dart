import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Uint8List comes through foundation (which also carries kDebugMode,
// debugPrint and @visibleForTesting) — importing dart:typed_data as well is a
// duplicate the analyzer rejects.
import 'package:flutter/foundation.dart';

/// One duplex byte channel to the far side, reduced to the six things a byte
/// pump needs.
///
/// **Why the seam exists:** neither of the two production implementations can
/// be constructed without a live `SSHClient` against a real server — dartssh2's
/// `SSHSession` (a remote exec) and `SSHForwardChannel` (a `direct-tcpip`
/// channel) are both handed out by the client and nothing else — so without
/// this interface every test of the pump below would need an sshd. The two
/// implementations are `_ExecChannel` (in `roost_tunnel.dart`, over the roost
/// exec seam) and `_SshForward` (in `lane_forward.dart`, over the port
/// channel); the wire-level proof that the far side is reached correctly lives
/// in shed's `tests/machine-transport` differential, not here.
abstract class DuplexChannel {
  /// The write half. Closing it sends EOF **without** closing the channel —
  /// see [DuplexPump] for why that must not happen early.
  ///
  /// Typed as `List<int>` because dartssh2 types the two halves differently
  /// (`SSHSession.stdin` is a `StreamSink<Uint8List>`, `SSHForwardChannel.sink`
  /// a `StreamSink<List<int>>`); the pump only ever writes the `Uint8List`
  /// chunks it read off a socket, so the wider type costs nothing.
  StreamSink<List<int>> get sink;

  /// The read half: everything the far side sends.
  Stream<Uint8List> get stream;

  /// The channel's out-of-band diagnostic band, or **null when the transport
  /// has none**.
  ///
  /// For a remote exec this is the process's stderr, and its *closing* is a
  /// fallback end-of-remote hint (see [DuplexPump]). A forwarded TCP channel
  /// has no such band at all, and null says so — handing the pump an
  /// already-closed empty stream instead would fire that hint immediately and
  /// tear every forwarded connection down one grace period after it opened.
  Stream<Uint8List>? get stderr;

  /// Completes when the far side's channel ends.
  Future<void> get done;

  /// Close our end gracefully. **May wait on the remote** (dartssh2's
  /// `SSHForwardChannel.close()` does), so every caller must bound it; the pump
  /// falls back to [destroy].
  Future<void> close();

  /// Force the channel shut in both directions, without waiting for anyone.
  void destroy();
}

/// Opens one channel to the far side, per accepted local socket.
typedef ChannelDial = Future<DuplexChannel> Function();

/// **A fixed local port whose every accepted socket is pumped over a freshly
/// opened [DuplexChannel]** — the local half shared by the roost tunnel and a
/// lane's port forward.
///
/// Binds loopback only, on an OS-assigned port — never a fixed one, so two
/// machines can be served at once and nothing collides with another app.
///
/// **The port is fixed for the listener's whole life**, and that is the
/// load-bearing property (the plan-012 invariant), not an implementation
/// detail. The listening socket outlives any individual SSH connection: when
/// the phone changes networks or wakes from the background, the next accepted
/// connection re-dials underneath the same port. Rust therefore sees an
/// ordinary "connection refused, retry" against a stable address rather than
/// needing a protocol to re-acquire one — which is what lets the reconnect
/// logic be written once, in Rust, for every client.
///
/// Extracted from `RoostTunnel` when a lane's port forward needed the same
/// port lifecycle (plan 018 §3.10) — two copies of this accept/close dance is
/// exactly the duplication that drifts.
///
/// [ChannelDial] is called per accepted connection, so a dropped link is
/// re-established on the next use rather than requiring the port to be torn
/// down and rebuilt. A failed dial closes **that connection only**. The caller
/// owns the `SSHClient` the dial rides: [close] frees the port and every
/// channel, but never a connection this class did not create.
class PortListener {
  PortListener._(this._server, this._dial, this._log);

  final ServerSocket _server;
  final ChannelDial _dial;
  final void Function(String) _log;

  bool _closed = false;
  final Set<DuplexPump> _pumps = <DuplexPump>{};

  /// The local port to hand out. Fixed for this listener's life.
  int get port => _server.port;

  /// Whether the listener has been closed (its port is no longer served).
  bool get isClosed => _closed;

  /// Bind a loopback port and start accepting.
  static Future<PortListener> bind({
    required ChannelDial dial,
    required void Function(String) log,
  }) async {
    final server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    final listener = PortListener._(server, dial, log);
    listener._accept();
    return listener;
  }

  void _accept() {
    _server.listen(
      (socket) async {
        if (_closed) {
          socket.destroy();
          return;
        }
        final DuplexChannel channel;
        try {
          channel = await _dial();
        } catch (error) {
          // A failed connect or a failed dial closes THIS connection only. The
          // Rust side reads that as "the socket refused" and retries under its
          // own backoff — the correct behaviour for a machine that is asleep,
          // and why this must not tear the listener down.
          _log('dial failed: $error');
          socket.destroy();
          return;
        }
        final pump = DuplexPump(socket, channel, _log);
        if (_closed) {
          // close() raced the dial; the pump was never registered, so stop it
          // here or the channel leaks.
          pump.start();
          unawaited(pump.stopAndWait());
          return;
        }
        _pumps.add(pump);
        unawaited(pump.done.whenComplete(() => _pumps.remove(pump)));
        pump.start();
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  /// Close the listener: stop accepting, tear down every live pump and its
  /// channel, and free the port.
  ///
  /// Idempotent. Does NOT close the SSH connection — see the class comment.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _server.close();
    final pumps = _pumps.toList();
    _pumps.clear();
    await Future.wait(pumps.map((p) => p.stopAndWait()));
  }
}

/// How long a *fallback* end-of-remote signal — the channel's
/// [DuplexChannel.done], or its stderr closing — waits for the read half to
/// finish on its own before teardown proceeds anyway. dartssh2 completes `done`
/// while `stream` can still hold buffered data, so acting on `done` directly
/// clips the channel's last frame.
const Duration _kStreamGrace = Duration(milliseconds: 500);

/// How long the local socket's EOF waits, after the write half has been closed,
/// for the remote to notice and finish its output.
const Duration _kRemoteEndGrace = Duration(milliseconds: 500);

/// Ceiling on closing the channel's write half: a wedged channel must not
/// strand the local socket, nor stall [PortListener.close].
const Duration _kSinkCloseTimeout = Duration(seconds: 1);

/// Ceiling on the channel's own graceful close before [DuplexChannel.destroy]
/// is used instead. `SSHForwardChannel.close()` waits for the remote to close
/// too, and a peer that never answers must not hold teardown open.
const Duration _kChannelCloseTimeout = Duration(seconds: 1);

/// Ceiling on pushing the drained bytes out before the FIN.
const Duration _kFlushTimeout = Duration(milliseconds: 500);

/// Ceiling on the graceful socket close before the fd is forced shut. Runs
/// off the teardown path, so it never delays [PortListener.close].
const Duration _kSocketCloseTimeout = Duration(seconds: 5);

/// Bytes both ways between one accepted local socket and one [DuplexChannel],
/// for the socket's whole life.
///
/// **Extracted from the roost tunnel, not written** (plan 018 §3.10). "Until
/// either side closes" is not a duplex protocol, and this class is the accreted
/// answer to what actually goes wrong; `roost_tunnel_test.dart` is its
/// regression control over the exec transport and does not move.
///
/// **Teardown is a drain, not a kill.** Two rules earn their complexity here:
///
/// 1. *The read half finishing* — not `done` — is what says the output is over.
///    dartssh2 documents that a channel's `done` can complete while its stream
///    still holds buffered data, so `done` (and stderr closing) only arm a
///    short grace period: if the stream has not finished by then, teardown goes
///    ahead. Treating `done` as the trigger drops the channel's final frame,
///    which on this wire is a whole IPC reply the Rust side is blocking on.
/// 2. *The local socket is closed, never destroyed*, on every non-error path:
///    `destroy()` on a socket the peer has half-closed resets the connection,
///    and a reset discards whatever is still in flight — the client sees a
///    connection error instead of the tail of its output followed by EOF. So
///    the order is: stop the pumps, flush what has already arrived, then FIN.
///
/// Stated once, since both transports obey it: local EOF closes the channel's
/// write half and keeps reading the remote; remote EOF flushes and then closes
/// the socket gracefully; an explicit shutdown waits a bounded moment and then
/// [DuplexChannel.destroy]s; any failure ends both directions.
class DuplexPump {
  DuplexPump(this._socket, this._channel, this._log);

  final Socket _socket;
  final DuplexChannel _channel;
  final void Function(String) _log;

  final Completer<void> _finished = Completer<void>();

  /// Completes when the channel's read half ends — the authoritative "the
  /// remote has said everything it is going to say".
  final Completer<void> _streamDone = Completer<void>();

  /// Completes when [DuplexChannel.done] settles, either way.
  final Completer<void> _channelEnded = Completer<void>();

  /// Completes when someone asked for teardown, so the bounded waits below can
  /// be cut short rather than holding [PortListener.close] open.
  final Completer<void> _stopRequested = Completer<void>();

  StreamSubscription<Uint8List>? _up;
  StreamSubscription<Uint8List>? _down;
  StreamSubscription<Uint8List>? _err;
  Timer? _grace;
  bool _localDone = false;
  bool _sinkClosing = false;
  bool _tearingDown = false;

  /// Completes when both halves are torn down.
  Future<void> get done => _finished.future;

  void start() {
    _up = _socket.listen(
      (chunk) {
        try {
          _channel.sink.add(chunk);
        } catch (error) {
          // The channel is closing/closed underneath us.
          _log('channel write failed: $error');
          _abort();
        }
      },
      // The ONLY trigger that may close the channel's write half.
      onDone: _onLocalDone,
      onError: (Object error) {
        _log('local socket error: $error');
        _abort();
      },
      cancelOnError: true,
    );

    _down = _channel.stream.listen(
      (chunk) {
        try {
          _socket.add(chunk);
        } catch (error) {
          _log('local socket write failed: $error');
          _abort();
        }
      },
      // The remote's output is finished: everything it sent is already queued
      // on the local socket, so this is the moment to drain and FIN.
      onDone: _onStreamDone,
      onError: (Object error) {
        _log('channel stream error: $error');
        _abort();
      },
      cancelOnError: true,
    );

    // Drained, never fatal for the listener: `client-bridge: no session` is a
    // per-connection answer (that host has no roost-session running), and the
    // Rust side classifies it from the stream ending, not from this text. A
    // transport with no diagnostic band at all (a forwarded TCP channel) has
    // nothing to listen to and, crucially, nothing to read as "closed".
    final stderr = _channel.stderr;
    if (stderr != null) {
      _err = stderr.listen(
        (chunk) => _log('stderr: ${utf8.decode(chunk, allowMalformed: true)}'),
        // A fallback, like `done`: stderr closing means the channel is going
        // away, but the read half may still have buffered frames to hand over.
        onDone: () => _armStreamGrace('stderr closed'),
        onError: (_) {},
        cancelOnError: false,
      );
    }

    // The far side's channel ended. NOT the trigger — see the class comment.
    unawaited(
      _channel.done.then<void>(
        (_) {
          _markChannelEnded();
          _armStreamGrace('channel done');
        },
        onError: (Object error) {
          _log('channel ended: $error');
          _markChannelEnded();
          _armStreamGrace('channel failed');
        },
      ),
    );
  }

  /// Tear down, and complete when teardown is finished.
  ///
  /// Bounded: the grace periods above are cut short, so this returns within
  /// roughly [_kSinkCloseTimeout] + [_kChannelCloseTimeout] + [_kFlushTimeout].
  Future<void> stopAndWait() {
    if (!_stopRequested.isCompleted) _stopRequested.complete();
    unawaited(_teardown(graceful: true));
    return done;
  }

  void _markChannelEnded() {
    if (!_channelEnded.isCompleted) _channelEnded.complete();
  }

  void _onStreamDone() {
    if (!_streamDone.isCompleted) _streamDone.complete();
    _cancelGrace();
    unawaited(_teardown(graceful: true));
  }

  /// A fallback end-of-remote signal fired. Give the read half [_kStreamGrace]
  /// to finish on its own; only if it does not do we tear down without it.
  void _armStreamGrace(String why) {
    if (_tearingDown || _streamDone.isCompleted || _grace != null) return;
    _grace = Timer(_kStreamGrace, () {
      _grace = null;
      if (_streamDone.isCompleted) return;
      _log('$why, but the stream did not finish within the grace period');
      unawaited(_teardown(graceful: true));
    });
  }

  void _cancelGrace() {
    _grace?.cancel();
    _grace = null;
  }

  /// The local client closed its write half. This is the one and only place
  /// the channel's write half may be closed — never as "we finished this
  /// request".
  void _onLocalDone() {
    if (_localDone) return;
    _localDone = true;
    unawaited(_finishFromLocal());
  }

  Future<void> _finishFromLocal() async {
    // Stop reading the local socket first: its read half is done, and this
    // keeps the channel's EOF the last thing that happens on the up-pump.
    await _up?.cancel();
    _up = null;
    await _closeSink();
    if (_tearingDown) return;
    // The client may still be reading. Give the remote a bounded moment to see
    // the EOF and hand over its last output before the down-pump is cancelled.
    await Future.any(<Future<void>>[
      _streamDone.future,
      _channelEnded.future,
      _stopRequested.future,
      Future<void>.delayed(_kRemoteEndGrace),
    ]);
    await _teardown(graceful: true);
  }

  void _abort() => unawaited(_teardown(graceful: false));

  /// Bounded, and exactly once: a second caller does not wait on the first.
  Future<void> _closeSink() async {
    if (_sinkClosing) return;
    _sinkClosing = true;
    try {
      await _channel.sink.close().timeout(_kSinkCloseTimeout);
    } catch (error) {
      _log('channel sink close failed: $error');
    }
  }

  Future<void> _teardown({required bool graceful}) async {
    if (_tearingDown) return _finished.future;
    _tearingDown = true;
    _cancelGrace();
    await _up?.cancel();
    await _down?.cancel();
    await _err?.cancel();
    // EOF, then the channel: roost ends a stream when its write half closes, so
    // the order is the difference between a clean end and a reset.
    await _closeSink();
    if (graceful) {
      await _closeChannel();
      await _drainAndCloseSocket();
    } else {
      _destroyChannel();
      _destroySocket();
    }
    if (!_finished.isCompleted) _finished.complete();
  }

  /// Close the channel, bounded. A `close()` that waits on a peer which never
  /// answers (the forwarded-port case) falls through to the forced seam rather
  /// than stranding teardown.
  Future<void> _closeChannel() async {
    try {
      await _channel.close().timeout(_kChannelCloseTimeout);
    } catch (error) {
      _log('channel close failed: $error');
      _destroyChannel();
    }
  }

  void _destroyChannel() {
    try {
      _channel.destroy();
    } catch (error) {
      _log('channel destroy failed: $error');
    }
  }

  /// Push everything already received out to the client, then FIN.
  Future<void> _drainAndCloseSocket() async {
    try {
      await _socket.flush().timeout(_kFlushTimeout);
    } catch (error) {
      // Nothing graceful left to do — the peer is already gone.
      _log('local socket flush failed: $error');
      _destroySocket();
      return;
    }
    // Not awaited: `close()` only settles once the client closes its end too,
    // and teardown must not hang on a client that is still reading.
    unawaited(_closeSocket());
  }

  Future<void> _closeSocket() async {
    try {
      await _socket.close().timeout(_kSocketCloseTimeout);
    } catch (error) {
      _log('local socket close failed: $error');
    }
    // The FIN has been sent and acknowledged (or the ceiling hit); releasing
    // the fd here cannot truncate anything.
    _destroySocket();
  }

  void _destroySocket() {
    try {
      _socket.destroy();
    } catch (error) {
      _log('local socket destroy failed: $error');
    }
  }
}
