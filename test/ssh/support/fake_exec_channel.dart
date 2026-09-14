import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shed_mobile/ssh/exec_bytes.dart';

/// **One remote exec under the test's control** — the [BootstrapExecSession]
/// every `exec_bytes.dart` and `roost_bootstrap_runner.dart` cell runs against.
///
/// It is the exec seam's own fake, distinct from `fake_channel.dart`'s
/// [FakeChannel](../support/fake_channel.dart) (which is a `DuplexChannel`, has
/// no exit status, and is the byte pump's). A bootstrap step's answer is mostly
/// its exit status, so the two cannot be one object.
///
/// Four things it can do that a real channel does and a simpler fake cannot:
///
/// * **Stall its drain** ([stall] / [release]), which is what makes
///   backpressure assertable: `addStream` pauses its source while this
///   subscription is paused, so a writer that WAITS pulls nothing more and a
///   writer that buffers pulls everything.
/// * **End without an exit status** ([finish] with no `exit`), which is the
///   dartssh2 behaviour the whole `exit: None` rule exists for.
/// * **Fail a band** ([failStdout] / [failDone]), which is a transport failure
///   rather than a clean end — the distinction a runner has to make.
/// * **Never end at all**, which is what a budget is for.
class FakeExecChannel implements BootstrapExecSession {
  FakeExecChannel({int? exit, bool stalled = false}) : _exitCode = exit {
    _drain = _stdin.stream.listen(_take, onDone: _closeStdin);
    if (stalled) _drain.pause();
  }

  final StreamController<Uint8List> _stdin = StreamController<Uint8List>();
  final StreamController<Uint8List> _stdout = StreamController<Uint8List>();
  final StreamController<Uint8List> _stderr = StreamController<Uint8List>();
  final Completer<void> _done = Completer<void>();
  final BytesBuilder _received = BytesBuilder(copy: true);
  late final StreamSubscription<Uint8List> _drain;

  int? _exitCode;

  /// Set when the runner closes stdin — the EOF a bootstrap step MUST send.
  bool stdinClosed = false;

  /// Set when the runner closes the channel POLITELY — EOF, and ask.
  bool closeCalled = false;

  /// Set when the runner FORCES the channel shut, which is what an abort must
  /// do: a remote command that ignores EOF survives a polite close, and its
  /// channel survives with it on the connection the whole app shares.
  bool destroyCalled = false;

  /// How many chunks reached the drain. With [stall] this is what says the
  /// writer waited rather than buffering.
  int writes = 0;

  void _take(Uint8List chunk) {
    _received.add(chunk);
    writes++;
  }

  void _closeStdin() => stdinClosed = true;

  Uint8List get received => _received.toBytes();

  String get receivedText => utf8.decode(received, allowMalformed: true);

  /// Stop draining stdin — a far side whose window is full.
  void stall() => _drain.pause();

  /// Drain again.
  void release() => _drain.resume();

  void emitStdout(List<int> bytes) {
    if (!_stdout.isClosed) _stdout.add(Uint8List.fromList(bytes));
  }

  void emitStderr(String text) {
    if (!_stderr.isClosed) _stderr.add(Uint8List.fromList(utf8.encode(text)));
  }

  /// The ordinary end of a step: both bands finish, the channel settles, and
  /// the far side reports [exit] — or reports nothing, which is the dropped
  /// `exit-status` the concession is about.
  void finish({int? exit}) {
    _exitCode = exit;
    if (!_stdout.isClosed) unawaited(_stdout.close());
    if (!_stderr.isClosed) unawaited(_stderr.close());
    if (!_done.isCompleted) _done.complete();
  }

  /// The read half fails rather than finishing — a transport error, not an EOF.
  void failStdout(Object error) {
    if (!_stdout.isClosed) _stdout.addError(error);
    if (!_stderr.isClosed) unawaited(_stderr.close());
    if (!_done.isCompleted) _done.complete();
  }

  /// The channel itself fails.
  void failDone(Object error) {
    if (!_stdout.isClosed) unawaited(_stdout.close());
    if (!_stderr.isClosed) unawaited(_stderr.close());
    if (!_done.isCompleted) _done.completeError(error);
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
  int? get exitCode => _exitCode;

  @override
  void close() {
    closeCalled = true;
    // A real close ends the channel; the run's abort must not then hang on a
    // `done` that never settles.
    finish(exit: _exitCode);
  }

  /// Kept independent of [close] on purpose: the two flags are how a cell says
  /// WHICH seam the code reached for, and a `destroy` that also set
  /// `closeCalled` would make the polite one unfalsifiable.
  @override
  void destroy() {
    destroyCalled = true;
    finish(exit: _exitCode);
  }
}
