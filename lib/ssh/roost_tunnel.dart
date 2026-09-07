import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
// Uint8List comes through foundation (which also carries kDebugMode,
// debugPrint and @visibleForTesting) — importing dart:typed_data as well is a
// duplicate the analyzer rejects.
import 'package:flutter/foundation.dart';

/// One remote exec, reduced to the four things a byte pump needs.
///
/// **Why the seam exists:** dartssh2's [SSHSession] can only be produced by a
/// live [SSHClient] against a real server, so without this interface every test
/// of the pump below would need an sshd. Production is [_SshExec], a
/// pass-through over `SSHClient.execute`; the wire-level proof that the exec
/// chain is composed and delivered correctly lives in shed's
/// `tests/machine-transport` differential, not here.
abstract class RoostExecSession {
  /// Stdin of the remote process. Closing it sends EOF — see [RoostTunnel] for
  /// why that must not happen early.
  StreamSink<Uint8List> get stdin;

  /// Stdout of the remote process: roost's IPC replies and event lines.
  Stream<Uint8List> get stdout;

  /// Stderr of the remote process. `client-bridge: no session` here is roost's
  /// "nothing is running on that host" signal.
  Stream<Uint8List> get stderr;

  /// Completes when the remote channel ends.
  Future<void> get done;

  /// Close the channel. After this the session is no longer usable.
  void close();
}

/// Opens one exec of [command] on the far side. See [RoostExecSession].
typedef RoostExec = Future<RoostExecSession> Function(String command);

/// **A local port that reaches a machine's `roost-session`** (plan 013 S3m).
///
/// This is the phone's half of the machine transport seam, re-pointed from the
/// RC hub onto roost. The shared Rust core does everything above the port — the
/// IPC framing, `tab.list`, the poll cadence, the reconnect/backoff — and is
/// handed nothing but an `int`:
///
/// ```text
///   Dart: ServerSocket ──execute(remoteCommand)──▶ roost-session client-bridge
///   Rust: RoostWatcher(FixedPort(port)) ──JSON lines──▶ 127.0.0.1:<port>
/// ```
///
/// **The port is fixed for the tunnel's whole life**, and that is the
/// load-bearing property (the plan-012 invariant), not an implementation
/// detail. The listening socket outlives any individual SSH connection: when the
/// phone changes networks or wakes from the background, the next accepted
/// connection re-execs underneath the same port. Rust therefore sees an ordinary
/// "connection refused, retry" against a stable address rather than needing a
/// protocol to re-acquire one — which is what lets the reconnect logic be
/// written once, in Rust, for every client.
///
/// **[remoteCommand] is opaque.** It is `roost_ipc::ssh::remote_command()`,
/// handed over the FRB bridge and passed to `execute` verbatim — a resolver
/// chain ending in `exec roost-session client-bridge`. Dart composes no part of
/// it; that is the whole point of the seam (shed's `tests/machine-transport`
/// owns the argv contract).
///
/// **Never half-close the exec's stdin early.** `client-bridge` is a pure byte
/// pump to the far side's session socket, and roost ends a stream when its write
/// half closes; the Rust watcher holds ONE connection and polls on it for
/// minutes. So stdin is closed at exactly one place — when the local socket
/// itself is done — and never as "we finished writing this request".
class RoostTunnel {
  RoostTunnel._(this._server, this._exec, this.remoteCommand, this.machine);

  final ServerSocket _server;

  /// Opens one exec on the far side. See [RoostExec].
  final RoostExec _exec;

  /// The exact string handed to `execute` on every accepted connection.
  final String remoteCommand;

  /// The machine's name — diagnostics only.
  final String machine;

  bool _closed = false;
  final Set<_RoostPump> _pumps = <_RoostPump>{};

  /// The local port the Rust roost client dials. Fixed for this tunnel's life.
  int get port => _server.port;

  /// Whether the tunnel has been closed (its port is no longer served).
  bool get isClosed => _closed;

  /// Open a tunnel to [machine]'s `roost-session`.
  ///
  /// Binds loopback only, on an OS-assigned port — never a fixed one, so two
  /// machines can be watched at once and nothing collides with another app.
  ///
  /// [connect] is called per accepted connection, so a dropped link is
  /// re-established on the next use rather than requiring the tunnel to be torn
  /// down and rebuilt. The caller owns the returned [SSHClient]'s lifetime:
  /// [close] frees the port and every exec, but never closes a connection this
  /// class did not create (backgrounding drops the SSH client at the call site,
  /// which may be sharing it with a PTY).
  static Future<RoostTunnel> open({
    required Future<SSHClient> Function() connect,
    required String remoteCommand,
    required String machine,
  }) {
    return openWithExec(
      exec: (command) async {
        final client = await connect();
        return _SshExec(await client.execute(command));
      },
      remoteCommand: remoteCommand,
      machine: machine,
    );
  }

  /// [open] with the SSH half replaced. See [RoostExecSession] for why.
  @visibleForTesting
  static Future<RoostTunnel> openWithExec({
    required RoostExec exec,
    required String remoteCommand,
    required String machine,
  }) async {
    final server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    final tunnel = RoostTunnel._(server, exec, remoteCommand, machine);
    tunnel._accept();
    return tunnel;
  }

  void _accept() {
    _server.listen(
      (socket) async {
        if (_closed) {
          socket.destroy();
          return;
        }
        final RoostExecSession session;
        try {
          session = await _exec(remoteCommand);
        } catch (error) {
          // A failed connect or a failed exec closes THIS connection only. The
          // Rust side reads that as "the socket refused" and retries under its
          // own backoff — the correct behaviour for a machine that is asleep,
          // and why this must not tear the tunnel down.
          _log('exec failed: $error');
          socket.destroy();
          return;
        }
        final pump = _RoostPump(socket, session, _log);
        if (_closed) {
          // close() raced the exec; the pump was never registered, so stop it
          // here or the exec leaks.
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

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('RoostTunnel[$machine] $message');
    }
  }

  /// Close the tunnel: stop accepting, tear down every live pump and its exec,
  /// and free the port.
  ///
  /// Idempotent. Does NOT close the SSH connection — see [open].
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _server.close();
    final pumps = _pumps.toList();
    _pumps.clear();
    await Future.wait(pumps.map((p) => p.stopAndWait()));
  }
}

/// How long a *fallback* end-of-remote signal — the exec's [RoostExecSession.done],
/// or stderr closing — waits for stdout to finish on its own before teardown
/// proceeds anyway. dartssh2 completes `done` while `stdout` can still hold
/// buffered data, so acting on `done` directly clips the exec's last frame.
const Duration _kStdoutGrace = Duration(milliseconds: 500);

/// How long the local socket's EOF waits, after stdin has been closed, for the
/// remote to notice and finish its output.
const Duration _kRemoteEndGrace = Duration(milliseconds: 500);

/// Ceiling on closing the exec's stdin: a wedged channel must not strand the
/// local socket, nor stall [RoostTunnel.close].
const Duration _kStdinCloseTimeout = Duration(seconds: 1);

/// Ceiling on pushing the drained bytes out before the FIN.
const Duration _kFlushTimeout = Duration(milliseconds: 500);

/// Ceiling on the graceful socket close before the fd is forced shut. Runs
/// off the teardown path, so it never delays [RoostTunnel.close].
const Duration _kSocketCloseTimeout = Duration(seconds: 5);

/// Bytes both ways between one accepted local socket and one exec, for the
/// socket's whole life.
///
/// **Teardown is a drain, not a kill.** Two rules earn their complexity here:
///
/// 1. *Stdout finishing* — not `done` — is what says the output is over.
///    dartssh2 documents that [SSHSession.done] can complete while `stdout`
///    still holds buffered data, so `done` (and stderr closing) only arm a
///    short grace period: if stdout has not finished by then, teardown goes
///    ahead. Treating `done` as the trigger drops the exec's final frame, which
///    on this wire is a whole IPC reply the Rust watcher is blocking on.
/// 2. *The local socket is closed, never destroyed*, on every non-error path:
///    `destroy()` on a socket the peer has half-closed resets the connection,
///    and a reset discards whatever is still in flight — the client sees a
///    connection error instead of the tail of its output followed by EOF. So
///    the order is: stop the pumps, flush what has already arrived, then FIN.
class _RoostPump {
  _RoostPump(this._socket, this._session, this._log);

  final Socket _socket;
  final RoostExecSession _session;
  final void Function(String) _log;

  final Completer<void> _finished = Completer<void>();

  /// Completes when the exec's stdout stream ends — the authoritative "the
  /// remote has said everything it is going to say".
  final Completer<void> _stdoutDone = Completer<void>();

  /// Completes when [RoostExecSession.done] settles, either way.
  final Completer<void> _sessionEnded = Completer<void>();

  /// Completes when someone asked for teardown, so the bounded waits below can
  /// be cut short rather than holding [RoostTunnel.close] open.
  final Completer<void> _stopRequested = Completer<void>();

  StreamSubscription<Uint8List>? _up;
  StreamSubscription<Uint8List>? _down;
  StreamSubscription<Uint8List>? _err;
  Timer? _grace;
  bool _localDone = false;
  bool _stdinClosing = false;
  bool _tearingDown = false;

  /// Completes when both halves are torn down.
  Future<void> get done => _finished.future;

  void start() {
    _up = _socket.listen(
      (chunk) {
        try {
          _session.stdin.add(chunk);
        } catch (error) {
          // The channel is closing/closed underneath us.
          _log('stdin write failed: $error');
          _abort();
        }
      },
      // The ONLY trigger that may close the exec's stdin.
      onDone: _onLocalDone,
      onError: (Object error) {
        _log('local socket error: $error');
        _abort();
      },
      cancelOnError: true,
    );

    _down = _session.stdout.listen(
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
      onDone: _onStdoutDone,
      onError: (Object error) {
        _log('stdout error: $error');
        _abort();
      },
      cancelOnError: true,
    );

    // Drained, never fatal for the tunnel: `client-bridge: no session` is a
    // per-connection answer (that host has no roost-session running), and the
    // Rust side classifies it from the stream ending, not from this text.
    _err = _session.stderr.listen(
      (chunk) => _log('stderr: ${utf8.decode(chunk, allowMalformed: true)}'),
      // A fallback, like `done`: stderr closing means the channel is going
      // away, but stdout may still have buffered frames to hand over.
      onDone: () => _armStdoutGrace('stderr closed'),
      onError: (_) {},
      cancelOnError: false,
    );

    // The remote process exited. NOT the trigger — see the class comment.
    unawaited(
      _session.done.then<void>(
        (_) {
          _markSessionEnded();
          _armStdoutGrace('exec done');
        },
        onError: (Object error) {
          _log('exec ended: $error');
          _markSessionEnded();
          _armStdoutGrace('exec failed');
        },
      ),
    );
  }

  /// Tear down, and complete when teardown is finished.
  ///
  /// Bounded: the grace periods above are cut short, so this returns within
  /// roughly [_kStdinCloseTimeout] + [_kFlushTimeout].
  Future<void> stopAndWait() {
    if (!_stopRequested.isCompleted) _stopRequested.complete();
    unawaited(_teardown(graceful: true));
    return done;
  }

  void _markSessionEnded() {
    if (!_sessionEnded.isCompleted) _sessionEnded.complete();
  }

  void _onStdoutDone() {
    if (!_stdoutDone.isCompleted) _stdoutDone.complete();
    _cancelGrace();
    unawaited(_teardown(graceful: true));
  }

  /// A fallback end-of-remote signal fired. Give stdout [_kStdoutGrace] to
  /// finish on its own; only if it does not do we tear down without it.
  void _armStdoutGrace(String why) {
    if (_tearingDown || _stdoutDone.isCompleted || _grace != null) return;
    _grace = Timer(_kStdoutGrace, () {
      _grace = null;
      if (_stdoutDone.isCompleted) return;
      _log('$why, but stdout did not finish within the grace period');
      unawaited(_teardown(graceful: true));
    });
  }

  void _cancelGrace() {
    _grace?.cancel();
    _grace = null;
  }

  /// The local client closed its write half. This is the one and only place
  /// the exec's stdin may be closed — never as "we finished this request".
  void _onLocalDone() {
    if (_localDone) return;
    _localDone = true;
    unawaited(_finishFromLocal());
  }

  Future<void> _finishFromLocal() async {
    // Stop reading the local socket first: its read half is done, and this
    // keeps the exec's EOF the last thing that happens on the up-pump.
    await _up?.cancel();
    _up = null;
    await _closeStdin();
    if (_tearingDown) return;
    // The client may still be reading. Give the remote a bounded moment to see
    // the EOF and hand over its last output before the down-pump is cancelled.
    await Future.any(<Future<void>>[
      _stdoutDone.future,
      _sessionEnded.future,
      _stopRequested.future,
      Future<void>.delayed(_kRemoteEndGrace),
    ]);
    await _teardown(graceful: true);
  }

  void _abort() => unawaited(_teardown(graceful: false));

  /// Bounded, and exactly once: a second caller does not wait on the first.
  Future<void> _closeStdin() async {
    if (_stdinClosing) return;
    _stdinClosing = true;
    try {
      await _session.stdin.close().timeout(_kStdinCloseTimeout);
    } catch (error) {
      _log('stdin close failed: $error');
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
    await _closeStdin();
    try {
      _session.close();
    } catch (error) {
      _log('exec close failed: $error');
    }
    if (graceful) {
      await _drainAndCloseSocket();
    } else {
      _destroySocket();
    }
    if (!_finished.isCompleted) _finished.complete();
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

/// Production [RoostExecSession]: dartssh2's own session, unchanged.
class _SshExec implements RoostExecSession {
  _SshExec(this._session);

  final SSHSession _session;

  @override
  StreamSink<Uint8List> get stdin => _session.stdin;

  @override
  Stream<Uint8List> get stdout => _session.stdout;

  @override
  Stream<Uint8List> get stderr => _session.stderr;

  @override
  Future<void> get done => _session.done;

  @override
  void close() => _session.close();
}
