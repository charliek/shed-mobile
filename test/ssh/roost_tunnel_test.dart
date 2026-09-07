import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/ssh/roost_tunnel.dart';

/// The exact string `roost_ipc::ssh::remote_command()` emits today. It reaches
/// Dart from the Rust bridge at runtime; the tunnel must treat it as OPAQUE and
/// hand it to `execute` unmodified, which is what the verbatim test below pins.
/// Dart composing any part of a remote command is the plan-012 drift this seam
/// exists to prevent.
const String kRoostRemoteCommand =
    r"""sh -c 'if [ -n "${HOME:-}" ]; then p="$HOME/.local/bin/roost-session"; [ -f "$p" ] && [ -x "$p" ] && exec "$p" client-bridge; fi; p=$(command -v roost-session 2>/dev/null) || p=; case "$p" in /*) [ -f "$p" ] && [ -x "$p" ] && exec "$p" client-bridge;; esac; p="/usr/bin/roost-session"; [ -f "$p" ] && [ -x "$p" ] && exec "$p" client-bridge; printf "%s\n" "roost-session: command not found" >&2; exit 127'""";

/// The roost tunnel's LOCAL half — the socket lifecycle and the byte pump.
///
/// Two things are proved here and nowhere else on this side of the wire:
///
/// 1. **The lifecycle**, because the Rust watcher's reconnect model assumes a
///    fixed loopback address that stops answering rather than one that moves,
///    and assumes a failed exec drops one connection, not the tunnel.
/// 2. **Delivered frames**, because plan 012 shipped a forwarded-hub check that
///    asserted liveness only — and passed against a completely dead feed. A
///    tunnel that accepts connections and never moves a byte must fail below.
///
/// The exec chain itself (does the far side really land in
/// `roost-session client-bridge`?) belongs to shed's `tests/machine-transport`
/// differential, which runs every wire line through a real sshd.
void main() {
  group('RoostTunnel', () {
    test('binds a loopback port that stays fixed and is freed on close', () async {
      final fixture = _Fixture(failAlways: true);
      final tunnel = await fixture.open();
      final port = tunnel.port;

      expect(port, greaterThan(0));
      expect(tunnel.isClosed, isFalse);
      // The port is a property of the TUNNEL, not of any connection: reading it
      // repeatedly (as the Rust side does on every reconnect) must not move it.
      expect(tunnel.port, port);
      expect(tunnel.port, port);

      // It is really listening, and really on loopback.
      final probe = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(seconds: 5),
      );
      probe.destroy();

      await tunnel.close();
      expect(tunnel.isClosed, isTrue);

      // Closing must FREE the port — a leaked listener would keep answering and
      // the Rust client would read a dead tunnel as healthy.
      await expectLater(
        Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(seconds: 2),
        ),
        throwsA(isA<SocketException>()),
      );
    });

    test('close is idempotent', () async {
      final fixture = _Fixture(failAlways: true);
      final tunnel = await fixture.open();
      await tunnel.close();
      await tunnel.close();
      expect(tunnel.isClosed, isTrue);
    });

    test('close tears down a live exec and its local socket', () async {
      final fixture = _Fixture();
      final tunnel = await fixture.open();
      final conn = await _connect(tunnel);
      addTearDown(conn.destroy);
      final exec = await fixture.execAt(0);

      await tunnel.close();

      expect(exec.stdinClosed, isTrue, reason: 'the exec must get its EOF');
      expect(exec.sessionClosed, isTrue, reason: 'and the channel must close');
      // The local end goes with it, so Rust sees the port stop answering.
      await conn.closedByPeer.timeout(const Duration(seconds: 5));
    });

    test('a failed exec closes only that connection, not the tunnel', () async {
      // Every exec attempt throws — the everyday "machine is asleep" case.
      final fixture = _Fixture(failAlways: true);
      final tunnel = await fixture.open();
      addTearDown(tunnel.close);
      final port = tunnel.port;

      // Two connections in a row: each is dropped, and the LISTENER survives.
      // This is the property that lets the Rust side back off and retry against
      // a stable address instead of the tunnel tearing itself down on the first
      // failure (which would strand a machine that is merely asleep).
      for (var i = 0; i < 2; i++) {
        final probe = await _connect(tunnel);
        await probe.closedByPeer.timeout(const Duration(seconds: 10));
        probe.destroy();
      }

      expect(fixture.commands.length, 2, reason: 'both dials tried to exec');
      expect(
        tunnel.isClosed,
        isFalse,
        reason: 'the tunnel must outlive a failed exec',
      );
      expect(tunnel.port, port, reason: 'and must keep the same port');
    });

    test(
      'a failed connect closes only that connection, not the tunnel',
      () async {
        // The production path (RoostTunnel.open), where the SSH dial itself is
        // what fails — a phone off the VPN, not a missing roost-session.
        var attempts = 0;
        final tunnel = await RoostTunnel.open(
          connect: () async {
            attempts++;
            throw const SocketException('no route to host');
          },
          remoteCommand: kRoostRemoteCommand,
          machine: 'test',
        );
        addTearDown(tunnel.close);

        final probe = await _connect(tunnel);
        await probe.closedByPeer.timeout(const Duration(seconds: 10));
        probe.destroy();
        expect(attempts, 1);
        expect(tunnel.isClosed, isFalse);

        // And the listener is still there for the retry.
        final again = await _connect(tunnel);
        addTearDown(again.destroy);
        await _waitFor(() => attempts == 2, 'the retry to reach connect');
      },
    );

    test('the remote command reaches execute verbatim', () async {
      final fixture = _Fixture(echo: _upper);
      final tunnel = await fixture.open();
      addTearDown(tunnel.close);

      final conn = await _connect(tunnel);
      addTearDown(conn.destroy);
      await conn.roundTrip('ping');

      expect(fixture.commands, [kRoostRemoteCommand]);
      expect(tunnel.remoteCommand, kRoostRemoteCommand);
      // Not a paraphrase of the constant: the real string ends in the
      // not-found rung, and Dart must not have touched a byte of it.
      expect(kRoostRemoteCommand, endsWith("exit 127'"));
    });

    group('delivered frames', () {
      test('local bytes reach the exec and its output comes back', () async {
        final fixture = _Fixture(echo: _upper);
        final tunnel = await fixture.open();
        addTearDown(tunnel.close);

        final conn = await _connect(tunnel);
        addTearDown(conn.destroy);

        // Both directions in one assertion: the bytes went up, the transformed
        // bytes came back. A tunnel that merely accepts fails here.
        expect(await conn.roundTrip('hello'), 'HELLO');

        final exec = await fixture.execAt(0);
        expect(exec.receivedText, 'hello');
      });

      test('unprompted exec output reaches the local socket', () async {
        // The direction that matters most: roost pushes lines nobody asked for
        // (and the poll's replies arrive with no local write in between), and
        // the Rust watcher only ever sees them through here.
        final fixture = _Fixture();
        final tunnel = await fixture.open();
        addTearDown(tunnel.close);

        final conn = await _connect(tunnel);
        addTearDown(conn.destroy);
        final exec = await fixture.execAt(0);

        const line = '{"jsonrpc":"2.0","id":1}\n';
        exec.emit(line);
        expect(await conn.read(line.length), line);
      });

      test('closing the local socket closes the exec stdin', () async {
        final fixture = _Fixture(echo: _upper);
        final tunnel = await fixture.open();
        addTearDown(tunnel.close);

        final conn = await _connect(tunnel);
        addTearDown(conn.destroy);
        expect(await conn.roundTrip('live'), 'LIVE');
        final exec = await fixture.execAt(0);
        // The invariant: a completed request must NOT have half-closed stdin —
        // roost would end the stream and the watcher's held connection with it.
        expect(
          exec.stdinClosed,
          isFalse,
          reason: 'stdin must stay open across a request/response',
        );

        conn.closeWrite();
        await _waitFor(() => exec.stdinClosed, 'the exec to see EOF');
        expect(exec.sessionClosed, isTrue, reason: 'and the channel to close');
      });

      test('the exec ending closes the local socket', () async {
        final fixture = _Fixture();
        final tunnel = await fixture.open();
        addTearDown(tunnel.close);

        final conn = await _connect(tunnel);
        addTearDown(conn.destroy);
        final exec = await fixture.execAt(0);

        // `done` alone, with stdout left open — the fallback path: after the
        // grace period expires the tunnel stops waiting for stdout.
        exec.endRemotely();

        // The local socket must die with it — one that keeps answering after
        // the far side is gone reads as a healthy tunnel in Rust.
        await conn.closedByPeer.timeout(const Duration(seconds: 5));
        // The listener, however, survives: the next dial re-execs.
        expect(tunnel.isClosed, isFalse);
      });

      test('a chunk emitted just before done still reaches the client', () async {
        // dartssh2 completes `done` while stdout can still hold buffered data.
        // Tearing down on `done` clips that tail — and the tail here is a whole
        // IPC reply the Rust watcher is blocking on. So: stdout finishing, not
        // `done`, is the trigger.
        final fixture = _Fixture();
        final tunnel = await fixture.open();
        addTearDown(tunnel.close);

        final conn = await _connect(tunnel);
        addTearDown(conn.destroy);
        final exec = await fixture.execAt(0);

        const tail = '{"jsonrpc":"2.0","id":9,"result":{"tabs":[]}}\n';
        // `done` fires FIRST — dartssh2's documented shape...
        exec.endRemotely();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        // ...with a frame still queued behind it, delivered only afterwards.
        exec.emit(tail);
        exec.endStdout();

        expect(
          await conn.read(tail.length, from: 0),
          tail,
          reason: 'the final frame must survive teardown',
        );
        await conn.closedByPeer.timeout(const Duration(seconds: 5));
        expect(conn.bytesReceived, tail.length, reason: 'and nothing after it');
      });

      test(
        'the remote finishing ends the local read with a clean EOF',
        () async {
          // Both halves of the same rule. Everything already received is DRAINED
          // into the local socket, and the socket is then CLOSED — `destroy()`
          // hands the client a truncated stream ending in a connection error
          // rather than its data followed by an end of stream, and the Rust
          // watcher reads that as a broken link instead of a finished one.
          final fixture = _Fixture();
          final tunnel = await fixture.open();
          addTearDown(tunnel.close);

          final conn = await _connect(tunnel);
          addTearDown(conn.destroy);
          final exec = await fixture.execAt(0);

          // More than one socket write's worth, so "drained" means something.
          final tail = List<String>.generate(
            8192,
            (i) => '{"jsonrpc":"2.0","method":"tab.changed","id":$i}\n',
          ).join();
          exec.emit(tail);
          exec.close();

          await conn.closedByPeer.timeout(const Duration(seconds: 10));
          expect(conn.error, isNull, reason: 'a reset is not an end of stream');
          expect(
            conn.bytesReceived,
            tail.length,
            reason: 'and every drained byte arrived first',
          );
        },
      );
    });

    test('close does not stall on a wedged exec', () async {
      // Every bounded wait in teardown, exercised at once: an exec whose stdin
      // never closes and whose channel never ends. close() must still return.
      final wedged = _WedgedExec();
      final tunnel = await RoostTunnel.openWithExec(
        exec: (_) async => wedged,
        remoteCommand: kRoostRemoteCommand,
        machine: 'test',
      );
      final conn = await _connect(tunnel);
      addTearDown(conn.destroy);
      await _waitFor(() => wedged.started, 'the wedged exec to be opened');

      final elapsed = Stopwatch()..start();
      await tunnel.close();
      elapsed.stop();

      expect(tunnel.isClosed, isTrue);
      expect(
        elapsed.elapsed,
        lessThan(const Duration(seconds: 3)),
        reason: 'teardown must be bounded, not wait on the far side',
      );
    });

    test('two concurrent connections get two independent execs', () async {
      final fixture = _Fixture(echo: _upper);
      final tunnel = await fixture.open();
      addTearDown(tunnel.close);

      final first = await _connect(tunnel);
      addTearDown(first.destroy);
      expect(await first.roundTrip('one'), 'ONE');

      final second = await _connect(tunnel);
      addTearDown(second.destroy);
      expect(await second.roundTrip('two'), 'TWO');

      expect(fixture.execs.length, 2);
      // Neither exec saw the other's bytes.
      expect(fixture.execs[0].receivedText, 'one');
      expect(fixture.execs[1].receivedText, 'two');

      // Tearing one down leaves the other running — the Rust peek holds a
      // second connection alongside the watcher's.
      first.closeWrite();
      await _waitFor(
        () => fixture.execs[0].stdinClosed,
        'the first exec to end',
      );
      expect(fixture.execs[1].stdinClosed, isFalse);
      expect(await second.roundTrip('still'), 'STILL');
    });
  });
}

Uint8List _upper(Uint8List data) =>
    Uint8List.fromList(utf8.encode(utf8.decode(data).toUpperCase()));

Future<_Conn> _connect(RoostTunnel tunnel) async => _Conn(
  await Socket.connect(
    InternetAddress.loopbackIPv4,
    tunnel.port,
    timeout: const Duration(seconds: 5),
  ),
);

/// A local client of the tunnel — the Rust side's stand-in. A [Socket] may only
/// be listened to once, so every read in a test goes through this buffer.
class _Conn {
  _Conn(this._socket) {
    _sub = _socket.listen(
      _bytes.addAll,
      onError: (Object e) {
        error ??= e;
        _end();
      },
      onDone: _end,
      cancelOnError: false,
    );
  }

  final Socket _socket;
  final List<int> _bytes = <int>[];
  final Completer<void> _closed = Completer<void>();
  late final StreamSubscription<Uint8List> _sub;

  /// The error the read ended with, if it ended in one. A clean end of stream
  /// leaves this null; a reset (`destroy()` on a half-closed peer) does not.
  Object? error;

  /// Completes when the tunnel closes this connection.
  Future<void> get closedByPeer => _closed.future;

  /// Everything read so far.
  String get text => utf8.decode(_bytes);

  int get bytesReceived => _bytes.length;

  /// Write [text] and read back the bytes that answer it.
  Future<String> roundTrip(String text) {
    final from = _bytes.length;
    _socket.add(utf8.encode(text));
    return read(text.length, from: from);
  }

  /// Read [length] bytes starting at [from] (default: wherever we are now).
  Future<String> read(int length, {int? from}) async {
    final start = from ?? _bytes.length;
    await _waitFor(
      () => _bytes.length >= start + length,
      '$length bytes from the tunnel',
    );
    return utf8.decode(_bytes.sublist(start, start + length));
  }

  /// Send FIN, the way the Rust side drops a connection it is done with.
  void closeWrite() => unawaited(_socket.close());

  void destroy() {
    unawaited(_sub.cancel());
    _socket.destroy();
    _end();
  }

  void _end() {
    if (!_closed.isCompleted) _closed.complete();
  }
}

/// A [RoostExecSession] under the test's control: it records what it received,
/// optionally transforms it back onto stdout, and can end on demand.
class _FakeExec implements RoostExecSession {
  _FakeExec({Uint8List Function(Uint8List)? echo}) {
    _stdin.stream.listen(
      (chunk) {
        _received.add(chunk);
        final out = echo?.call(chunk);
        if (out != null && !_stdout.isClosed) _stdout.add(out);
      },
      onDone: () {
        stdinClosed = true;
        // `client-bridge` is a byte pump: EOF on its stdin is what makes it
        // exit, so the channel ends here too rather than lingering.
        endRemotely();
      },
    );
  }

  final StreamController<Uint8List> _stdin = StreamController<Uint8List>();
  final StreamController<Uint8List> _stdout = StreamController<Uint8List>();
  final StreamController<Uint8List> _stderr = StreamController<Uint8List>();
  final Completer<void> _done = Completer<void>();
  final BytesBuilder _received = BytesBuilder();

  /// Set when the tunnel closes stdin — the EOF that must never come early.
  bool stdinClosed = false;

  /// Set when the tunnel closes the channel.
  bool sessionClosed = false;

  String get receivedText => utf8.decode(_received.toBytes());

  /// Push bytes the local side never asked for (a roost event line).
  ///
  /// A no-op once the tunnel has closed the channel — so a tunnel that tears
  /// down too early fails on the bytes the client never received, which is the
  /// behaviour under test, rather than on a state error in this fake.
  void emit(String text) {
    if (_stdout.isClosed) return;
    _stdout.add(utf8.encode(text));
  }

  /// The remote process exits on its own — `done` only. Stdout is left open on
  /// purpose: that is dartssh2's documented shape, and the tunnel must treat
  /// this as a hint, not as "the output is over".
  void endRemotely() {
    if (!_done.isCompleted) _done.complete();
  }

  /// The output stream itself finishes — the authoritative end of the exec's
  /// output, and the tunnel's real teardown trigger.
  void endStdout() {
    if (!_stdout.isClosed) unawaited(_stdout.close());
  }

  @override
  StreamSink<Uint8List> get stdin => _stdin.sink;

  @override
  Stream<Uint8List> get stdout => _stdout.stream;

  @override
  Stream<Uint8List> get stderr => _stderr.stream;

  @override
  Future<void> get done => _done.future;

  @override
  void close() {
    sessionClosed = true;
    if (!_stdout.isClosed) unawaited(_stdout.close());
    if (!_stderr.isClosed) unawaited(_stderr.close());
    endRemotely();
  }
}

/// A session that never answers: stdin never closes, the channel never ends,
/// stdout never finishes. Every bounded wait in teardown, in one object.
class _WedgedExec implements RoostExecSession {
  final _NeverSink _stdin = _NeverSink();
  final StreamController<Uint8List> _stdout = StreamController<Uint8List>();
  final StreamController<Uint8List> _stderr = StreamController<Uint8List>();
  final Completer<void> _never = Completer<void>();

  /// Set once the tunnel has started pumping this session.
  bool get started => _stdout.hasListener;

  @override
  StreamSink<Uint8List> get stdin => _stdin;

  @override
  Stream<Uint8List> get stdout => _stdout.stream;

  @override
  Stream<Uint8List> get stderr => _stderr.stream;

  @override
  Future<void> get done => _never.future;

  @override
  void close() {}
}

class _NeverSink implements StreamSink<Uint8List> {
  final Completer<void> _never = Completer<void>();

  @override
  void add(Uint8List data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<Uint8List> stream) => _never.future;

  @override
  Future<void> close() => _never.future;

  @override
  Future<void> get done => _never.future;
}

/// Builds tunnels whose SSH half is a [_FakeExec], and records every command
/// the tunnel asked to exec.
class _Fixture {
  _Fixture({this.echo, this.failAlways = false});

  final Uint8List Function(Uint8List)? echo;
  final bool failAlways;
  final List<String> commands = <String>[];
  final List<_FakeExec> execs = <_FakeExec>[];

  Future<RoostTunnel> open() => RoostTunnel.openWithExec(
    exec: _exec,
    remoteCommand: kRoostRemoteCommand,
    machine: 'test',
  );

  Future<RoostExecSession> _exec(String command) async {
    commands.add(command);
    if (failAlways) {
      throw const SocketException('exec refused');
    }
    final exec = _FakeExec(echo: echo);
    execs.add(exec);
    return exec;
  }

  /// The exec for the [index]th accepted connection, once it exists (the tunnel
  /// opens it asynchronously, after accept).
  Future<_FakeExec> execAt(int index) async {
    await _waitFor(() => execs.length > index, 'exec #$index to be opened');
    return execs[index];
  }
}

/// Poll until [condition] holds. Polling, not sleeping: everything here is
/// driven by real sockets, so a fixed delay is either flaky or slow.
Future<void> _waitFor(bool Function() condition, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
