import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shed_mobile/ssh/duplex_pump.dart';

/// Which stderr band a [FakeChannel] offers.
enum StderrBand {
  /// A live band, like a remote exec's — the normal case.
  open,

  /// No band at all, like a forwarded TCP channel's.
  none,

  /// A band that closes at once, which must only ARM the grace period.
  closed,
}

/// A [DuplexChannel] under the test's control: it records what it received,
/// optionally transforms it back onto the read half, and can end on demand.
///
/// Shared by `duplex_pump_test.dart` (which tests the pump over it) and
/// `lane_forward_test.dart` (which tests the forward and the registry above
/// it). `roost_tunnel_test.dart` has its own frozen equivalent over the exec
/// seam — that file is the pump extraction's control and does not move.
class FakeChannel implements DuplexChannel {
  FakeChannel({
    Uint8List Function(Uint8List)? echo,
    this.band = StderrBand.open,
  }) {
    _sink.stream.listen((chunk) {
      final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
      _received.add(bytes);
      final out = echo?.call(bytes);
      if (out != null && !_stream.isClosed) _stream.add(out);
    }, onDone: () => sinkClosed = true);
  }

  final StderrBand band;
  final StreamController<List<int>> _sink = StreamController<List<int>>();
  final StreamController<Uint8List> _stream = StreamController<Uint8List>();
  final StreamController<Uint8List> _stderr = StreamController<Uint8List>();
  final Completer<void> _done = Completer<void>();
  final BytesBuilder _received = BytesBuilder();

  /// Set when the pump closes the write half — the EOF that must never come
  /// early.
  bool sinkClosed = false;

  /// Set when the pump asks for a graceful close.
  bool closeCalled = false;

  /// Set when the pump forces the channel shut.
  bool destroyCalled = false;

  String get receivedText => utf8.decode(_received.toBytes());

  /// Push bytes the local side never asked for.
  ///
  /// A no-op once the channel has been closed — so a pump that tears down too
  /// early fails on the bytes the client never received, which is the behaviour
  /// under test, rather than on a state error in this fake.
  void emit(String text) {
    if (_stream.isClosed) return;
    _stream.add(Uint8List.fromList(utf8.encode(text)));
  }

  /// The far side's channel ends — `done` only. The read half is left open on
  /// purpose: that is dartssh2's documented shape, and the pump must treat this
  /// as a hint, not as "the output is over".
  void endRemotely() {
    if (!_done.isCompleted) _done.complete();
  }

  /// The read half itself finishes — the authoritative end of the channel's
  /// output, and the pump's real teardown trigger.
  void endStream() {
    if (!_stream.isClosed) unawaited(_stream.close());
  }

  @override
  StreamSink<List<int>> get sink => _sink.sink;

  @override
  Stream<Uint8List> get stream => _stream.stream;

  @override
  Stream<Uint8List>? get stderr => switch (band) {
    StderrBand.open => _stderr.stream,
    StderrBand.none => null,
    StderrBand.closed => const Stream<Uint8List>.empty(),
  };

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close() async {
    closeCalled = true;
    endStream();
    if (!_stderr.isClosed) unawaited(_stderr.close());
    endRemotely();
  }

  @override
  void destroy() {
    destroyCalled = true;
    unawaited(close());
  }
}

/// A channel that never answers: its write half never closes, its `close()`
/// never returns, its `done` never settles, its read half never finishes. Every
/// bounded wait in teardown, in one object.
class WedgedChannel implements DuplexChannel {
  final _NeverSink _sink = _NeverSink();
  final StreamController<Uint8List> _stream = StreamController<Uint8List>();
  final Completer<void> _never = Completer<void>();

  bool destroyCalled = false;

  /// Set once the pump has started reading this channel.
  bool get started => _stream.hasListener;

  @override
  StreamSink<List<int>> get sink => _sink;

  @override
  Stream<Uint8List> get stream => _stream.stream;

  @override
  Stream<Uint8List>? get stderr => null;

  @override
  Future<void> get done => _never.future;

  @override
  Future<void> close() => _never.future;

  @override
  void destroy() => destroyCalled = true;
}

class _NeverSink implements StreamSink<List<int>> {
  final Completer<void> _never = Completer<void>();

  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) => _never.future;

  @override
  Future<void> close() => _never.future;

  @override
  Future<void> get done => _never.future;
}

/// Upper-cases everything written to a channel — the smallest transform that
/// proves the bytes went UP and a distinguishable answer came back DOWN.
Uint8List upperEcho(Uint8List data) =>
    Uint8List.fromList(utf8.encode(utf8.decode(data).toUpperCase()));

/// A logger that says nothing, for tests that are not about the log.
void quietLog(String _) {}
