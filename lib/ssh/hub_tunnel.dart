import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import 'host_key_store.dart';
import 'ssh_connection.dart';

/// The RC activity hub's fixed loopback port on the far side (`rc.HubAddr`).
/// Mirrors `shed_core::hub_client::HUB_PORT`; a machine's hub always answers
/// there, which is why nothing configures it.
const int kHubRemotePort = 1029;

/// **A local port that reaches a machine's RC activity hub** (plan 012 R4).
///
/// This is the phone's half of the machine transport seam. The shared Rust core
/// does everything above the port — health, the snapshot, the SSE feed, the
/// reconnect/backoff — and is handed nothing but an `int`:
///
/// ```text
///   Dart: ServerSocket on 127.0.0.1:<port>  ──forwardLocal──▶ machine:1029
///   Rust: MachineHubWatcher(FixedPort(port)) ──HTTP/SSE──▶ 127.0.0.1:<port>
/// ```
///
/// **The port is stable for the tunnel's whole life**, and that is the
/// load-bearing property, not an implementation detail. The listening socket
/// outlives any individual SSH connection: when the phone changes networks or
/// wakes from the background, the next accepted connection re-dials SSH
/// underneath the same port. Rust therefore sees an ordinary "connection
/// refused, retry" rather than needing a protocol to re-acquire an address —
/// which is exactly what lets the reconnect logic be written once, in Rust, for
/// every client.
///
/// Deliberately NOT a persistent single channel: `forwardLocal` yields one
/// channel per connection, and the hub client opens several (health, snapshot,
/// a long-lived SSE stream, message fetches). Accepting per connection is both
/// simpler and closer to what `ssh -L` does.
class HubTunnel {
  HubTunnel._(this._server, this._connect, this.machine);

  final ServerSocket _server;

  /// Opens (or reuses) the SSH connection. Called per accepted connection, so a
  /// dropped link is re-established on the next use rather than requiring the
  /// tunnel to be torn down and rebuilt.
  final Future<SSHClient> Function() _connect;

  /// The machine's name — diagnostics only.
  final String machine;

  SSHClient? _client;
  bool _closed = false;
  final List<StreamSubscription<void>> _pumps = [];

  /// The local port the Rust hub client dials. Fixed for this tunnel's life.
  int get port => _server.port;

  /// Whether the tunnel has been closed (its port is no longer served).
  bool get isClosed => _closed;

  /// Open a tunnel to [machine]'s hub.
  ///
  /// Binds loopback only, on an OS-assigned port — never a fixed one, so two
  /// machines can be watched at once and nothing collides with another app.
  static Future<HubTunnel> open({
    required String machine,
    required String host,
    required int sshPort,
    required String user,
    required List<SSHKeyPair> identities,
    required HostKeyStore hostKeys,
  }) async {
    final server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    SSHClient? shared;
    Future<SSHClient> connect() async {
      final existing = shared;
      if (existing != null && !existing.isClosed) return existing;
      final client = await openSshClient(
        host: host,
        port: sshPort,
        user: user,
        identities: identities,
        hostKeys: hostKeys,
      );
      shared = client;
      return client;
    }

    final tunnel = HubTunnel._(server, connect, machine);
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
        try {
          final client = await _connect();
          _client = client;
          final channel = await client.forwardLocal(
            InternetAddress.loopbackIPv4.address,
            kHubRemotePort,
          );
          _pipe(socket, channel);
        } catch (_) {
          // A failed dial closes THIS connection only. The Rust side reads that
          // as "the socket refused" and retries under its own backoff — which is
          // the correct behaviour for a machine that is asleep, and is why this
          // must not tear the tunnel down.
          socket.destroy();
        }
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  /// Pump bytes both ways until either side closes.
  void _pipe(Socket socket, SSHForwardChannel channel) {
    late final StreamSubscription<void> up;
    late final StreamSubscription<void> down;

    void closeBoth() {
      up.cancel();
      down.cancel();
      _pumps.remove(up);
      _pumps.remove(down);
      socket.destroy();
      channel.close();
    }

    up = socket.listen(
      channel.sink.add,
      onDone: closeBoth,
      onError: (_) => closeBoth(),
      cancelOnError: true,
    );
    down = channel.stream.listen(
      socket.add,
      onDone: closeBoth,
      onError: (_) => closeBoth(),
      cancelOnError: true,
    );
    _pumps.addAll([up, down]);
  }

  /// Close the tunnel: stop accepting, drop every in-flight pipe, and close the
  /// SSH connection.
  ///
  /// **Called when the app backgrounds**, not just on teardown. Holding an SSH
  /// connection open behind a backgrounded phone is what gets an app killed by
  /// the OS and drains a battery; the hub's snapshot is authoritative, so
  /// re-opening on foreground is a complete resync with nothing lost.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final p in _pumps.toList()) {
      await p.cancel();
    }
    _pumps.clear();
    await _server.close();
    _client?.close();
    _client = null;
  }
}
