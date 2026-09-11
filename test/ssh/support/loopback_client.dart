import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// A local client of a listening loopback port — the Rust side's stand-in.
///
/// A [Socket] may only be listened to once, so every read in a test goes
/// through this buffer. Shared by `duplex_pump_test.dart` and
/// `lane_forward_test.dart`; `roost_tunnel_test.dart` predates it and keeps its
/// own frozen copy on purpose (it is the pump extraction's control, so not one
/// byte of it moves).
class LoopbackClient {
  LoopbackClient(this._socket) {
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

  /// Connect to [port] on loopback.
  static Future<LoopbackClient> connect(int port) async => LoopbackClient(
    await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
      timeout: const Duration(seconds: 5),
    ),
  );

  final Socket _socket;
  final List<int> _bytes = <int>[];
  final Completer<void> _closed = Completer<void>();
  late final StreamSubscription<Uint8List> _sub;

  /// The error the read ended with, if it ended in one. A clean end of stream
  /// leaves this null; a reset (`destroy()` on a half-closed peer) does not.
  Object? error;

  /// Completes when the far end closes this connection.
  Future<void> get closedByPeer => _closed.future;

  /// Everything read so far.
  String get text => utf8.decode(_bytes);

  int get bytesReceived => _bytes.length;

  /// Write [text] and read back the bytes that answer it.
  Future<String> roundTrip(String text) {
    final from = _bytes.length;
    write(text);
    return read(text.length, from: from);
  }

  void write(String text) => _socket.add(utf8.encode(text));

  /// Read [length] bytes starting at [from] (default: wherever we are now).
  Future<String> read(int length, {int? from}) async {
    final start = from ?? _bytes.length;
    await waitFor(
      () => _bytes.length >= start + length,
      '$length bytes from the port',
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

/// Poll until [condition] holds. Polling, not sleeping: everything in these
/// tests is driven by real sockets, so a fixed delay is either flaky or slow.
Future<void> waitFor(
  bool Function() condition,
  String what, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Poll until [port] stops answering on loopback.
///
/// The honest form of "no listener was left behind": a close that happens on a
/// later turn (a forward that had to close itself once its dial landed) is
/// still a close, but a leak never becomes one.
Future<void> waitForPortFree(
  int port, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (await portAccepts(port)) {
    if (DateTime.now().isAfter(deadline)) {
      fail('port $port is still listening');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Whether [port] still answers on loopback — "did close() really free it?".
Future<bool> portAccepts(int port) async {
  try {
    final probe = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
      timeout: const Duration(seconds: 2),
    );
    probe.destroy();
    return true;
  } on SocketException {
    return false;
  }
}
