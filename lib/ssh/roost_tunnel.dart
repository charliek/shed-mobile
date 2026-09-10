import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
// Uint8List comes through foundation (which also carries kDebugMode,
// debugPrint and @visibleForTesting) — importing dart:typed_data as well is a
// duplicate the analyzer rejects.
import 'package:flutter/foundation.dart';

import 'duplex_pump.dart';

/// One remote exec, reduced to the four things a byte pump needs.
///
/// **Why the seam exists:** dartssh2's [SSHSession] can only be produced by a
/// live [SSHClient] against a real server, so without this interface every test
/// of the tunnel would need an sshd. Production is [_SshExec], a pass-through
/// over `SSHClient.execute`; the wire-level proof that the exec chain is
/// composed and delivered correctly lives in shed's `tests/machine-transport`
/// differential, not here.
///
/// **This is the exec's OWN shape, not the pump's.** The bytes are moved by the
/// generic [DuplexPump] (`duplex_pump.dart`), which a lane's forwarded port
/// shares; `_ExecChannel` below is the whole of the difference between the two.
/// The names here are a remote *process*'s — `stdin`/`stdout`/`stderr` — and
/// they stay that way because that is what an exec has.
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
/// The port, the accept loop and the byte pump are [PortListener]'s (a lane's
/// port forward is the same machinery over a different channel); what lives
/// here is the exec seam and the opaque command it runs.
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
  RoostTunnel._(this._listener, this.remoteCommand, this.machine);

  final PortListener _listener;

  /// The exact string handed to `execute` on every accepted connection.
  final String remoteCommand;

  /// The machine's name — diagnostics only.
  final String machine;

  /// The local port the Rust roost client dials. Fixed for this tunnel's life.
  int get port => _listener.port;

  /// Whether the tunnel has been closed (its port is no longer served).
  bool get isClosed => _listener.isClosed;

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
    final listener = await PortListener.bind(
      dial: () async => _ExecChannel(await exec(remoteCommand)),
      log: (message) {
        if (kDebugMode) {
          debugPrint('RoostTunnel[$machine] $message');
        }
      },
    );
    return RoostTunnel._(listener, remoteCommand, machine);
  }

  /// Close the tunnel: stop accepting, tear down every live pump and its exec,
  /// and free the port.
  ///
  /// Idempotent. Does NOT close the SSH connection — see [open].
  Future<void> close() => _listener.close();
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

/// One [RoostExecSession] as the [DuplexChannel] the pump moves bytes over.
///
/// The whole adapter, and deliberately thin: the exec seam is what the tunnel's
/// tests implement, so it keeps its process-shaped names and its synchronous
/// `close()`, while the pump speaks in sinks and streams for both transports.
class _ExecChannel implements DuplexChannel {
  _ExecChannel(this._session);

  final RoostExecSession _session;
  bool _closed = false;

  @override
  StreamSink<List<int>> get sink => _session.stdin;

  @override
  Stream<Uint8List> get stream => _session.stdout;

  /// An exec HAS a stderr band, and its closing is a real end-of-remote hint —
  /// unlike a forwarded TCP channel, which has none at all.
  @override
  Stream<Uint8List>? get stderr => _session.stderr;

  @override
  Future<void> get done => _session.done;

  /// An exec's close never waits on the far side ([RoostExecSession.close] is
  /// synchronous, as is dartssh2's `SSHSession.close()`), so this settles at
  /// once and the pump's bounded wait never fires.
  @override
  Future<void> close() async => _closeOnce();

  /// The same call: an [SSHSession] exposes no forced seam of its own (only its
  /// private channel does), so an exec's graceful and forced closes are one
  /// thing. Guarded, so the pump's "close() threw, destroy() instead" path
  /// cannot close the same session twice.
  @override
  void destroy() => _closeOnce();

  void _closeOnce() {
    if (_closed) return;
    _closed = true;
    _session.close();
  }
}
