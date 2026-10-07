import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shed_mobile/src/rust/api/roost.dart';
import 'package:shed_mobile/ssh/duplex_pump.dart';
import 'package:shed_mobile/ssh/rolling_tail.dart';
import 'package:shed_mobile/ssh/roost_reach.dart';

import 'support/fake_channel.dart';
import 'support/loopback_client.dart';

/// **The generic byte pump and the port it serves** — the machinery under both
/// `RoostTunnel` (a remote exec) and `LaneForward` (a forwarded TCP channel).
///
/// It was extracted from the roost tunnel rather than written, so
/// `roost_tunnel_test.dart` is its regression control over the exec transport
/// and this file is the same contract stated over the *channel* interface, plus
/// the two things only a forward exercises: a `close()` that waits on the
/// remote (and must therefore be bounded and fall through to `destroy()`), and
/// a transport with no stderr band at all.
///
/// Every assertion here is on DELIVERED BYTES, never on liveness. Plan 012
/// shipped a forwarded-hub check that asserted the tunnel was up and passed
/// against a completely dead feed (`roost_tunnel_test.dart:18-30`); a pump that
/// accepts connections and moves nothing must fail below.
void main() {
  group('DuplexPump', () {
    group('delivered bytes', () {
      test('go up to the channel and come back down', () async {
        final fixture = _Fixture(echo: upperEcho);
        final listener = await fixture.bind();
        addTearDown(listener.close);

        final conn = await LoopbackClient.connect(listener.port);
        addTearDown(conn.destroy);

        // Both directions in one assertion: the bytes went up, the transformed
        // bytes came back. A pump that merely accepts fails here.
        expect(await conn.roundTrip('hello'), 'HELLO');
        expect((await fixture.channelAt(0)).receivedText, 'hello');
      });

      test('arrive unprompted, with no local write to answer', () async {
        // The direction that matters most: an agent's SSE frames arrive with no
        // request in between, and Rust only ever sees them through here.
        final fixture = _Fixture();
        final listener = await fixture.bind();
        addTearDown(listener.close);

        final conn = await LoopbackClient.connect(listener.port);
        addTearDown(conn.destroy);
        final channel = await fixture.channelAt(0);

        const frame = 'data: {"type":"message.part.updated"}\n\n';
        channel.emit(frame);
        expect(await conn.read(frame.length), frame);
      });

      test('include a frame that lands after `done` has fired', () async {
        // dartssh2 completes `done` while the stream can still hold buffered
        // data. Tearing down on `done` clips that tail — and the tail here is a
        // whole HTTP response body the Rust client is blocking on. So: the
        // stream finishing, not `done`, is the trigger.
        final fixture = _Fixture();
        final listener = await fixture.bind();
        addTearDown(listener.close);

        final conn = await LoopbackClient.connect(listener.port);
        addTearDown(conn.destroy);
        final channel = await fixture.channelAt(0);

        const tail = 'HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}';
        // `done` first — dartssh2's documented shape...
        channel.endRemotely();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        // ...with a frame still queued behind it, delivered only afterwards.
        channel.emit(tail);
        channel.endStream();

        expect(
          await conn.read(tail.length, from: 0),
          tail,
          reason: 'the final frame must survive teardown',
        );
        await conn.closedByPeer.timeout(const Duration(seconds: 5));
        expect(conn.bytesReceived, tail.length, reason: 'and nothing after it');
      });

      test('are drained, then the local read ends with a clean EOF', () async {
        // `destroy()` on a socket the peer has half-closed RESETS it, and a
        // reset discards whatever is still in flight: the client sees a
        // connection error instead of its data followed by an end of stream,
        // and Rust reads that as a broken link rather than a finished body.
        final fixture = _Fixture();
        final listener = await fixture.bind();
        addTearDown(listener.close);

        final conn = await LoopbackClient.connect(listener.port);
        addTearDown(conn.destroy);
        final channel = await fixture.channelAt(0);

        // More than one socket write's worth, so "drained" means something.
        final tail = List<String>.generate(
          8192,
          (i) => 'data: {"seq":$i}\n\n',
        ).join();
        channel.emit(tail);
        channel.endStream();

        await conn.closedByPeer.timeout(const Duration(seconds: 10));
        expect(conn.error, isNull, reason: 'a reset is not an end of stream');
        expect(
          conn.bytesReceived,
          tail.length,
          reason: 'and every drained byte arrived first',
        );
      });
    });

    test(
      'an async EPIPE on the local socket is observed, not left uncaught',
      () async {
        // `_socket.add` in the down-pump only catches a SYNCHRONOUS write
        // failure. When the local peer has already closed, the write fails
        // ASYNCHRONOUSLY instead: `Socket.done` completes with a
        // `SocketException: Broken pipe` that nothing was listening for — it
        // escaped as an uncaught async error. A real test run hit exactly
        // this swapping one craze transcript for another, with the remote
        // bridge still emitting buffered bytes into the torn-down local side.
        //
        // Built directly on `DuplexPump` (not through `PortListener`) so the
        // test can see `pump.done` complete — the listener keeps its pumps
        // private.
        //
        // `Socket.destroy()` on the peer does not GUARANTEE this lands as an
        // asynchronous EPIPE rather than, say, a clean local FIN that the
        // existing `_onLocalDone` path already handles within its grace
        // period — so this cell must not merely hope the race goes the
        // interesting way and pass either way. It captures the pump's own
        // log (the injected logger `DuplexPump` already takes) and polls,
        // bounded, until the fix's own log line shows up, failing loudly if
        // it never does — so removing the fix cannot pass this cell by
        // accident.
        //
        // An SO_LINGER{on:1,linger:0} RST was tried here and rejected: it
        // forces the LOCAL socket's READ side to see `Connection reset by
        // peer` immediately, which the pump's PRE-EXISTING `_up` stream
        // `onError` handler (unrelated to this fix) already tears down on —
        // and once that handler fires first, `_socket.done` never settles at
        // all in testing here, so the one path this cell exists to exercise
        // never runs. A plain `destroy()` (an idle connection, so a clean
        // FIN) leaves the read side quiet and is what actually reaches
        // `_socket.done`.
        const asyncMarker = 'write failed asynchronously';
        final logs = <String>[];
        Object? uncaught;
        var doneTimedOut = false;
        late DuplexPump pump;
        await runZonedGuarded(
          () async {
            // The accept must happen INSIDE this zone: dart:io binds a
            // socket's asynchronous error reporting to whichever zone was
            // current when the connection was accepted, not to whichever
            // zone later calls `.listen`/`.then` on it. Accepting outside
            // and only starting the pump in here would make the broken-pipe
            // error unobservable to this zone no matter what `start()` does.
            final server = await ServerSocket.bind(
              InternetAddress.loopbackIPv4,
              0,
            );
            final acceptFuture = server.first;
            final peer = await Socket.connect(
              InternetAddress.loopbackIPv4,
              server.port,
            );
            final localSocket = await acceptFuture;
            await server.close();

            final channel = FakeChannel();
            pump = DuplexPump(localSocket, channel, logs.add);
            pump.start();

            peer.destroy();
            await Future<void>.delayed(const Duration(milliseconds: 50));

            // Remote bytes keep arriving after the local side is already
            // gone — the scenario the bug report hit. Keep emitting, bounded,
            // until the async observer's own log line shows up; the bound is
            // enforced by the loop CONDITION, not by throwing — a `fail()`
            // (or any other throw) from inside `runZonedGuarded`'s body does
            // not reach the `await` below at all. It is instead delivered to
            // this zone's `onError`, which is this cell's OWN handler; since
            // that handler does not rethrow, the awaited call would simply
            // hang until the suite's global per-test timeout. So: no
            // assertions inside the zone, ever — everything observable here
            // is read back and asserted once the zone has returned.
            final deadline = DateTime.now().add(const Duration(seconds: 5));
            var i = 0;
            while (!logs.any((m) => m.contains(asyncMarker)) &&
                DateTime.now().isBefore(deadline)) {
              channel.emit('data: {"seq":${i++}}\n\n');
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }

            // Same reasoning: catch the timeout locally rather than letting
            // it propagate out of the zone, and report it via a flag below.
            try {
              await pump.done.timeout(const Duration(seconds: 5));
            } catch (_) {
              doneTimedOut = true;
            }
          },
          (error, stack) {
            uncaught ??= error;
          },
        );

        expect(
          uncaught,
          isNull,
          reason: 'the broken pipe must not escape as an uncaught error',
        );
        // Non-vacuous: the fix's own log line must actually have fired, and
        // it must name the failure the bug report hit, not just any error —
        // otherwise this cell would pass even with the fix removed, on a
        // host where `destroy()` happened not to race into an async EPIPE.
        expect(
          logs.any((m) => m.contains(asyncMarker) && m.contains('Broken pipe')),
          isTrue,
          reason:
              'the new async `done` observer must actually have run — '
              'otherwise this cell would pass even with it removed',
        );
        // The pump must still have torn itself down despite the failed
        // write — the whole point is to handle it, not to swallow it into a
        // state where the pump is wedged.
        expect(
          doneTimedOut,
          isFalse,
          reason: 'the pump never finished tearing down',
        );
      },
    );

    test('a local half-close reaches the sink, and reading continues', () async {
      // The rule stated once: local EOF closes the channel's write half and
      // KEEPS READING the remote. A pump that treats the local FIN as "we are
      // done" loses the response to the last request the client sent.
      final fixture = _Fixture();
      final listener = await fixture.bind();
      addTearDown(listener.close);

      final conn = await LoopbackClient.connect(listener.port);
      addTearDown(conn.destroy);
      conn.write('GET /event HTTP/1.1\r\n\r\n');
      final channel = await fixture.channelAt(0);
      await waitFor(() => channel.receivedText.isNotEmpty, 'the request');
      expect(
        channel.sinkClosed,
        isFalse,
        reason: 'a completed request must NOT half-close the channel',
      );

      conn.closeWrite();
      await waitFor(() => channel.sinkClosed, 'the channel to see EOF');

      // Still reading: the far side answers after the local write half is gone.
      const body = 'HTTP/1.1 204 No Content\r\n\r\n';
      channel.emit(body);
      expect(await conn.read(body.length, from: 0), body);
    });

    test(
      'a graceful stop closes the channel; it does not destroy it',
      () async {
        final fixture = _Fixture();
        final listener = await fixture.bind();
        final conn = await LoopbackClient.connect(listener.port);
        addTearDown(conn.destroy);
        final channel = await fixture.channelAt(0);

        await listener.close();

        expect(
          channel.sinkClosed,
          isTrue,
          reason: 'the channel must get its EOF',
        );
        expect(channel.closeCalled, isTrue, reason: 'and a graceful close');
        expect(
          channel.destroyCalled,
          isFalse,
          reason: 'destroy() resets, and a reset drops bytes still in flight',
        );
        await conn.closedByPeer.timeout(const Duration(seconds: 5));
      },
    );

    test('a wedged channel is destroyed within the bound', () async {
      // A forwarded channel's close() WAITS ON THE REMOTE
      // (dartssh2-2.18.0/lib/src/ssh_forward.dart:45-68). Against a peer that
      // never answers, an unbounded await strands teardown forever, so the
      // bound and the forced seam are the contract: close(), then destroy().
      final wedged = WedgedChannel();
      final listener = await PortListener.bind(
        dial: () async => wedged,
        log: quietLog,
      );
      final conn = await LoopbackClient.connect(listener.port);
      addTearDown(conn.destroy);
      await waitFor(() => wedged.started, 'the wedged channel to be pumped');

      final elapsed = Stopwatch()..start();
      await listener.close();
      elapsed.stop();

      expect(listener.isClosed, isTrue);
      expect(
        elapsed.elapsed,
        lessThan(const Duration(seconds: 4)),
        reason: 'teardown must be bounded, not wait on the far side',
      );
      expect(
        wedged.destroyCalled,
        isTrue,
        reason: 'the forced seam is what actually frees a wedged channel',
      );
    });

    test('a channel with NO stderr band is left alone by it', () async {
      // The trap this nullability exists for: stderr CLOSING is a fallback
      // end-of-remote hint, so handing the pump an already-empty stream for a
      // transport that has no diagnostic band at all would arm that hint
      // immediately and tear every forwarded connection down one grace period
      // (500 ms) after it opened.
      final fixture = _Fixture(echo: upperEcho, stderr: StderrBand.none);
      final listener = await fixture.bind();
      addTearDown(listener.close);

      final conn = await LoopbackClient.connect(listener.port);
      addTearDown(conn.destroy);
      expect(await conn.roundTrip('early'), 'EARLY');

      // Well past the grace period, and still carrying bytes.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(await conn.roundTrip('late'), 'LATE');
      expect((await fixture.channelAt(0)).closeCalled, isFalse);
    });

    test('a stderr band that closes only ARMS the grace period', () async {
      // The other half of the same rule, on the transport that does have one:
      // stderr closing means the channel is going away, but the read half may
      // still have buffered frames, so the pump waits out the grace before
      // giving up on them.
      final fixture = _Fixture(stderr: StderrBand.closed);
      final listener = await fixture.bind();
      addTearDown(listener.close);

      final conn = await LoopbackClient.connect(listener.port);
      addTearDown(conn.destroy);
      final channel = await fixture.channelAt(0);

      const frame = 'still here\n';
      channel.emit(frame);
      expect(await conn.read(frame.length, from: 0), frame);
      // ...and only then does the connection end.
      await conn.closedByPeer.timeout(const Duration(seconds: 5));
      expect(conn.bytesReceived, frame.length);
    });

    group('PortListener', () {
      test('binds a fixed loopback port and frees it on close', () async {
        final fixture = _Fixture();
        final listener = await fixture.bind();
        final port = listener.port;

        expect(port, greaterThan(0));
        // The port is a property of the LISTENER, not of any connection.
        expect(listener.port, port);
        expect(await portAccepts(port), isTrue);

        await listener.close();
        expect(listener.isClosed, isTrue);
        // A leaked listener would keep answering and Rust would read a dead
        // transport as a healthy one.
        expect(await portAccepts(port), isFalse);
      });

      test('close is idempotent', () async {
        final fixture = _Fixture();
        final listener = await fixture.bind();
        await listener.close();
        await listener.close();
        expect(listener.isClosed, isTrue);
      });

      test('a failed dial closes only that connection', () async {
        // The everyday "the machine is asleep" case. The LISTENER must survive
        // it, or a phone that lost its network would strand the port Rust is
        // retrying against.
        final fixture = _Fixture(echo: upperEcho, failDials: 2);
        final listener = await fixture.bind();
        addTearDown(listener.close);
        final port = listener.port;

        for (var i = 0; i < 2; i++) {
          final probe = await LoopbackClient.connect(port);
          await probe.closedByPeer.timeout(const Duration(seconds: 10));
          probe.destroy();
        }
        expect(fixture.dials, 2, reason: 'both connections tried to dial');
        expect(listener.isClosed, isFalse);
        expect(listener.port, port);

        // And the next connection, whose dial succeeds, carries bytes.
        final conn = await LoopbackClient.connect(port);
        addTearDown(conn.destroy);
        expect(await conn.roundTrip('back'), 'BACK');
      });

      test('two connections get two independent channels', () async {
        final fixture = _Fixture(echo: upperEcho);
        final listener = await fixture.bind();
        addTearDown(listener.close);

        final first = await LoopbackClient.connect(listener.port);
        addTearDown(first.destroy);
        expect(await first.roundTrip('one'), 'ONE');
        final second = await LoopbackClient.connect(listener.port);
        addTearDown(second.destroy);
        expect(await second.roundTrip('two'), 'TWO');

        expect(fixture.channels.length, 2);
        expect(fixture.channels[0].receivedText, 'one');
        expect(fixture.channels[1].receivedText, 'two');

        // Tearing one down leaves the other carrying bytes.
        first.closeWrite();
        await waitFor(
          () => fixture.channels[0].sinkClosed,
          'the first channel to see EOF',
        );
        expect(fixture.channels[1].sinkClosed, isFalse);
        expect(await second.roundTrip('still'), 'STILL');
      });
    });

    group('the diagnostic band', () {
      test('reaches an observer, which is the only way the phone learns WHY a '
          'reach is refusing', () async {
        // Plan 020 amendment A2. Rust is handed a loopback port and can only
        // ever watch it stop answering; the sentence that says whether an
        // install or a start would fix it is on THIS band and nowhere else. A
        // pump that only logged it (which is all it used to do) leaves every
        // `Down` the watcher publishes carrying `kind: Other`.
        final seen = <String>[];
        final fixture = _Fixture(echo: upperEcho, onStderr: seen.add);
        final listener = await fixture.bind();
        addTearDown(listener.close);

        final conn = await LoopbackClient.connect(listener.port);
        addTearDown(conn.destroy);
        expect(await conn.roundTrip('hello'), 'HELLO');

        final channel = await fixture.channelAt(0);
        channel.emitStderr('roost-session: command not found\n');
        await waitFor(() => seen.isNotEmpty, 'the stderr chunk');

        expect(seen, <String>['roost-session: command not found\n']);
      });

      test('is classified from the ACCUMULATED tail, so a marker split across '
          'two frames still classifies', () async {
        // The defect amendment A2 exists to prevent, and it is invisible in a
        // one-frame test. SSH frame boundaries are arbitrary: `client-bridge`
        // writes one line and the far side's transport is free to deliver it as
        // two data messages. An observer handed each chunk on its own sees
        // 'client-bridge: no ' (matches nothing) and then 'session\n' (matches
        // nothing) — so a stopped session classifies as NOTHING, every `Down`
        // keeps `kind: Other`, and the card never offers a start.
        final seen = <String>[];
        final fixture = _Fixture(echo: upperEcho, onStderr: seen.add);
        final listener = await fixture.bind();
        addTearDown(listener.close);

        final conn = await LoopbackClient.connect(listener.port);
        addTearDown(conn.destroy);
        expect(await conn.roundTrip('hello'), 'HELLO');
        final channel = await fixture.channelAt(0);

        channel.emitStderr('client-bridge: no ');
        await waitFor(() => seen.length == 1, 'the first frame');
        expect(
          noteForExecStderr(seen.last),
          isNull,
          reason: 'half a marker is not a classification',
        );

        channel.emitStderr('session\n');
        await waitFor(() => seen.length == 2, 'the second frame');

        expect(seen.last, 'client-bridge: no session\n');
        expect(
          noteForExecStderr(seen.last)?.kind,
          BridgeReachKind.noSession,
          reason: 'the two frames are one line, and it names a start',
        );
      });

      test('joins THREE frames, including a cut inside a UTF-8 '
          'sequence', () async {
        // Two boundaries, each in a place a per-chunk observer cannot survive:
        // one inside a multi-byte character (decoding each chunk on its own
        // burns it into a permanent replacement character) and one inside the
        // marker itself. Held as bytes and decoded once, both heal.
        const line = 'roost-session: ✗ command not found\n';
        final all = utf8.encode(line);
        // 'roost-session: ' is 15 bytes and '✗' is three, so 16 cuts the
        // character; 25 lands inside 'command'.
        expect(all.length, greaterThan(25));

        final seen = <String>[];
        final fixture = _Fixture(echo: upperEcho, onStderr: seen.add);
        final listener = await fixture.bind();
        addTearDown(listener.close);

        final conn = await LoopbackClient.connect(listener.port);
        addTearDown(conn.destroy);
        expect(await conn.roundTrip('hello'), 'HELLO');
        final channel = await fixture.channelAt(0);

        channel.emitStderrBytes(all.sublist(0, 16));
        await waitFor(() => seen.length == 1, 'the first frame');
        expect(noteForExecStderr(seen.last), isNull);

        channel.emitStderrBytes(all.sublist(16, 25));
        await waitFor(() => seen.length == 2, 'the second frame');
        expect(
          noteForExecStderr(seen.last),
          isNull,
          reason: "'comman' is not 'command not found'",
        );

        channel.emitStderrBytes(all.sublist(25));
        await waitFor(() => seen.length == 3, 'the third frame');

        // Byte-for-byte the original: no replacement character survived the
        // cut through '✗', which is what decoding once at the end buys.
        expect(seen.last, line);
        expect(
          noteForExecStderr(seen.last)?.kind,
          BridgeReachKind.notInstalled,
        );
      });

      test('is BOUNDED: a chatty remote cannot grow the tail without '
          'limit', () async {
        // An accumulator with no ceiling is its own bug. The window is the
        // LAST bytes, for the same reason the exec seam's `stderr_cap` is: a
        // login banner comes first and the useful line last.
        final seen = <String>[];
        final fixture = _Fixture(echo: upperEcho, onStderr: seen.add);
        final listener = await fixture.bind();
        addTearDown(listener.close);

        final conn = await LoopbackClient.connect(listener.port);
        addTearDown(conn.destroy);
        expect(await conn.roundTrip('hello'), 'HELLO');
        final channel = await fixture.channelAt(0);

        channel.emitStderr('BANNER${'.' * (kStderrTailBytes * 2)}');
        await waitFor(() => seen.isNotEmpty, 'the banner');
        channel.emitStderr('client-bridge: no session\n');
        await waitFor(() => seen.length == 2, 'the line that matters');

        expect(seen.last.length, lessThanOrEqualTo(kStderrTailBytes));
        expect(seen.last, isNot(contains('BANNER')));
        expect(
          noteForExecStderr(seen.last)?.kind,
          BridgeReachKind.noSession,
          reason: 'the tail keeps the end, which is where the answer is',
        );
      });

      test('is optional: a listener with no observer still pumps', () async {
        // Every other caller of `PortListener` (a lane forward) passes none,
        // and a null observer must be a no-op rather than a null dereference
        // on the first byte of a banner.
        final fixture = _Fixture(echo: upperEcho);
        final listener = await fixture.bind();
        addTearDown(listener.close);

        final conn = await LoopbackClient.connect(listener.port);
        addTearDown(conn.destroy);
        final channel = await fixture.channelAt(0);
        channel.emitStderr('a banner\n');

        expect(await conn.roundTrip('hello'), 'HELLO');
      });
    });
  });
}

/// Binds listeners whose channel half is a [FakeChannel].
class _Fixture {
  _Fixture({
    this.echo,
    this.stderr = StderrBand.open,
    this.failDials = 0,
    this.onStderr,
  });

  final Uint8List Function(Uint8List)? echo;
  final StderrBand stderr;

  /// How many of the first dials throw, the way an asleep machine's would.
  final int failDials;

  /// The observer of the channel's diagnostic band, when a cell is about it.
  final void Function(String)? onStderr;

  int dials = 0;
  final List<FakeChannel> channels = <FakeChannel>[];

  Future<PortListener> bind() =>
      PortListener.bind(dial: _dial, log: quietLog, onStderr: onStderr);

  Future<DuplexChannel> _dial() async {
    dials++;
    if (dials <= failDials) {
      throw const SocketException('no route to host');
    }
    final channel = FakeChannel(echo: echo, band: stderr);
    channels.add(channel);
    return channel;
  }

  /// The channel for the [index]th accepted connection, once it exists (the
  /// listener dials asynchronously, after accept).
  Future<FakeChannel> channelAt(int index) async {
    await waitFor(() => channels.length > index, 'channel #$index');
    return channels[index];
  }
}
